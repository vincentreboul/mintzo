"""FastAPI app — ADR-002 contract.

POST /v1/transcribe  multipart(file ≤ 50 MB, language eu|fr, correct bool)
                     → 200 {text, rawText, language, durationSeconds,
                            timings: {asr, correction}}
GET  /v1/health      → {status, models: {eu, fr, latxa}}

Errors are always JSON ``{error, message}``: 413 size, 415 format,
422 params, 500 pipeline. The uploaded file lives in a per-request tmpdir and
is deleted in ``finally`` — nothing is ever persisted server-side (product
promise: audio removed right after processing).
"""

from __future__ import annotations

import logging
import shutil
import tempfile
import time
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Form, Request, UploadFile
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from . import config, models, pipeline
from .llama_runtime import LlamaServer, LlamaServerError
from .pipeline import (
    DecodeError,
    PipelineError,
    UnsupportedFormatError,
    correct_text,
    make_llama_corrector,
)

logger = logging.getLogger("mintzo.api")

_UPLOAD_CHUNK = 1024 * 1024


class ApiError(Exception):
    """Typed API error → JSON {error, message} with an HTTP status."""

    def __init__(self, status_code: int, error: str, message: str) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.error = error
        self.message = message


class Runtime:
    """Real engine runtime: model bootstrap, resident llama-server, pipeline calls."""

    def __init__(self, models_directory: Path | None = None) -> None:
        self.models_directory = models_directory
        self.llama: LlamaServer | None = None

    # -- lifecycle ------------------------------------------------------------

    def startup(self) -> None:
        if models.skip_ensure():
            logger.warning("MINTZO_SKIP_ENSURE=1 — model download/verification skipped")
        else:
            models.ensure_required(self.models_directory)
        if config.llama_autostart():
            latxa = models.model_path(models.LATXA, self.models_directory)
            self.llama = LlamaServer(latxa)
            self.llama.start()
        else:
            logger.warning("LLAMA_AUTOSTART=0 — correction will fall back to raw text")

    def shutdown(self) -> None:
        if self.llama is not None:
            self.llama.stop()
            self.llama = None

    # -- request work ----------------------------------------------------------

    def process(self, source: Path, language: str, correct: bool) -> dict:
        with tempfile.TemporaryDirectory(prefix="mintzo-decode-") as work_dir:
            decoded = pipeline.decode(source, Path(work_dir))

            asr_started = time.perf_counter()
            raw_text = pipeline.transcribe(decoded.path, language, self.models_directory)
            asr_seconds = time.perf_counter() - asr_started

            text = raw_text
            correction_seconds: float | None = None
            if correct:
                correction_started = time.perf_counter()
                outcome = correct_text(raw_text, language, corrector=self._corrector)
                correction_seconds = time.perf_counter() - correction_started
                text = outcome.text

            return {
                "text": text,
                "rawText": raw_text,
                "language": language,
                "durationSeconds": round(decoded.duration_seconds, 3),
                "timings": {
                    "asr": round(asr_seconds, 3),
                    "correction": (
                        round(correction_seconds, 3) if correction_seconds is not None else None
                    ),
                },
            }

    def _corrector(self, text: str, language: str) -> str:
        if self.llama is None or not self.llama.alive:
            raise LlamaServerError("correction engine not running")
        return make_llama_corrector(self.llama.chat)(text, language)

    def models_status(self) -> dict[str, bool]:
        return models.status(self.models_directory)


def create_app(runtime: Runtime | None = None) -> FastAPI:
    runtime = runtime or Runtime()

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        runtime.startup()
        try:
            yield
        finally:
            runtime.shutdown()

    app = FastAPI(title="Mintzo transcription server", version="0.1.0", lifespan=lifespan)
    app.state.runtime = runtime

    app.add_middleware(
        CORSMiddleware,
        allow_origins=config.cors_origins(),
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # -- error envelope --------------------------------------------------------

    def _json_error(status_code: int, error: str, message: str) -> JSONResponse:
        return JSONResponse(status_code=status_code, content={"error": error, "message": message})

    @app.exception_handler(ApiError)
    async def handle_api_error(_: Request, exc: ApiError) -> JSONResponse:
        return _json_error(exc.status_code, exc.error, exc.message)

    @app.exception_handler(UnsupportedFormatError)
    async def handle_unsupported(_: Request, exc: UnsupportedFormatError) -> JSONResponse:
        return _json_error(415, "unsupported_format", str(exc))

    @app.exception_handler(DecodeError)
    async def handle_decode(_: Request, exc: DecodeError) -> JSONResponse:
        return _json_error(415, "undecodable_audio", str(exc))

    @app.exception_handler(PipelineError)
    async def handle_pipeline(_: Request, exc: PipelineError) -> JSONResponse:
        logger.error("pipeline failure: %s", exc)
        return _json_error(500, "pipeline_error", "transcription pipeline failed")

    @app.exception_handler(RequestValidationError)
    async def handle_validation(_: Request, exc: RequestValidationError) -> JSONResponse:
        first = exc.errors()[0] if exc.errors() else {}
        location = ".".join(str(part) for part in first.get("loc", ()))
        detail = first.get("msg", "invalid request")
        return _json_error(422, "invalid_params", f"{location}: {detail}".strip(": "))

    @app.exception_handler(Exception)
    async def handle_unexpected(_: Request, exc: Exception) -> JSONResponse:
        logger.exception("unhandled error", exc_info=exc)
        return _json_error(500, "pipeline_error", "internal server error")

    # -- routes -----------------------------------------------------------------

    @app.get("/v1/health")
    def health() -> dict:
        statuses = runtime.models_status()
        return {"status": "ok" if all(statuses.values()) else "degraded", "models": statuses}

    @app.post("/v1/transcribe")
    def transcribe(file: UploadFile, language: str = Form(...), correct: bool = Form(False)) -> dict:
        if language not in pipeline.LANGUAGES:
            raise ApiError(
                422, "invalid_params",
                f"language must be one of {'|'.join(pipeline.LANGUAGES)}, got {language!r}",
            )
        suffix = Path(file.filename or "").suffix.lower()
        if suffix not in pipeline.ALLOWED_EXTENSIONS:
            raise ApiError(
                415, "unsupported_format",
                f"unsupported format {suffix or '(none)'} — accepted: "
                + ", ".join(sorted(pipeline.ALLOWED_EXTENSIONS)),
            )

        # Nothing persists: the upload lives in this tmpdir for the duration of
        # the request only, removed in finally whatever happens.
        work_dir = Path(tempfile.mkdtemp(prefix="mintzo-upload-"))
        try:
            upload_path = work_dir / f"upload{suffix}"
            limit = config.max_upload_bytes()
            written = 0
            with upload_path.open("wb") as out:
                while chunk := file.file.read(_UPLOAD_CHUNK):
                    written += len(chunk)
                    if written > limit:
                        raise ApiError(
                            413, "file_too_large",
                            f"file exceeds the {limit // (1024 * 1024)} MB limit",
                        )
                    out.write(chunk)
            if written == 0:
                raise ApiError(422, "invalid_params", "file: empty upload")
            return runtime.process(upload_path, language, correct)
        finally:
            shutil.rmtree(work_dir, ignore_errors=True)

    return app


# uvicorn entry point: `uvicorn app.main:app`
app = create_app()
