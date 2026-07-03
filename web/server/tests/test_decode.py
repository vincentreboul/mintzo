"""Decode step: real ffmpeg on a generated opus fixture + rejection paths."""

from __future__ import annotations

import wave
from pathlib import Path

import pytest

from app import pipeline
from app.pipeline import DecodeError, UnsupportedFormatError


def test_decode_opus_to_wav_16k_mono(opus_fixture: Path, tmp_path: Path):
    decoded = pipeline.decode(opus_fixture, tmp_path)

    assert decoded.path.exists()
    with wave.open(str(decoded.path), "rb") as wav:
        assert wav.getframerate() == 16000
        assert wav.getnchannels() == 1
        assert wav.getsampwidth() == 2  # s16
    assert decoded.duration_seconds == pytest.approx(1.2, abs=0.15)


def test_decode_rejects_unknown_extension(tmp_path: Path):
    bogus = tmp_path / "note.txt"
    bogus.write_bytes(b"not audio")
    with pytest.raises(UnsupportedFormatError):
        pipeline.decode(bogus, tmp_path)


def test_decode_rejects_extensionless_file(tmp_path: Path):
    bogus = tmp_path / "note"
    bogus.write_bytes(b"not audio")
    with pytest.raises(UnsupportedFormatError):
        pipeline.decode(bogus, tmp_path)


def test_decode_rejects_corrupt_opus(tmp_path: Path):
    corrupt = tmp_path / "note.opus"
    corrupt.write_bytes(b"\x00\x01garbage-not-ogg\xff" * 64)
    with pytest.raises(DecodeError):
        pipeline.decode(corrupt, tmp_path)
