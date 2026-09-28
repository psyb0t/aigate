#!/usr/bin/env python3
"""Black-box tests for the llamacpp model-pull sidecar command."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_DIR = Path(__file__).resolve().parents[2]
PULL_MODELS = REPOSITORY_DIR / "llamacpp" / "pull_models.py"
PRODUCTION_CPU_REGISTRY = REPOSITORY_DIR / "llamacpp" / "models.cpu.json"
PRODUCTION_CUDA_REGISTRY = REPOSITORY_DIR / "llamacpp" / "models.cuda.json"
QWEN3_Q8_FILENAME = "Qwen3-8B-Q8_0.gguf"
QWEN3_Q8_REPOSITORY = "ggml-org/Qwen3-8B-GGUF"


def sha256(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def registry_entry(
    *,
    repository: str,
    revision: str,
    filename: str,
    digest: str,
    mmproj_filename: str | None = None,
    mmproj_digest: str | None = None,
) -> dict[str, object]:
    model: dict[str, str] = {
        "repo": repository,
        "revision": revision,
        "gguf_file": filename,
        "gguf_sha256": digest,
    }
    if mmproj_filename is not None:
        model["mmproj_file"] = mmproj_filename
    if mmproj_digest is not None:
        model["mmproj_sha256"] = mmproj_digest
    return {"models": {"test-model": model}}


class PullModelsTest(unittest.TestCase):
    def write_registry(
        self,
        directory: Path,
        name: str,
        content: dict[str, object],
    ) -> Path:
        path = directory / name
        path.write_text(json.dumps(content), encoding="utf-8")
        return path

    def write_downloader(self, directory: Path) -> Path:
        downloader = directory / "huggingface-cli"
        downloader.write_text(
            """#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

args = sys.argv[1:]
with Path(os.environ[\"TEST_DOWNLOAD_LOG\"]).open(\"a\", encoding=\"utf-8\") as handle:
    handle.write(json.dumps(args) + \"\\n\")

local_dir = Path(args[args.index(\"--local-dir\") + 1])
filename = args[-1]
destination = local_dir / filename
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_bytes(os.environ[\"TEST_ARTIFACT_CONTENT\"].encode(\"utf-8\"))
""",
            encoding="utf-8",
        )
        downloader.chmod(0o755)
        return downloader

    def run_pull(
        self,
        *,
        registries: list[Path],
        model_root: Path,
        environment: dict[str, str],
        dry_run: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        command = [
            "python3",
            str(PULL_MODELS),
            "--model-root",
            str(model_root),
        ]
        for registry in registries:
            command.extend(("--registry", str(registry)))
        if dry_run:
            command.append("--dry-run")
        return subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            env={**os.environ, **environment},
        )

    def test_downloads_exact_artifact_and_verifies_checksum(self) -> None:
        content = b"the requested artifact only"
        revision = "a" * 40
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            registry = self.write_registry(
                temporary,
                "registry.json",
                registry_entry(
                    repository="owner/model",
                    revision=revision,
                    filename="weights.gguf",
                    digest=sha256(content),
                ),
            )
            downloader = self.write_downloader(temporary)
            command_log = temporary / "download-commands.jsonl"
            result = self.run_pull(
                registries=[registry],
                model_root=temporary / "models",
                environment={
                    "PATH": f"{temporary}:{os.environ['PATH']}",
                    "TEST_ARTIFACT_CONTENT": content.decode(),
                    "TEST_DOWNLOAD_LOG": str(command_log),
                },
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                json.loads(command_log.read_text(encoding="utf-8")),
                [
                    "download",
                    "--quiet",
                    "--max-workers",
                    "1",
                    "--local-dir",
                    str(temporary / "models" / "owner" / "model"),
                    "--revision",
                    revision,
                    "owner/model",
                    "weights.gguf",
                ],
            )
            self.assertEqual(
                (temporary / "models" / "owner" / "model" / "weights.gguf").read_bytes(),
                content,
            )
            self.assertEqual(downloader.name, "huggingface-cli")

    def test_deduplicates_identical_artifacts_across_registries(self) -> None:
        content = b"deduplicated artifact"
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            entry = registry_entry(
                repository="owner/model",
                revision="b" * 40,
                filename="weights.gguf",
                digest=sha256(content),
            )
            first = self.write_registry(temporary, "first.json", entry)
            second = self.write_registry(temporary, "second.json", entry)
            self.write_downloader(temporary)
            command_log = temporary / "download-commands.jsonl"
            result = self.run_pull(
                registries=[first, second],
                model_root=temporary / "models",
                environment={
                    "PATH": f"{temporary}:{os.environ['PATH']}",
                    "TEST_ARTIFACT_CONTENT": content.decode(),
                    "TEST_DOWNLOAD_LOG": str(command_log),
                },
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(command_log.read_text(encoding="utf-8").splitlines()), 1)

    def test_downloads_declared_multimodal_projection(self) -> None:
        content = b"projection artifact"
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            registry = self.write_registry(
                temporary,
                "registry.json",
                registry_entry(
                    repository="owner/model",
                    revision="f" * 40,
                    filename="weights.gguf",
                    digest=sha256(content),
                    mmproj_filename="projection.gguf",
                    mmproj_digest=sha256(content),
                ),
            )
            self.write_downloader(temporary)
            command_log = temporary / "download-commands.jsonl"
            result = self.run_pull(
                registries=[registry],
                model_root=temporary / "models",
                environment={
                    "PATH": f"{temporary}:{os.environ['PATH']}",
                    "TEST_ARTIFACT_CONTENT": content.decode(),
                    "TEST_DOWNLOAD_LOG": str(command_log),
                },
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(command_log.read_text(encoding="utf-8").splitlines()), 2)
            self.assertEqual(
                (temporary / "models" / "owner" / "model" / "projection.gguf").read_bytes(),
                content,
            )

    def test_rejects_path_traversal_before_downloader_runs(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            registry = self.write_registry(
                temporary,
                "registry.json",
                registry_entry(
                    repository="owner/model",
                    revision="c" * 40,
                    filename="../outside.gguf",
                    digest="d" * 64,
                ),
            )
            self.write_downloader(temporary)
            command_log = temporary / "download-commands.jsonl"
            result = self.run_pull(
                registries=[registry],
                model_root=temporary / "models",
                environment={
                    "PATH": f"{temporary}:{os.environ['PATH']}",
                    "TEST_ARTIFACT_CONTENT": "ignored",
                    "TEST_DOWNLOAD_LOG": str(command_log),
                },
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unsafe artifact filename", result.stderr)
            self.assertFalse(command_log.exists())

    def test_rejects_checksum_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            registry = self.write_registry(
                temporary,
                "registry.json",
                registry_entry(
                    repository="owner/model",
                    revision="e" * 40,
                    filename="weights.gguf",
                    digest=sha256(b"expected"),
                ),
            )
            self.write_downloader(temporary)
            command_log = temporary / "download-commands.jsonl"
            result = self.run_pull(
                registries=[registry],
                model_root=temporary / "models",
                environment={
                    "PATH": f"{temporary}:{os.environ['PATH']}",
                    "TEST_ARTIFACT_CONTENT": "tampered",
                    "TEST_DOWNLOAD_LOG": str(command_log),
                },
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("SHA-256 mismatch", result.stderr)
            self.assertTrue(command_log.exists())

    def test_production_registry_dry_run_lists_qwen_encoder_once(self) -> None:
        result = self.run_pull(
            registries=[PRODUCTION_CPU_REGISTRY, PRODUCTION_CUDA_REGISTRY],
            model_root=Path("/unused"),
            environment={},
            dry_run=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        artifacts = [json.loads(line) for line in result.stdout.splitlines()]
        qwen_artifacts = [
            artifact
            for artifact in artifacts
            if artifact["repo"] == QWEN3_Q8_REPOSITORY
        ]
        self.assertEqual(len(qwen_artifacts), 1)
        self.assertEqual(qwen_artifacts[0]["filename"], QWEN3_Q8_FILENAME)


if __name__ == "__main__":
    unittest.main()
