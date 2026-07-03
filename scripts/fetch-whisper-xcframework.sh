#!/usr/bin/env bash
# Télécharge le whisper.xcframework précompilé depuis la release officielle
# ggml-org/whisper.cpp (asset publié par la CI upstream), vérifie son SHA256,
# et l'installe dans Vendor/whisper.xcframework.
#
# Le xcframework (~192 Mo décompressé, toutes plateformes Apple + dSYMs) est
# volontairement gitignoré : ce script est la source de vérité pour le régénérer.
#
# Usage : scripts/fetch-whisper-xcframework.sh [--force]

set -euo pipefail

WHISPER_VERSION="v1.9.1"
ZIP_NAME="whisper-${WHISPER_VERSION}-xcframework.zip"
URL="https://github.com/ggml-org/whisper.cpp/releases/download/${WHISPER_VERSION}/${ZIP_NAME}"
# SHA256 de l'asset officiel, calculé le 2026-07-03 sur le zip téléchargé (50 438 515 octets).
SHA256_EXPECTED="8c3ecbe73f48b0cb9318fc3058264f951ab336fd530e82c4ccdd2298d1311a4c"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${ROOT}/Vendor/whisper.xcframework"

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
if [[ ! -d "${TMP}/build-apple/whisper.xcframework" ]]; then
  echo "ERREUR : structure inattendue dans le zip (build-apple/whisper.xcframework absent)." >&2
  exit 1
fi

rm -rf "${DEST}"
mkdir -p "${ROOT}/Vendor"
mv "${TMP}/build-apple/whisper.xcframework" "${DEST}"
echo "OK : whisper.xcframework ${WHISPER_VERSION} installé dans Vendor/."
