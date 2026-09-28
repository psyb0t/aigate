#!/usr/bin/env python3
"""Fetch the exact GGUF artifacts declared by llama.cpp model registries."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import logging
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path, PurePosixPath
from typing import Any, Sequence


_ARTIFACT_KEYS = (("gguf_file", "gguf_sha256"), ("mmproj_file", "mmproj_sha256"))
_CHUNK_SIZE_BYTES = 1024 * 1024
_LOCK_FILENAME = ".pull.lock"
_REPOSITORY_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$")
_REVISION_PATTERN = re.compile(r"^[0-9a-f]{40}$")
_SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
_DOWNLOADER_COMMAND = "huggingface-cli"


class ModelPullError(RuntimeError):
    """Raised when a registry entry or downloaded artifact is unsafe or invalid."""


@dataclass(frozen=True)
class Artifact:
    """One immutable Hugging Face artifact selected for the local model store."""

    repository: str
    revision: str
    filename: str
    sha256: str

    @property
    def destination_suffix(self) -> Path:
        return Path(*self.repository.split("/"), *PurePosixPath(self.filename).parts)

    @property
    def identity(self) -> tuple[str, str]:
        return self.repository, self.filename


class JsonFormatter(logging.Formatter):
    """Emit bounded structured logs to the sidecar's Docker-managed log stream."""

    _EXTRA_FIELDS = ("artifact_count", "artifact_filename", "error", "repository")

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, object] = {
            "time": datetime.now(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
            "level": record.levelname,
            "file": record.filename,
            "line": record.lineno,
            "func": record.funcName,
            "msg": record.getMessage(),
        }
        for field in self._EXTRA_FIELDS:
            value = getattr(record, field, None)
            if value is not None:
                payload[field] = value
        return json.dumps(payload, sort_keys=True)


def configure_logging() -> logging.Logger:
    """Configure diagnostics for the short-lived pull sidecar."""
    logger = logging.getLogger("llamacpp_pull")
    logger.setLevel(logging.INFO)
    handler = logging.StreamHandler(sys.stderr)
    handler.setFormatter(JsonFormatter())
    logger.handlers.clear()
    logger.addHandler(handler)
    logger.propagate = False
    return logger


def parse_args(arguments: Sequence[str]) -> argparse.Namespace:
    """Parse explicit registry inputs and the host-visible model root."""
    parser = argparse.ArgumentParser(description="Download checksum-pinned llama.cpp model artifacts.")
    parser.add_argument(
        "--registry",
        action="append",
        type=Path,
        required=True,
        help="Model registry JSON file. May be supplied more than once.",
    )
    parser.add_argument(
        "--model-root",
        type=Path,
        default=Path("/data/models"),
        help="Root of the flat local artifact store.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the selected immutable artifacts as JSON lines without downloading.",
    )
    return parser.parse_args(arguments)


def require_string(entry: dict[str, Any], key: str, context: str) -> str:
    """Return a non-empty string registry field or fail before any download."""
    value = entry.get(key)
    if not isinstance(value, str) or not value:
        raise ModelPullError(f"{context}: missing non-empty string {key!r}")
    return value


def validate_repository(repository: str, context: str) -> None:
    """Allow one Hugging Face namespace and repository without traversal syntax."""
    if not _REPOSITORY_PATTERN.fullmatch(repository):
        raise ModelPullError(f"{context}: unsafe repository {repository!r}")


def validate_revision(revision: str, context: str) -> None:
    """Require an immutable full commit hash, never a mutable branch or tag."""
    if not _REVISION_PATTERN.fullmatch(revision):
        raise ModelPullError(f"{context}: revision must be a 40-character lowercase commit hash")


def validate_filename(filename: str, context: str) -> None:
    """Reject paths that could escape the repository-specific model directory."""
    path = PurePosixPath(filename)
    invalid_path = filename.startswith("/") or "\\" in filename or any(
        part in {"", ".", ".."} for part in path.parts
    )
    if invalid_path:
        raise ModelPullError(f"{context}: unsafe artifact filename {filename!r}")


def validate_sha256(digest: str, context: str) -> None:
    """Require the registry to pin an artifact by its complete SHA-256 digest."""
    if not _SHA256_PATTERN.fullmatch(digest):
        raise ModelPullError(f"{context}: SHA-256 must be 64 lowercase hexadecimal characters")


def artifacts_from_registry(registry_path: Path) -> list[Artifact]:
    """Read every declared GGUF and multimodal projection artifact safely."""
    try:
        raw = json.loads(registry_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ModelPullError(f"cannot read registry {registry_path}: {error}") from error
    if not isinstance(raw, dict) or not isinstance(raw.get("models"), dict):
        raise ModelPullError(f"{registry_path}: expected an object with a models object")

    artifacts: list[Artifact] = []
    for model_id, entry in raw["models"].items():
        context = f"{registry_path}:{model_id}"
        if not isinstance(model_id, str) or not isinstance(entry, dict):
            raise ModelPullError(f"{context}: model entries must be objects keyed by a string")
        repository = require_string(entry, "repo", context)
        revision = require_string(entry, "revision", context)
        validate_repository(repository, context)
        validate_revision(revision, context)
        for filename_key, digest_key in _ARTIFACT_KEYS:
            filename = entry.get(filename_key)
            digest = entry.get(digest_key)
            if filename is None and digest is None:
                continue
            if not isinstance(filename, str) or not filename:
                raise ModelPullError(f"{context}: {filename_key} must be a non-empty string")
            if not isinstance(digest, str) or not digest:
                raise ModelPullError(f"{context}: {digest_key} must be a non-empty string")
            validate_filename(filename, context)
            validate_sha256(digest, context)
            artifacts.append(Artifact(repository, revision, filename, digest))
    return artifacts


def collect_artifacts(registries: Sequence[Path]) -> list[Artifact]:
    """Combine registries while rejecting conflicting pins for the same output file."""
    unique: dict[tuple[str, str], Artifact] = {}
    for registry in registries:
        for artifact in artifacts_from_registry(registry):
            existing = unique.get(artifact.identity)
            if existing is None:
                unique[artifact.identity] = artifact
                continue
            if existing != artifact:
                raise ModelPullError(
                    "conflicting immutable pins for "
                    f"{artifact.repository}/{artifact.filename}"
                )
    return sorted(unique.values(), key=lambda artifact: (artifact.repository, artifact.filename))


def file_sha256(path: Path) -> str:
    """Hash a local artifact incrementally without loading model weights into memory."""
    digest = hashlib.sha256()
    with path.open("rb") as artifact_file:
        while chunk := artifact_file.read(_CHUNK_SIZE_BYTES):
            digest.update(chunk)
    return digest.hexdigest()


def verify_artifact(artifact: Artifact, destination: Path) -> None:
    """Fail closed when a local or freshly downloaded file does not match its pin."""
    actual = file_sha256(destination)
    if actual != artifact.sha256:
        raise ModelPullError(
            f"SHA-256 mismatch for {artifact.repository}/{artifact.filename}: "
            f"expected {artifact.sha256}, got {actual}"
        )


def download_artifact(artifact: Artifact, model_root: Path, logger: logging.Logger) -> None:
    """Download one declared file, or validate the already-present immutable copy."""
    destination = model_root / artifact.destination_suffix
    if destination.exists():
        verify_artifact(artifact, destination)
        logger.info(
            "artifact already verified",
            extra={
                "repository": artifact.repository,
                "artifact_filename": artifact.filename,
            },
        )
        return

    destination.parent.mkdir(parents=True, exist_ok=True)
    logger.info(
        "downloading artifact",
        extra={
            "repository": artifact.repository,
            "artifact_filename": artifact.filename,
        },
    )
    try:
        subprocess.run(
            [
                _DOWNLOADER_COMMAND,
                "download",
                "--quiet",
                "--max-workers",
                "1",
                "--local-dir",
                str(destination.parent),
                "--revision",
                artifact.revision,
                artifact.repository,
                artifact.filename,
            ],
            check=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise ModelPullError(
            f"download failed for {artifact.repository}/{artifact.filename}: {error}"
        ) from error
    if not destination.is_file():
        raise ModelPullError(
            f"downloader did not create {artifact.repository}/{artifact.filename}"
        )
    verify_artifact(artifact, destination)
    logger.info(
        "artifact verified",
        extra={
            "repository": artifact.repository,
            "artifact_filename": artifact.filename,
        },
    )


def pull_artifacts(artifacts: Sequence[Artifact], model_root: Path, logger: logging.Logger) -> None:
    """Serialize shared-store writers so CPU and CUDA pull jobs cannot race."""
    model_root.mkdir(parents=True, exist_ok=True)
    lock_path = model_root / _LOCK_FILENAME
    with lock_path.open("a", encoding="utf-8") as lock_file:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        try:
            for artifact in artifacts:
                download_artifact(artifact, model_root, logger)
        finally:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)


def emit_dry_run(artifacts: Sequence[Artifact]) -> None:
    """Print the bounded machine-readable artifact plan for tests and review."""
    for artifact in artifacts:
        print(
            json.dumps(
                {
                    "filename": artifact.filename,
                    "repo": artifact.repository,
                    "revision": artifact.revision,
                    "sha256": artifact.sha256,
                },
                sort_keys=True,
            )
        )


def main(arguments: Sequence[str] | None = None) -> int:
    """Run the model pull plan and return a process status code."""
    args = parse_args(arguments if arguments is not None else sys.argv[1:])
    logger = configure_logging()
    try:
        artifacts = collect_artifacts(args.registry)
        if args.dry_run:
            emit_dry_run(artifacts)
            return 0
        pull_artifacts(artifacts, args.model_root, logger)
    except ModelPullError as error:
        logger.error("model pull failed", extra={"error": str(error)})
        return 1
    logger.info("model pull completed", extra={"artifact_count": len(artifacts)})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
