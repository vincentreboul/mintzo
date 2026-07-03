"""API contract tests with a stubbed runtime (no models, no binaries)."""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.main import Runtime, create_app
from app.pipeline import TranscriptionError


class StubRuntime(Runtime):
    """Runtime double: no llama-server, canned pipeline result."""

    def __init__(self, statuses: dict[str, bool] | None = None, error: Exception | None = None):
        super().__init__(models_directory=Path("/nonexistent"))
        self.statuses = statuses or {"eu": True, "fr": True, "latxa": True}
        self.error = error
        self.calls: list[tuple[str, str, bool]] = []

    def startup(self) -> None:  # no models, no child process
        pass

    def shutdown(self) -> None:
        pass

    def process(self, source: Path, language: str, correct: bool) -> dict:
        self.calls.append((source.name, language, correct))
        assert source.exists()
        if self.error is not None:
            raise self.error
        return {
            "text": "Kaixo, Maite!",
            "rawText": "kaixo maite",
            "language": language,
            "durationSeconds": 5.803,
            "timings": {"asr": 2.5, "correction": 1.2 if correct else None},
        }

    def models_status(self) -> dict[str, bool]:
        return self.statuses


@pytest.fixture()
def client() -> TestClient:
    return TestClient(create_app(StubRuntime()), raise_server_exceptions=False)


def _upload(name: str = "note.opus", content: bytes = b"fake-opus-bytes"):
    return {"file": (name, content, "audio/ogg")}


# -- nominal ---------------------------------------------------------------------


def test_transcribe_nominal_contract(client: TestClient):
    response = client.post(
        "/v1/transcribe",
        files=_upload(),
        data={"language": "eu", "correct": "true"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body == {
        "text": "Kaixo, Maite!",
        "rawText": "kaixo maite",
        "language": "eu",
        "durationSeconds": 5.803,
        "timings": {"asr": 2.5, "correction": 1.2},
    }


def test_transcribe_without_correction(client: TestClient):
    response = client.post(
        "/v1/transcribe", files=_upload(), data={"language": "fr", "correct": "false"}
    )
    assert response.status_code == 200
    assert response.json()["timings"]["correction"] is None


def test_correct_defaults_to_false():
    runtime = StubRuntime()
    client = TestClient(create_app(runtime), raise_server_exceptions=False)
    assert client.post("/v1/transcribe", files=_upload(), data={"language": "eu"}).status_code == 200
    assert runtime.calls == [("upload.opus", "eu", False)]


# -- typed errors ------------------------------------------------------------------


def test_413_file_too_large(client: TestClient, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("MAX_UPLOAD_BYTES", "10")
    response = client.post(
        "/v1/transcribe",
        files=_upload(content=b"x" * 64),
        data={"language": "eu"},
    )
    assert response.status_code == 413
    body = response.json()
    assert body["error"] == "file_too_large"
    assert "message" in body


def test_415_unsupported_extension(client: TestClient):
    response = client.post(
        "/v1/transcribe", files=_upload(name="notes.pdf"), data={"language": "eu"}
    )
    assert response.status_code == 415
    assert response.json()["error"] == "unsupported_format"


def test_422_bad_language(client: TestClient):
    response = client.post("/v1/transcribe", files=_upload(), data={"language": "es"})
    assert response.status_code == 422
    body = response.json()
    assert body["error"] == "invalid_params"
    assert "language" in body["message"]


def test_422_missing_file(client: TestClient):
    response = client.post("/v1/transcribe", data={"language": "eu"})
    assert response.status_code == 422
    assert response.json()["error"] == "invalid_params"


def test_422_empty_upload(client: TestClient):
    response = client.post(
        "/v1/transcribe", files=_upload(content=b""), data={"language": "eu"}
    )
    assert response.status_code == 422
    assert response.json()["error"] == "invalid_params"


def test_500_pipeline_error_is_typed_json():
    stub = StubRuntime(error=TranscriptionError("engine blew up"))
    client = TestClient(create_app(stub), raise_server_exceptions=False)
    response = client.post("/v1/transcribe", files=_upload(), data={"language": "eu"})
    assert response.status_code == 500
    body = response.json()
    assert body["error"] == "pipeline_error"
    assert "engine blew up" not in body["message"]  # internals never leak


# -- health ------------------------------------------------------------------------


def test_health_ok(client: TestClient):
    response = client.get("/v1/health")
    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "models": {"eu": True, "fr": True, "latxa": True},
    }


def test_health_degraded_when_model_missing():
    stub = StubRuntime(statuses={"eu": True, "fr": True, "latxa": False})
    client = TestClient(create_app(stub), raise_server_exceptions=False)
    body = client.get("/v1/health").json()
    assert body["status"] == "degraded"
    assert body["models"]["latxa"] is False


# -- CORS ---------------------------------------------------------------------------


def test_cors_open_by_default(client: TestClient):
    response = client.get("/v1/health", headers={"Origin": "https://mintzo.eus"})
    assert response.headers.get("access-control-allow-origin") == "*"


def test_cors_restricted_via_env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("CORS_ORIGINS", "https://mintzo.eus,https://staging.mintzo.eus")
    client = TestClient(create_app(StubRuntime()), raise_server_exceptions=False)
    allowed = client.get("/v1/health", headers={"Origin": "https://mintzo.eus"})
    assert allowed.headers.get("access-control-allow-origin") == "https://mintzo.eus"
    denied = client.get("/v1/health", headers={"Origin": "https://evil.example"})
    assert "access-control-allow-origin" not in denied.headers
