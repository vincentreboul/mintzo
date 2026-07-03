"""Modal GPU wrapper for the Mintzo transcription server (ADR-002).

⚠️ NOT DEPLOYED / NOT TESTED: no Modal account on the dev machine. Every API
call below was verified against docs.modal.com on 2026-07-03:
- ``modal.Image.from_dockerfile`` + ``add_local_python_source``
  (guide/existing-images, guide/images) — the image must ship python+pip on
  $PATH (the Dockerfile runtime stage does);
- ``@modal.asgi_app`` returning a FastAPI instance, ASGI lifespan supported
  (guide/webhooks) — our lifespan boots the resident llama-server;
- ``@app.function(gpu="T4", volumes=..., scaledown_window=..., timeout=...)``
  (guide/gpu: "T4" is a supported value; guide/cold-start: scaledown_window in
  seconds, 2 s → 20 min; guide/volumes: ``Volume.from_name`` +
  ``volumes={"/models": vol}`` + explicit ``vol.commit()`` to persist writes).

Deploy runbook (≈5 min): see README.md § Déploiement Modal.
"""

import modal

# The Dockerfile builds whisper.cpp + llama.cpp with CUDA (multi-stage) and
# installs ffmpeg + Python deps. The FastAPI code itself is attached with
# add_local_python_source so a code change redeploys in seconds without an
# image rebuild.
image = (
    modal.Image.from_dockerfile("Dockerfile")
    .env({"MODELS_DIR": "/models"})
    .add_local_python_source("app")
)

app = modal.App("mintzo-transcribe")

# Persistent volume for the GGML/GGUF files (~7 GB): downloaded once at the
# first-ever boot, then mounted read-write on every container.
volume = modal.Volume.from_name("mintzo-models", create_if_missing=True)


@app.function(
    image=image,
    gpu="T4",  # 16 GB VRAM: large-v3-eu (~3.1 GB) + Latxa Q4_K_M (~2.5 GB) fit easily
    volumes={"/models": volume},
    scaledown_window=300,  # keep the container (and the loaded Latxa) warm 5 min
    timeout=900,  # long voice notes: decode + ASR can take minutes
    cpu=4.0,
    memory=8192,
)
@modal.asgi_app()
def web():
    import os

    os.environ.setdefault("MODELS_DIR", "/models")

    # First-ever boot: download + sha256-verify the models into the volume,
    # then commit so every future container finds them already there.
    from app import models

    models.ensure_required()
    volume.commit()
    os.environ["MINTZO_SKIP_ENSURE"] = "1"  # the ASGI lifespan won't redo it

    from app.main import create_app

    # The FastAPI lifespan (run by Modal at container start) boots the
    # resident llama-server with -ngl 99 → Latxa lives in VRAM for the whole
    # container lifetime; whisper-cli runs per request on the same GPU.
    return create_app()
