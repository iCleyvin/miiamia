#!/usr/bin/env bash
# Descarga un modelo whisper ggml si falta. Acepta 'base' o 'ggml-base'.
set -euo pipefail
m="${1:?uso: get_stt.sh <tiny|base|small>}"
m="${m#ggml-}"
MODELS="${XDG_CACHE_HOME:-$HOME/.cache}/miiamia/models"
mkdir -p "$MODELS"
f="$MODELS/ggml-$m.bin"
[[ -f "$f" ]] || curl -L --fail -C - -o "$f" \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$m.bin"
echo "$f"
