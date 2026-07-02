#!/usr/bin/env python3
"""Sintetiza el paisaje sonoro de Nyx (humana cyberpunk) — stdlib puro.

Nyx no hace ruidos de animal: suena su TECNOLOGÍA. Boot de sistema (arpegio synth),
blips de interfaz, zap de glitch (ruido + AM metálico), whoosh de teletransporte,
latido sub del corazón sintético. Salida: characters/nyx_cyber/sounds/*.wav.

Uso: python tools/art/gen_nyx_sounds.py
"""
from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

SR = 22050
OUT = Path(__file__).resolve().parents[2] / "characters" / "nyx_cyber" / "sounds"
random.seed(2077)


def write_wav(name: str, samples: list[float], gain: float = 0.8):
    peak = max(1e-9, max(abs(s) for s in samples))
    norm = gain / peak
    data = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * norm)) * 32767)) for s in samples)
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(data)
    print(f"  ✓ {name} ({len(samples)/SR:.2f}s)")


def silence(dur): return [0.0] * int(SR * dur)


def mix_at(base, add, at):
    i0 = int(SR * at)
    for i, s in enumerate(add):
        if i0 + i < len(base):
            base[i0 + i] += s


def synth_note(freq, dur, vol=1.0, detune=1.003, decay=5.0):
    """Nota synth: 2 sierras suaves desafinadas (súper-saw ligera) con decay."""
    n = int(SR * dur)
    out, p1, p2 = [], 0.0, 0.0
    for i in range(n):
        t = i / n
        p1 = (p1 + freq / SR) % 1.0
        p2 = (p2 + freq * detune / SR) % 1.0
        saw = (p1 - 0.5) * 0.6 + (p2 - 0.5) * 0.4
        soft = saw - saw ** 3 / 3           # suaviza la sierra (menos áspera)
        env = min(1.0, i / (SR * 0.008)) * math.exp(-decay * t)
        out.append(soft * env * vol)
    return out


def noise_lp(dur, c0, c1):
    n = int(SR * dur)
    out, y = [], 0.0
    for i in range(n):
        fc = c0 + (c1 - c0) * (i / n)
        a = 1.0 - math.exp(-2 * math.pi * fc / SR)
        y += a * (random.uniform(-1, 1) - y)
        out.append(y)
    return out


print(f"Sintetizando sonidos de Nyx en {OUT}")

# --- boot.wav: arranque del sistema — arpegio ascendente + shimmer ---
s = silence(1.4)
for k, (f, at) in enumerate([(220, 0.0), (330, 0.14), (440, 0.28), (660, 0.42), (880, 0.56)]):
    mix_at(s, synth_note(f, 0.5, vol=0.7 + k * 0.06, decay=4), at)
mix_at(s, [v * 0.10 * math.sin(i / SR * 2 * math.pi * 6) for i, v in enumerate(noise_lp(0.7, 6000, 9000))], 0.62)
write_wav("boot.wav", s, gain=0.55)

# --- blip.wav: blip de interfaz (curiosidad / toque) ---
s = synth_note(1245, 0.09, decay=9)
mix_at(s, synth_note(1660, 0.06, vol=0.5, decay=10), 0.03)
write_wav("blip.wav", s, gain=0.4)

# --- happy.wav: acorde cálido breve (caricia que le gusta) ---
s = silence(0.9)
for f, at, v in [(523, 0.0, 0.8), (659, 0.05, 0.7), (784, 0.10, 0.75), (1047, 0.18, 0.5)]:
    mix_at(s, synth_note(f, 0.65, vol=v, decay=3.5), at)
write_wav("happy.wav", s, gain=0.45)

# --- glitch.wav: zap de glitch — ruido troceado con AM metálica ---
n = int(SR * 0.38)
s = []
for i in range(n):
    t = i / n
    seg = int(t * 9)
    on = (seg * 2654435761 % 7) > 2          # troceado pseudoaleatorio determinista
    am = 0.5 + 0.5 * math.sin(2 * math.pi * 87 * i / SR)
    s.append((random.uniform(-1, 1) * 0.8 + math.sin(2 * math.pi * 440 * (1 + 2 * t) * i / SR) * 0.3)
             * (1.0 if on else 0.12) * am * math.exp(-2.2 * t))
write_wav("glitch.wav", s, gain=0.5)

# --- teleport.wav: desmaterializa (barrido abajo) + rematerializa (arriba) ---
s = silence(0.85)
dn, ph = [], 0.0
for i in range(int(SR * 0.35)):
    t = i / (SR * 0.35)
    f = 900 * (1 - 0.85 * t)
    ph += 2 * math.pi * f / SR
    dn.append(math.sin(ph) * (1 - t) * 0.9)
mix_at(s, dn, 0.0)
up, ph = [], 0.0
for i in range(int(SR * 0.4)):
    t = i / (SR * 0.4)
    f = 200 + 1100 * t * t
    ph += 2 * math.pi * f / SR
    up.append(math.sin(ph) * math.sin(math.pi * t) * 0.8)
mix_at(s, up, 0.42)
mix_at(s, [v * 0.25 for v in noise_lp(0.2, 3000, 800)], 0.36)
write_wav("teleport.wav", s, gain=0.5)

# --- heartbeat.wav: lub-dub sintético grave (sobresalto, sutil) ---
s = silence(0.7)
for at, v in [(0.0, 1.0), (0.16, 0.75)]:
    th, ph = [], 0.0
    for i in range(int(SR * 0.14)):
        t = i / (SR * 0.14)
        f = 62 - 18 * t
        ph += 2 * math.pi * f / SR
        th.append(math.sin(ph) * math.exp(-7 * t) * v)
    mix_at(s, th, at)
write_wav("heartbeat.wav", s, gain=0.55)

# --- sleep.wav: apagado de pantalla (acorde descendente + hum que muere) ---
s = silence(1.1)
for f, at in [(660, 0.0), (440, 0.15), (330, 0.30), (220, 0.45)]:
    mix_at(s, synth_note(f, 0.5, vol=0.6, decay=5), at)
mix_at(s, [0.18 * math.sin(2 * math.pi * 110 * i / SR) * math.exp(-3 * i / SR) for i in range(int(SR * 0.9))], 0.35)
write_wav("sleep.wav", s, gain=0.4)

print("listo")
