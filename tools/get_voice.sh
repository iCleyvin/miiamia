#!/usr/bin/env bash
# Descarga una voz de Piper por nombre a ~/.local/share/miiamia/voice/voices/
# Ej:  bash tools/get_voice.sh es_AR-daniela-high
# El nombre se descompone como <lang>-<speaker>-<quality> (ruta HF: <idioma>/<lang>/<speaker>/<quality>/).
set -euo pipefail
voice="${1:?uso: get_voice.sh <xx_XX-speaker-quality>}"
VOICES="${XDG_DATA_HOME:-$HOME/.local/share}/miiamia/voice/voices"
mkdir -p "$VOICES"

IFS='-' read -r lang speaker quality <<<"$voice"
prefix="${lang%%_*}"   # es_AR -> es, en_US -> en (antes /es/ iba fijo y toda voz no-española daba 404)
base="https://huggingface.co/rhasspy/piper-voices/resolve/main/${prefix}/${lang}/${speaker}/${quality}"

# La voz son DOS archivos (.onnx + .onnx.json). Descarga a .part y mueve al final:
# si algo falla a medias no queda una voz rota que el re-run saltaría por "ya existe".
if [[ ! -f "$VOICES/$voice.onnx" || ! -f "$VOICES/$voice.onnx.json" ]]; then
  curl -L --fail -o "$VOICES/$voice.onnx.part"      "$base/$voice.onnx"
  curl -L --fail -o "$VOICES/$voice.onnx.json.part" "$base/$voice.onnx.json"
  mv "$VOICES/$voice.onnx.part"      "$VOICES/$voice.onnx"
  mv "$VOICES/$voice.onnx.json.part" "$VOICES/$voice.onnx.json"
  echo "✓ $VOICES/$voice.onnx"
else
  echo "ya está: $voice"
fi
