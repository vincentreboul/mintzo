"""Model catalogue + boot-time download with sha256 verification.

Ported verbatim from the Swift sources of truth (2026-07-03):
- ``Sources/MintzoCore/Models/ModelCatalog.swift`` (Whisper GGML models)
- ``Sources/MintzoCore/Correction/LatxaCatalog.swift`` (Latxa GGUF)

URLs are the Hugging Face ``resolve/main`` endpoints; sha256 values are the
``lfs.oid`` returned by the HF tree API — authoritative. File names follow the
same conventions as the Mac app (``<id>.bin`` for Whisper models, URL last path
component for GGUF), so a MODELS_DIR pointed at the Mac app's Models directory
reuses the already-downloaded files byte-for-byte.
"""

from __future__ import annotations

import hashlib
import logging
import os
import shutil
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from . import config

logger = logging.getLogger("mintzo.models")

Role = Literal["basque", "french", "testing", "correction"]


@dataclass(frozen=True)
class ModelSpec:
    id: str
    display_name: str
    download_url: str
    size_bytes: int
    sha256: str
    role: Role
    file_name: str


# Whisper large-v3 fine-tuned Basque (xezpeleta/whisper-large-v3-eu), ~3.1 GB.
WHISPER_EU = ModelSpec(
    id="whisper-eu",
    display_name="Whisper Large v3 — Euskara",
    download_url="https://huggingface.co/xezpeleta/whisper-large-v3-eu/resolve/main/ggml-large-v3.eu.bin",
    size_bytes=3_095_033_483,
    sha256="dae98a83f5450d1a26632430649633842f0b6e535c246baa5b46b962bedf8cab",
    role="basque",
    file_name="whisper-eu.bin",
)

# Whisper large-v3-turbo multilingual (ggerganov/whisper.cpp), ~1.6 GB.
WHISPER_FR = ModelSpec(
    id="whisper-fr",
    display_name="Whisper Large v3 Turbo — Français",
    download_url="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin",
    size_bytes=1_624_555_275,
    sha256="1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69",
    role="french",
    file_name="whisper-fr.bin",
)

# Whisper tiny multilingual (~75 MB) — automated tests only.
WHISPER_TINY = ModelSpec(
    id="whisper-tiny",
    display_name="Whisper Tiny (tests)",
    download_url="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin",
    size_bytes=77_691_713,
    sha256="be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21",
    role="testing",
    file_name="whisper-tiny.bin",
)

# Correction model: Latxa-Qwen3-VL-4B-Instruct Q4_K_M (mradermacher quant of
# HiTZ/Latxa-Qwen3-VL-4B-Instruct, Apache 2.0), ~2.5 GB. Text-only use: the
# mmproj vision projector is intentionally NOT downloaded.
LATXA = ModelSpec(
    id="latxa-qwen3-vl-4b-instruct-q4_k_m",
    display_name="Latxa Qwen3-VL 4B Instruct (Q4_K_M)",
    download_url="https://huggingface.co/mradermacher/Latxa-Qwen3-VL-4B-Instruct-GGUF/resolve/main/Latxa-Qwen3-VL-4B-Instruct.Q4_K_M.gguf",
    size_bytes=2_497_282_176,
    sha256="3eae629d2714189689aa8de1b1d7cfdf8ec846c405b26e4faeeb1fdfa3b4f26b",
    role="correction",
    file_name="Latxa-Qwen3-VL-4B-Instruct.Q4_K_M.gguf",
)

ALL: tuple[ModelSpec, ...] = (WHISPER_EU, WHISPER_FR, WHISPER_TINY, LATXA)

#: Models the server needs at runtime (tiny is test-only, never downloaded at boot).
REQUIRED: tuple[ModelSpec, ...] = (WHISPER_EU, WHISPER_FR, LATXA)

#: Request language -> ASR model.
ASR_BY_LANGUAGE: dict[str, ModelSpec] = {"eu": WHISPER_EU, "fr": WHISPER_FR}


class ModelIntegrityError(RuntimeError):
    """Downloaded/present file does not match the catalogue size or sha256."""


def model_path(spec: ModelSpec, directory: Path | None = None) -> Path:
    return (directory or config.models_dir()) / spec.file_name


def sha256_file(path: Path, chunk_size: int = 8 * 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        while chunk := fh.read(chunk_size):
            digest.update(chunk)
    return digest.hexdigest()


def _marker_path(path: Path) -> Path:
    return path.with_name(path.name + ".sha256-verified")


def _verify(spec: ModelSpec, path: Path) -> None:
    """Full integrity check: exact size then sha256. Raises on mismatch."""
    actual_size = path.stat().st_size
    if actual_size != spec.size_bytes:
        raise ModelIntegrityError(
            f"{spec.id}: size mismatch — expected {spec.size_bytes}, got {actual_size}"
        )
    actual_sha = sha256_file(path)
    if actual_sha != spec.sha256:
        raise ModelIntegrityError(
            f"{spec.id}: sha256 mismatch — expected {spec.sha256}, got {actual_sha}"
        )


def _download(spec: ModelSpec, destination: Path, chunk_size: int = 8 * 1024 * 1024) -> None:
    """Stream the model to ``<destination>.part`` (hashing on the fly), verify, rename."""
    part = destination.with_name(destination.name + ".part")
    digest = hashlib.sha256()
    written = 0
    logger.info("downloading %s (%d bytes) from %s", spec.id, spec.size_bytes, spec.download_url)
    request = urllib.request.Request(spec.download_url, headers={"User-Agent": "mintzo-server/0.1"})
    with urllib.request.urlopen(request) as response, part.open("wb") as out:
        while chunk := response.read(chunk_size):
            digest.update(chunk)
            out.write(chunk)
            written += len(chunk)
    if written != spec.size_bytes:
        part.unlink(missing_ok=True)
        raise ModelIntegrityError(
            f"{spec.id}: downloaded {written} bytes, expected {spec.size_bytes}"
        )
    if digest.hexdigest() != spec.sha256:
        part.unlink(missing_ok=True)
        raise ModelIntegrityError(
            f"{spec.id}: downloaded sha256 {digest.hexdigest()} != expected {spec.sha256}"
        )
    part.replace(destination)


def ensure_model(spec: ModelSpec, directory: Path | None = None) -> Path:
    """Make sure the model file is present and verified; download it if absent.

    A ``<file>.sha256-verified`` marker (containing the hash) is written after a
    successful full check so subsequent boots only re-check the size — hashing
    ~7 GB at every restart would be pointless. Delete the markers (or the files)
    to force a full re-verification.
    """
    directory = directory or config.models_dir()
    directory.mkdir(parents=True, exist_ok=True)
    path = model_path(spec, directory)
    marker = _marker_path(path)

    if not path.exists():
        free = shutil.disk_usage(directory).free
        if free < spec.size_bytes:
            raise ModelIntegrityError(
                f"{spec.id}: not enough disk space ({free} free, {spec.size_bytes} needed)"
            )
        _download(spec, path)
        marker.write_text(spec.sha256 + "\n")
        logger.info("downloaded and verified %s -> %s", spec.id, path)
        return path

    if path.stat().st_size != spec.size_bytes:
        raise ModelIntegrityError(
            f"{spec.id}: existing file has wrong size "
            f"({path.stat().st_size} != {spec.size_bytes}) — delete {path} to re-download"
        )
    if not (marker.exists() and marker.read_text().strip() == spec.sha256):
        logger.info("verifying sha256 of existing %s (one-time)", path.name)
        _verify(spec, path)
        marker.write_text(spec.sha256 + "\n")
    return path


def ensure_required(directory: Path | None = None) -> dict[str, Path]:
    """Boot-time hook: ensure every runtime model, return id -> path."""
    return {spec.id: ensure_model(spec, directory) for spec in REQUIRED}


def status(directory: Path | None = None) -> dict[str, bool]:
    """Presence (correct size) of the runtime models, keyed for /v1/health."""
    directory = directory or config.models_dir()

    def ok(spec: ModelSpec) -> bool:
        path = model_path(spec, directory)
        return path.exists() and path.stat().st_size == spec.size_bytes

    return {"eu": ok(WHISPER_EU), "fr": ok(WHISPER_FR), "latxa": ok(LATXA)}


def skip_ensure() -> bool:
    """Env escape hatch for tests/CI without 7 GB of models."""
    return os.environ.get("MINTZO_SKIP_ENSURE", "0") == "1"
