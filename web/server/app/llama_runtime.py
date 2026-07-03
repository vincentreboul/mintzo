"""llama.cpp runtime: a resident llama-server child process + minimal HTTP client.

Why a resident server instead of one llama-cli process per request:
- llama-cli ≥ b9860 is conversation-only (``-no-cnv`` removed) and pollutes
  stdout with a banner/echoed prompt — unfit for reliable parsing;
- reloading a 2.5 GB GGUF per request costs seconds (disk + warmup) both on the
  local M4 and on a Modal GPU container; loaded once, a correction runs ~1 s.

The child process is spawned with stderr captured to a log file, health-polled
until the model is loaded, and terminated on shutdown. Generation is greedy
(``temperature 0``) like the Mac app ``LlamaEngine`` (pure greedy sampler), and
each request is stateless — the server applies the GGUF chat template
(system + user), same contract as ``llama_chat_apply_template`` in Swift.
"""

from __future__ import annotations

import json
import logging
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

from . import config

logger = logging.getLogger("mintzo.llama")


class LlamaServerError(RuntimeError):
    """The llama-server child failed to boot, died, or answered garbage."""


class LlamaServer:
    """Owns one llama-server child bound to 127.0.0.1 and speaks chat-completions to it."""

    def __init__(
        self,
        model_path: Path,
        binary: str | None = None,
        port: int | None = None,
        ctx_size: int | None = None,
    ) -> None:
        self.model_path = model_path
        self.binary = binary or config.llama_server_bin()
        self.port = port or config.llama_port()
        self.ctx_size = ctx_size or config.llama_ctx_size()
        self._process: subprocess.Popen[bytes] | None = None
        self._log_path: Path | None = None

    # -- lifecycle -----------------------------------------------------------

    def start(self, ready_timeout_s: float = 300.0) -> None:
        """Spawn the child and block until the model is loaded (health 200)."""
        if self.alive:
            return
        if not self.model_path.exists():
            raise LlamaServerError(f"model not found: {self.model_path}")
        self._ensure_port_free()

        log = tempfile.NamedTemporaryFile(
            mode="wb", prefix="mintzo-llama-server-", suffix=".log", delete=False
        )
        self._log_path = Path(log.name)
        command = [
            self.binary,
            "-m", str(self.model_path),
            "--host", "127.0.0.1",
            "--port", str(self.port),
            "-c", str(self.ctx_size),
            "-ngl", "99",
            "--threads", str(config.n_threads()),
        ]
        logger.info("starting llama-server: %s (log: %s)", " ".join(command), self._log_path)
        try:
            self._process = subprocess.Popen(
                command, stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL
            )
        except FileNotFoundError as error:
            raise LlamaServerError(
                f"llama-server binary not found: {self.binary} — brew install llama.cpp"
            ) from error
        finally:
            log.close()

        deadline = time.monotonic() + ready_timeout_s
        while time.monotonic() < deadline:
            if self._process.poll() is not None:
                raise LlamaServerError(
                    f"llama-server exited with code {self._process.returncode} "
                    f"during startup — see {self._log_path}"
                )
            if self._health_ok():
                logger.info("llama-server ready on port %d", self.port)
                return
            time.sleep(0.25)
        self.stop()
        raise LlamaServerError(f"llama-server not ready after {ready_timeout_s}s")

    def stop(self) -> None:
        process = self._process
        self._process = None
        if process is None or process.poll() is not None:
            return
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)

    @property
    def alive(self) -> bool:
        return self._process is not None and self._process.poll() is None

    # -- generation ----------------------------------------------------------

    def chat(self, system: str, user: str, max_tokens: int, timeout_s: float | None = None) -> str:
        """One stateless greedy chat completion; returns the assistant text."""
        if not self.alive:
            raise LlamaServerError("llama-server is not running")
        payload = json.dumps(
            {
                "messages": [
                    {"role": "system", "content": system},
                    {"role": "user", "content": user},
                ],
                "temperature": 0,
                "max_tokens": max_tokens,
            }
        ).encode("utf-8")
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.port}/v1/chat/completions",
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(
                request, timeout=timeout_s or config.correction_timeout_s()
            ) as response:
                body = json.load(response)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
            raise LlamaServerError(f"chat completion failed: {error}") from error
        try:
            content = body["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError) as error:
            raise LlamaServerError(f"unexpected chat response shape: {body!r}") from error
        return (content or "").strip()

    # -- helpers ---------------------------------------------------------------

    def _health_ok(self) -> bool:
        try:
            with urllib.request.urlopen(
                f"http://127.0.0.1:{self.port}/health", timeout=2
            ) as response:
                return response.status == 200
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            return False

    def _ensure_port_free(self) -> None:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
            if probe.connect_ex(("127.0.0.1", self.port)) == 0:
                raise LlamaServerError(
                    f"port {self.port} already in use — set LLAMA_PORT to a free port"
                )
