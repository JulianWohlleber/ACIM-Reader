#!/usr/bin/env bash
# Fetches the Kokoro v1.0 int8 TTS model (English-only subset) into ACIMAudio/Resources/Voices/.
set -euo pipefail

URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-multi-lang-v1_0.tar.bz2"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/ACIMAudio/Resources/Voices"
FILES=(model.int8.onnx voices.bin tokens.txt lexicon-us-en.txt)

missing=0
for f in "${FILES[@]}"; do [[ -s "$DEST/$f" ]] || missing=1; done
if [[ $missing -eq 0 ]]; then
  echo "Voices already present in $DEST - nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading Kokoro v1.0 (~126 MB)..."
curl -fL --progress-bar -o "$TMP/kokoro.tar.bz2" "$URL" \
  || { echo "ERROR: download failed: $URL" >&2; exit 1; }

echo "==> Extracting..."
tar -xjf "$TMP/kokoro.tar.bz2" -C "$TMP" \
  || { echo "ERROR: extraction failed (corrupt download?)" >&2; exit 1; }

SRC="$TMP/kokoro-int8-multi-lang-v1_0"
mkdir -p "$DEST"
for f in "${FILES[@]}"; do
  [[ -f "$SRC/$f" ]] || { echo "ERROR: $f missing from archive" >&2; exit 1; }
  echo "==> Copying $f"
  cp "$SRC/$f" "$DEST/$f"
done

echo "==> Done. Files in $DEST:"
ls -lh "$DEST"
