#!/usr/bin/env bash
# Télécharge le llama.xcframework précompilé depuis la release officielle
# ggml-org/llama.cpp (asset publié par la CI upstream), vérifie son SHA256,
# et l'installe dans Vendor/llama.xcframework.
#
# llama.cpp ne publie pas de versions sémantiques : chaque build master taggé
# (bNNNN) publie un asset `llama-bNNNN-xcframework.zip`. On pinne un build
# précis + SHA256 → reproductible. Le xcframework (~254 Mo zippé, toutes
# plateformes Apple + dSYMs) est volontairement gitignoré : ce script est la
# source de vérité pour le régénérer.
#
# Usage : scripts/fetch-llama-xcframework.sh [--force]

set -euo pipefail

LLAMA_BUILD="b9862"
ZIP_NAME="llama-${LLAMA_BUILD}-xcframework.zip"
URL="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_BUILD}/${ZIP_NAME}"
# SHA256 de l'asset officiel, calculé le 2026-07-03 sur le zip téléchargé (254 366 428 octets).
SHA256_EXPECTED="414f8481752a74dedfd0134b75b093d4cb58e022bb036339bcffce2f6e570afb"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${ROOT}/Vendor/llama.xcframework"

if [[ -d "${DEST}" && "${1:-}" != "--force" ]]; then
  echo "OK : ${DEST} déjà présent (--force pour re-télécharger)."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "Téléchargement de ${URL} ..."
curl -sSL --fail -o "${TMP}/${ZIP_NAME}" "${URL}"

SHA256_ACTUAL="$(shasum -a 256 "${TMP}/${ZIP_NAME}" | awk '{print $1}')"
if [[ "${SHA256_ACTUAL}" != "${SHA256_EXPECTED}" ]]; then
  echo "ERREUR : SHA256 invalide pour ${ZIP_NAME}" >&2
  echo "  attendu : ${SHA256_EXPECTED}" >&2
  echo "  obtenu  : ${SHA256_ACTUAL}" >&2
  exit 1
fi
echo "SHA256 vérifié."

unzip -q "${TMP}/${ZIP_NAME}" -d "${TMP}"
if [[ ! -d "${TMP}/build-apple/llama.xcframework" ]]; then
  echo "ERREUR : structure inattendue dans le zip (build-apple/llama.xcframework absent)." >&2
  exit 1
fi

rm -rf "${DEST}"
mkdir -p "${ROOT}/Vendor"
mv "${TMP}/build-apple/llama.xcframework" "${DEST}"
echo "OK : llama.xcframework ${LLAMA_BUILD} installé dans Vendor/."
