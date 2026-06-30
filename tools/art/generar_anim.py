#!/usr/bin/env python3
"""Convierte la ilustración estática de una criatura en una ANIMACIÓN VIVA (estilo Live2D ligero)
SIN separar capas: deforma la imagen completa por columnas/filas.
  - alas (columnas laterales) oscilan en vertical -> aleteo
  - respiración (squash vertical) + sway (deslizamiento horizontal) anclados a los pies
  - parpadeo: unos frames usan la variante de ojos cerrados (blink.png), deformada igual
Sale un sprite sheet horizontal `sprites/anim.png` (N frames) y apunta TODOS los estados a él
en el manifest. El motor (AnimatedSprite) lo reproduce en bucle.

  ~/miiamia-art/.venv/bin/python tools/art/generar_anim.py drag_kawaii
  ~/miiamia-art/.venv/bin/python tools/art/generar_anim.py            # todas las *_kawaii
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[2]
CHARS = REPO / "characters"
N = 24                      # frames
FPS = 16
SIZE = 256
BLINK_FRAMES = {10, 11}     # en qué frames se cierran los ojos (parpadeo breve)
STATES = ["idle", "typing", "gaming", "browsing", "talking", "sleeping", "watching", "music"]


def warp(arr: np.ndarray, ph: float) -> Image.Image:
    H, W = arr.shape[:2]
    xs = np.arange(W)
    edge = (np.abs(xs - W / 2) / (W / 2)) ** 1.7        # 0 centro -> 1 bordes (alas)
    out = np.zeros_like(arr)
    for x in range(W):
        dy = int(round(11 * edge[x] * math.sin(ph + x * 0.012)))   # aleteo
        col = np.roll(arr[:, x], dy, axis=0)
        if dy > 0:
            col[:dy] = 0
        elif dy < 0:
            col[dy:] = 0
        out[:, x] = col
    im = Image.fromarray(out)
    breath = 1.0 + 0.025 * math.sin(ph)                  # respiración
    sway = int(round(4 * math.sin(ph * 0.5)))            # balanceo
    bob = int(round(3 * math.sin(ph * 0.5 + 1)))
    nh = max(1, int(H * breath))
    im = im.resize((W, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    canvas.alpha_composite(im, (sway, H - nh + bob))
    return canvas


def build(name: str):
    sp = CHARS / name / "sprites"
    idle_p = sp / "idle.png"
    if not idle_p.exists():
        print("SKIP", name, "(sin idle)"); return
    idle = np.array(Image.open(idle_p).convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS))
    blink_p = sp / "blink.png"
    blink = np.array(Image.open(blink_p).convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS)) if blink_p.exists() else idle

    sheet = Image.new("RGBA", (SIZE * N, SIZE), (0, 0, 0, 0))
    for f in range(N):
        ph = 2 * math.pi * f / N
        base = blink if f in BLINK_FRAMES else idle
        sheet.alpha_composite(warp(base, ph), (f * SIZE, 0))
    sheet.save(sp / "anim.png")

    mp = CHARS / name / f"{name}.json"
    manifest = json.loads(mp.read_text())
    anim = {"source": "sprites/anim.png", "frameCount": N, "frameWidth": SIZE,
            "frameHeight": SIZE, "fps": FPS}
    manifest["animations"] = {st: dict(anim) for st in STATES}
    manifest["animated"] = True
    mp.write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    print("OK", name, f"({N} frames vivos)")


names = sys.argv[1:] or [d.name for d in sorted(CHARS.glob("*_kawaii")) if (d / "sprites" / "idle.png").exists()]
for n in names:
    build(n)
print("DONE")
