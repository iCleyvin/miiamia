#!/usr/bin/env python3
"""Sintetiza los sonidos del mundo de Otto (pulpo LEGO) — stdlib puro, sin samples.

El pulpo no vocaliza: su mundo suena a agua. Burbujas = chirps senoidales ascendentes con
resonancia; sifón = ráfaga de ruido filtrado (paso-bajo con barrido); tinta = golpe sordo
grave + puff de ruido. Salida: characters/pulpo_lego/sounds/*.wav (22050 Hz, mono, s16).

Uso: python tools/art/gen_otto_sounds.py
"""
from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

SR = 22050
OUT = Path(__file__).resolve().parents[2] / "characters" / "pulpo_lego" / "sounds"
random.seed(8)  # ocho brazos: sonidos reproducibles


def write_wav(name: str, samples: list[float], gain: float = 0.85):
    peak = max(1e-9, max(abs(s) for s in samples))
    norm = gain / peak
    data = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * norm)) * 32767)) for s in samples)
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print(f"  ✓ {name} ({len(samples)/SR:.2f}s)")


def silence(dur: float) -> list[float]:
    return [0.0] * int(SR * dur)


def bubble(f0: float, f1: float, dur: float, vol: float = 1.0) -> list[float]:
    """Una burbuja: chirp ascendente (la burbuja sube y encoge -> sube el tono) con decay."""
    n = int(SR * dur)
    out, ph = [], 0.0
    for i in range(n):
        t = i / n
        f = f0 + (f1 - f0) * (t ** 0.7)
        ph += 2 * math.pi * f / SR
        env = math.sin(min(1.0, t * 12) * math.pi / 2) * math.exp(-3.2 * t)
        out.append(math.sin(ph) * env * vol)
    return out


def mix_at(base: list[float], add: list[float], at: float):
    i0 = int(SR * at)
    for i, s in enumerate(add):
        j = i0 + i
        if j < len(base):
            base[j] += s


def noise_lp(dur: float, cutoff0: float, cutoff1: float) -> list[float]:
    """Ruido blanco con paso-bajo de 1 polo cuyo corte barre cutoff0 -> cutoff1."""
    n = int(SR * dur)
    out, y = [], 0.0
    for i in range(n):
        t = i / n
        fc = cutoff0 + (cutoff1 - cutoff0) * t
        a = 1.0 - math.exp(-2 * math.pi * fc / SR)
        y += a * (random.uniform(-1, 1) - y)
        out.append(y)
    return out


def env_apply(sig: list[float], attack: float, release: float) -> list[float]:
    n = len(sig)
    na, nr = max(1, int(SR * attack)), max(1, int(SR * release))
    for i in range(n):
        e = 1.0
        if i < na:
            e = i / na
        if i > n - nr:
            e = min(e, (n - i) / nr)
        sig[i] *= e
    return sig


print(f"Sintetizando sonidos de Otto en {OUT}")

# --- pop.wav: una burbujita suelta (primer contacto, curiosidad) ---
write_wav("pop.wav", bubble(340, 780, 0.14), gain=0.5)

# --- happy.wav: trino de burbujas ascendentes (caricia que le encanta) ---
s = silence(1.0)
for k, at in enumerate([0.0, 0.12, 0.22, 0.34, 0.50, 0.68]):
    mix_at(s, bubble(300 + 70 * k, 700 + 140 * k, 0.16, vol=0.8 + 0.05 * k), at)
write_wav("happy.wav", s, gain=0.55)

# --- jet.wav: sifón a presión (huida a chorro): whoosh de ruido con barrido ---
s = noise_lp(0.55, 2600, 350)
n = len(s)
for i in range(n):  # envolvente de ráfaga: golpe rápido y cola
    t = i / n
    s[i] *= math.exp(-2.4 * t) * min(1.0, t * 30)
write_wav("jet.wav", env_apply(s, 0.005, 0.1), gain=0.6)

# --- ink.wav: pseudomorfo de tinta: thump grave + puff corto ---
s = silence(0.5)
th, ph = [], 0.0
for i in range(int(SR * 0.35)):
    t = i / (SR * 0.35)
    f = 130 - 60 * t
    ph += 2 * math.pi * f / SR
    th.append(math.sin(ph) * math.exp(-6 * t))
mix_at(s, th, 0.0)
mix_at(s, [v * 0.35 * math.exp(-9 * i / SR / 0.2) for i, v in enumerate(noise_lp(0.2, 1400, 500))], 0.01)
write_wav("ink.wav", s, gain=0.6)

# --- startle.wav: respingo (chirp descendente rapidito, "¡glup!") ---
sq, ph = [], 0.0
for i in range(int(SR * 0.16)):
    t = i / (SR * 0.16)
    f = 900 - 620 * t
    ph += 2 * math.pi * f / SR
    sq.append(math.sin(ph) * math.exp(-4 * t))
write_wav("startle.wav", env_apply(sq, 0.004, 0.03), gain=0.5)

# --- sleep.wav: blub lento y grave (se queda dormido) ---
s = silence(0.9)
mix_at(s, bubble(160, 300, 0.4, vol=1.0), 0.0)
mix_at(s, bubble(140, 250, 0.45, vol=0.6), 0.4)
write_wav("sleep.wav", s, gain=0.45)

# --- hello.wav: saludo burbujeante corto (2 burbujas alegres) ---
s = silence(0.5)
mix_at(s, bubble(350, 800, 0.15), 0.0)
mix_at(s, bubble(450, 980, 0.16, vol=0.9), 0.18)
write_wav("hello.wav", s, gain=0.5)

print("listo")
