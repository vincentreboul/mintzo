#!/usr/bin/env bash
# Télécharge le modèle de test ggml-tiny.bin (~75 Mo) depuis le repo Hugging Face
# officiel ggerganov/whisper.cpp, vérifie son SHA256, et l'installe dans Models/.
# Models/ est gitignoré : ce modèle sert au smoke test XCTest de MintzoCore.
#
# Usage : scripts/download-test-model.sh [--force]

set -euo pipefail

MODEL_NAME="ggml-tiny.bin"
URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${MODEL_NAME}"
# SHA256 autoritatif = lfs.oid de l'API Hugging Face
# (https://huggingface.co/api/models/ggerganov/whisper.cpp/tree/main),
# vérifié le 2026-07-03 (77 691 713 octets).
SHA256_EXPECTED="be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${ROOT}/Models/${MODEL_NAME}"

if [[ -f "${DEST}" && "${1:-}" != "--force" ]]; then
  echo "OK : ${DEST} déjà présent (--force pour re-télécharger)."
  exit 0
fi

mkdir -p "${ROOT}/Models"
TMP_FILE="$(mktemp)"
trap 'rm -f "${TMP_FILE}"' EXIT

echo "Téléchargement de ${URL} ..."
curl -sSL --fail -o "${TMP_FILE}" "${URL}"

SHA256_ACTUAL="$(shasum -a 256 "${TMP_FILE}" | awk '{print $1}')"
if [[ "${SHA256_ACTUAL}" != "${SHA256_EXPECTED}" ]]; then
  echo "ERREUR : SHA256 invalide pour ${MODEL_NAME}" >&2
  echo "  attendu : ${SHA256_EXPECTED}" >&2
  echo "  obtenu  : ${SHA256_ACTUAL}" >&2
  exit 1
fi
echo "SHA256 vérifié."

mv "${TMP_FILE}" "${DEST}"
trap - EXIT
echo "OK : ${MODEL_NAME} installé dans Models/."
