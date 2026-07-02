#!/usr/bin/env python3
"""Diseño sonoro CINEMATOGRÁFICO de Nyx (humana cyberpunk) — sfx_kit (numpy+scipy).

Nada de bleeps: cada evento son 2-4 capas (sub-bass saturado + barrido de ruido + pad
desafinado + cristal FM) fundidas con reverb Schroeder y cola. Referencias: UI holográfica
de cine sci-fi, no chiptune.

Correr con el venv de arte:
  ~/miiamia-art/.venv/bin/python tools/art/gen_nyx_sounds.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
from sfx_kit import (SR, env_exp, env_swell, fm_bell, grains, lowpass_sweep, master, mix,
                     noise_sweep, pad, reverb, sine_sweep, sub, t_axis, write_wav)

OUT = Path(__file__).resolve().parents[2] / "characters" / "nyx_cyber" / "sounds"
OUT.mkdir(parents=True, exist_ok=True)
print(f"Diseño sonoro de Nyx -> {OUT}")

# --- boot.wav: encendido de holograma — sub que despierta + aire que sube + pad que
#     florece + "ready" de cristal. Cola de reverb larga. (~2.6s)
boot = mix(
    (sub(28, 55, 1.3, decay=1.6) * 0.9, 0.0),                       # el peso despierta
    (noise_sweep(1.5, 150, 7000, q=2.0, curve=1.4) * env_swell(1.5, 1.2, 0.25) * 0.5, 0.05),
    (pad([110, 165, 220, 277], 1.8) * env_swell(1.8, 0.9, 0.5) * 0.55, 0.55),  # A+E+A+C#: florece
    (fm_bell(880, 1.0, ratio=3.01, index=2.2, decay=3.0) * 0.5, 1.45),          # "sistema listo"
    (fm_bell(1760, 0.8, ratio=2.41, index=1.5, decay=4.0) * 0.22, 1.52),
)
write_wav(OUT / "boot.wav", master(reverb(boot, wet=0.42, size=1.15, tail=1.1), 0.72))

# --- blip.wav: toque holográfico — gota de cristal, no un bleep. (~0.6s)
blip = mix(
    (fm_bell(1320, 0.35, ratio=2.756, index=2.0, decay=9.0) * 0.8, 0.0),
    (noise_sweep(0.12, 3000, 8000, q=3.0) * env_exp(0.12, 0.002, 18) * 0.18, 0.0),
)
write_wav(OUT / "blip.wav", master(reverb(blip, wet=0.3, size=0.8, tail=0.45), 0.5))

# --- happy.wav: floración cálida — acorde mayor desafinado que respira + chispas de
#     cristal esparcidas. (~1.8s)
sparks = mix(*[(fm_bell(f, 0.5, ratio=3.7, index=1.6, decay=6.0) * 0.16, off)
               for f, off in ((2093, 0.42), (2637, 0.61), (3136, 0.83))])
happy = mix(
    (pad([392, 494, 587, 784], 1.5, vib_hz=5.2, vib_amt=0.004) * env_swell(1.5, 0.45, 0.6) * 0.7, 0.0),
    (sub(60, 49, 0.9, decay=2.5) * 0.35, 0.0),
    (sparks, 0.0),
)
write_wav(OUT / "happy.wav", master(reverb(happy, wet=0.45, size=1.1, tail=1.0), 0.6))

# --- glitch.wav: desgarro digital — textura granulada + sub impacto + zap descendente.
#     El bitcrush va DENTRO de la textura, no crudo. (~0.8s)
tex = pad([220, 227, 331], 0.6, voices=4, detune=0.012)
g = grains(tex, 0.55, g_ms=(12, 38), seed=13)
from sfx_kit import bitcrush
g = 0.6 * g + 0.4 * bitcrush(g, bits=5, down=6)
glitch = mix(
    (sub(70, 32, 0.35, decay=6.0) * 0.9, 0.0),
    (g * env_exp(0.55, 0.002, 3.0) * 0.85, 0.01),
    (noise_sweep(0.4, 6000, 300, q=2.0) * env_exp(0.4, 0.002, 6) * 0.4, 0.0),
)
write_wav(OUT / "glitch.wav", master(reverb(glitch, wet=0.22, size=0.7, tail=0.4), 0.62))

# --- teleport.wav: carga (riser) -> hueco de silencio -> IMPACTO sub -> disipación de
#     cristal con cola larga. La gramática cinematográfica completa. (~2.1s)
charge = mix(
    (noise_sweep(0.72, 250, 9000, q=2.2, curve=1.6) * env_swell(0.72, 0.6, 0.06) * 0.6, 0.0),
    (sine_sweep(180, 1500, 0.72, curve=1.8) * env_swell(0.72, 0.5, 0.05) * 0.3, 0.0),
)
impact = mix(
    (sub(90, 30, 0.7, decay=3.5, drive=2.8), 0.0),
    (noise_sweep(0.5, 4000, 150, q=1.5) * env_exp(0.5, 0.001, 5) * 0.5, 0.0),
)
shimmer = pad([1568, 1976, 2349], 0.9, detune=0.006) * env_exp(0.9, 0.01, 3.0) * 0.3
tele = mix((charge, 0.0), (impact, 0.80), (shimmer, 0.84))   # 0.72-0.80: el hueco dramático
write_wav(OUT / "teleport.wav", master(reverb(tele, wet=0.4, size=1.2, tail=1.1), 0.72))

# --- heartbeat.wav: lub-dub de sub PROFUNDO con aire de sala. (~1.0s)
def thump(vol):
    return sub(58, 34, 0.22, decay=8.0, drive=2.6) * vol
hb = mix((thump(1.0), 0.0), (thump(0.62), 0.30))
write_wav(OUT / "heartbeat.wav", master(reverb(hb, wet=0.16, size=0.9, tail=0.5), 0.68))

# --- sleep.wav: apagado — el pad se cierra (paso-bajo que baja), el sub se despide,
#     un último cristal grave y silencio. (~2.4s)
fade_pad = lowpass_sweep(pad([440, 330, 277], 1.7) * env_swell(1.7, 0.15, 0.9), 4500, 220) * 0.7
slp = mix(
    (fade_pad, 0.0),
    (sub(52, 26, 1.6, decay=1.8) * 0.5, 0.1),
    (fm_bell(330, 1.2, ratio=1.99, index=1.2, decay=2.5) * 0.3, 1.0),
)
write_wav(OUT / "sleep.wav", master(reverb(slp, wet=0.45, size=1.3, tail=1.2), 0.55))

print("listo — diseño por capas + reverb, cero Atari")
