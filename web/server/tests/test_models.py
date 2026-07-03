"""Catalogue integrity + ensure_model behavior (no network: file:// downloads)."""

from __future__ import annotations

import hashlib
from pathlib import Path

import pytest

from app import models
from app.models import ModelIntegrityError, ModelSpec


def test_catalogue_matches_swift_source_of_truth():
    """Values pinned from ModelCatalog.swift / LatxaCatalog.swift (2026-07-03)."""
    assert models.WHISPER_EU.download_url == (
        "https://huggingface.co/xezpeleta/whisper-large-v3-eu/resolve/main/ggml-large-v3.eu.bin"
    )
    assert models.WHISPER_EU.size_bytes == 3_095_033_483
    assert models.WHISPER_EU.sha256 == (
        "dae98a83f5450d1a26632430649633842f0b6e535c246baa5b46b962bedf8cab"
    )
    assert models.WHISPER_EU.file_name == "whisper-eu.bin"

    assert models.WHISPER_FR.download_url == (
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"
    )
    assert models.WHISPER_FR.size_bytes == 1_624_555_275
    assert models.WHISPER_FR.sha256 == (
        "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"
    )
    assert models.WHISPER_FR.file_name == "whisper-fr.bin"

    assert models.LATXA.download_url == (
        "https://huggingface.co/mradermacher/Latxa-Qwen3-VL-4B-Instruct-GGUF"
        "/resolve/main/Latxa-Qwen3-VL-4B-Instruct.Q4_K_M.gguf"
    )
    assert models.LATXA.size_bytes == 2_497_282_176
    assert models.LATXA.sha256 == (
        "3eae629d2714189689aa8de1b1d7cfdf8ec846c405b26e4faeeb1fdfa3b4f26b"
    )
    assert models.LATXA.file_name == "Latxa-Qwen3-VL-4B-Instruct.Q4_K_M.gguf"

    for spec in models.ALL:
        assert spec.download_url.startswith("https://huggingface.co/")
        assert len(spec.sha256) == 64
    assert models.WHISPER_TINY not in models.REQUIRED  # test-only model


def _spec_for(payload: bytes, url: str, file_name: str = "model.bin") -> ModelSpec:
    return ModelSpec(
        id="test-model",
        display_name="Test model",
        download_url=url,
        size_bytes=len(payload),
        sha256=hashlib.sha256(payload).hexdigest(),
        role="testing",
        file_name=file_name,
    )


def test_ensure_model_downloads_verifies_and_renames(tmp_path: Path):
    payload = b"gguf-fake-payload" * 100
    source = tmp_path / "src.bin"
    source.write_bytes(payload)
    spec = _spec_for(payload, source.as_uri())
    target_dir = tmp_path / "models"

    path = models.ensure_model(spec, target_dir)

    assert path == target_dir / "model.bin"
    assert path.read_bytes() == payload
    assert not (target_dir / "model.bin.part").exists()
    marker = target_dir / "model.bin.sha256-verified"
    assert marker.read_text().strip() == spec.sha256


def test_ensure_model_rejects_corrupt_download(tmp_path: Path):
    payload = b"expected-content"
    source = tmp_path / "src.bin"
    source.write_bytes(b"tampered-content")  # same length, different bytes
    spec = _spec_for(payload, source.as_uri())

    with pytest.raises(ModelIntegrityError, match="sha256"):
        models.ensure_model(spec, tmp_path / "models")
    assert not (tmp_path / "models" / "model.bin").exists()


def test_ensure_model_accepts_existing_verified_file(tmp_path: Path):
    payload = b"already-here" * 50
    spec = _spec_for(payload, "https://huggingface.co/never/hit")
    target_dir = tmp_path / "models"
    target_dir.mkdir()
    (target_dir / "model.bin").write_bytes(payload)

    # No marker yet -> full sha256 check, then marker written. URL is never hit.
    path = models.ensure_model(spec, target_dir)
    assert path.read_bytes() == payload
    assert (target_dir / "model.bin.sha256-verified").exists()

    # Second call: size + marker only.
    assert models.ensure_model(spec, target_dir) == path


def test_ensure_model_rejects_existing_wrong_size(tmp_path: Path):
    payload = b"right-size-content"
    spec = _spec_for(payload, "https://huggingface.co/never/hit")
    target_dir = tmp_path / "models"
    target_dir.mkdir()
    (target_dir / "model.bin").write_bytes(b"short")

    with pytest.raises(ModelIntegrityError, match="size"):
        models.ensure_model(spec, target_dir)


def test_status_reflects_presence(tmp_path: Path):
    assert models.status(tmp_path) == {"eu": False, "fr": False, "latxa": False}
