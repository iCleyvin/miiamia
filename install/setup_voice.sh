#!/usr/bin/env bash
# miiamia — setup de voz: descarga Piper (TTS) + voz española + modelo whisper (STT).
# Los binarios de los motores (whisper-server) van por pacman; esto baja lo que NO requiere sudo.
#
#   bash install/setup_voice.sh
set -euo pipefail

VOICE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/miiamia/voice"
MODELS="${XDG_CACHE_HOME:-$HOME/.cache}/miiamia/models"
say() { printf '\033[1;35m▸ %s\033[0m\n' "$*"; }
mkdir -p "$VOICE_DIR/voices" "$MODELS"

# --- 0. Motor STT (pacman, informativo) ---
if ! command -v whisper-server >/dev/null 2>&1; then
  printf '\033[1;33m! Falta whisper-server. Instálalo:  sudo pacman -S --needed whisper-cpp-vulkan\033[0m\n'
fi

# --- 1. Piper (binario estático, NO del AUR) ---
if [[ ! -x "$VOICE_DIR/piper/piper" ]]; then
  say "Descargando Piper (TTS)…"
  curl -L --fail -o /tmp/miiamia-piper.tgz \
    https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_linux_x86_64.tar.gz
  tar -xzf /tmp/miiamia-piper.tgz -C "$VOICE_DIR"   # crea $VOICE_DIR/piper/
  rm -f /tmp/miiamia-piper.tgz
  echo "   ✓ $VOICE_DIR/piper/piper"
else
  echo "   Piper ya está."
fi

# --- 2. Voz es_ES-sharvard-medium (CC-BY-4.0) ---
V="$VOICE_DIR/voices/es_ES-sharvard-medium"
if [[ ! -f "$V.onnx" ]]; then
  say "Descargando voz es_ES-sharvard-medium…"
  base="https://huggingface.co/rhasspy/piper-voices/resolve/main/es/es_ES/sharvard/medium"
  curl -L --fail -o "$V.onnx"      "$base/es_ES-sharvard-medium.onnx"
  curl -L --fail -o "$V.onnx.json" "$base/es_ES-sharvard-medium.onnx.json"
  echo "   ✓ $V.onnx"
else
  echo "   Voz ya está."
fi

# --- 3. Modelo whisper ggml-base (multilingüe) ---
if [[ ! -f "$MODELS/ggml-base.bin" ]]; then
  say "Descargando modelo whisper ggml-base…"
  curl -L --fail -C - -o "$MODELS/ggml-base.bin" \
    https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
  echo "   ✓ $MODELS/ggml-base.bin"
else
  echo "   Modelo whisper ya está."
fi

say "Voz lista. Mantén click derecho sobre la mascota para hablarle."
