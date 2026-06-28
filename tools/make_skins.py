#!/usr/bin/env python3
"""Genera MUCHAS skins (personajes) placeholder para miiamia.

Cada skin = una paleta + estilo (cuernos, ojos) -> un personaje completo en
characters/<name>/ con sus 8 sprites de estado y su <name>.json. Además escribe
characters/skins.json (índice que lee el menú de configuración).

Es arte procedural de relleno: el SISTEMA de skins es real; reemplaza los sprites
por tu propio arte cuando quieras (mismo formato de sprite sheet 6x128px por estado).

Uso:  python tools/make_skins.py
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw

FRAME = 128
ROOT = Path(__file__).resolve().parent.parent
CHARS = ROOT / "characters"

WHITE = (255, 255, 255, 255)

# name, label, body, dark, belly, wing, horn, eye, blush, hstyle (curved|straight|spike)
SKINS = [
    ("kira",   "Kira — violeta",   (150, 110, 230), (108, 78, 180), (224, 206, 250), (124, 92, 200), (245, 238, 255), (40, 30, 60),   (240, 150, 190), "curved"),
    ("ember",  "Ember — fuego",    (235, 90, 60),   (180, 55, 40),  (255, 210, 170), (210, 70, 50),  (255, 240, 220), (60, 20, 20),   (255, 160, 120), "straight"),
    ("aqua",   "Aqua — océano",    (70, 170, 220),  (45, 120, 170), (210, 240, 250), (60, 150, 200), (235, 250, 255), (20, 40, 60),   (150, 210, 235), "curved"),
    ("verde",  "Verde — bosque",   (95, 190, 110),  (60, 140, 75),  (225, 245, 210), (80, 170, 95),  (240, 255, 235), (25, 50, 30),   (170, 220, 150), "spike"),
    ("dorada", "Dorada — oro",     (235, 190, 70),  (190, 150, 45), (255, 245, 205), (215, 170, 55), (255, 250, 225), (60, 45, 15),   (255, 215, 150), "straight"),
    ("sombra", "Sombra — noche",   (70, 60, 95),    (45, 38, 65),   (130, 120, 160), (55, 48, 80),   (180, 170, 210), (200, 180, 255),(110, 90, 140),  "curved"),
    ("rosa",   "Rosa — pétalo",    (240, 140, 185), (200, 95, 145), (255, 225, 240), (225, 115, 165),(255, 240, 248), (70, 30, 55),   (255, 175, 205), "curved"),
    ("nieve",  "Nieve — hielo",    (220, 235, 245), (170, 195, 215),(245, 250, 255), (200, 220, 238),(255, 255, 255), (80, 110, 140), (200, 225, 240), "spike"),
    ("lava",   "Lava — magma",     (60, 40, 45),    (40, 25, 30),   (255, 140, 60),  (90, 50, 45),   (255, 200, 120), (255, 150, 40), (200, 90, 60),   "straight"),
    ("menta",  "Menta — fresco",   (140, 225, 205), (95, 180, 160), (230, 255, 248), (120, 205, 185),(245, 255, 252), (30, 70, 60),   (180, 235, 220), "curved"),
]


def _a(t, alpha=255):
    return (t[0], t[1], t[2], alpha)


def draw_horns(d, cx, cy, sk):
    horn = _a(sk["horn"])
    style = sk["hstyle"]
    if style == "straight":
        d.line([cx - 12, cy - 28, cx - 13, cy - 48], fill=horn, width=5)
        d.line([cx + 12, cy - 28, cx + 13, cy - 48], fill=horn, width=5)
    elif style == "spike":
        for off in (-18, -6, 6, 18):
            d.polygon([(cx + off - 4, cy - 26), (cx + off, cy - 40), (cx + off + 4, cy - 26)], fill=horn)
    else:  # curved
        d.polygon([(cx - 16, cy - 28), (cx - 10, cy - 46), (cx - 4, cy - 28)], fill=horn)
        d.polygon([(cx + 16, cy - 28), (cx + 10, cy - 46), (cx + 4, cy - 28)], fill=horn)


def draw_creature(d, cx, cy, sk, *, blink=False, mouth=0.0, eye_dir=0):
    body, dark, belly = _a(sk["body"]), _a(sk["dark"]), _a(sk["belly"])
    wing, eye, blush = _a(sk["wing"], 230), _a(sk["eye"]), _a(sk["blush"], 160)
    d.polygon([(cx - 30, cy - 6), (cx - 54, cy - 24), (cx - 46, cy + 14)], fill=wing)
    d.polygon([(cx + 30, cy - 6), (cx + 54, cy - 24), (cx + 46, cy + 14)], fill=wing)
    d.ellipse([cx - 34, cy - 30, cx + 34, cy + 40], fill=body)
    d.ellipse([cx - 34, cy - 30, cx + 34, cy + 40], outline=dark, width=3)
    d.ellipse([cx - 20, cy - 4, cx + 20, cy + 36], fill=belly)
    draw_horns(d, cx, cy, sk)
    ex = eye_dir * 2
    if blink:
        d.line([cx - 18, cy - 8, cx - 6, cy - 8], fill=eye, width=3)
        d.line([cx + 6, cy - 8, cx + 18, cy - 8], fill=eye, width=3)
    else:
        d.ellipse([cx - 18, cy - 14, cx - 8, cy - 2], fill=eye)
        d.ellipse([cx + 8, cy - 14, cx + 18, cy - 2], fill=eye)
        d.ellipse([cx - 16 + ex, cy - 12, cx - 12 + ex, cy - 8], fill=WHITE)
        d.ellipse([cx + 10 + ex, cy - 12, cx + 14 + ex, cy - 8], fill=WHITE)
    d.ellipse([cx - 26, cy - 2, cx - 16, cy + 6], fill=blush)
    d.ellipse([cx + 16, cy - 2, cx + 26, cy + 6], fill=blush)
    if mouth <= 0.05:
        d.arc([cx - 7, cy - 2, cx + 7, cy + 8], start=20, end=160, fill=eye, width=2)
    else:
        h = int(4 + 8 * mouth)
        d.ellipse([cx - 6, cy + 2, cx + 6, cy + 2 + h], fill=(90, 40, 70, 255))


def _paw(d, x, y, sk):
    d.ellipse([x - 7, y - 7, x + 7, y + 7], fill=_a(sk["body"]))
    d.ellipse([x - 7, y - 7, x + 7, y + 7], outline=_a(sk["dark"]), width=2)


def draw_console(d, cx, cy, sk, press=0):
    d.rounded_rectangle([cx - 30, cy + 18, cx + 30, cy + 46], radius=6, fill=(60, 62, 74, 255))
    d.rectangle([cx - 16, cy + 22, cx + 16, cy + 40], fill=(120, 210, 235, 255))
    d.rectangle([cx - 26, cy + 28, cx - 18, cy + 36], fill=(40, 42, 52, 255))
    a = (235, 120, 150, 255) if press == 0 else (90, 92, 104, 255)
    b = (235, 120, 150, 255) if press == 1 else (90, 92, 104, 255)
    d.ellipse([cx + 18, cy + 26, cx + 24, cy + 32], fill=a)
    d.ellipse([cx + 24, cy + 32, cx + 30, cy + 38], fill=b)
    _paw(d, cx - 30, cy + 32, sk); _paw(d, cx + 30, cy + 38, sk)


def draw_keyboard(d, cx, cy, sk, paw_side):
    d.rounded_rectangle([cx - 28, cy + 30, cx + 28, cy + 46], radius=4, fill=(70, 72, 86, 255))
    for i in range(-2, 3):
        for j in range(2):
            kx, ky = cx + i * 10, cy + 33 + j * 7
            d.rectangle([kx - 3, ky - 2, kx + 3, ky + 2], fill=(200, 202, 214, 255))
    _paw(d, cx - 14, cy + (34 if paw_side <= 0 else 26), sk)
    _paw(d, cx + 14, cy + (34 if paw_side > 0 else 26), sk)


def draw_zzz(d, cx, cy, rise):
    for i, s in enumerate((10, 13, 16)):
        zx, zy = cx + 22 + i * 8, cy - 30 - i * 10 - rise
        d.line([zx, zy, zx + s * 0.5, zy], fill=(120, 110, 160, 230), width=2)
        d.line([zx + s * 0.5, zy, zx, zy + s * 0.5], fill=(120, 110, 160, 230), width=2)
        d.line([zx, zy + s * 0.5, zx + s * 0.5, zy + s * 0.5], fill=(120, 110, 160, 230), width=2)


def draw_headphones(d, cx, cy):
    d.arc([cx - 30, cy - 48, cx + 30, cy - 4], start=200, end=340, fill=(48, 48, 60, 255), width=4)
    for sx in (-1, 1):
        d.ellipse([cx + sx * 30 - 7, cy - 20, cx + sx * 30 + 7, cy - 2], fill=(58, 60, 72, 255))
        d.ellipse([cx + sx * 30 - 4, cy - 18, cx + sx * 30 + 4, cy - 4], fill=(168, 140, 255, 255))


def draw_notes(d, cx, cy, i):
    cols = [(255, 140, 190, 235), (150, 200, 255, 235), (185, 240, 170, 235)]
    for k in range(3):
        nx, ny = cx + 26 + k * 11, cy - 22 - ((i + k) % 4) * 9
        d.line([nx + 2, ny + 3, nx + 2, ny - 9], fill=cols[k], width=2)
        d.line([nx + 2, ny - 9, nx + 7, ny - 7], fill=cols[k], width=2)
        d.ellipse([nx - 4, ny, nx + 2, ny + 5], fill=cols[k])


def draw_popcorn(d, cx, cy, sk, phase):
    d.polygon([(cx + 13, cy + 22), (cx + 35, cy + 22), (cx + 32, cy + 47), (cx + 16, cy + 47)], fill=(235, 235, 240, 255))
    for x in range(cx + 15, cx + 34, 6):
        d.line([x, cy + 22, x - 1, cy + 47], fill=(220, 70, 70, 255), width=2)
    for ox, oy in [(-9, -2), (-3, -4), (3, -2), (-1, 2)]:
        d.ellipse([cx + 24 + ox - 3, cy + 17 + oy - 3, cx + 24 + ox + 3, cy + 17 + oy + 3], fill=(250, 240, 200, 255))
    py = cy + 6 - phase * 6
    _paw(d, cx - 7, py, sk)
    d.ellipse([cx - 9, py - 9, cx - 3, py - 3], fill=(250, 240, 200, 255))


def sheet(out_dir, name, n, render):
    img = Image.new("RGBA", (FRAME * n, FRAME), (0, 0, 0, 0))
    for i in range(n):
        cell = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
        render(ImageDraw.Draw(cell), i)
        img.paste(cell, (i * FRAME, 0), cell)
    img.save(out_dir / f"{name}.png")


def gen_skin(sk):
    out = CHARS / sk["name"] / "sprites"
    out.mkdir(parents=True, exist_ok=True)
    C = FRAME // 2
    bob = [0, -2, -3, -2, 0, 1]
    sheet(out, "idle", 6, lambda d, i: draw_creature(d, C, C + bob[i], sk, blink=(i == 3)))
    sheet(out, "talking", 6, lambda d, i: draw_creature(d, C, C, sk, mouth=[0, .5, 1, .6, .2, .8][i]))
    sheet(out, "typing", 6, lambda d, i: (draw_creature(d, C, C + (i % 2), sk), draw_keyboard(d, C, C + (i % 2), sk, 1 if i % 2 else -1))[0])
    sheet(out, "gaming", 6, lambda d, i: (draw_creature(d, C, C + (i % 2) - 1, sk), draw_console(d, C, C + (i % 2) - 1, sk, press=i % 2))[0])
    scan = [-1, -1, 0, 1, 1, 0]
    sheet(out, "browsing", 6, lambda d, i: draw_creature(d, C, C, sk, eye_dir=scan[i]))
    sheet(out, "sleeping", 6, lambda d, i: (draw_creature(d, C, C + [0, 1, 2, 2, 1, 0][i], sk, blink=True), draw_zzz(d, C, C, [0, 2, 4, 6, 3, 1][i]))[0])
    wp = [0, 1, 2, 1, 0, 0]
    sheet(out, "watching", 6, lambda d, i: (draw_creature(d, C, C, sk, blink=(i == 5)), draw_popcorn(d, C, C, sk, wp[i]))[0])
    sway = [-3, -1, 1, 3, 1, -1]
    sheet(out, "music", 6, lambda d, i: (draw_creature(d, C + sway[i], C, sk, mouth=[0, .3, 0, .3, 0, .2][i]), draw_headphones(d, C + sway[i], C), draw_notes(d, C, C, i))[0])

    states = ["idle", "typing", "gaming", "browsing", "talking", "sleeping", "watching", "music"]
    fps = {"idle": 8, "typing": 10, "gaming": 8, "browsing": 6, "talking": 12, "sleeping": 4, "watching": 6, "music": 8}
    anims = {s: {"source": f"sprites/{s}.png", "frameCount": 6, "frameWidth": 128, "frameHeight": 128, "fps": fps[s]} for s in states}
    short = sk["label"].split("—")[-1].strip()
    manifest = {
        "name": sk["label"].split("—")[0].strip(),
        "backend": "sprite", "scale": 2.0, "defaultState": "idle",
        "animations": anims,
        "voice": {"tts": "piper", "voice": "es_ES-sharvard-medium"},
        "persona": f"Eres {sk['label'].split('—')[0].strip()}, una dragona ({short}) juguetona y curiosa que vive en la pantalla y acompaña a tu humano. Hablas español dominicano, cálida, breve (1-2 frases). Si algo no se entiende, pregunta con cariño en vez de inventar.",
    }
    (CHARS / sk["name"] / f"{sk['name']}.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))


def main():
    print(f"Generando {len(SKINS)} skins en {CHARS}")
    index = []
    for s in SKINS:
        sk = dict(zip(["name", "label", "body", "dark", "belly", "wing", "horn", "eye", "blush", "hstyle"], s))
        gen_skin(sk)
        index.append({"id": sk["name"], "label": sk["label"]})
        print(f"  ✓ {sk['name']}")
    (CHARS / "skins.json").write_text(json.dumps(index, ensure_ascii=False, indent=2))
    print(f"índice: {CHARS / 'skins.json'} ({len(index)} skins)")


if __name__ == "__main__":
    main()
