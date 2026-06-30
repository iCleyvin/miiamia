#!/usr/bin/env python3
"""agent_daemon.py — el "cerebro" enrutador de miiamia.

Servidor HTTP **OpenAI-compatible** en 127.0.0.1:9090. Como ChatBubble.qml y voice_daemon.py
ya hablan `/v1/chat/completions` (SSE) contra `ai.endpoint`, basta apuntar ese endpoint aquí
para integrarlos SIN cambiarles una línea.

Hace tres cosas:
  1) PROVIDER routing: local (llama.cpp :8080) por defecto; o cloud OpenAI-compat
     (claude / opencode / openai / groq / custom). Regla: si hay cloud bien configurado úsalo,
     si no, cae a local (nunca deja a la pet sin cerebro).
  2) TOOL-CALLING ("manos"): si está activado, corre el loop pedir→tool_calls→ejecutar→re-pedir
     con agent/tools_exec.py (seguro). Si NO está activado: passthrough SSE puro (latencia = hoy).
  3) Lee la config en vivo de ~/.config/miiamia/settings.json (cacheada por mtime). Las API keys
     viven solo ahí (gitignored) y NUNCA pasan por el cliente QML ni se loguean.

stdlib pura (sin torch/openai-sdk). Footprint ~15-20 MB, idle ~0% CPU.
Endpoints:  GET /health   ·   POST /v1/chat/completions
"""
from __future__ import annotations

import http.client
import base64
import json
import mimetypes
import os
import shutil
import subprocess
import sys
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tools_exec  # noqa: E402

HOST = "127.0.0.1"
PORT = int(os.environ.get("MIIAMIA_AGENT_PORT", "9090"))
LOCAL_URL = "http://127.0.0.1:8080/v1/chat/completions"
LOCAL_HEALTH = "http://127.0.0.1:8080/health"
SETTINGS = os.environ.get("MIIAMIA_SETTINGS", os.path.expanduser("~/.config/miiamia/settings.json"))
MAX_TOOL_HOPS = 4
EYES_DIR = os.path.expanduser("~/.cache/miiamia/eyes")

# Guía que se añade a la persona cuando las herramientas están activas (mejora el uso real de tools).
TOOL_SYSTEM = (
    "Tienes HERRAMIENTAS REALES en esta computadora; úsalas de verdad y encadena varias si hace falta. "
    "Reglas IMPORTANTES: "
    "1) Para ABRIR una web o BUSCAR algo en el NAVEGADOR (que el usuario lo VEA), usa open_url con la URL "
    "completa — para buscar en Google usa https://www.google.com/search?q=CONSULTA, para YouTube "
    "https://www.youtube.com/results?search_query=CONSULTA. NO uses web_search para eso. "
    "2) web_search/fetch_url son SOLO para que TÚ leas información y la cuentes; no abren nada en pantalla. "
    "3) Para poner música/canciones usa play_media (abre Spotify en la búsqueda; el usuario le da play). "
    "4) NUNCA digas que hiciste algo que la herramienta no confirmó. Reporta solo lo que de verdad ocurrió; "
    "si solo abriste una búsqueda, dilo así, no digas que ya está sonando."
)

# Reglas para el modo "manos completas" de Claude Code (cuando tiene Bash permitido).
HANDS_SYSTEM = (
    "ACCIONES: Tienes una terminal (Bash) para ayudar a tu humano en su Linux (Hyprland/Wayland). "
    "Úsala para ABRIR programas (lánzalos en segundo plano: `setsid firefox >/dev/null 2>&1 &`, "
    "`gtk-launch APP`, `xdg-open URL`), poner música (abrir Spotify, `playerctl play/pause/next`), "
    "ajustar volumen (`wpctl set-volume @DEFAULT_AUDIO_SINK@ 50%`), abrir webs/búsquedas "
    "(`xdg-open 'https://www.google.com/search?q=...'`). SIEMPRE lanza los programas en segundo plano "
    "(con setsid y &) para no quedarte esperando. "
    "REGLAS DE SEGURIDAD ESTRICTAS E INVIOLABLES: NUNCA borres, muevas, sobrescribas ni edites archivos; "
    "NUNCA uses rm, dd, mkfs, sudo, kill de procesos del sistema, ni nada destructivo o irreversible. "
    "Si una orden es ambigua o peligrosa, PREGUNTA antes en vez de ejecutar. Solo abres, lanzas y controlas."
)

# endpoint COMPLETO + model default + tipo de auth por provider (todos OpenAI-compat)
PROVIDERS = {
    "local":    {"url": LOCAL_URL, "model": "", "auth": None},
    "claude":   {"url": "https://api.anthropic.com/v1/chat/completions", "model": "claude-haiku-4-5-20251001", "auth": "anthropic"},
    "opencode": {"url": "https://opencode.ai/zen/v1/chat/completions", "model": "claude-haiku-4-5", "auth": "bearer"},
    "openai":   {"url": "https://api.openai.com/v1/chat/completions", "model": "gpt-4o-mini", "auth": "bearer"},
    "groq":     {"url": "https://api.groq.com/openai/v1/chat/completions", "model": "llama-3.3-70b-versatile", "auth": "bearer"},
    "custom":   {"url": "", "model": "", "auth": "bearer"},
}

_cache = {"mtime": 0, "agent": None}


def load_agent() -> dict:
    """Bloque `agent` de settings.json con defaults, cacheado por mtime."""
    try:
        st = os.stat(SETTINGS)
        if st.st_mtime != _cache["mtime"] or _cache["agent"] is None:
            with open(SETTINGS, encoding="utf-8") as f:
                s = json.load(f)
            _cache["agent"] = s.get("agent", {}) or {}
            _cache["mtime"] = st.st_mtime
    except Exception:
        _cache["agent"] = _cache["agent"] or {}
    a = dict(_cache["agent"])
    a.setdefault("provider", "local")
    a.setdefault("api_key", "")
    a.setdefault("base_url", "")
    a.setdefault("model", "")
    if not isinstance(a.get("tools"), dict):
        a["tools"] = {"enabled": False}
    a["tools"].setdefault("enabled", False)
    a["tools"].setdefault("verbose", False)
    return a


def _claude_bin() -> str:
    """Ruta al CLI `claude` (Claude Code), o "" si no está instalado."""
    b = shutil.which("claude")
    if b:
        return b
    home = os.path.expanduser("~/.local/bin/claude")
    return home if os.path.exists(home) else ""


def effective(agent: dict):
    """Devuelve (provider, url, model, api_key, auth). Cae a local si está mal configurado."""
    p = (agent.get("provider") or "local").lower()
    key = agent.get("api_key") or os.environ.get("MIIAMIA_API_KEY", "")
    if p == "local":
        prov = PROVIDERS["local"]
        return "local", prov["url"], agent.get("model") or "", "", None
    if p in ("claude-cli", "claude-max", "agent-sdk"):
        # Usa el CLI `claude` (Claude Code) con el LOGIN del usuario (p.ej. suscripción Max).
        # Sin API key, sin HTTP. Si el CLI no está, cae a local.
        if _claude_bin():
            return "claude-cli", "", agent.get("model") or "", "", "cli"
        return effective({"provider": "local"})
    if p in ("cloud", "custom"):
        base = (agent.get("base_url") or "").rstrip("/")
        if not (base and key):
            return effective({"provider": "local"})
        # construir el endpoint sin duplicar el path si el usuario ya dio la URL completa
        if base.endswith("/chat/completions"):
            url = base
        elif base.endswith("/v1"):
            url = base + "/chat/completions"
        else:
            url = base + "/v1/chat/completions"
        return "cloud", url, agent.get("model") or "", key, "bearer"
    prov = PROVIDERS.get(p)
    if not prov or not key:
        return effective({"provider": "local"})
    return p, prov["url"], agent.get("model") or prov["model"], key, prov["auth"]


def auth_headers(auth: str | None, key: str) -> dict:
    h = {"Content-Type": "application/json"}
    if auth == "anthropic":
        # Endpoint OpenAI-compat de Anthropic. Mandamos x-api-key + anthropic-version (lo que la API
        # de Anthropic exige) y además Authorization Bearer (lo que acepta el endpoint compat) -> robusto.
        h["x-api-key"] = key
        h["anthropic-version"] = "2023-06-01"
        h["Authorization"] = "Bearer " + key
    elif auth == "bearer":
        h["Authorization"] = "Bearer " + key
    return h


def _image_url_to_data_url(url: str) -> str:
    """Convierte file:///path o path local a data URL para providers OpenAI-compat."""
    if not url:
        return url
    if url.startswith("data:"):
        return url
    path = url[7:] if url.startswith("file://") else url
    if not os.path.exists(path):
        return url
    mt = mimetypes.guess_type(path)[0] or "image/png"
    with open(path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("ascii")
    return f"data:{mt};base64,{b64}"


def _normalize_multimodal_messages(messages: list[dict], for_provider: str) -> list[dict]:
    """Prepara mensajes con imágenes locales para providers HTTP.

    - local llama.cpp actual: no tiene visión; convierte la imagen en aviso textual.
    - cloud/openai-compatible: convierte file:// a data URL.
    """
    out = []
    for m in messages:
        content = m.get("content")
        if not isinstance(content, list):
            out.append(m)
            continue

        parts = []
        text_bits = []
        has_image = False
        for p in content:
            if not isinstance(p, dict):
                continue
            if p.get("type") == "text":
                txt = p.get("text") or ""
                text_bits.append(txt)
                parts.append({"type": "text", "text": txt})
            elif p.get("type") == "image_url":
                has_image = True
                iu = p.get("image_url") or {}
                url = iu.get("url") or ""
                parts.append({"type": "image_url", "image_url": {"url": _image_url_to_data_url(url)}})
        if for_provider == "local" and has_image:
            text = "\n".join(t for t in text_bits if t).strip()
            text += "\n\n[El usuario te mostró una imagen de la pantalla, pero el cerebro local activo no soporta visión. Pídele cambiar a un proveedor con visión como claude-cli/openai si quiere que la analices.]"
            out.append({**m, "content": text})
        else:
            out.append({**m, "content": parts})
    return out


def _content_text_and_images(content) -> tuple[str, list[str]]:
    """Extrae texto y rutas locales de un content OpenAI multimodal."""
    if isinstance(content, str):
        return content.strip(), []
    if not isinstance(content, list):
        return str(content or "").strip(), []
    texts, images = [], []
    for p in content:
        if not isinstance(p, dict):
            continue
        if p.get("type") == "text":
            texts.append(p.get("text") or "")
        elif p.get("type") == "image_url":
            url = ((p.get("image_url") or {}).get("url") or "").strip()
            if url.startswith("file://"):
                path = url[7:]
                if os.path.exists(path):
                    images.append(path)
            elif url.startswith("/") and os.path.exists(url):
                images.append(url)
    return "\n".join(t for t in texts if t).strip(), images


def _conn(url: str):
    u = urllib.parse.urlparse(url)
    cls = http.client.HTTPSConnection if u.scheme == "https" else http.client.HTTPConnection
    path = u.path + ("?" + u.query if u.query else "")
    return cls(u.netloc, timeout=120), path


def upstream_once(url, headers, payload):
    """Pide al provider en NO-stream. Devuelve el message dict (content, tool_calls) o lanza."""
    payload = dict(payload); payload["stream"] = False
    conn, path = _conn(url)
    try:
        conn.request("POST", path, body=json.dumps(payload), headers=headers)
        r = conn.getresponse()
        raw = r.read(2_000_000).decode("utf-8", "ignore")
        if r.status >= 400:
            sys.stderr.write(f"[agent] upstream {r.status}: {raw[:200]}\n")   # detalle SOLO en log
            raise RuntimeError(f"HTTP {r.status}")                            # al cliente, sin body
        data = json.loads(raw)
        return (data.get("choices") or [{}])[0].get("message", {}) or {}
    finally:
        conn.close()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass  # silencio (no ensuciar journal ni filtrar nada)

    # ---- health: para local refleja el estado de llama-server; para cloud, ok ----
    def do_GET(self):
        if self.path.rstrip("/") != "/health":
            self.send_error(404); return
        agent = load_agent()
        prov, *_ = effective(agent)
        ok = True
        if prov == "local":
            try:
                conn, path = _conn(LOCAL_HEALTH)
                try:
                    conn.request("GET", path); ok = conn.getresponse().status < 500
                finally:
                    conn.close()   # cierre garantizado (evita fuga de descriptores)
            except Exception:
                ok = False
        body = json.dumps({"status": "ok" if ok else "loading", "provider": prov}).encode()
        self.send_response(200 if ok else 503)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path.rstrip("/") not in ("/v1/chat/completions", "/chat/completions"):
            self.send_error(404); return
        try:
            n = int(self.headers.get("Content-Length", 0))
            req = json.loads(self.rfile.read(n).decode("utf-8", "ignore"))
        except Exception:
            self.send_error(400); return

        agent = load_agent()
        prov, url, model, key, auth = effective(agent)

        # Proveedor "Claude Code" (CLI `claude -p` con el login del usuario) — no es HTTP.
        if prov == "claude-cli":
            self._start_sse()
            try:
                self._claude_cli(req.get("messages", []), model, bool(agent["tools"]["enabled"]))
            except Exception as e:
                self._sse_text(f"(error de Claude Code: {e})"); self._sse_done()
            return

        headers = auth_headers(auth, key)
        tools_on = bool(agent["tools"]["enabled"])

        # payload base hacia el provider
        payload = {k: v for k, v in req.items() if k in ("messages", "temperature", "top_p", "max_tokens", "stop")}
        payload["messages"] = _normalize_multimodal_messages(req.get("messages", []), prov)
        if model:
            payload["model"] = model
        elif req.get("model"):
            payload["model"] = req["model"]
        if prov == "local":
            # Qwen3: sin "thinking" para respuestas directas (igual que hoy)
            payload.setdefault("chat_template_kwargs", req.get("chat_template_kwargs", {"enable_thinking": False}))

        # Con tools activas, reforzar a la persona cómo usar las herramientas (sin pisarla).
        if tools_on:
            m = payload["messages"]
            if m and m[0].get("role") == "system":
                m[0] = {"role": "system", "content": (m[0].get("content") or "") + "\n\n" + TOOL_SYSTEM}
            else:
                m.insert(0, {"role": "system", "content": TOOL_SYSTEM})

        self._start_sse()
        try:
            if not tools_on:
                self._passthrough_stream(url, headers, payload)
            else:
                self._tool_loop(url, headers, payload, prov)
        except BrokenPipeError:
            return
        except Exception as e:
            self._sse_text(f"(error del cerebro: {e})")
            self._sse_done()

    # -------------------------------------------------- SSE helpers
    def _start_sse(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")   # cerrar al terminar => el cliente detecta el fin del stream
        self.end_headers()
        self.close_connection = True

    def _write(self, b: bytes):
        self.wfile.write(b); self.wfile.flush()

    def _sse_text(self, text: str):
        if not text:
            return
        obj = {"choices": [{"index": 0, "delta": {"content": text}, "finish_reason": None}]}
        self._write(b"data: " + json.dumps(obj, ensure_ascii=False).encode() + b"\n\n")

    def _sse_done(self):
        obj = {"choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]}
        self._write(b"data: " + json.dumps(obj).encode() + b"\n\n")
        self._write(b"data: [DONE]\n\n")

    # -------------------------------------------------- modo sin tools: proxy SSE puro
    def _passthrough_stream(self, url, headers, payload):
        payload = dict(payload); payload["stream"] = True
        conn, path = _conn(url)
        try:
            conn.request("POST", path, body=json.dumps(payload), headers=headers)
            r = conn.getresponse()
            if r.status >= 400:
                sys.stderr.write(f"[agent] provider {r.status}: {r.read(2000).decode('utf-8','ignore')[:200]}\n")
                self._sse_text(f"(error del proveedor: HTTP {r.status})")   # sin body al cliente
                self._sse_done(); return
            # reenvío por LÍNEAS con readline() (no bloquea esperando llenar buffer cuando el
            # upstream no manda Content-Length) y paro en [DONE].
            saw_done = False
            while True:
                line = r.readline()
                if not line:
                    break
                self._write(line)
                if line.strip() == b"data: [DONE]":
                    saw_done = True
                    break
            if not saw_done:
                self._sse_done()   # cierre SSE limpio aunque el upstream corte sin [DONE]
        finally:
            conn.close()

    # frases cortas mientras ejecuta una acción (se ven en el chat y se leen por TTS)
    FEEDBACK = {
        "open_app": "🔧 abriendo… ", "open_url": "🌐 abriendo la web… ", "media": "⏯️ ",
        "play_media": "🎵 poniendo música… ", "set_volume": "🔊 ", "web_search": "🔎 buscando… ",
        "fetch_url": "📄 leyendo… ",
    }

    # -------------------------------------------------- modo con tools: loop de orquestación
    def _tool_loop(self, url, headers, payload, prov):
        msgs = list(payload["messages"])
        oai_tools = [{"type": "function", "function": t} for t in tools_exec.TOOLS_SPEC]
        verbose = bool(load_agent()["tools"].get("verbose"))
        for _ in range(MAX_TOOL_HOPS):
            p = dict(payload); p["messages"] = msgs; p["tools"] = oai_tools; p["tool_choice"] = "auto"
            msg = upstream_once(url, headers, p)
            calls = msg.get("tool_calls") or []
            if not calls:
                self._sse_text(msg.get("content") or "")
                self._sse_done(); return
            # content "" (no None): algunos providers rechazan content:null junto a tool_calls
            msgs.append({"role": "assistant", "content": msg.get("content") or "", "tool_calls": calls})
            for tc in calls:
                fn = tc.get("function", {})
                name = fn.get("name", "")
                try:
                    args = json.loads(fn.get("arguments") or "{}")
                except Exception:
                    args = {}
                if verbose:
                    self._sse_text(self.FEEDBACK.get(name, f"[{name}] "))
                res = tools_exec.execute(name, args)
                # tool_call_id DEBE ser el id real del tool_call (correlación con el result)
                msgs.append({"role": "tool", "tool_call_id": tc.get("id") or f"call_{name}",
                             "content": json.dumps(res, ensure_ascii=False)[:1500]})
        # agotó hops -> una respuesta final sin tools
        p = dict(payload); p["messages"] = msgs
        try:
            msg = upstream_once(url, headers, p)
            self._sse_text(msg.get("content") or "(no pude completar la acción)")
        except Exception as e:
            self._sse_text(f"(error: {e})")
        self._sse_done()

    # -------------------------------------------------- Claude Code (CLI con login del usuario)
    def _claude_cli(self, msgs, model, hands=False):
        # persona (system) + historial como prompt -> el CLI mantiene la inteligencia de Claude.
        persona, convo = [], []
        image_paths = []
        for m in msgs:
            role = m.get("role")
            content, imgs = _content_text_and_images(m.get("content"))
            image_paths.extend(imgs)
            if not content:
                continue
            if role == "system":
                persona.append(content)
            elif role == "user":
                convo.append("Usuario: " + content)
            elif role == "assistant":
                convo.append("Tú: " + content)
        prompt = "\n".join(convo) if convo else "Hola"
        # stream-json -> tokens en vivo (no esperar toda la respuesta en blanco).
        # --strict-mcp-config + config vacía: NO cargar los MCP servers del usuario (Canva/Gmail/
        # android…) -> arranque mucho más rápido. La pet no los necesita.
        cmd = [_claude_bin(), "-p", "--output-format", "stream-json",
               "--include-partial-messages", "--verbose",
               "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}']
        if model:
            cmd += ["--model", model]
        sp = "\n".join(persona).strip()
        allowed_tools = []
        if hands:
            # "manos completas": Claude Code puede ejecutar comandos (Bash) con reglas de seguridad.
            sp = (sp + "\n\n" + HANDS_SYSTEM).strip()
            allowed_tools.append("Bash")
        if image_paths:
            # Claude Code puede inspeccionar imágenes locales con Read. Limitamos el acceso al cache
            # de capturas y pedimos explícitamente que las lea como contexto visual.
            cmd += ["--add-dir", EYES_DIR]
            allowed_tools.append("Read")
            prompt += "\n\nImágenes adjuntas por el usuario (capturas de pantalla locales). Usa Read para inspeccionarlas visualmente antes de responder:\n"
            prompt += "\n".join(f"- {p}" for p in image_paths)
        if allowed_tools:
            cmd += ["--allowedTools", ",".join(sorted(set(allowed_tools)))]
        if sp:
            cmd += ["--append-system-prompt", sp]
        # cwd neutro y dedicado: evita cargar el CLAUDE.md/proyecto del directorio del servicio.
        workdir = os.path.expanduser("~/.cache/miiamia/agent")
        try:
            os.makedirs(workdir, exist_ok=True)
        except Exception:
            workdir = None
        try:
            proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, text=True, cwd=workdir)
        except Exception as e:
            self._sse_text(f"(no pude lanzar Claude Code: {e})"); self._sse_done(); return
        killer = threading.Timer(150, lambda: proc.kill())   # watchdog anti-cuelgue
        killer.start()
        got = False
        try:
            proc.stdin.write(prompt); proc.stdin.close()
            for line in proc.stdout:
                line = line.strip()
                if not line:
                    continue
                try:
                    ev = json.loads(line)
                except Exception:
                    continue
                t = ev.get("type")
                if t == "stream_event":
                    e = ev.get("event", {})
                    if e.get("type") == "content_block_delta":
                        d = e.get("delta", {})
                        if d.get("type") == "text_delta" and d.get("text"):
                            self._sse_text(d["text"]); got = True
                elif t == "result":
                    if not got and ev.get("result"):     # fallback si no hubo deltas
                        self._sse_text(ev["result"]); got = True
                    break
        except Exception as e:
            sys.stderr.write(f"[claude-cli] stream err: {e}\n")
        finally:
            killer.cancel()
            try:
                proc.terminate(); proc.wait(timeout=5)
            except Exception:
                try: proc.kill()
                except Exception: pass
        if not got:
            err = ""
            try: err = (proc.stderr.read() or "")[:200]
            except Exception: pass
            sys.stderr.write(f"[claude-cli] sin salida. stderr: {err}\n")
            self._sse_text("(no pude usar Claude Code; verifica que `claude` esté logueado en tu terminal)")
        self._sse_done()


def main():
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    srv.daemon_threads = True   # los hilos de request no bloquean el cierre
    sys.stderr.write(f"agent_daemon escuchando en http://{HOST}:{PORT}\n"); sys.stderr.flush()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.server_close()      # libera el socket/puerto (evita 'Address already in use' al reiniciar)


if __name__ == "__main__":
    main()
