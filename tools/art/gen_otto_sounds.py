#!/usr/bin/env python3
"""Diseño sonoro CINEMATOGRÁFICO submarino de Otto (pulpo LEGO) — sfx_kit (numpy+scipy).

El agua manda: las burbujas usan resonancia tipo Minnaert (senoide decayente con glide
ascendente + armónico + transitorio de formación), los agudos se los traga el agua
(paso-bajo global) y todo vive en una reverb de tanque oscura. Nada de sine chirps a pelo.

Correr con el venv de arte:
  ~/miiamia-art/.venv/bin/python tools/art/gen_otto_sounds.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
from scipy import signal
from sfx_kit import (SR, env_exp, env_swell, master, mix, noise_sweep, pad, reverb,
                     sine_sweep, sub, t_axis, write_wav)

OUT = Path(__file__).resolve().parents[2] / "characters" / "pulpo_lego" / "sounds"
OUT.mkdir(parents=True, exist_ok=True)
print(f"Diseño sonoro submarino de Otto -> {OUT}")

rng = np.random.default_rng(8)


def bubble(f0: float, dur: float = 0.22, glide: float = 1.6, vol: float = 1.0) -> np.ndarray:
    """Burbuja física (Minnaert): senoide decayente cuyo tono SUBE al encoger la burbuja,
    con 2º armónico suave y un transitorio de formación (plip de agua)."""
    t = t_axis(dur)
    f = f0 * (1 + (glide - 1) * (t / dur) ** 0.65)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = (np.sin(ph) + 0.22 * np.sin(2 * ph + 0.7)) * env_exp(dur, 0.003, 5.5)
    plip = noise_sweep(0.03, 1200, 3500, q=2.0) * env_exp(0.03, 0.001, 30) * 0.4
    return mix((body * vol, 0.0), (plip * vol, 0.0))


def water(x: np.ndarray, wet: float = 0.35, cutoff: float = 2800, tail: float = 0.8) -> np.ndarray:
    """Acústica de agua: el agua se traga los agudos + reverb de tanque oscura."""
    sos = signal.butter(2, cutoff, "lowpass", fs=SR, output="sos")
    return reverb(signal.sosfilt(sos, x), wet=wet, size=0.9, damp=0.6, tail=tail)


# --- pop.wav: UNA burbuja curiosa con cuerpo (primer contacto) ---
write_wav(OUT / "pop.wav", master(water(bubble(340, 0.24, 2.1), wet=0.3, tail=0.5), 0.5))

# --- hello.wav: dos burbujas alegres que conversan ---
hello = mix((bubble(320, 0.22, 2.0), 0.0), (bubble(430, 0.24, 2.2, 0.9), 0.20))
write_wav(OUT / "hello.wav", master(water(hello, wet=0.35, tail=0.6), 0.52))

# --- happy.wav: trino de burbujas ascendentes + brillo de agua (caricia que encanta) ---
trill = mix(*[(bubble(260 + 55 * k, 0.2, 2.0, 0.75 + 0.04 * k), 0.11 * k) for k in range(7)])
shimmer = pad([1245, 1567], 0.9, detune=0.008, vib_hz=6.0, vib_amt=0.006) \
          * env_swell(0.9, 0.3, 0.5) * 0.14
happy = mix((trill, 0.0), (shimmer, 0.25), (sub(70, 55, 0.6, decay=3.0) * 0.25, 0.0))
write_wav(OUT / "happy.wav", master(water(happy, wet=0.4, cutoff=3400, tail=0.9), 0.55))

# --- jet.wav: sifón a presión — empuje sub + ráfaga de agua (whoosh grave, no estática) ---
jet = mix(
    (sub(85, 34, 0.5, decay=4.0, drive=2.6) * 0.9, 0.0),
    (noise_sweep(0.6, 1800, 220, q=1.4) * env_exp(0.6, 0.004, 4.0) * 0.8, 0.0),
    (noise_sweep(0.35, 500, 120, q=1.8) * env_exp(0.35, 0.002, 5.0) * 0.5, 0.02),
)
write_wav(OUT / "jet.wav", master(water(jet, wet=0.28, cutoff=2200, tail=0.6), 0.62))

# --- ink.wav: pseudomorfo — golpe sordo profundo + nube turbia que se expande ---
ink = mix(
    (sub(95, 30, 0.5, decay=4.5, drive=2.8), 0.0),
    (noise_sweep(0.55, 900, 150, q=1.2) * env_swell(0.55, 0.06, 0.35) * 0.55, 0.02),
    (bubble(140, 0.3, 1.5, 0.4), 0.18),   # borboteo grave dentro de la nube
)
write_wav(OUT / "ink.wav", master(water(ink, wet=0.3, cutoff=1600, tail=0.7), 0.6))

# --- startle.wav: ¡glup! — burbuja asustada descendente + mini-sub ---
gulp_t = t_axis(0.18)
gulp_f = 720 * (1 - 0.6 * (gulp_t / 0.18) ** 0.8)
gulp = np.sin(2 * np.pi * np.cumsum(gulp_f) / SR) * env_exp(0.18, 0.002, 6.0)
st = mix((gulp, 0.0), (sub(90, 50, 0.15, decay=9.0) * 0.5, 0.0), (bubble(500, 0.12, 1.3, 0.3), 0.05))
write_wav(OUT / "startle.wav", master(water(st, wet=0.25, tail=0.4), 0.55))

# --- sleep.wav: dos burbujas lentas y graves + arrullo de agua que se apaga ---
lull = pad([98, 147], 1.6, detune=0.01, vib_hz=0.8, vib_amt=0.01) * env_swell(1.6, 0.4, 0.9) * 0.3
slp = mix(
    (bubble(150, 0.5, 1.5, 0.9), 0.0),
    (bubble(120, 0.55, 1.4, 0.6), 0.55),
    (lull, 0.1),
)
write_wav(OUT / "sleep.wav", master(water(slp, wet=0.45, cutoff=1400, tail=1.0), 0.45))

print("listo — acústica submarina por capas, cero Atari")
