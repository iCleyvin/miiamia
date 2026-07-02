#!/usr/bin/env python3
"""Las "manos" de miiamia: ejecutor SEGURO de acciones del sistema para el agente.

Sin dependencias (stdlib). Sin shell=True ni interpolación de strings en comandos
(todo por listas de argumentos) -> sin inyección. Cada acción valida su entrada y
devuelve {"ok": bool, "result"|"error": str}.

Uso como librería:   from tools_exec import execute, TOOLS_SPEC
Uso CLI (pruebas):   python tools_exec.py open_url https://archlinux.org
                     python tools_exec.py web_search "qué es wayland"
                     python tools_exec.py media playpause
"""
from __future__ import annotations

import glob
import html
import ipaddress
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

UA = "Mozilla/5.0 (X11; Linux x86_64) miiamia/1.0"
_APP_DIRS = [
    os.path.expanduser("~/.local/share/applications"),
    "/usr/share/applications",
    "/usr/local/share/applications",
    os.path.expanduser("~/.nix-profile/share/applications"),
    "/var/lib/flatpak/exports/share/applications",
]


def _ok(msg: str) -> dict:
    return {"ok": True, "result": msg}


def _err(msg: str) -> dict:
    return {"ok": False, "error": msg}


def _spawn(argv: list[str]) -> None:
    """Lanza desacoplado del proceso (no zombies, sobrevive al daemon)."""
    subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                      stdin=subprocess.DEVNULL, start_new_session=True)


def _run(argv: list[str], timeout: int = 8) -> subprocess.CompletedProcess:
    return subprocess.run(argv, capture_output=True, text=True, timeout=timeout)


def _host_blocked(url: str) -> bool:
    """True si la URL apunta a localhost / loopback / IP privada (evita SSRF a servicios internos
    como el propio daemon :9090 o llama-server :8080)."""
    try:
        host = (urllib.parse.urlparse(url).hostname or "").lower()
    except Exception:
        return True
    if not host or host in ("localhost", "localhost.localdomain", "ip6-localhost"):
        return True
    addrs = []
    try:
        ipaddress.ip_address(host)
        addrs = [host]                       # ya es una IP literal
    except ValueError:
        try:
            addrs = [ai[4][0] for ai in socket.getaddrinfo(host, None)]
        except Exception:
            return False                     # no resuelve -> que falle la request normal
    for a in addrs:
        try:
            ip = ipaddress.ip_address(a)
            if ip.is_loopback or ip.is_private or ip.is_link_local or ip.is_reserved or ip.is_unspecified:
                return True
        except ValueError:
            pass
    return False


# ---------------------------------------------------------------- abrir apps
def _find_desktop(name: str) -> str | None:
    n = name.strip().lower().replace(" ", "")
    for d in _APP_DIRS:
        for f in glob.glob(os.path.join(d, "*.desktop")):
            base = os.path.basename(f)[:-8].lower()
            if n == base or n in base:
                return os.path.basename(f)[:-8]
    return None


def open_app(app: str) -> dict:
    """Abre un programa por nombre (binario en PATH o entrada .desktop)."""
    if not app or not re.match(r"^[\w .+\-]{1,60}$", app):
        return _err("nombre de app inválido")
    name = app.strip()
    exe = shutil.which(name) or shutil.which(name.lower())
    if exe:
        _spawn([exe])
        return _ok(f"abriendo {name}")
    desk = _find_desktop(name)
    if desk and shutil.which("gtk-launch"):
        _spawn(["gtk-launch", desk])
        return _ok(f"abriendo {name}")
    if desk and shutil.which("gio"):
        _spawn(["gio", "launch", desk])
        return _ok(f"abriendo {name}")
    return _err(f"no encontré la app «{name}» (ni binario ni .desktop)")


# ---------------------------------------------------------------- abrir URL
def open_url(url: str) -> dict:
    """Abre una página web en el navegador por defecto."""
    u = (url or "").strip()
    if not re.match(r"^https?://", u):
        u = "https://" + u
    if not re.match(r"^https?://[\w.\-]+(:\d+)?(/.*)?$", u):
        return _err("URL inválida")
    if _host_blocked(u):
        return _err("no abro direcciones locales/privadas")
    opener = shutil.which("xdg-open")
    if not opener:
        return _err("no hay xdg-open")
    _spawn([opener, u])
    return _ok(f"abriendo {u}")


# ---------------------------------------------------------------- música / media
def media(action: str) -> dict:
    """Controla el reproductor activo (MPRIS): playpause|play|pause|next|previous|stop."""
    act = (action or "").strip().lower()
    m = {"playpause": "play-pause", "play": "play", "pause": "pause",
         "next": "next", "previous": "previous", "prev": "previous", "stop": "stop"}
    if act not in m:
        return _err("acción de media inválida")
    pc = shutil.which("playerctl")
    if not pc:
        return _err("playerctl no instalado")
    try:
        r = _run([pc, m[act]])
        return _ok(f"media: {act}") if r.returncode == 0 else _err(r.stderr.strip() or "sin reproductor activo")
    except Exception as e:
        return _err(str(e))


def play_media(query: str, service: str = "spotify") -> dict:
    """Pone música/video: busca `query` en el servicio (spotify/youtube/ytmusic) y lo abre.
    Sin query, solo reanuda el reproductor activo."""
    q = (query or "").strip()
    if not q:
        return media("play")
    svc = (service or "spotify").lower()
    enc = urllib.parse.quote(q)
    urls = {
        "spotify": f"https://open.spotify.com/search/{enc}",
        "youtube": f"https://www.youtube.com/results?search_query={enc}",
        "ytmusic": f"https://music.youtube.com/search?q={enc}",
    }
    # Spotify de escritorio: abre la búsqueda y, en mejor esfuerzo, intenta darle play
    # (el cliente tarda en cargar; reintenta playerctl unos segundos). Reproducir una pista EXACTA
    # por nombre requeriría la Web API de Spotify (con login) — mejora futura.
    if svc == "spotify" and shutil.which("spotify"):
        _spawn(["spotify", f"spotify:search:{enc}"])
        if shutil.which("playerctl"):
            _spawn(["sh", "-c", "for i in $(seq 1 8); do sleep 1; playerctl -p spotify play 2>/dev/null && exit 0; done"])
        return _ok(f"abrí Spotify buscando «{q}» e intenté darle play; si no suena, toca el primer resultado")
    return open_url(urls.get(svc, urls["spotify"]))


# ---------------------------------------------------------------- volumen
def set_volume(level: str) -> dict:
    """Ajusta el volumen: "50" (porcentaje absoluto), "+10"/"-10" (relativo), "mute"."""
    lv = str(level).strip()
    wp = shutil.which("wpctl")
    sink = "@DEFAULT_AUDIO_SINK@"
    try:
        if lv in ("mute", "toggle"):
            if wp:
                _run([wp, "set-mute", sink, "toggle"]); return _ok("mute toggled")
            return _err("wpctl no disponible")
        if not re.match(r"^[+\-]?\d{1,3}$", lv):
            return _err("volumen inválido")
        if wp:
            if lv[0] in "+-":
                _run([wp, "set-volume", sink, f"{abs(int(lv))}%{'+' if lv[0]=='+' else '-'}"])
            else:
                _run([wp, "set-volume", sink, f"{min(int(lv),120)}%"])
            return _ok(f"volumen {lv}")
        pa = shutil.which("pactl")
        if pa:
            arg = f"{lv}%" if lv[0] in "+-" else f"{min(int(lv),120)}%"
            _run([pa, "set-sink-volume", "@DEFAULT_SINK@", arg]); return _ok(f"volumen {lv}")
        return _err("ni wpctl ni pactl")
    except Exception as e:
        return _err(str(e))


# ---------------------------------------------------------------- web (internet)
def web_search(query: str, n: int = 5) -> dict:
    """Busca en internet (DuckDuckGo HTML, sin API key). Devuelve título + url + extracto."""
    q = (query or "").strip()
    if not q:
        return _err("consulta vacía")
    if len(q) > 500:
        return _err("consulta muy larga (máx 500)")
    try:
        data = urllib.parse.urlencode({"q": q}).encode()
        req = urllib.request.Request("https://html.duckduckgo.com/html/", data=data,
                                     headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=12) as r:
            page = r.read().decode("utf-8", "ignore")
        results = []
        for m in re.finditer(r'<a[^>]+class="result__a"[^>]+href="([^"]+)"[^>]*>(.*?)</a>', page, re.S):
            url = urllib.parse.unquote(re.sub(r".*uddg=", "", m.group(1)).split("&")[0]) if "uddg=" in m.group(1) else m.group(1)
            title = html.unescape(re.sub("<.*?>", "", m.group(2))).strip()
            if title:
                results.append({"title": title, "url": url})
            if len(results) >= n:
                break
        if not results:
            return _err("sin resultados")
        text = "\n".join(f"{i+1}. {r['title']} — {r['url']}" for i, r in enumerate(results))
        return {"ok": True, "result": text, "results": results}
    except Exception as e:
        return _err(f"búsqueda falló: {e}")


class _SafeRedirects(urllib.request.HTTPRedirectHandler):
    """Re-valida cada redirect contra _host_blocked: sin esto, una página pública podía
    redirigir a http://127.0.0.1:8080 (o a la IP del router) y fetch_url la leía igual."""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if _host_blocked(newurl):
            raise urllib.error.URLError("redirect a dirección local/privada bloqueado")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


_SAFE_OPENER = urllib.request.build_opener(_SafeRedirects())


def fetch_url(url: str, max_chars: int = 2500) -> dict:
    """Descarga una página y devuelve su texto (sin HTML), recortado."""
    u = (url or "").strip()
    if not re.match(r"^https?://", u):
        u = "https://" + u
    if _host_blocked(u):
        return _err("no leo direcciones locales/privadas")
    try:
        req = urllib.request.Request(u, headers={"User-Agent": UA})
        with _SAFE_OPENER.open(req, timeout=12) as r:
            raw = r.read(400_000).decode("utf-8", "ignore")
        raw = re.sub(r"(?is)<(script|style|head|nav|footer).*?</\1>", " ", raw)
        text = html.unescape(re.sub(r"<[^>]+>", " ", raw))
        text = re.sub(r"\s+", " ", text).strip()
        return _ok(text[:max_chars])
    except Exception as e:
        return _err(f"fetch falló: {e}")


# ---------------------------------------------------------------- registro
_DISPATCH = {
    "open_app": lambda a: open_app(a.get("app", "")),
    "open_url": lambda a: open_url(a.get("url", "")),
    "media": lambda a: media(a.get("action", "")),
    "play_media": lambda a: play_media(a.get("query", ""), a.get("service", "spotify")),
    "set_volume": lambda a: set_volume(a.get("level", "")),
    "web_search": lambda a: web_search(a.get("query", ""), int(a.get("n", 5))),
    "fetch_url": lambda a: fetch_url(a.get("url", ""), int(a.get("max_chars", 2500))),
}

# Especificación OpenAI/Anthropic-style para function calling (la consume el agent_daemon).
TOOLS_SPEC = [
    {"name": "open_app", "description": "Abrir/lanzar un programa del sistema por su nombre (ej: firefox, code, spotify, kitty).",
     "parameters": {"type": "object", "properties": {"app": {"type": "string"}}, "required": ["app"]}},
    {"name": "open_url", "description": "Abrir una página web EN EL NAVEGADOR (el usuario la ve). Úsala también para mostrar búsquedas: para buscar en Google pasa https://www.google.com/search?q=CONSULTA, para YouTube https://www.youtube.com/results?search_query=CONSULTA.",
     "parameters": {"type": "object", "properties": {"url": {"type": "string"}}, "required": ["url"]}},
    {"name": "media", "description": "Controlar la reproducción actual: playpause, play, pause, next, previous, stop.",
     "parameters": {"type": "object", "properties": {"action": {"type": "string", "enum": ["playpause", "play", "pause", "next", "previous", "stop"]}}, "required": ["action"]}},
    {"name": "play_media", "description": "Poner música o un video: busca la consulta en Spotify/YouTube y lo abre. Sin query, reanuda.",
     "parameters": {"type": "object", "properties": {"query": {"type": "string"}, "service": {"type": "string", "enum": ["spotify", "youtube", "ytmusic"]}}, "required": ["query"]}},
    {"name": "set_volume", "description": "Ajustar volumen: '50' absoluto, '+10'/'-10' relativo, o 'mute'.",
     "parameters": {"type": "object", "properties": {"level": {"type": "string"}}, "required": ["level"]}},
    {"name": "web_search", "description": "Buscar información en internet SOLO para que TÚ la leas y se la cuentes al usuario (NO abre el navegador ni muestra nada en pantalla). Si el usuario quiere VER la búsqueda, usa open_url en su lugar.",
     "parameters": {"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]}},
    {"name": "fetch_url", "description": "Leer el contenido de texto de una página web.",
     "parameters": {"type": "object", "properties": {"url": {"type": "string"}}, "required": ["url"]}},
]


def execute(name: str, args: dict | None = None) -> dict:
    """Ejecuta una herramienta por nombre con sus argumentos (dict). Punto de entrada del agente."""
    fn = _DISPATCH.get(name)
    if not fn:
        return _err(f"herramienta desconocida: {name}")
    try:
        return fn(args or {})
    except Exception as e:
        return _err(f"{name} falló: {e}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps([t["name"] for t in TOOLS_SPEC]))
        sys.exit(0)
    cmd = sys.argv[1]
    rest = sys.argv[2:]
    # mapeo rápido para pruebas CLI
    quick = {
        "open_app": {"app": " ".join(rest)}, "open_url": {"url": " ".join(rest)},
        "media": {"action": " ".join(rest)}, "set_volume": {"level": " ".join(rest)},
        "web_search": {"query": " ".join(rest)}, "fetch_url": {"url": " ".join(rest)},
        "play_media": {"query": " ".join(rest)},
    }
    print(json.dumps(execute(cmd, quick.get(cmd, {})), ensure_ascii=False, indent=2))
