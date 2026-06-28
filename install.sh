#!/usr/bin/env bash
# miiamia — instalador universal para Linux (Hyprland/Wayland).
#
#   En el repo:        bash install.sh
#   De una línea:      curl -fsSL https://raw.githubusercontent.com/iCleyvin/miiamia/main/install.sh | bash
#
# Instala dependencias según tu distro, descarga el modelo de IA y la voz (según tu hardware),
# e instala el servicio systemd --user. No necesita root salvo para los paquetes del sistema.
set -euo pipefail

REPO="${MIIAMIA_REPO:-https://github.com/iCleyvin/miiamia.git}"
DEST="${MIIAMIA_DIR:-$HOME/miiamia}"
say()  { printf '\033[1;35m▸ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m! %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }

# --- 0. Obtener el código (si se ejecuta por curl|bash) ---
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/shell/shell.qml" ]]; then
  SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  command -v git >/dev/null || { echo "Necesito git para clonar. Instálalo y reintenta."; exit 1; }
  say "Clonando miiamia en $DEST…"
  [[ -d "$DEST/.git" ]] && git -C "$DEST" pull --ff-only || git clone --depth 1 "$REPO" "$DEST"
  SRC="$DEST"
fi
cd "$SRC"

# --- 1. Requisitos básicos ---
[[ "${XDG_SESSION_TYPE:-}" == "wayland" || -n "${WAYLAND_DISPLAY:-}" ]] || \
  warn "No detecté Wayland. miiamia necesita Hyprland/Wayland para el overlay."
command -v hyprctl >/dev/null || warn "No detecté Hyprland (hyprctl). La mascota usa wlr-layer-shell de Hyprland."

# --- 2. Detectar gestor de paquetes ---
PM=""
for p in pacman apt-get dnf zypper xbps-install; do command -v "$p" >/dev/null && { PM="$p"; break; }; done
SUDO=""; [[ $EUID -ne 0 ]] && SUDO="sudo"

pm_install() { # instala paquetes (best-effort, no aborta si alguno falta)
  case "$PM" in
    pacman)        $SUDO pacman -S --needed --noconfirm "$@" || true ;;
    apt-get)       $SUDO apt-get update -qq && $SUDO apt-get install -y "$@" || true ;;
    dnf)           $SUDO dnf install -y "$@" || true ;;
    zypper)        $SUDO zypper -n install "$@" || true ;;
    xbps-install)  $SUDO xbps-install -Sy "$@" || true ;;
    *) warn "Gestor de paquetes no reconocido. Instala manualmente: $*" ;;
  esac
}

say "Instalando dependencias (distro: ${PM:-desconocida})…"
case "$PM" in
  pacman)
    # En Arch todo está en repos oficiales (sin AUR).
    pm_install jq playerctl pipewire python qt6-declarative qt6-wayland espeak-ng \
               quickshell whisper-cpp-vulkan
    # Motor LLM por GPU (elige el que aplique; vulkan es vendor-neutral)
    pm_install llama-cpp-vulkan || pm_install llama-cpp
    ;;
  apt-get)
    pm_install jq playerctl pipewire-bin python3 espeak-ng \
               qt6-declarative-dev qml6-module-qtquick qml6-module-qtquick-controls
    ;;
  dnf)
    pm_install jq playerctl pipewire-utils python3 espeak-ng qt6-qtdeclarative
    ;;
  zypper)
    pm_install jq playerctl pipewire-tools python3 espeak-ng qt6-declarative
    ;;
  xbps-install)
    pm_install jq playerctl pipewire python3 espeak-ng qt6-declarative
    ;;
esac

# --- 3. Componentes no empaquetados fuera de Arch: guía clara, sin abortar ---
command -v quickshell >/dev/null || warn \
  "Falta Quickshell (motor del overlay). Instálalo: https://quickshell.org/docs/guide/install/"
command -v llama-server >/dev/null || warn \
  "Falta llama-server (IA). Arch: pacman -S llama-cpp-vulkan · Otros: build de github.com/ggml-org/llama.cpp · o se usará llamafile como fallback."
command -v whisper-server >/dev/null || warn \
  "Falta whisper-server (voz a texto). Arch: pacman -S whisper-cpp-vulkan · Otros: build de github.com/ggml-org/whisper.cpp"

# --- 4. Sprites placeholder ---
if [[ ! -f characters/kira/sprites/idle.png ]]; then
  { command -v python >/dev/null && python tools/make_skins.py; } 2>/dev/null || \
    python3 tools/make_skins.py 2>/dev/null || warn "No pude generar skins (falta python-pillow); ya vienen en el repo."
fi

# --- 5. Modelo de IA (según tu hardware) ---
if command -v llama-server >/dev/null || command -v llamafile >/dev/null; then
  AI_TOML="${XDG_CONFIG_HOME:-$HOME/.config}/miiamia/ai.toml"
  grep -q 'downloaded = true' "$AI_TOML" 2>/dev/null || { say "Descargando el modelo de IA…"; bash tools/provision.sh || warn "Reintenta luego: bash tools/provision.sh"; }
fi

# --- 6. Voz (Piper + modelo whisper), opcional ---
if command -v whisper-server >/dev/null; then
  say "Configurando la voz (Piper + modelo whisper)…"
  bash install/setup_voice.sh || warn "Voz incompleta; reintenta: bash install/setup_voice.sh"
fi

# --- 7. Servicio systemd --user ---
say "Instalando el servicio…"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$UNIT_DIR"
# Genera la unidad apuntando a la ruta real de instalación.
sed "s|%h/miiamia/shell|$SRC/shell|" services/miiamia.service > "$UNIT_DIR/miiamia.service"
systemctl --user daemon-reload
systemctl --user enable --now miiamia.service 2>/dev/null || \
  warn "No pude habilitar el servicio (¿sesión systemd --user?). Lánzalo a mano: quickshell -p $SRC/shell"

# --- 8. Verificación ---
sleep 1
if hyprctl layers 2>/dev/null | grep -q miiamia; then
  ok "miiamia está vivo. Click izquierdo = chat · ⚙ = configuración · click derecho mantenido = hablarle."
else
  warn "No veo el overlay todavía. Revisa: journalctl --user -u miiamia -f"
fi
echo
ok "Listo. Personaliza todo desde el menú ⚙ (en el chat)."
