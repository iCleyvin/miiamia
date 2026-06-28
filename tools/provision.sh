#!/usr/bin/env bash
# miiamia — provisioning de la IA embebida.
# Detecta el hardware, elige el tier de modelo, descarga el GGUF (resumible + verificado)
# y escribe ~/.config/miiamia/ai.toml. No requiere sudo.
#
#   bash tools/provision.sh            # detecta, descarga el modelo del tier y escribe ai.toml
#   bash tools/provision.sh --detect   # solo detecta e imprime el plan (sin descargar)
#   bash tools/provision.sh --tier slim   # fuerza un tier concreto
#
# Modelos: familia Qwen3 (Apache 2.0, multilingue, roleplay). Repos GGUF publicos de unsloth.
set -euo pipefail

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/miiamia/models"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/miiamia"
AI_TOML="$CFG/ai.toml"

DETECT_ONLY=0
FORCE_TIER=""
while (($#)); do
  case "$1" in
    --detect) DETECT_ONLY=1 ;;
    --tier)   FORCE_TIER="${2:-}"; shift ;;
    *) echo "arg desconocido: $1" >&2; exit 2 ;;
  esac
  shift
done

say() { printf '\033[1;35m▸ %s\033[0m\n' "$*"; }

# --- Catálogo de modelos por tier (repo, archivo, ctx, n_predict) ---
# SHA256 del 1.7B verificado el 2026-06-28; el resto se obtiene de la cabecera HF en runtime.
declare -A REPO FILE CTX NPRED SHA
REPO[micro]="unsloth/Qwen3-0.6B-GGUF";  FILE[micro]="Qwen3-0.6B-Q4_K_M.gguf"; CTX[micro]=1024; NPRED[micro]=256
REPO[slim]="unsloth/Qwen3-1.7B-GGUF";   FILE[slim]="Qwen3-1.7B-Q4_K_M.gguf";  CTX[slim]=4096; NPRED[slim]=512
SHA[slim]="b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897"
REPO[default]="unsloth/Qwen3-4B-GGUF";  FILE[default]="Qwen3-4B-Q4_K_M.gguf"; CTX[default]=4096; NPRED[default]=512
REPO[full]="unsloth/Qwen3-4B-GGUF";     FILE[full]="Qwen3-4B-Q4_K_M.gguf";    CTX[full]=8192; NPRED[full]=512

# --- Detección de recursos ---
free_ram_mb=$(awk '/MemAvailable/{printf "%.0f",$2/1024}' /proc/meminfo)
vram_free_mb=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -dc '0-9')
vram_free_mb=${vram_free_mb:-0}

if [[ -n "$FORCE_TIER" ]]; then
  tier="$FORCE_TIER"
elif (( vram_free_mb >= 6000 || free_ram_mb >= 16384 )); then tier=full
elif (( vram_free_mb >= 3000 || free_ram_mb >= 8192  )); then tier=default
elif (( free_ram_mb >= 2048 )); then tier=slim
else tier=micro
fi
[[ -n "${REPO[$tier]:-}" ]] || { echo "tier invalido: $tier" >&2; exit 2; }

repo="${REPO[$tier]}"; file="${FILE[$tier]}"
url="https://huggingface.co/$repo/resolve/main/$file"
dest="$CACHE/$file"

say "RAM libre ${free_ram_mb}MB · VRAM libre ${vram_free_mb}MB  ->  tier: $tier"
echo "   modelo: $repo / $file"
echo "   ctx=${CTX[$tier]} n_predict=${NPRED[$tier]}"
(( DETECT_ONLY )) && exit 0

mkdir -p "$CACHE" "$CFG"

# --- Tamaño + SHA esperados desde la cabecera de HuggingFace (302 con x-linked-*) ---
say "Consultando HuggingFace…"
hdr=$(curl -sIL "$url" || true)
exp_size=$(grep -i '^x-linked-size:' <<<"$hdr" | head -1 | tr -dc '0-9')
exp_sha=$(grep -i '^x-linked-etag:' <<<"$hdr" | head -1 | awk '{print $2}' | tr -d '\r"')
[[ -n "${SHA[$tier]:-}" ]] && exp_sha="${SHA[$tier]}"   # preferir el hardcoded verificado si existe
[[ -n "$exp_size" ]] && echo "   tamaño esperado: $((exp_size/1024/1024)) MB"

# --- Descarga resumible ---
say "Descargando (resumible con curl -C -)…"
curl -L -C - --fail --connect-timeout 30 --retry 3 --retry-delay 5 --retry-connrefused \
  --progress-bar -o "$dest" "$url"

# --- Verificación ---
if [[ -n "$exp_sha" ]]; then
  say "Verificando SHA256…"
  got=$(sha256sum "$dest" | cut -d' ' -f1)
  if [[ "$got" != "$exp_sha" ]]; then
    echo "✗ SHA256 no coincide (esperado $exp_sha, obtenido $got). Borra $dest y reintenta." >&2
    exit 1
  fi
  echo "   ✓ SHA256 OK"
elif [[ -n "$exp_size" ]]; then
  got_size=$(stat -c%s "$dest")
  (( got_size == exp_size )) || { echo "✗ tamaño no coincide ($got_size != $exp_size)" >&2; exit 1; }
  echo "   ✓ tamaño OK (sin SHA disponible)"
fi

# --- Escribir ai.toml activo ---
cat > "$AI_TOML" <<EOF
[ai]
backend          = "embedded"
endpoint         = "http://127.0.0.1:8080"
model_tier       = "$tier"
model_path       = "$dest"
ctx_size         = ${CTX[$tier]}
n_predict        = ${NPRED[$tier]}
downloaded       = true
sha256           = "${exp_sha:-}"
idle_unload_secs = 180
gaming_unload    = true
reasoning        = "off"
external_url     = ""
external_api_key = ""
EOF

say "Listo."
echo "   modelo: $dest"
echo "   config: $AI_TOML"
