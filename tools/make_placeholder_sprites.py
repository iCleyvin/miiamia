#!/usr/bin/env python3
"""Genera sprite sheets placeholder para miiamia (personaje 'Kira', una dragona).

Un estado = una tira horizontal de N frames de 128x128 px, fondo transparente.
Arte de relleno para validar el pipeline de animacion del SpriteBackend; se reemplaza
luego por sprites reales (dibujados o generados por IA).

Estados: idle, typing, gaming (consola portatil), browsing, talking, sleeping.

Uso:  python tools/make_placeholder_sprites.py
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

FRAME = 128
OUT = Path(__file__).resolve().parent.parent / "characters" / "kira" / "sprites"

# Paleta de Kira (dragona violeta)
BODY = (150, 110, 230, 255)
BODY_DARK = (108, 78, 180, 255)
BELLY = (224, 206, 250, 255)
WING = (124, 92, 200, 230)
HORN = (245, 238, 255, 255)
EYE = (40, 30, 60, 255)
BLUSH = (240, 150, 190, 160)
WHITE = (255, 255, 255, 255)


def draw_kira(d, cx, cy, *, blink=False, mouth=0.0, eye_dir=0, paw=0.0):
    """Dibuja a Kira centrada en (cx, cy).
    mouth: 0 cerrada..1 abierta. eye_dir: -1 izq, 0 centro, +1 der. paw: -1..1 alza paws."""
    # Alas
    d.polygon([(cx - 30, cy - 6), (cx - 54, cy - 24), (cx - 46, cy + 14)], fill=WING)
    d.polygon([(cx + 30, cy - 6), (cx + 54, cy - 24), (cx + 46, cy + 14)], fill=WING)
    # Cuerpo
    d.ellipse([cx - 34, cy - 30, cx + 34, cy + 40], fill=BODY)
    d.ellipse([cx - 34, cy - 30, cx + 34, cy + 40], outline=BODY_DARK, width=3)
    d.ellipse([cx - 20, cy - 4, cx + 20, cy + 36], fill=BELLY)
    # Cuernos
    d.polygon([(cx - 16, cy - 28), (cx - 10, cy - 46), (cx - 4, cy - 28)], fill=HORN)
    d.polygon([(cx + 16, cy - 28), (cx + 10, cy - 46), (cx + 4, cy - 28)], fill=HORN)
    # Ojos
    ex = eye_dir * 2
    if blink:
        d.line([cx - 18, cy - 8, cx - 6, cy - 8], fill=EYE, width=3)
        d.line([cx + 6, cy - 8, cx + 18, cy - 8], fill=EYE, width=3)
    else:
        d.ellipse([cx - 18, cy - 14, cx - 8, cy - 2], fill=EYE)
        d.ellipse([cx + 8, cy - 14, cx + 18, cy - 2], fill=EYE)
        d.ellipse([cx - 16 + ex, cy - 12, cx - 12 + ex, cy - 8], fill=WHITE)
        d.ellipse([cx + 10 + ex, cy - 12, cx + 14 + ex, cy - 8], fill=WHITE)
    # Cachetes
    d.ellipse([cx - 26, cy - 2, cx - 16, cy + 6], fill=BLUSH)
    d.ellipse([cx + 16, cy - 2, cx + 26, cy + 6], fill=BLUSH)
    # Boca
    if mouth <= 0.05:
        d.arc([cx - 7, cy - 2, cx + 7, cy + 8], start=20, end=160, fill=EYE, width=2)
    else:
        h = int(4 + 8 * mouth)
        d.ellipse([cx - 6, cy + 2, cx + 6, cy + 2 + h], fill=(90, 40, 70, 255))


def _paw(d, x, y):
    d.ellipse([x - 7, y - 7, x + 7, y + 7], fill=BODY)
    d.ellipse([x - 7, y - 7, x + 7, y + 7], outline=BODY_DARK, width=2)


def draw_console(d, cx, cy, press=0):
    """Consola portatil sostenida por Kira frente a ella."""
    # Cuerpo de la consola
    d.rounded_rectangle([cx - 30, cy + 18, cx + 30, cy + 46], radius=6, fill=(60, 62, 74, 255))
    # Pantalla
    d.rectangle([cx - 16, cy + 22, cx + 16, cy + 40], fill=(120, 210, 235, 255))
    d.rectangle([cx - 16, cy + 22, cx + 16, cy + 40], outline=(30, 34, 44, 255), width=1)
    # D-pad
    d.rectangle([cx - 26, cy + 28, cx - 18, cy + 36], fill=(40, 42, 52, 255))
    # Botones (uno se ilumina al presionar)
    a = (235, 120, 150, 255) if press == 0 else (90, 92, 104, 255)
    b = (235, 120, 150, 255) if press == 1 else (90, 92, 104, 255)
    d.ellipse([cx + 18, cy + 26, cx + 24, cy + 32], fill=a)
    d.ellipse([cx + 24, cy + 32, cx + 30, cy + 38], fill=b)
    # Paws sosteniendo
    _paw(d, cx - 30, cy + 32)
    _paw(d, cx + 30, cy + 38)


def draw_keyboard(d, cx, cy, paw_side):
    """Tecladito frente a Kira; una paw teclea."""
    d.rounded_rectangle([cx - 28, cy + 30, cx + 28, cy + 46], radius=4, fill=(70, 72, 86, 255))
    for i in range(-2, 3):
        for j in range(2):
            kx = cx + i * 10
            ky = cy + 33 + j * 7
            d.rectangle([kx - 3, ky - 2, kx + 3, ky + 2], fill=(200, 202, 214, 255))
    # Paws: una abajo (tecleando), otra arriba
    _paw(d, cx - 14, cy + (34 if paw_side <= 0 else 26))
    _paw(d, cx + 14, cy + (34 if paw_side > 0 else 26))


def draw_zzz(d, cx, cy, rise):
    for i, s in enumerate((10, 13, 16)):
        zx = cx + 22 + i * 8
        zy = cy - 30 - i * 10 - rise
        d.text((zx, zy), "z", fill=(120, 110, 160, 230))
        # 'z' estilizada con lineas
        d.line([zx, zy, zx + s * 0.5, zy], fill=(120, 110, 160, 230), width=2)
        d.line([zx + s * 0.5, zy, zx, zy + s * 0.5], fill=(120, 110, 160, 230), width=2)
        d.line([zx, zy + s * 0.5, zx + s * 0.5, zy + s * 0.5], fill=(120, 110, 160, 230), width=2)


def draw_headphones(d, cx, cy):
    d.arc([cx - 30, cy - 48, cx + 30, cy - 4], start=200, end=340, fill=(48, 48, 60, 255), width=4)
    d.ellipse([cx - 37, cy - 20, cx - 23, cy - 2], fill=(58, 60, 72, 255))
    d.ellipse([cx + 23, cy - 20, cx + 37, cy - 2], fill=(58, 60, 72, 255))
    d.ellipse([cx - 34, cy - 18, cx - 26, cy - 4], fill=(168, 140, 255, 255))
    d.ellipse([cx + 26, cy - 18, cx + 34, cy - 4], fill=(168, 140, 255, 255))


def draw_notes(d, cx, cy, i):
    cols = [(255, 140, 190, 235), (150, 200, 255, 235), (185, 240, 170, 235)]
    for k in range(3):
        nx = cx + 26 + k * 11
        ny = cy - 22 - ((i + k) % 4) * 9
        col = cols[k]
        d.ellipse([nx - 4, ny, nx + 2, ny + 5], fill=col)
        d.line([nx + 2, ny + 3, nx + 2, ny - 9], fill=col, width=2)
        d.line([nx + 2, ny - 9, nx + 7, ny - 7], fill=col, width=2)


def draw_popcorn(d, cx, cy, phase):
    # cubo de palomitas a la derecha
    d.polygon([(cx + 13, cy + 22), (cx + 35, cy + 22), (cx + 32, cy + 47), (cx + 16, cy + 47)],
              fill=(235, 235, 240, 255))
    for x in range(cx + 15, cx + 34, 6):
        d.line([x, cy + 22, x - 1, cy + 47], fill=(220, 70, 70, 255), width=2)
    for ox, oy in [(-9, -2), (-3, -4), (3, -2), (-1, 2)]:
        d.ellipse([cx + 24 + ox - 3, cy + 17 + oy - 3, cx + 24 + ox + 3, cy + 17 + oy + 3], fill=(250, 240, 200, 255))
    # paw llevando una palomita a la boca (sube con phase)
    py = cy + 6 - phase * 6
    _paw(d, cx - 7, py)
    d.ellipse([cx - 9, py - 9, cx - 3, py - 3], fill=(250, 240, 200, 255))


def sheet(name, n, render):
    img = Image.new("RGBA", (FRAME * n, FRAME), (0, 0, 0, 0))
    for i in range(n):
        cell = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
        render(ImageDraw.Draw(cell), i)
        img.paste(cell, (i * FRAME, 0), cell)
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / f"{name}.png")
    print(f"  {name}.png  ({n} frames)")


def main():
    print("Generando sprites de Kira en", OUT)
    C = FRAME // 2
    bob = [0, -2, -3, -2, 0, 1]

    sheet("idle", 6, lambda d, i: draw_kira(d, C, C + bob[i], blink=(i == 3)))

    sheet("talking", 6, lambda d, i: draw_kira(d, C, C, mouth=[0, .5, 1, .6, .2, .8][i]))

    sheet("typing", 6, lambda d, i: (
        draw_kira(d, C, C + (i % 2), eye_dir=0),
        draw_keyboard(d, C, C + (i % 2), 1 if i % 2 else -1),
    )[0])

    def gaming(d, i):
        draw_kira(d, C, C + (i % 2) - 1, eye_dir=0)
        draw_console(d, C, C + (i % 2) - 1, press=i % 2)
    sheet("gaming", 6, gaming)

    scan = [-1, -1, 0, 1, 1, 0]
    sheet("browsing", 6, lambda d, i: draw_kira(d, C, C, eye_dir=scan[i]))

    rise = [0, 2, 4, 6, 3, 1]
    sheet("sleeping", 6, lambda d, i: (
        draw_kira(d, C, C + [0, 1, 2, 2, 1, 0][i], blink=True),
        draw_zzz(d, C, C, rise[i]),
    )[0])

    # watching: viendo video/peli, palomitas, ojos pegados a la pantalla
    wphase = [0, 1, 2, 1, 0, 0]
    sheet("watching", 6, lambda d, i: (
        draw_kira(d, C, C, blink=(i == 5)),
        draw_popcorn(d, C, C, wphase[i]),
    )[0])

    # music: con audifonos, meneandose al ritmo, notas flotando
    sway = [-3, -1, 1, 3, 1, -1]
    msmouth = [0.0, 0.3, 0.0, 0.3, 0.0, 0.2]
    sheet("music", 6, lambda d, i: (
        draw_kira(d, C + sway[i], C, mouth=msmouth[i]),
        draw_headphones(d, C + sway[i], C),
        draw_notes(d, C, C, i),
    )[0])

    print("Listo.")


if __name__ == "__main__":
    main()
