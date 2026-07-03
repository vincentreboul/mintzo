"""Transcription pipeline: decode (ffmpeg) → transcribe (whisper-cli) → correct (Latxa).

Engine invocations mirror the Mac app (ADR-001 — same binaries family, same
models, same parameters):
- whisper: greedy sampling (``WHISPER_SAMPLING_GREEDY`` in Swift → ``-bs 1``),
  ``no_timestamps``, forced language, threads clamped to min(8, cores);
- correction: greedy/temperature 0 via the resident llama-server (chat template
  from the GGUF), prompt from :mod:`app.prompts`, guardrails from
  :mod:`app.guardrails`, raw-text fallback with a reason — the user's dictation
  is never lost nor degraded.
"""

from __future__ import annotations

import dataclasses
import logging
import subprocess
import wave
from pathlib import Path
from typing import Callable, Protocol

from . import config, guardrails, models, prompts
from .guardrails import FallbackReason

logger = logging.getLogger("mintzo.pipeline")

LANGUAGES: tuple[str, ...] = ("eu", "fr")

#: Formats accepted by /v1/transcribe (WhatsApp voice notes are .opus).
ALLOWED_EXTENSIONS: frozenset[str] = frozenset(
    {".opus", ".m4a", ".mp3", ".wav", ".aac", ".ogg", ".flac"}
)


class PipelineError(RuntimeError):
    """Base class — maps to HTTP 500 unless a subclass says otherwise."""


class UnsupportedFormatError(PipelineError):
    """File extension not in ALLOWED_EXTENSIONS (HTTP 415)."""


class DecodeError(PipelineError):
    """ffmpeg could not decode the file (corrupt/mislabeled audio, HTTP 415)."""


class TranscriptionError(PipelineError):
    """whisper-cli failed (HTTP 500)."""


@dataclasses.dataclass(frozen=True)
class DecodedAudio:
    path: Path
    duration_seconds: float


@dataclasses.dataclass(frozen=True)
class CorrectionOutcome:
    """Result of the guarded correction pass (port of Swift ``CorrectionResult``)."""

    text: str
    #: "corrected" | "unchanged" | "fallbackRaw"
    outcome: str
    fallback_reason: FallbackReason | None = None


class Corrector(Protocol):
    """One correction pass returning the RAW engine output (guardrails on top)."""

    def __call__(self, text: str, language: str) -> str: ...


# -- decode -------------------------------------------------------------------


def decode(source: Path, work_dir: Path) -> DecodedAudio:
    """Decode any accepted container to 16 kHz mono s16 WAV (whisper input format)."""
    extension = source.suffix.lower()
    if extension not in ALLOWED_EXTENSIONS:
        raise UnsupportedFormatError(
            f"unsupported format {extension or '(none)'} — accepted: "
            + ", ".join(sorted(ALLOWED_EXTENSIONS))
        )

    target = work_dir / "decoded.wav"
    command = [
        config.ffmpeg_bin(),
        "-hide_banner", "-nostdin", "-y",
        "-i", str(source),
        "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
        str(target),
    ]
    try:
        result = subprocess.run(
            command, capture_output=True, timeout=config.asr_timeout_s()
        )
    except subprocess.TimeoutExpired as error:
        raise DecodeError("ffmpeg timed out") from error
    except FileNotFoundError as error:
        raise PipelineError(f"ffmpeg binary not found: {config.ffmpeg_bin()}") from error
    if result.returncode != 0:
        stderr = result.stderr.decode("utf-8", errors="replace").strip()
        logger.warning("ffmpeg failed (rc=%d): %s", result.returncode, stderr[-500:])
        raise DecodeError("audio could not be decoded — corrupt or unsupported file")

    with wave.open(str(target), "rb") as wav:
        frames = wav.getnframes()
        rate = wav.getframerate() or 16000
    return DecodedAudio(path=target, duration_seconds=frames / rate)


# -- transcribe -----------------------------------------------------------------


def transcribe(wav_path: Path, language: str, models_directory: Path | None = None) -> str:
    """Run whisper-cli on a decoded WAV. Greedy, no timestamps, forced language."""
    if language not in models.ASR_BY_LANGUAGE:
        raise PipelineError(f"unsupported language: {language}")
    model_file = models.model_path(models.ASR_BY_LANGUAGE[language], models_directory)
    if not model_file.exists():
        raise TranscriptionError(f"ASR model missing: {model_file}")

    command = [
        config.whisper_cli(),
        "-m", str(model_file),
        "-f", str(wav_path),
        "-l", language,
        "--no-timestamps",
        "--no-prints",
        "-bs", "1",  # greedy — same sampling strategy as the Mac app engine
        "-t", str(config.n_threads()),
    ]
    try:
        result = subprocess.run(
            command, capture_output=True, timeout=config.asr_timeout_s()
        )
    except subprocess.TimeoutExpired as error:
        raise TranscriptionError("whisper-cli timed out") from error
    except FileNotFoundError as error:
        raise TranscriptionError(
            f"whisper-cli binary not found: {config.whisper_cli()}"
        ) from error
    if result.returncode != 0:
        stderr = result.stderr.decode("utf-8", errors="replace").strip()
        logger.error("whisper-cli failed (rc=%d): %s", result.returncode, stderr[-500:])
        raise TranscriptionError("transcription engine failed")

    stdout = result.stdout.decode("utf-8", errors="replace")
    # One line per segment; dictation text carries no meaningful line structure.
    return " ".join(part.strip() for part in stdout.splitlines() if part.strip())


# -- correct --------------------------------------------------------------------


def correct_text(text: str, language: str, corrector: Corrector) -> CorrectionOutcome:
    """Guarded correction pass — port of Swift ``CorrectionService.correct``.

    Never raises: on engine failure or suspicious output, returns the RAW text
    with a fallback reason.
    """
    input_text = text.strip()
    if not input_text:
        return CorrectionOutcome(text=input_text, outcome="unchanged")

    try:
        raw = corrector(input_text, language)
    except Exception as error:  # noqa: BLE001 — any engine failure means raw fallback
        logger.warning("correction engine error (%s) — falling back to raw text", error)
        return CorrectionOutcome(
            text=input_text, outcome="fallbackRaw", fallback_reason=FallbackReason.ENGINE_ERROR
        )

    cleaned = guardrails.sanitize(raw)
    reason = guardrails.evaluate(input_text, cleaned)
    if reason is not None:
        logger.info("correction rejected (%s) — falling back to raw text", reason.value)
        return CorrectionOutcome(
            text=input_text, outcome="fallbackRaw", fallback_reason=reason
        )
    return CorrectionOutcome(
        text=cleaned, outcome="unchanged" if cleaned == input_text else "corrected"
    )


def make_llama_corrector(chat: Callable[[str, str, int], str]) -> Corrector:
    """Bind a chat function (system, user, max_tokens) -> raw output to the prompt port."""

    def corrector(text: str, language: str) -> str:
        return chat(prompts.system(language), text, prompts.max_tokens(text))

    return corrector
