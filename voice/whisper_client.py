"""Cliente de whisper-server (whisper.cpp) + gestión de su ciclo de vida.

whisper-server expone /inference (multipart/form-data, campo 'file' = audio WAV).
Lo arrancamos como proceso hijo perezoso y lo matamos para liberar RAM. Solo stdlib."""
from __future__ import annotations

import http.client
import json
import os
import socket
import subprocess
import time
import uuid


class WhisperServer:
    def __init__(self, binary: str = "whisper-server", model: str = "",
                 port: int = 8765, language: str = "es"):
        self.binary = binary or "whisper-server"
        self.model = model
        self.port = int(port)
        self.language = language
        self.proc = None

    def is_up(self) -> bool:
        with socket.socket() as s:
            s.settimeout(0.2)
            try:
                s.connect(("127.0.0.1", self.port))
                return True
            except OSError:
                return False

    def start(self, timeout: float = 45.0) -> bool:
        if self.is_up():
            return True
        if not self.model or not os.path.exists(self.model):
            raise FileNotFoundError("modelo whisper no encontrado: %r" % self.model)
        self.proc = subprocess.Popen(
            [self.binary, "-m", self.model, "--host", "127.0.0.1",
             "--port", str(self.port), "--language", self.language, "--threads", "4"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        t0 = time.monotonic()
        while time.monotonic() - t0 < timeout:
            if self.is_up():
                return True
            if self.proc.poll() is not None:
                raise RuntimeError("whisper-server salió con código %s" % self.proc.returncode)
            time.sleep(0.3)
        raise TimeoutError("whisper-server no respondió a tiempo")

    def transcribe(self, wav_bytes: bytes) -> str:
        boundary = "----miiamia" + uuid.uuid4().hex
        b = bytearray()
        b += ("--%s\r\n" % boundary).encode()
        b += b'Content-Disposition: form-data; name="file"; filename="a.wav"\r\n'
        b += b"Content-Type: audio/wav\r\n\r\n"
        b += wav_bytes + b"\r\n"
        for name, value in (("response_format", "json"),
                            ("language", self.language),
                            ("temperature", "0")):
            b += ("--%s\r\n" % boundary).encode()
            b += ('Content-Disposition: form-data; name="%s"\r\n\r\n' % name).encode()
            b += ("%s\r\n" % value).encode()
        b += ("--%s--\r\n" % boundary).encode()

        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=60)
        conn.request("POST", "/inference", bytes(b),
                     {"Content-Type": "multipart/form-data; boundary=%s" % boundary})
        resp = conn.getresponse()
        data = resp.read().decode("utf-8", "replace")
        conn.close()
        try:
            return (json.loads(data).get("text") or "").strip()
        except Exception:
            return data.strip()

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()   # recolecta el zombie tras SIGKILL
        self.proc = None
