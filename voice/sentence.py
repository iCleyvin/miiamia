"""Divide un stream de texto (tokens del LLM) en frases completas para TTS por chunks.

Permite pipelining: hablar la frase N mientras el LLM genera la N+1."""
from __future__ import annotations

import re

_END = re.compile(r"[.!?;…]")


class SentenceSplitter:
    def __init__(self, min_words: int = 4):
        self.buf = ""
        self.min_words = min_words

    def feed(self, chunk: str) -> list[str]:
        """Acumula `chunk` y devuelve las frases completas que hayan quedado listas."""
        out: list[str] = []
        self.buf += chunk
        search_from = 0
        while True:
            m = _END.search(self.buf, search_from)
            if not m:
                break
            idx = m.end()
            sent = self.buf[:idx].strip()
            if len(sent.split()) >= self.min_words:
                out.append(sent)
                self.buf = self.buf[idx:].lstrip()
                search_from = 0
            else:
                # frase demasiado corta (abreviatura, número): sigue acumulando
                search_from = idx
        return out

    def flush(self) -> list[str]:
        """Lo que quede sin terminador al final del stream."""
        s = self.buf.strip()
        self.buf = ""
        return [s] if s else []
