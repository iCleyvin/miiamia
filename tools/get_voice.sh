#!/usr/bin/env bash
# Descarga una voz de Piper por nombre a ~/.local/share/miiamia/voice/voices/
# Ej:  bash tools/get_voice.sh es_AR-daniela-high
# El nombre se descompone como <lang>-<speaker>-<quality> (ruta HF: es/<lang>/<speaker>/<quality>/).
set -euo pipefail
voice="${1:?uso: get_voice.sh <es_XX-speaker-quality>}"
VOICES="${XDG_DATA_HOME:-$HOME/.local/share}/miiamia/voice/voices"
mkdir -p "$VOICES"

IFS='-' read -r lang speaker quality <<<"$voice"
base="https://huggingface.co/rhasspy/piper-voices/resolve/main/es/${lang}/${speaker}/${quality}"

if [[ ! -f "$VOICES/$voice.onnx" ]]; then
  curl -L --fail -o "$VOICES/$voice.onnx"      "$base/$voice.onnx"
  curl -L --fail -o "$VOICES/$voice.onnx.json" "$base/$voice.onnx.json"
  echo "✓ $VOICES/$voice.onnx"
else
  echo "ya está: $voice"
fi
