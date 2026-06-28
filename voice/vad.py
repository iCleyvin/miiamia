"""Utilidades de audio: amplitud (RMS) y detección de habla sostenida (barge-in).

Trabaja sobre bloques PCM s16le mono. Solo stdlib (array, math)."""
from __future__ import annotations

import array
import math


def rms_norm(block: bytes) -> float:
    """RMS normalizado a [0,1] de un bloque PCM s16le."""
    a = array.array("h")
    try:
        a.frombytes(block)
    except ValueError:
        return 0.0
    if not a:
        return 0.0
    acc = 0
    for x in a:
        acc += x * x
    return min(1.0, math.sqrt(acc / len(a)) / 32768.0)


class BargeInDetector:
    """True cuando hay habla por encima del umbral durante `sustain_ms` seguidos."""

    def __init__(self, threshold: float = 0.045, sustain_ms: int = 200, block_ms: int = 32):
        self.threshold = threshold
        self.need = max(1, sustain_ms // block_ms)
        self.count = 0

    def feed(self, block: bytes) -> bool:
        if rms_norm(block) >= self.threshold:
            self.count += 1
        else:
            self.count = 0
        return self.count >= self.need
