"""Real integration: opus fixture → full pipeline → non-empty Basque text.

Marked ``real``; auto-skipped when the models, the binaries or a speech sample
are missing. The speech sample comes from ``MINTZO_REAL_AUDIO`` (any audio file
with Basque speech; converted to an opus voice note by the test itself).
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app import models
from app.main import Runtime, create_app

_SAMPLE = os.environ.get("MINTZO_REAL_AUDIO", "")

real = pytest.mark.real
requires_stack = pytest.mark.skipif(
    shutil.which("whisper-cli") is None
    or shutil.which("ffmpeg") is None
    or not models.status().get("eu", False)
    or not _SAMPLE
    or not Path(_SAMPLE).exists(),
    reason="needs whisper-cli + ffmpeg + eu model + MINTZO_REAL_AUDIO sample",
)


@real
@requires_stack
def test_real_basque_opus_transcription(tmp_path: Path):
    opus = tmp_path / "sample.opus"
    subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-nostdin", "-y",
            "-i", _SAMPLE,
            "-c:a", "libopus", "-b:a", "24k", "-ac", "1", "-ar", "48000",
            str(opus),
        ],
        check=True,
        capture_output=True,
    )

    os.environ.setdefault("MINTZO_SKIP_ENSURE", "1")  # models already on disk
    os.environ.setdefault("LLAMA_AUTOSTART", "0")  # ASR-only: correction covered by E2E curl

    runtime = Runtime()
    client = TestClient(create_app(runtime), raise_server_exceptions=False)
    with client:
        response = client.post(
            "/v1/transcribe",
            files={"file": ("sample.opus", opus.read_bytes(), "audio/ogg")},
            data={"language": "eu", "correct": "false"},
        )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["language"] == "eu"
    assert body["durationSeconds"] > 0
    assert body["timings"]["asr"] > 0
    assert len(body["rawText"].strip()) > 0
    assert body["text"] == body["rawText"]
