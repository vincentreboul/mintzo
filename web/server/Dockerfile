# Mintzo transcription server — generic CUDA image (Modal, Fly GPU, VPS).
# Multi-stage: build whisper.cpp + llama.cpp with CUDA, then a slim runtime.
#
# ⚠️ Not built/tested locally (Apple Silicon dev machine, no CUDA): cmake flags
# follow the official upstream CUDA images of both projects (-DGGML_CUDA=ON).
# CUDA architectures: 75 = T4, 86 = A10G, 89 = L4/L40S.

ARG CUDA_IMAGE_VERSION=12.6.3
FROM nvidia/cuda:${CUDA_IMAGE_VERSION}-devel-ubuntu24.04 AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
        git cmake build-essential ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ARG CUDA_ARCHS="75;86;89"
# Pins: whisper.cpp v1.9.x per ADR-001; llama.cpp b9860 = the build validated
# on the M4 (brew) with Latxa.
ARG WHISPER_REF=v1.9.1
ARG LLAMA_REF=b9860

RUN git clone --depth 1 --branch ${WHISPER_REF} https://github.com/ggml-org/whisper.cpp /src/whisper.cpp \
    && cmake -S /src/whisper.cpp -B /build/whisper \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_CUDA=ON \
        -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCHS}" \
        -DBUILD_SHARED_LIBS=OFF \
    && cmake --build /build/whisper --config Release -j --target whisper-cli

RUN git clone --depth 1 --branch ${LLAMA_REF} https://github.com/ggml-org/llama.cpp /src/llama.cpp \
    && cmake -S /src/llama.cpp -B /build/llama \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_CUDA=ON \
        -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCHS}" \
        -DBUILD_SHARED_LIBS=OFF \
        -DLLAMA_CURL=OFF \
    && cmake --build /build/llama --config Release -j --target llama-server

# ---------------------------------------------------------------------------

FROM nvidia/cuda:${CUDA_IMAGE_VERSION}-runtime-ubuntu24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg python3 python3-pip \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/python3 /usr/local/bin/python

COPY --from=build /build/whisper/bin/whisper-cli /usr/local/bin/whisper-cli
COPY --from=build /build/llama/bin/llama-server /usr/local/bin/llama-server

# Ubuntu 24.04 ships Python 3.12 (PEP 668: system pip needs the override flag).
RUN pip install --no-cache-dir --break-system-packages \
        "fastapi>=0.115" "uvicorn[standard]>=0.30" "python-multipart>=0.0.9"

WORKDIR /srv/mintzo
COPY app ./app

ENV MODELS_DIR=/models \
    WHISPER_CLI=/usr/local/bin/whisper-cli \
    LLAMA_SERVER=/usr/local/bin/llama-server

EXPOSE 8000
# Used by generic deployments (Fly, VPS). Modal ignores CMD and serves the
# ASGI app from modal_app.py directly.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
