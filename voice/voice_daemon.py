#!/usr/bin/env python3
"""miiamia — daemon de voz (Python 3 stdlib puro; nada de torch/ctranslate2).

Protocolo con VoiceManager.qml por stdio JSON-lines:
  stdin  (comandos): {"cmd":"config", ...} | {"cmd":"ptt_start"} | {"cmd":"ptt_stop"}
                     | {"cmd":"cancel"} | {"cmd":"gaming","on":true}
  stdout (eventos):  {"event":"ready"}
                     {"event":"state","value":"idle|listening|thinking|speaking"}
                     {"event":"amplitude","value":0.0..1.0}
                     {"event":"transcript","text":...} | {"event":"reply","text":...}
                     {"event":"error","msg":...}

Pipeline: mantener pulsado -> graba mic (pw-cat) -> soltar -> whisper (STT) ->
LLM local (/v1 streaming) -> Piper (TTS) frase por frase -> pw-play, con lip-sync.
"""
from __future__ import annotations

import http.client
import io
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vad import rms_norm                # noqa: E402
from whisper_client import WhisperServer  # noqa: E402
from sentence import SentenceSplitter   # noqa: E402
import tts                              # noqa: E402

_OUT_LOCK = threading.Lock()
_THINK = re.compile(r"\s*<think>[\s\S]*?</think>\s*")
# "Ojos por voz": si le pides que mire la pantalla, captura y manda la imagen al cerebro.
_VISION_RE = re.compile(
    r"(mira|miras|ve|ves|checa|revisa|observa|dime)[^.!?]{0,40}(pantalla|monitor)"
    r"|qu[eé] (ves|hay|estoy (viendo|haciendo))"
    r"|mira (esto|lo que)", re.I)


def emit(**obj):
    with _OUT_LOCK:
        sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
        sys.stdout.flush()


def _strip_think(t: str) -> str:
    m = _THINK.match(t)
    if m:
        return t[m.end():]
    if re.match(r"\s*<think>", t) and "</think>" not in t:
        return ""   # bloque abierto, aún sin cerrar -> no mostrar todavía
    return t


def _pcm_to_wav(pcm: bytes, rate: int) -> bytes:
    b = io.BytesIO()
    w = wave.open(b, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(rate)
    w.writeframes(pcm)
    w.close()
    return b.getvalue()


def _hostport(url: str):
    u = url.split("://", 1)[-1].split("/", 1)[0]
    if ":" in u:
        h, p = u.split(":", 1)
        return h, int(p)
    return u, 80


class VoiceDaemon:
    REC_RATE = 16000

    def __init__(self):
        self.cfg = {
            "ai_url": "http://127.0.0.1:8080", "model": "kira", "persona": "",
            "piper_bin": "piper", "piper_voice": "", "speaker": 1,
            "whisper_bin": "whisper-server", "whisper_model": "",
            "whisper_port": 8765, "language": "es",
            "vision": False,   # el cerebro efectivo tiene visión (lo pone shell.qml)
            "monitor": "",     # monitor a capturar para los "ojos por voz"
        }
        self._voice_dl = threading.Lock()   # una descarga de voz a la vez
        self.whisper = None
        self.rec_proc = None
        self.rec_buf = bytearray()
        self.recording = False
        self.speaking = False
        self.stop_speaking = False
        self.history = []   # memoria de la conversación (se comparte entre turnos de voz)
        self.whisper_idle_secs = 180   # descarga whisper-server tras N s sin usarlo (libera VRAM)
        self._whisper_timer = None
        self._whisper_lock = threading.Lock()      # serializa start/stop/transcribe de whisper
        self._pipeline_active = threading.Event()  # evita dos pipelines de voz en paralelo

    # ---------------- comandos ----------------
    def handle(self, msg: dict):
        cmd = msg.get("cmd")
        if cmd == "config":
            new = {k: v for k, v in msg.items() if k != "cmd"}
            # si cambió el modelo de escucha, reinicia whisper-server (carga el nuevo bajo demanda)
            if (self.whisper is not None and new.get("whisper_model")
                    and new["whisper_model"] != self.cfg.get("whisper_model")):
                with self._whisper_lock:
                    if self.whisper:
                        self.whisper.stop()
                        self.whisper = None
            self.cfg.update(new)
            self._ensure_voice()   # voz per-pet que aún no está en disco -> descargarla ya
        elif cmd == "ptt_start":
            self.start_recording()
        elif cmd == "ptt_stop":
            self.stop_recording_and_process()
        elif cmd == "cancel":
            self.cancel()
        elif cmd == "reset":
            self.history = []
        elif cmd == "say":
            # La pet habla por iniciativa propia (comentario espontáneo): solo TTS, sin STT/LLM.
            threading.Thread(target=self.speak_text, args=(msg.get("text", ""),), daemon=True).start()
        elif cmd == "gaming" and msg.get("on"):
            with self._whisper_lock:
                if self.whisper:
                    self.whisper.stop()
                    self.whisper = None

    # ---------------- voz per-pet: auto-descarga si falta ----------------
    def _ensure_voice(self):
        """Si la voz Piper configurada no está en disco, la baja en segundo plano con
        tools/get_voice.sh. Así una skin con voz temática funciona a la primera."""
        vm = self.cfg.get("piper_voice", "")
        if not vm or os.path.exists(vm):
            return
        name = os.path.basename(vm)
        if name.endswith(".onnx"):
            name = name[:-5]
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools", "get_voice.sh")
        if not os.path.exists(script):
            return

        def dl():
            if not self._voice_dl.acquire(blocking=False):
                return   # ya hay una descarga en curso
            try:
                emit(event="info", msg=f"descargando la voz {name}…")
                r = subprocess.run(["bash", script, name], capture_output=True, text=True, timeout=600)
                if r.returncode == 0:
                    emit(event="info", msg=f"voz {name} lista")
                else:
                    emit(event="error", msg=f"no pude descargar la voz {name}")
            except Exception as e:
                emit(event="error", msg=f"descarga de voz falló: {e}")
            finally:
                self._voice_dl.release()

        threading.Thread(target=dl, daemon=True).start()

    # ---------------- ojos por voz ----------------
    def _capture_screen(self):
        """Captura la pantalla para el cerebro con visión. Devuelve la ruta o None."""
        path = os.path.expanduser("~/.cache/miiamia/eyes/voice.png")
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            cmd = ["grim"]
            mon = self.cfg.get("monitor") or ""
            if mon:
                cmd += ["-o", mon]
            cmd += ["-t", "png", path]
            subprocess.run(cmd, check=True, timeout=10, capture_output=True)
        except Exception:
            return None
        if shutil.which("magick"):   # menos tokens/latencia; sin magick va completa
            try:
                subprocess.run(["magick", path, "-resize", "1280x>", path],
                               timeout=15, capture_output=True)
            except Exception:
                pass
        return path

    # ---------------- grabación ----------------
    def start_recording(self):
        if self.recording:
            return
        if self.speaking:          # apretar para hablar mientras habla = barge-in
            self.stop_speaking = True
        self._cancel_whisper_idle()   # lo vamos a usar, no lo descargues
        self.rec_buf = bytearray()
        self.recording = True
        emit(event="state", value="listening")
        # pw-cat: PCM s16 mono 16k crudo a stdout
        self.rec_proc = subprocess.Popen(
            ["pw-cat", "--record", "--rate", str(self.REC_RATE), "--channels", "1",
             "--format", "s16", "--raw", "-"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        threading.Thread(target=self._rec_loop, daemon=True).start()

    def _rec_loop(self):
        p = self.rec_proc
        while self.recording and p and p.poll() is None:
            block = p.stdout.read(1024)   # 512 samples @16k ≈ 32 ms
            if not block:
                break
            self.rec_buf += block
            emit(event="amplitude", value=round(rms_norm(block), 3))

    def _reap_rec(self):
        """Termina y recolecta pw-cat (sin dejar zombie)."""
        if self.rec_proc:
            try:
                self.rec_proc.terminate()
                try:
                    self.rec_proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.rec_proc.kill()
                    self.rec_proc.wait()
            except Exception:
                pass
            self.rec_proc = None

    def stop_recording_and_process(self):
        if not self.recording:
            return
        self.recording = False
        self._reap_rec()
        emit(event="amplitude", value=0.0)
        if self._pipeline_active.is_set():
            # ya hay un pipeline en curso; descarta este audio (evita solapamiento) — pero
            # AVISA: antes se tiraba en silencio y el QML quedaba en "listening" sin feedback.
            emit(event="error", msg="aún estaba respondiendo; repite eso en un momento")
            emit(event="state", value="idle")
            return
        audio = bytes(self.rec_buf)
        threading.Thread(target=self._pipeline, args=(audio,), daemon=True).start()

    def cancel(self):
        self.recording = False
        self.stop_speaking = True
        self._reap_rec()
        emit(event="state", value="idle")
        emit(event="amplitude", value=0.0)

    # ---------------- descarga perezosa de whisper (libera VRAM) ----------------
    def _cancel_whisper_idle(self):
        if self._whisper_timer:
            self._whisper_timer.cancel()
            self._whisper_timer = None

    def _arm_whisper_idle(self):
        self._cancel_whisper_idle()
        t = threading.Timer(self.whisper_idle_secs, self._unload_whisper)
        t.daemon = True
        self._whisper_timer = t
        t.start()

    def _unload_whisper(self):
        # No descargues si hay una transcripción en curso (lock ocupado); reintenta luego.
        if self._whisper_lock.acquire(blocking=False):
            try:
                if self.whisper:
                    self.whisper.stop()
                    self.whisper = None
                    emit(event="info", msg="whisper descargado por inactividad")
            finally:
                self._whisper_lock.release()
        else:
            self._arm_whisper_idle()

    # ---------------- pipeline STT -> LLM -> TTS ----------------
    def _pipeline(self, audio: bytes):
        if len(audio) < int(self.REC_RATE * 2 * 0.3):   # < ~0.3 s -> ignora
            emit(event="state", value="idle")
            return
        self._pipeline_active.set()
        try:
            emit(event="state", value="thinking")
            text = self._transcribe(audio)
            if not text:
                emit(event="state", value="idle")
                return
            emit(event="transcript", text=text)
            self._converse(text)
        except Exception as e:
            emit(event="error", msg=str(e))
            emit(event="state", value="idle")
        finally:
            self._pipeline_active.clear()
            self._arm_whisper_idle()   # si no hablas más, descarga whisper y libera VRAM

    def _transcribe(self, audio: bytes) -> str:
        with self._whisper_lock:
            if self.whisper is None:
                self.whisper = WhisperServer(self.cfg["whisper_bin"], self.cfg["whisper_model"],
                                             self.cfg["whisper_port"], self.cfg["language"])
            self.whisper.start()
            return self.whisper.transcribe(_pcm_to_wav(audio, self.REC_RATE))

    def _converse(self, user_text: str):
        self._last_user = user_text
        # "Ojos por voz": si pides que mire la pantalla y el cerebro tiene visión, se captura
        # y se adjunta la imagen a este turno (el historial guarda solo el texto).
        image_path = None
        if self.cfg.get("vision") and _VISION_RE.search(user_text):
            image_path = self._capture_screen()
            if image_path is None:
                emit(event="error", msg="no pude capturar la pantalla (¿grim instalado?)")
        self.stop_speaking = False   # limpia ANTES de marcar speaking (evita carrera con barge-in)
        splitter = SentenceSplitter()
        self.speaking = True
        emit(event="state", value="speaking")
        reply = []

        def say(sentence: str):
            if self.stop_speaking:
                return
            tts.speak(sentence, self.cfg["piper_bin"], self.cfg["piper_voice"],
                      speaker=self.cfg.get("speaker", 1),
                      fx=self.cfg.get("voice_fx", ""),
                      length_scale=self.cfg.get("length_scale", 1.0),
                      amplitude_cb=lambda v: emit(event="amplitude", value=round(v, 3)),
                      stop_flag=lambda: self.stop_speaking)

        try:
            for chunk in self._llm_stream(user_text, image_path=image_path):
                if self.stop_speaking:
                    break
                for sent in splitter.feed(chunk):
                    reply.append(sent)
                    say(sent)
            if not self.stop_speaking:
                for sent in splitter.flush():
                    reply.append(sent)
                    say(sent)
        finally:
            # tts.speak puede lanzar (p.ej. voz Piper inexistente); sin esto `speaking`
            # quedaba True para siempre y cada PTT posterior mandaba un barge-in espurio.
            self.speaking = False
        reply_text = " ".join(reply)
        # Guarda el turno en la memoria (limitada a ~6 turnos para acotar el contexto).
        self.history.append({"role": "user", "content": self._last_user})
        self.history.append({"role": "assistant", "content": reply_text})
        self.history = self.history[-12:]
        emit(event="reply", text=reply_text)
        emit(event="amplitude", value=0.0)
        emit(event="state", value="idle")

    def speak_text(self, text: str):
        """TTS de un texto dado (comentario espontáneo de la pet). Sin STT ni LLM.

        Reusa el mismo camino que _converse: estado speaking + amplitud (lip-sync) + barge-in.
        No pisa una conversación de voz en curso (respeta _pipeline_active)."""
        text = (text or "").strip()
        if not text or self._pipeline_active.is_set():
            return
        self._pipeline_active.set()
        self.stop_speaking = False
        self.speaking = True
        emit(event="state", value="speaking")
        splitter = SentenceSplitter()

        def say(sentence: str):
            if self.stop_speaking:
                return
            tts.speak(sentence, self.cfg["piper_bin"], self.cfg["piper_voice"],
                      speaker=self.cfg.get("speaker", 1),
                      fx=self.cfg.get("voice_fx", ""),
                      length_scale=self.cfg.get("length_scale", 1.0),
                      amplitude_cb=lambda v: emit(event="amplitude", value=round(v, 3)),
                      stop_flag=lambda: self.stop_speaking)

        try:
            for sent in splitter.feed(text):
                if self.stop_speaking:
                    break
                say(sent)
            if not self.stop_speaking:
                for sent in splitter.flush():
                    say(sent)
        except Exception as e:
            emit(event="error", msg=str(e))
        finally:
            self.speaking = False
            emit(event="amplitude", value=0.0)
            emit(event="state", value="idle")
            self._pipeline_active.clear()

    def _llm_stream(self, user_text: str, image_path: str = None):
        msgs = []
        if self.cfg.get("persona"):
            msgs.append({"role": "system", "content": self.cfg["persona"]})
        msgs.extend(self.history)   # turnos anteriores -> continuidad
        # OJO: NO añadir "/no_think" al mensaje (es de SmolLM3, no de Qwen3): con Qwen3 entra
        # como texto plano al prompt y con provider cloud le llega tal cual a Claude. El thinking
        # se suprime con chat_template_kwargs.enable_thinking=false (abajo).
        if image_path:
            content = [{"type": "text", "text": user_text},
                       {"type": "image_url", "image_url": {"url": "file://" + image_path}}]
        else:
            content = user_text
        msgs.append({"role": "user", "content": content})
        body = json.dumps({
            "model": self.cfg["model"], "messages": msgs, "stream": True,
            "chat_template_kwargs": {"enable_thinking": False},
        })
        host, port = _hostport(self.cfg["ai_url"])
        conn = http.client.HTTPConnection(host, port, timeout=30)   # voz: no congelar 2 min si el motor cuelga
        try:
            conn.request("POST", "/v1/chat/completions", body,
                         {"Content-Type": "application/json"})
            resp = conn.getresponse()
            raw, emitted = "", 0
            for line in resp:
                s = line.decode("utf-8", "replace").strip()
                if not s.startswith("data:"):
                    continue
                payload = s[5:].strip()
                if payload == "[DONE]" or not payload:
                    continue
                try:
                    o = json.loads(payload)
                except Exception:
                    continue
                piece = (o.get("choices") or [{}])[0].get("delta", {}).get("content") or ""
                if not piece:
                    continue
                raw += piece
                stripped = _strip_think(raw)
                if len(stripped) > emitted:
                    yield stripped[emitted:]
                    emitted = len(stripped)
        finally:
            conn.close()   # cierra el socket aunque haya barge-in (generador cerrado)


def main():
    d = VoiceDaemon()

    def _cleanup(sig, frame):
        try:
            d.cancel()
            if d.whisper:
                d.whisper.stop()
        finally:
            sys.exit(0)
    signal.signal(signal.SIGTERM, _cleanup)
    signal.signal(signal.SIGINT, _cleanup)

    emit(event="ready")
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except Exception:
            continue
        try:
            d.handle(msg)
        except Exception as e:
            emit(event="error", msg=str(e))


if __name__ == "__main__":
    main()
