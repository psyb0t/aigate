#!/usr/bin/env python3
"""
OpenAI-compatible TTS API server for faster-qwen3-tts.

Exposes POST /v1/audio/speech compatible with OpenAI's TTS API, enabling
integration with OpenWebUI, llama-swap, and other OpenAI-compatible clients.
Also exposes POST /unload and POST /load for VRAM management.

Usage:
    pip install "faster-qwen3-tts[demo]"

    # Multiple named voices from a JSON config:
    python openai_server.py --voices voices.json

Voices config (voices.json):
    {
        "alloy": {"ref_audio": "voice.wav", "ref_text": "...", "language": "English"},
        "echo":  {"ref_audio": "voice2.wav", "ref_text": "...", "language": "English"}
    }

API usage:
    curl -s http://localhost:8000/v1/audio/speech \\
        -H "Content-Type: application/json" \\
        -d '{"model": "tts-1", "input": "Hello!", "voice": "alloy", "response_format": "wav"}' \\
        --output speech.wav

    # VRAM management (called by LiteLLM resource manager):
    curl -X POST http://localhost:8000/unload
    curl -X POST http://localhost:8000/load
"""
import argparse
import asyncio
import gc
import io
import json
import logging
import os
import queue
import struct
import sys
import threading
from typing import AsyncGenerator, Optional

import numpy as np
import torch
import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.responses import Response, StreamingResponse
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Global state
# ---------------------------------------------------------------------------

app = FastAPI(title="faster-qwen3-tts OpenAI-compatible API")

tts_model = None
_model_id: str = ""
_model_dtype = None
_model_device: str = "cuda"
_model_loaded: bool = False
voices: dict = {}
default_voice: Optional[str] = None
SAMPLE_RATE = 24000
_model_lock = threading.Lock()     # prevent concurrent GPU inference
_load_lock = asyncio.Lock()        # prevent concurrent load/unload ops

# ---------------------------------------------------------------------------
# Request / response models
# ---------------------------------------------------------------------------


class SpeechRequest(BaseModel):
    model: str = "tts-1"
    input: str
    voice: str = "alloy"
    response_format: str = "wav"   # wav | pcm | mp3
    speed: float = 1.0             # accepted but not applied


# ---------------------------------------------------------------------------
# Audio helpers
# ---------------------------------------------------------------------------


def _to_pcm16(pcm: np.ndarray) -> bytes:
    return np.clip(pcm * 32768, -32768, 32767).astype(np.int16).tobytes()


def _wav_header(sample_rate: int, data_len: int = 0xFFFFFFFF) -> bytes:
    n_channels = 1
    bits = 16
    byte_rate = sample_rate * n_channels * bits // 8
    block_align = n_channels * bits // 8
    riff_size = 0xFFFFFFFF if data_len == 0xFFFFFFFF else 36 + data_len
    buf = io.BytesIO()
    buf.write(b"RIFF")
    buf.write(struct.pack("<I", riff_size))
    buf.write(b"WAVE")
    buf.write(b"fmt ")
    buf.write(struct.pack("<IHHIIHH", 16, 1, n_channels, sample_rate,
                          byte_rate, block_align, bits))
    buf.write(b"data")
    buf.write(struct.pack("<I", data_len))
    return buf.getvalue()


def _to_mp3_bytes(pcm: np.ndarray, sample_rate: int) -> bytes:
    try:
        from pydub import AudioSegment
    except ImportError:
        raise HTTPException(status_code=400, detail="mp3 requires pydub: pip install pydub")
    segment = AudioSegment(_to_pcm16(pcm), frame_rate=sample_rate, sample_width=2, channels=1)
    buf = io.BytesIO()
    segment.export(buf, format="mp3")
    return buf.getvalue()


# ---------------------------------------------------------------------------
# Model management — load / unload
# ---------------------------------------------------------------------------


def _do_load():
    """Load model into VRAM. Blocking — run in executor."""
    global tts_model, _model_loaded, SAMPLE_RATE
    from faster_qwen3_tts import FasterQwen3TTS
    logger.info("Loading model %s on %s ...", _model_id, _model_device)
    tts_model = FasterQwen3TTS.from_pretrained(
        _model_id,
        device=_model_device,
        dtype=_model_dtype,
    )
    SAMPLE_RATE = tts_model.sample_rate
    _model_loaded = True
    logger.info("Model loaded. Sample rate: %d Hz", SAMPLE_RATE)


def _do_unload():
    """Delete model object and free VRAM. Blocking — run in executor."""
    global tts_model, _model_loaded
    if tts_model is None:
        return
    logger.info("Unloading model from VRAM ...")
    with _model_lock:
        del tts_model
        tts_model = None
    gc.collect()
    if torch.cuda.is_available():
        torch.cuda.empty_cache()
    _model_loaded = False
    logger.info("VRAM freed.")


async def _ensure_loaded():
    """Auto-load before serving a request if model was unloaded."""
    if _model_loaded and tts_model is not None:
        return
    async with _load_lock:
        if _model_loaded and tts_model is not None:
            return
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, _do_load)


# ---------------------------------------------------------------------------
# Voice resolution
# ---------------------------------------------------------------------------


def resolve_voice(voice_name: str) -> dict:
    if voice_name in voices:
        return voices[voice_name]
    if default_voice and default_voice in voices:
        logger.warning("Voice %r not found, using default %r", voice_name, default_voice)
        return voices[default_voice]
    raise HTTPException(
        status_code=400,
        detail=f"Voice {voice_name!r} not configured. Available: {list(voices.keys())}",
    )


# ---------------------------------------------------------------------------
# Streaming generation
# ---------------------------------------------------------------------------


async def _stream_chunks(voice_cfg: dict, text: str) -> AsyncGenerator[bytes, None]:
    q: queue.Queue = queue.Queue()
    _DONE = object()

    def producer():
        try:
            with _model_lock:
                for chunk, _sr, _timing in tts_model.generate_voice_clone_streaming(
                    text=text,
                    language=voice_cfg.get("language", "Auto"),
                    ref_audio=voice_cfg["ref_audio"],
                    ref_text=voice_cfg.get("ref_text", ""),
                    chunk_size=voice_cfg.get("chunk_size", 12),
                    non_streaming_mode=False,
                ):
                    q.put(chunk)
        except Exception as exc:
            q.put(exc)
        finally:
            q.put(_DONE)

    thread = threading.Thread(target=producer, daemon=True)
    thread.start()

    loop = asyncio.get_event_loop()
    while True:
        item = await loop.run_in_executor(None, q.get)
        if item is _DONE:
            break
        if isinstance(item, Exception):
            raise item
        yield _to_pcm16(item)


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@app.get("/health")
async def health():
    vram_mb = None
    if torch.cuda.is_available():
        vram_mb = round(torch.cuda.memory_allocated() / 1024 / 1024, 1)
    return {"status": "ok", "model_loaded": _model_loaded, "vram_allocated_mb": vram_mb}


@app.post("/unload")
async def unload():
    """Release model from VRAM. Auto-reloads on next TTS request."""
    async with _load_lock:
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, _do_unload)
    return {"status": "unloaded"}


@app.post("/load")
async def load():
    """Pre-load model into VRAM (also happens automatically on first TTS request)."""
    await _ensure_loaded()
    return {"status": "loaded"}


@app.post("/v1/audio/speech")
async def create_speech(req: SpeechRequest):
    if not req.input.strip():
        raise HTTPException(status_code=400, detail="'input' text is empty")

    await _ensure_loaded()

    voice_cfg = resolve_voice(req.voice)
    fmt = req.response_format.lower()

    _CONTENT_TYPES = {"wav": "audio/wav", "pcm": "audio/pcm", "mp3": "audio/mpeg"}
    if fmt not in _CONTENT_TYPES:
        raise HTTPException(status_code=400, detail=f"response_format {fmt!r} not supported. Use: wav, pcm, mp3")
    content_type = _CONTENT_TYPES[fmt]

    if fmt == "mp3":
        loop = asyncio.get_event_loop()

        def _generate():
            with _model_lock:
                return tts_model.generate_voice_clone(
                    text=req.input,
                    language=voice_cfg.get("language", "Auto"),
                    ref_audio=voice_cfg["ref_audio"],
                    ref_text=voice_cfg.get("ref_text", ""),
                )

        audio_arrays, sr = await loop.run_in_executor(None, _generate)
        audio = audio_arrays[0] if audio_arrays else np.zeros(1, dtype=np.float32)
        return Response(content=_to_mp3_bytes(audio, sr), media_type=content_type)

    async def audio_stream():
        if fmt == "wav":
            yield _wav_header(SAMPLE_RATE)
        async for raw_chunk in _stream_chunks(voice_cfg, req.input):
            yield raw_chunk

    return StreamingResponse(audio_stream(), media_type=content_type)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def _parse_args():
    p = argparse.ArgumentParser(description="OpenAI-compatible TTS server for faster-qwen3-tts")
    p.add_argument("--model", default=os.environ.get("QWEN_TTS_MODEL", "Qwen/Qwen3-TTS-12Hz-1.7B-Base"))
    p.add_argument("--voices", default=os.environ.get("QWEN_TTS_VOICES"), metavar="FILE")
    p.add_argument("--ref-audio", default=os.environ.get("QWEN_TTS_REF_AUDIO"), metavar="FILE")
    p.add_argument("--ref-text", default=os.environ.get("QWEN_TTS_REF_TEXT", ""))
    p.add_argument("--language", default=os.environ.get("QWEN_TTS_LANGUAGE", "Auto"))
    p.add_argument("--host", default="0.0.0.0")
    p.add_argument("--port", type=int, default=8000)
    p.add_argument("--device", default="cuda")
    return p.parse_args()


def main():
    global voices, default_voice, _model_id, _model_dtype, _model_device

    args = _parse_args()
    _model_id = args.model
    _model_dtype = torch.bfloat16
    _model_device = args.device

    if args.voices:
        with open(args.voices) as f:
            voices = json.load(f)
        default_voice = next(iter(voices))
        logger.info("Loaded %d voice(s) from %s", len(voices), args.voices)
    elif args.ref_audio:
        voices = {"default": {"ref_audio": args.ref_audio, "ref_text": args.ref_text, "language": args.language}}
        default_voice = "default"
    else:
        print("ERROR: provide --ref-audio <file> or --voices <config.json>", file=sys.stderr)
        sys.exit(1)

    _do_load()

    logger.info("Server listening on http://%s:%d", args.host, args.port)
    uvicorn.run(app, host=args.host, port=args.port)


if __name__ == "__main__":
    main()
