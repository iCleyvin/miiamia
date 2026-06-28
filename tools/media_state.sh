#!/usr/bin/env bash
# Detecta qué media se reproduce (MPRIS/playerctl) y si lo ESTÁS VIENDO o solo escuchando.
# Imprime: watching | music | none
#
# Lógica:
#   - Reproductor de música (Spotify…) o sitio de música (YouTube Music, SoundCloud…) -> music
#   - Reproductor de video (mpv/vlc) -> watching
#   - Navegador reproduciendo:
#       * enfocado o en pantalla completa (lo estás mirando) -> watching  (video, podcast)
#       * en segundo plano (tabeaste a otra cosa, solo suena)  -> music    (escuchando)
set -uo pipefail

command -v playerctl >/dev/null 2>&1 || { echo none; exit 0; }
mapfile -t lines < <(playerctl -a metadata --format '{{playerName}}|{{status}}' 2>/dev/null)
((${#lines[@]})) || { echo none; exit 0; }

shopt -s nocasematch
_BROWSER='firefox|zen|chromium|chrome|brave|vivaldi|epiphany|librewolf|chrom'

# Ventana activa (clase + fullscreen) para saber si estás MIRANDO el navegador.
awj=$(hyprctl activewindow -j 2>/dev/null)
acls=$(jq -r '.class // ""'      <<<"$awj" 2>/dev/null)
afull=$(jq -r '.fullscreen // 0' <<<"$awj" 2>/dev/null)

music_app=0; video_app=0; browser=0
for ln in "${lines[@]}"; do
  name="${ln%%|*}"; status="${ln##*|}"
  [[ "$status" == "Playing" ]] || continue
  if   [[ "$name" =~ (spotify|spotifyd|tidal|deezer|mpd|cmus|rhythmbox|elisa|amberol|lollypop|audacious|clementine|strawberry) ]]; then music_app=1
  elif [[ "$name" =~ (mpv|vlc|celluloid|totem|smplayer|haruna) ]]; then video_app=1
  elif [[ "$name" =~ ($_BROWSER) ]]; then browser=1
  else music_app=1
  fi
done

# 1) Reproductor de video dedicado -> ver
((video_app)) && { echo watching; exit 0; }

# 2) Navegador reproduciendo -> distinguir música vs ver
if ((browser)); then
  # Títulos de las ventanas de navegador (sitio actual) para detectar música explícita
  btitles=$(hyprctl clients -j 2>/dev/null \
    | jq -r --arg b "$_BROWSER" '[.[] | select(.class|test($b;"i")) | .title] | join("  ")' 2>/dev/null)
  # a) Sitios de MÚSICA explícitos -> music (aunque esté enfocado)
  if [[ "$btitles" =~ (youtube music|soundcloud|bandcamp|· album|· single|· playlist|deezer|tidal|spotify) ]]; then
    echo music; exit 0
  fi
  # b) Plataformas de VIDEO conocidas (Prime, Netflix…) -> watching (aunque esté de fondo: es un show)
  if [[ "$btitles" =~ (prime video|netflix|disney|hbo|hulu|twitch|crunchyroll|vimeo|peacock|paramount|plex|jellyfin|apple tv) ]]; then
    echo watching; exit 0
  fi
  # c) YouTube genérico / desconocido: depende de si lo MIRAS (enfocado/fullscreen) o solo suena de fondo
  if [[ "$afull" != "0" || "$acls" =~ ($_BROWSER) ]]; then echo watching; else echo music; fi
  exit 0
fi

# 3) App de audio -> música
((music_app)) && { echo music; exit 0; }
echo none
