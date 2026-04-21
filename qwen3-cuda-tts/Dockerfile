FROM nvidia/cuda:12.6.3-cudnn-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV TORCHINDUCTOR_CACHE_DIR=/tmp/torch_inductor
ENV HF_HOME=/data

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip libsndfile1 ffmpeg sox \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m pip install --upgrade pip --quiet \
    && python3 -m pip install --quiet \
        --index-url https://download.pytorch.org/whl/cu126 \
        torch torchaudio \
    && python3 -m pip install --quiet "faster-qwen3-tts[demo]"

WORKDIR /app
COPY openai_server.py voices.json ref_audio.wav ref_audio_2.wav ref_audio_3.wav ./

EXPOSE 8000
CMD ["python3", "openai_server.py", "--voices", "voices.json"]
