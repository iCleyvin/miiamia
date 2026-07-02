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
  # Piper publica binarios por arquitectura; antes se bajaba x86_64 incondicional y en
  # aarch64 (Raspberry/Asahi) daba "Exec format error" al primer TTS.
  case "$(uname -m)" in
    x86_64)          PIPER_ARCH="x86_64" ;;
    aarch64|arm64)   PIPER_ARCH="aarch64" ;;
    armv7l)          PIPER_ARCH="armv7l" ;;
    *) printf '\033[1;33m! Arquitectura %s sin binario Piper oficial; la pet no hablará (TTS off).\033[0m\n' "$(uname -m)"; PIPER_ARCH="" ;;
  esac
  if [[ -n "$PIPER_ARCH" ]]; then
    say "Descargando Piper (TTS, $PIPER_ARCH)…"
    tgz="$(mktemp -t miiamia-piper-XXXXXX.tgz)"
    curl -L --fail -o "$tgz" \
      "https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_linux_${PIPER_ARCH}.tar.gz"
    tar -xzf "$tgz" -C "$VOICE_DIR"   # crea $VOICE_DIR/piper/
    rm -f "$tgz"
    echo "   ✓ $VOICE_DIR/piper/piper"
  fi
else
  echo "   Piper ya está."
fi

# --- 2. Voz es_ES-sharvard-medium (CC-BY-4.0) ---
# Reusa get_voice.sh: descarga atómica de los DOS archivos (.onnx + .onnx.json); antes un corte
# a mitad dejaba la voz rota para siempre (el re-run la saltaba por "ya existe").
V="$VOICE_DIR/voices/es_ES-sharvard-medium"
if [[ ! -f "$V.onnx" || ! -f "$V.onnx.json" ]]; then
  say "Descargando voz es_ES-sharvard-medium…"
  bash "$(dirname "${BASH_SOURCE[0]}")/../tools/get_voice.sh" es_ES-sharvard-medium
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
