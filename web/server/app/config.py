"""Runtime configuration, read from the environment at call time (testable via env)."""

from __future__ import annotations

import os
import sys
from pathlib import Path


def models_dir() -> Path:
    """Directory holding the GGML/GGUF model files.

    Env ``MODELS_DIR`` wins. Local default mirrors the Mac app so the models
    already downloaded by Mintzo.app are reused as-is; elsewhere (Linux/Modal)
    the default is a cache dir typically mounted as a volume.
    """
    if env := os.environ.get("MODELS_DIR"):
        return Path(env).expanduser()
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "Mintzo" / "Models"
    return Path.home() / ".cache" / "mintzo" / "models"


def whisper_cli() -> str:
    return os.environ.get("WHISPER_CLI", "whisper-cli")


def llama_server_bin() -> str:
    return os.environ.get("LLAMA_SERVER", "llama-server")


def ffmpeg_bin() -> str:
    return os.environ.get("FFMPEG", "ffmpeg")


def llama_port() -> int:
    return int(os.environ.get("LLAMA_PORT", "8089"))


def llama_ctx_size() -> int:
    """Context size in tokens — same default as the Mac app LlamaEngine (4096)."""
    return int(os.environ.get("LLAMA_CTX", "4096"))


def max_upload_bytes() -> int:
    """Upload cap: 50 MB per ADR-002."""
    return int(os.environ.get("MAX_UPLOAD_BYTES", str(50 * 1024 * 1024)))


def asr_timeout_s() -> float:
    return float(os.environ.get("ASR_TIMEOUT_S", "900"))


def correction_timeout_s() -> float:
    return float(os.environ.get("CORRECTION_TIMEOUT_S", "180"))


def cors_origins() -> list[str]:
    """Comma-separated allowed origins; default ``*`` (open, per ADR-002 early phase)."""
    raw = os.environ.get("CORS_ORIGINS", "*")
    return [origin.strip() for origin in raw.split(",") if origin.strip()]


def n_threads() -> int:
    """Same clamp as the Mac app engines: min(8, active cores), at least 1."""
    return max(1, min(8, os.cpu_count() or 4))
