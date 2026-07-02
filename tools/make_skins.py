#!/usr/bin/env python3
"""Genera MUCHAS skins (criatura x paleta) placeholder para miiamia.

Cada skin = un TIPO de criatura (dragón, gato, zorro, slime, conejo, osito, pollito,
fantasma, ajolote) con una PALETA -> un personaje completo en characters/<name>/ con
sus 8 sprites de estado + <name>.json. Además escribe characters/skins.json (índice
que lee el menú de configuración).

Arte procedural de relleno: el SISTEMA de skins es real. Reemplaza los sprites por tu
propio arte (sprite sheet 6x128px por estado) y añade tu entrada a skins.json.

Para AÑADIR criaturas: agrega una función draw_<tipo>(d, cx, cy, P, *, blink, mouth, eye_dir)
con la misma interfaz, regístrala en TYPES y añade skins de ese tipo a SKINS.

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


# ---------------- objetos que sostiene/usa la criatura (agnósticos al tipo) ----------------
def _paw(d, x, y, P):
    d.ellipse([x - 7, y - 7, x + 7, y + 7], fill=P["body"])
    d.ellipse([x - 7, y - 7, x + 7, y + 7], outline=P["dark"], width=2)


def draw_console(d, cx, cy, P, press=0):
    d.rounded_rectangle([cx - 30, cy + 18, cx + 30, cy + 46], radius=6, fill=(60, 62, 74, 255))
    d.rectangle([cx - 16, cy + 22, cx + 16, cy + 40], fill=(120, 210, 235, 255))
    d.rectangle([cx - 26, cy + 28, cx - 18, cy + 36], fill=(40, 42, 52, 255))
    a = (235, 120, 150, 255) if press == 0 else (90, 92, 104, 255)
    b = (235, 120, 150, 255) if press == 1 else (90, 92, 104, 255)
    d.ellipse([cx + 18, cy + 26, cx + 24, cy + 32], fill=a)
    d.ellipse([cx + 24, cy + 32, cx + 30, cy + 38], fill=b)
    _paw(d, cx - 30, cy + 32, P)
    _paw(d, cx + 30, cy + 38, P)


def draw_keyboard(d, cx, cy, P, paw_side):
    d.rounded_rectangle([cx - 28, cy + 30, cx + 28, cy + 46], radius=4, fill=(70, 72, 86, 255))
    for i in range(-2, 3):
        for j in range(2):
            kx, ky = cx + i * 10, cy + 33 + j * 7
            d.rectangle([kx - 3, ky - 2, kx + 3, ky + 2], fill=(200, 202, 214, 255))
    _paw(d, cx - 14, cy + (34 if paw_side <= 0 else 26), P)
    _paw(d, cx + 14, cy + (34 if paw_side > 0 else 26), P)


def draw_popcorn(d, cx, cy, P, phase):
    d.polygon([(cx + 13, cy + 22), (cx + 35, cy + 22), (cx + 32, cy + 47), (cx + 16, cy + 47)], fill=(235, 235, 240, 255))
    for x in range(cx + 15, cx + 34, 6):
        d.line([x, cy + 22, x - 1, cy + 47], fill=(220, 70, 70, 255), width=2)
    for ox, oy in [(-9, -2), (-3, -4), (3, -2), (-1, 2)]:
        d.ellipse([cx + 24 + ox - 3, cy + 17 + oy - 3, cx + 24 + ox + 3, cy + 17 + oy + 3], fill=(250, 240, 200, 255))
    py = cy + 6 - phase * 6
    _paw(d, cx - 7, py, P)
    d.ellipse([cx - 9, py - 9, cx - 3, py - 3], fill=(250, 240, 200, 255))


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


def draw_zzz(d, cx, cy, rise):
    for i, s in enumerate((10, 13, 16)):
        zx, zy = cx + 22 + i * 8, cy - 30 - i * 10 - rise
        d.line([zx, zy, zx + s * 0.5, zy], fill=(120, 110, 160, 230), width=2)
        d.line([zx + s * 0.5, zy, zx, zy + s * 0.5], fill=(120, 110, 160, 230), width=2)
        d.line([zx, zy + s * 0.5, zx + s * 0.5, zy + s * 0.5], fill=(120, 110, 160, 230), width=2)


# ---------------- criatura base: dragón (paleta unificada P) ----------------
def draw_dragon(d, cx, cy, P, *, blink=False, mouth=0.0, eye_dir=0):
    d.polygon([(cx - 30, cy - 6), (cx - 54, cy - 24), (cx - 46, cy + 14)], fill=P["accent"])
    d.polygon([(cx + 30, cy - 6), (cx + 54, cy - 24), (cx + 46, cy + 14)], fill=P["accent"])
    d.ellipse([cx - 34, cy - 30, cx + 34, cy + 40], fill=P["body"])
    d.ellipse([cx - 34, cy - 30, cx + 34, cy + 40], outline=P["dark"], width=3)
    d.ellipse([cx - 20, cy - 4, cx + 20, cy + 36], fill=P["belly"])
    d.polygon([(cx - 16, cy - 28), (cx - 10, cy - 46), (cx - 4, cy - 28)], fill=P["accent"])
    d.polygon([(cx + 16, cy - 28), (cx + 10, cy - 46), (cx + 4, cy - 28)], fill=P["accent"])
    if blink:
        d.line([cx - 18, cy - 8, cx - 6, cy - 8], fill=P["eye"], width=3)
        d.line([cx + 6, cy - 8, cx + 18, cy - 8], fill=P["eye"], width=3)
    else:
        ex = eye_dir * 2
        d.ellipse([cx - 18, cy - 14, cx - 8, cy - 2], fill=P["eye"])
        d.ellipse([cx + 8, cy - 14, cx + 18, cy - 2], fill=P["eye"])
        d.ellipse([cx - 16 + ex, cy - 12, cx - 12 + ex, cy - 8], fill=WHITE)
        d.ellipse([cx + 10 + ex, cy - 12, cx + 14 + ex, cy - 8], fill=WHITE)
    d.ellipse([cx - 26, cy - 2, cx - 16, cy + 6], fill=P["blush"])
    d.ellipse([cx + 16, cy - 2, cx + 26, cy + 6], fill=P["blush"])
    if mouth <= 0.05:
        d.arc([cx - 7, cy - 2, cx + 7, cy + 8], start=20, end=160, fill=P["eye"], width=2)
    else:
        h = int(4 + 8 * mouth)
        d.ellipse([cx - 6, cy + 2, cx + 6, cy + 2 + h], fill=(90, 40, 70, 255))


# --- criaturas (diseñadas por agentes) ---
def draw_cat(d, cx, cy, P, *, blink=False, mouth=0.0, eye_dir=0):
    # Cola (derecha, curva hacia arriba — dibujada primero para quedar detrás del cuerpo)
    d.arc([cx+14, cy+8, cx+46, cy+44], start=200, end=350, fill=P["accent"], width=8)
    # Orejas exteriores (color body)
    d.polygon([(cx-26,cy-20),(cx-36,cy-46),(cx-8,cy-26)], fill=P["body"])
    d.polygon([(cx+26,cy-20),(cx+36,cy-46),(cx+8,cy-26)], fill=P["body"])
    # Orejas interiores (accent)
    d.polygon([(cx-24,cy-22),(cx-31,cy-40),(cx-12,cy-26)], fill=P["accent"])
    d.polygon([(cx+24,cy-22),(cx+31,cy-40),(cx+12,cy-26)], fill=P["accent"])
    # Cuerpo redondo chibi (tapa la base de las orejas)
    d.ellipse([cx-32,cy-26,cx+32,cy+40], fill=P["body"])
    d.ellipse([cx-32,cy-26,cx+32,cy+40], outline=P["dark"], width=2)
    # Panza
    d.ellipse([cx-18,cy+2,cx+18,cy+38], fill=P["belly"])
    # Cachetes
    d.ellipse([cx-28,cy-4,cx-16,cy+6], fill=P["blush"])
    d.ellipse([cx+16,cy-4,cx+28,cy+6], fill=P["blush"])
    # Ojos
    if blink:
        d.line([cx-17,cy-10,cx-7,cy-10], fill=P["eye"], width=3)
        d.line([cx+7,cy-10,cx+17,cy-10], fill=P["eye"], width=3)
    else:
        ex = eye_dir*2
        d.ellipse([cx-18,cy-16,cx-8,cy-4], fill=P["eye"])
        d.ellipse([cx+8,cy-16,cx+18,cy-4], fill=P["eye"])
        d.ellipse([cx-16+ex,cy-14,cx-12+ex,cy-9], fill=WHITE)
        d.ellipse([cx+10+ex,cy-14,cx+14+ex,cy-9], fill=WHITE)
    # Nariz (rosa fija, pequeño detalle)
    d.ellipse([cx-3,cy-3,cx+3,cy+2], fill=(210,120,140,255))
    # Boca
    if mouth <= 0.05:
        d.arc([cx-6,cy+1,cx+6,cy+8], start=20, end=160, fill=P["dark"], width=2)
    else:
        h = int(4+8*mouth)
        d.ellipse([cx-5,cy+2,cx+5,cy+2+h], fill=(90,40,70,255))
    # Bigotes (cuatro líneas finas)
    d.line([cx-4,cy-2,cx-26,cy-5], fill=P["dark"], width=1)
    d.line([cx-4,cy+1,cx-26,cy+4], fill=P["dark"], width=1)
    d.line([cx+4,cy-2,cx+26,cy-5], fill=P["dark"], width=1)
    d.line([cx+4,cy+1,cx+26,cy+4], fill=P["dark"], width=1)

def draw_fox(d, cx, cy, P, *, blink=False, mouth=0.0, eye_dir=0):
    # Cola esponjada (derecha, dibujada primero para quedar detrás del cuerpo)
    d.ellipse([cx+16, cy+4, cx+46, cy+38], fill=P["accent"])
    d.ellipse([cx+22, cy-2, cx+46, cy+26], fill=P["accent"])
    d.ellipse([cx+28, cy+2, cx+46, cy+28], fill=WHITE)
    # Cuerpo
    d.ellipse([cx-22, cy+4, cx+22, cy+40], fill=P["body"])
    d.ellipse([cx-22, cy+4, cx+22, cy+40], outline=P["dark"], width=2)
    # Cabeza
    d.ellipse([cx-28, cy-30, cx+28, cy+8], fill=P["body"])
    d.ellipse([cx-28, cy-30, cx+28, cy+8], outline=P["dark"], width=2)
    # Orejas exteriores (grandes y puntiagudas)
    d.polygon([(cx-26, cy-26), (cx-14, cy-46), (cx-2, cy-26)], fill=P["accent"])
    d.polygon([(cx+2, cy-26), (cx+14, cy-46), (cx+26, cy-26)], fill=P["accent"])
    d.polygon([(cx-26, cy-26), (cx-14, cy-46), (cx-2, cy-26)], outline=P["dark"])
    d.polygon([(cx+2, cy-26), (cx+14, cy-46), (cx+26, cy-26)], outline=P["dark"])
    # Orejas interiores (color claro)
    d.polygon([(cx-22, cy-27), (cx-14, cy-41), (cx-6, cy-27)], fill=P["belly"])
    d.polygon([(cx+6, cy-27), (cx+14, cy-41), (cx+22, cy-27)], fill=P["belly"])
    # Hocico estrecho con punta oscura
    d.ellipse([cx-13, cy-4, cx+13, cy+14], fill=P["belly"])
    # Mejillas marcadas (antes de los ojos para que los ojos queden encima)
    d.ellipse([cx-28, cy-8, cx-16, cy+2], fill=P["blush"])
    d.ellipse([cx+16, cy-8, cx+28, cy+2], fill=P["blush"])
    # Ojos
    if blink:
        d.line([cx-18, cy-10, cx-8, cy-10], fill=P["eye"], width=3)
        d.line([cx+8, cy-10, cx+18, cy-10], fill=P["eye"], width=3)
    else:
        ex = eye_dir * 2
        d.ellipse([cx-20, cy-16, cx-8, cy-2], fill=P["eye"])
        d.ellipse([cx+8, cy-16, cx+20, cy-2], fill=P["eye"])
        d.ellipse([cx-17+ex, cy-14, cx-12+ex, cy-8], fill=WHITE)
        d.ellipse([cx+12+ex, cy-14, cx+17+ex, cy-8], fill=WHITE)
    # Nariz oscura en la punta del hocico
    d.ellipse([cx-5, cy-5, cx+5, cy+3], fill=P["dark"])
    # Boca
    if mouth <= 0.05:
        d.arc([cx-7, cy+2, cx+7, cy+12], start=20, end=160, fill=P["eye"], width=2)
    else:
        h = int(4 + 8 * mouth)
        d.ellipse([cx-6, cy+4, cx+6, cy+4+h], fill=(90, 40, 70, 255))

def draw_slime(d, cx, cy, P, *, blink=False, mouth=0.0, eye_dir=0):
    # Blob/water-drop silhouette — 14 points approximate the classic slime teardrop
    blob = [
        (cx,    cy-42),
        (cx+12, cy-38),
        (cx+26, cy-28),
        (cx+36, cy-10),
        (cx+38, cy+8),
        (cx+34, cy+24),
        (cx+22, cy+36),
        (cx,    cy+40),
        (cx-22, cy+36),
        (cx-34, cy+24),
        (cx-38, cy+8),
        (cx-36, cy-10),
        (cx-26, cy-28),
        (cx-12, cy-38),
    ]
    d.polygon(blob, fill=P["body"], outline=P["dark"], width=3)
    # Belly — lighter, translucent-look center
    d.ellipse([cx-22, cy-4, cx+22, cy+28], fill=P["belly"])
    # Iconic slime shine: large oval + small dot, top-left
    d.ellipse([cx-24, cy-34, cx-8,  cy-22], fill=(255, 255, 255, 230))
    d.ellipse([cx-10, cy-40, cx-2,  cy-32], fill=(255, 255, 255, 190))
    # Eyes (center ~cy-10)
    if blink:
        d.line([cx-19, cy-10, cx-9,  cy-10], fill=P["eye"], width=3)
        d.line([cx+9,  cy-10, cx+19, cy-10], fill=P["eye"], width=3)
    else:
        ex = eye_dir * 2
        d.ellipse([cx-20, cy-18, cx-8,  cy-2], fill=P["eye"])
        d.ellipse([cx+8,  cy-18, cx+20, cy-2], fill=P["eye"])
        d.ellipse([cx-17+ex, cy-16, cx-13+ex, cy-12], fill=WHITE)
        d.ellipse([cx+11+ex, cy-16, cx+15+ex, cy-12], fill=WHITE)
    # Blush
    d.ellipse([cx-32, cy-4, cx-20, cy+4], fill=P["blush"])
    d.ellipse([cx+20, cy-4, cx+32, cy+4], fill=P["blush"])
    # Mouth
    if mouth <= 0.05:
        d.arc([cx-6, cy+2, cx+6, cy+10], start=20, end=160, fill=P["eye"], width=2)
    else:
        h = int(4 + 8 * mouth)
        d.ellipse([cx-5, cy+2, cx+5, cy+2+h], fill=(90, 40, 70, 255))

def draw_bunny(d, cx, cy, P, *, blink=False, mouth=0.0, eye_dir=0):
    # Long ears — most characteristic bunny feature
    # Left ear outer (body color)
    d.ellipse([cx-26, cy-46, cx-8, cy-2], fill=P["body"])
    # Left ear inner (accent — pink interior)
    d.ellipse([cx-24, cy-44, cx-10, cy-6], fill=P["accent"])
    # Left ear outline
    d.ellipse([cx-26, cy-46, cx-8, cy-2], outline=P["dark"], width=2)
    # Right ear outer
    d.ellipse([cx+8, cy-46, cx+26, cy-2], fill=P["body"])
    # Right ear inner
    d.ellipse([cx+10, cy-44, cx+24, cy-6], fill=P["accent"])
    # Right ear outline
    d.ellipse([cx+8, cy-46, cx+26, cy-2], outline=P["dark"], width=2)
    # Fluffy tail peeking from right side (drawn before body so body covers its edge)
    d.ellipse([cx+28, cy+6, cx+44, cy+22], fill=P["belly"])
    d.ellipse([cx+28, cy+6, cx+44, cy+22], outline=P["dark"], width=1)
    # Round body
    d.ellipse([cx-34, cy-22, cx+34, cy+40], fill=P["body"])
    d.ellipse([cx-34, cy-22, cx+34, cy+40], outline=P["dark"], width=3)
    # Belly patch (lighter center)
    d.ellipse([cx-18, cy-2, cx+18, cy+34], fill=P["belly"])
    # Small front paws — on sides so center clear zone stays free
    d.ellipse([cx-40, cy+22, cx-22, cy+38], fill=P["body"])
    d.ellipse([cx-40, cy+22, cx-22, cy+38], outline=P["dark"], width=2)
    d.ellipse([cx+22, cy+22, cx+40, cy+38], fill=P["body"])
    d.ellipse([cx+22, cy+22, cx+40, cy+38], outline=P["dark"], width=2)
    # Blush cheeks
    d.ellipse([cx-30, cy-6, cx-16, cy+4], fill=P["blush"])
    d.ellipse([cx+16, cy-6, cx+30, cy+4], fill=P["blush"])
    # Eyes
    if blink:
        d.line([cx-16, cy-10, cx-6, cy-10], fill=P["eye"], width=3)
        d.line([cx+6, cy-10, cx+16, cy-10], fill=P["eye"], width=3)
    else:
        ex = eye_dir * 2
        d.ellipse([cx-17, cy-16, cx-7, cy-4], fill=P["eye"])
        d.ellipse([cx+7, cy-16, cx+17, cy-4], fill=P["eye"])
        d.ellipse([cx-15+ex, cy-14, cx-11+ex, cy-10], fill=WHITE)
        d.ellipse([cx+9+ex, cy-14, cx+13+ex, cy-10], fill=WHITE)
    # Y-shaped nose: small pink oval + philtrum stem line going down
    d.ellipse([cx-4, cy-8, cx+4, cy-1], fill=(220, 110, 140, 255))
    d.line([cx, cy-1, cx, cy+4], fill=P["dark"], width=2)
    # Mouth
    if mouth <= 0.05:
        # W/cat-style: two small downward arches side by side
        d.arc([cx-8, cy+3, cx+0, cy+11], start=200, end=340, fill=P["eye"], width=2)
        d.arc([cx+0, cy+3, cx+8, cy+11], start=200, end=340, fill=P["eye"], width=2)
    else:
        h = int(4 + 8 * mouth)
        d.ellipse([cx-6, cy+3, cx+6, cy+3+h], fill=(90, 40, 70, 255))

def draw_bear(d, cx, cy, P, *, blink=False, mouth=0.0, eye_dir=0):
    # Ears behind head
    d.ellipse([cx-42, cy-46, cx-14, cy-18], fill=P["body"])
    d.ellipse([cx-42, cy-46, cx-14, cy-18], outline=P["dark"], width=2)
    d.ellipse([cx-38, cy-43, cx-19, cy-23], fill=P["accent"])
    d.ellipse([cx+14, cy-46, cx+42, cy-18], fill=P["body"])
    d.ellipse([cx+14, cy-46, cx+42, cy-18], outline=P["dark"], width=2)
    d.ellipse([cx+19, cy-43, cx+38, cy-23], fill=P["accent"])
    # Body (rechoncho)
    d.ellipse([cx-36, cy-30, cx+36, cy+40], fill=P["body"])
    d.ellipse([cx-36, cy-30, cx+36, cy+40], outline=P["dark"], width=3)
    # Belly
    d.ellipse([cx-22, cy-6, cx+22, cy+36], fill=P["belly"])
    # Snout/hocico
    d.ellipse([cx-16, cy-2, cx+16, cy+16], fill=P["belly"])
    d.ellipse([cx-16, cy-2, cx+16, cy+16], outline=P["dark"], width=1)
    # Nose
    d.ellipse([cx-5, cy-1, cx+5, cy+5], fill=(50, 25, 15, 255))
    # Blush
    d.ellipse([cx-34, cy-6, cx-20, cy+4], fill=P["blush"])
    d.ellipse([cx+20, cy-6, cx+34, cy+4], fill=P["blush"])
    # Eyes
    if blink:
        d.line([cx-20, cy-10, cx-8, cy-10], fill=P["eye"], width=3)
        d.line([cx+8, cy-10, cx+20, cy-10], fill=P["eye"], width=3)
    else:
        ex = eye_dir * 2
        d.ellipse([cx-21, cy-16, cx-8, cy-3], fill=P["eye"])
        d.ellipse([cx+8, cy-16, cx+21, cy-3], fill=P["eye"])
        d.ellipse([cx-18+ex, cy-14, cx-13+ex, cy-9], fill=WHITE)
        d.ellipse([cx+13+ex, cy-14, cx+18+ex, cy-9], fill=WHITE)
    # Mouth
    if mouth <= 0.05:
        d.arc([cx-7, cy+7, cx+7, cy+14], start=20, end=160, fill=P["dark"], width=2)
    else:
        h = int(4 + 8 * mouth)
        d.ellipse([cx-6, cy+7, cx+6, cy+7+h], fill=(90, 40, 50, 255))

def draw_chick(d, cx, cy, P, *, blink=False, mouth=0.0, eye_dir=0):
    # Wings: small round bumps peeking behind body on each side
    d.ellipse([cx-46, cy+6, cx-20, cy+32], fill=P["accent"])
    d.ellipse([cx-46, cy+6, cx-20, cy+32], outline=P["dark"], width=2)
    d.ellipse([cx+20, cy+6, cx+46, cy+32], fill=P["accent"])
    d.ellipse([cx+20, cy+6, cx+46, cy+32], outline=P["dark"], width=2)
    # Copete: 3 feather tufts drawn before body so body covers their bases naturally
    d.polygon([(cx-12, cy-20), (cx-9, cy-42), (cx-2, cy-22)], fill=P["accent"])
    d.polygon([(cx-5, cy-24), (cx, cy-46), (cx+5, cy-24)], fill=P["accent"])
    d.polygon([(cx+2, cy-22), (cx+9, cy-42), (cx+12, cy-20)], fill=P["accent"])
    # Main round chubby body
    d.ellipse([cx-32, cy-22, cx+32, cy+40], fill=P["body"])
    d.ellipse([cx-32, cy-22, cx+32, cy+40], outline=P["dark"], width=3)
    # Belly / chest highlight
    d.ellipse([cx-16, cy+4, cx+16, cy+36], fill=P["belly"])
    # Eyes
    if blink:
        d.line([cx-18, cy-8, cx-8, cy-8], fill=P["eye"], width=3)
        d.line([cx+8, cy-8, cx+18, cy-8], fill=P["eye"], width=3)
    else:
        ex = eye_dir * 2
        d.ellipse([cx-18, cy-14, cx-8, cy-2], fill=P["eye"])
        d.ellipse([cx+8, cy-14, cx+18, cy-2], fill=P["eye"])
        d.ellipse([cx-16+ex, cy-12, cx-12+ex, cy-8], fill=WHITE)
        d.ellipse([cx+10+ex, cy-12, cx+14+ex, cy-8], fill=WHITE)
    # Blush cheeks
    d.ellipse([cx-28, cy-4, cx-18, cy+4], fill=P["blush"])
    d.ellipse([cx+18, cy-4, cx+28, cy+4], fill=P["blush"])
    # Beak (fixed orange)
    bk = (240, 140, 30, 255)
    if mouth <= 0.05:
        d.polygon([(cx-7, cy+1), (cx+7, cy+1), (cx+3, cy+8), (cx-3, cy+8)], fill=bk)
    else:
        bh = int(3 + 6 * mouth)
        d.polygon([(cx-8, cy), (cx+8, cy), (cx+4, cy+4), (cx-4, cy+4)], fill=bk)
        d.ellipse([cx-4, cy+3, cx+4, cy+3+bh], fill=(70, 25, 10, 255))
        d.polygon([(cx-5, cy+4+bh), (cx+5, cy+4+bh), (cx+2, cy+8+bh), (cx-2, cy+8+bh)], fill=bk)

def draw_ghost(d, cx, cy, P, *, blink=False, mouth=0.0, eye_dir=0):
    # ── ARMS (short stubs, behind body) ──────────────────
    d.ellipse([cx-44, cy-4,  cx-28, cy+12], fill=P["body"])
    d.ellipse([cx+28, cy-4,  cx+44, cy+12], fill=P["body"])

    # ── BODY: rounded dome (top ellipse) ─────────────────
    d.ellipse([cx-32, cy-44, cx+32, cy+8],  fill=P["body"])

    # ── BODY: wavy lower trunk (polygon with 3 bumps) ────
    d.polygon([
        (cx-32, cy-18),
        (cx+32, cy-18),
        (cx+32, cy+26),
        (cx+22, cy+40),
        (cx+10, cy+26),
        (cx,    cy+40),
        (cx-10, cy+26),
        (cx-22, cy+40),
        (cx-32, cy+26),
    ], fill=P["body"])

    # ── BELLY (lighter inner glow) ────────────────────────
    d.ellipse([cx-16, cy-20, cx+16, cy+14], fill=P["belly"])

    # ── DARK OUTLINES ─────────────────────────────────────
    # Top dome arc (left → top → right, clockwise in PIL)
    d.arc([cx-32, cy-44, cx+32, cy+8],
          start=180, end=360, fill=P["dark"], width=3)
    # Body sides
    d.line([cx-32, cy-18, cx-32, cy+26], fill=P["dark"], width=3)
    d.line([cx+32, cy-18, cx+32, cy+26], fill=P["dark"], width=3)
    # Wavy bottom hem outline (zigzag polyline)
    d.line([
        (cx-32, cy+26), (cx-22, cy+40),
        (cx-10, cy+26), (cx,    cy+40),
        (cx+10, cy+26), (cx+22, cy+40),
        (cx+32, cy+26),
    ], fill=P["dark"], width=3)
    # Arm outer arcs only
    d.arc([cx-44, cy-4, cx-28, cy+12], start=90,  end=270, fill=P["dark"], width=2)
    d.arc([cx+28, cy-4, cx+44, cy+12], start=270, end=90,  fill=P["dark"], width=2)

    # ── EYES ──────────────────────────────────────────────
    ey = cy - 8
    ex = eye_dir * 2
    if blink:
        d.line([cx-19, ey, cx-7,  ey], fill=P["eye"], width=3)
        d.line([cx+7,  ey, cx+19, ey], fill=P["eye"], width=3)
    else:
        d.ellipse([cx-21, ey-11, cx-7,  ey+5],  fill=P["eye"])
        d.ellipse([cx+7,  ey-11, cx+21, ey+5],  fill=P["eye"])
        d.ellipse([cx-19+ex, ey-9, cx-12+ex, ey-2], fill=WHITE)
        d.ellipse([cx+10+ex, ey-9, cx+17+ex, ey-2], fill=WHITE)

    # ── BLUSH ─────────────────────────────────────────────
    d.ellipse([cx-28, cy-3, cx-18, cy+5], fill=P["blush"])
    d.ellipse([cx+18, cy-3, cx+28, cy+5], fill=P["blush"])

    # ── MOUTH ─────────────────────────────────────────────
    my = cy + 2
    if mouth <= 0.05:
        d.arc([cx-7, my, cx+7, my+10], start=20, end=160, fill=P["dark"], width=2)
    else:
        h = int(4 + 8 * mouth)
        d.ellipse([cx-6, my+1, cx+6, my+1+h], fill=(90, 40, 70, 255))

def draw_axolotl(d, cx, cy, P, *, blink=False, mouth=0.0, eye_dir=0):
    # Tail fin peeking bottom-right (drawn first, behind body)
    d.polygon([(cx+20, cy+26), (cx+46, cy+14), (cx+40, cy+38)], fill=P["accent"])
    d.polygon([(cx+20, cy+26), (cx+46, cy+14), (cx+40, cy+38)], outline=P["dark"], width=2)

    # Left gills — 3 feathery stalks with bulbous tips
    glx, gly = cx - 20, cy - 14
    d.line([glx, gly, cx - 42, cy - 35], fill=P["accent"], width=4)
    d.ellipse([cx - 46, cy - 39, cx - 38, cy - 31], fill=P["accent"])
    d.line([glx, gly, cx - 33, cy - 40], fill=P["accent"], width=4)
    d.ellipse([cx - 37, cy - 44, cx - 29, cy - 36], fill=P["accent"])
    d.line([glx, gly, cx - 24, cy - 37], fill=P["accent"], width=4)
    d.ellipse([cx - 28, cy - 41, cx - 20, cy - 33], fill=P["accent"])

    # Right gills (mirror)
    grx, gry = cx + 20, cy - 14
    d.line([grx, gry, cx + 42, cy - 35], fill=P["accent"], width=4)
    d.ellipse([cx + 38, cy - 39, cx + 46, cy - 31], fill=P["accent"])
    d.line([grx, gry, cx + 33, cy - 40], fill=P["accent"], width=4)
    d.ellipse([cx + 29, cy - 44, cx + 37, cy - 36], fill=P["accent"])
    d.line([grx, gry, cx + 24, cy - 37], fill=P["accent"], width=4)
    d.ellipse([cx + 20, cy - 41, cx + 28, cy - 33], fill=P["accent"])

    # Main chubby body
    d.ellipse([cx - 30, cy - 18, cx + 30, cy + 38], fill=P["body"])
    d.ellipse([cx - 30, cy - 18, cx + 30, cy + 38], outline=P["dark"], width=3)

    # Belly
    d.ellipse([cx - 16, cy - 2, cx + 16, cy + 32], fill=P["belly"])

    # Stubby front legs
    d.ellipse([cx - 38, cy + 8, cx - 24, cy + 22], fill=P["body"])
    d.ellipse([cx - 38, cy + 8, cx - 24, cy + 22], outline=P["dark"], width=2)
    d.ellipse([cx + 24, cy + 8, cx + 38, cy + 22], fill=P["body"])
    d.ellipse([cx + 24, cy + 8, cx + 38, cy + 22], outline=P["dark"], width=2)

    # Eyes
    if blink:
        d.line([cx - 18, cy - 8, cx - 6, cy - 8], fill=P["eye"], width=3)
        d.line([cx + 6, cy - 8, cx + 18, cy - 8], fill=P["eye"], width=3)
    else:
        ex = eye_dir * 2
        d.ellipse([cx - 20, cy - 16, cx - 8, cy - 2], fill=P["eye"])
        d.ellipse([cx + 8, cy - 16, cx + 20, cy - 2], fill=P["eye"])
        d.ellipse([cx - 18 + ex, cy - 13, cx - 13 + ex, cy - 8], fill=WHITE)
        d.ellipse([cx + 11 + ex, cy - 13, cx + 16 + ex, cy - 8], fill=WHITE)

    # Blush cheeks
    d.ellipse([cx - 28, cy - 2, cx - 16, cy + 6], fill=P["blush"])
    d.ellipse([cx + 16, cy - 2, cx + 28, cy + 6], fill=P["blush"])

    # Wide kawaii axolotl smile
    if mouth <= 0.05:
        d.arc([cx - 14, cy + 2, cx + 14, cy + 14], start=15, end=165, fill=P["dark"], width=2)
    else:
        h = int(4 + 8 * mouth)
        d.ellipse([cx - 8, cy + 2, cx + 8, cy + 2 + h], fill=(90, 40, 70, 255))


TYPES = {
    "dragon": draw_dragon,
    "cat": draw_cat,
    "fox": draw_fox,
    "slime": draw_slime,
    "bunny": draw_bunny,
    "bear": draw_bear,
    "chick": draw_chick,
    "ghost": draw_ghost,
    "axolotl": draw_axolotl,
}

SKINS = [{'name': 'kira', 'label': 'Kira — violeta', 'type': 'dragon', 'nice': 'Kira', 'P': {'body': (150, 110, 230, 255), 'dark': (108, 78, 180, 255), 'belly': (224, 206, 250, 255), 'accent': (124, 92, 200, 255), 'eye': (40, 30, 60, 255), 'blush': (240, 150, 190, 255)}}, {'name': 'ember', 'label': 'Ember — fuego', 'type': 'dragon', 'nice': 'Ember', 'P': {'body': (235, 90, 60, 255), 'dark': (180, 55, 40, 255), 'belly': (255, 210, 170, 255), 'accent': (210, 70, 50, 255), 'eye': (60, 20, 20, 255), 'blush': (255, 160, 120, 255)}}, {'name': 'aqua', 'label': 'Aqua — océano', 'type': 'dragon', 'nice': 'Aqua', 'P': {'body': (70, 170, 220, 255), 'dark': (45, 120, 170, 255), 'belly': (210, 240, 250, 255), 'accent': (60, 150, 200, 255), 'eye': (20, 40, 60, 255), 'blush': (150, 210, 235, 255)}}, {'name': 'verde', 'label': 'Verde — bosque', 'type': 'dragon', 'nice': 'Verde', 'P': {'body': (95, 190, 110, 255), 'dark': (60, 140, 75, 255), 'belly': (225, 245, 210, 255), 'accent': (80, 170, 95, 255), 'eye': (25, 50, 30, 255), 'blush': (170, 220, 150, 255)}}, {'name': 'dorada', 'label': 'Dorada — oro', 'type': 'dragon', 'nice': 'Dorada', 'P': {'body': (235, 190, 70, 255), 'dark': (190, 150, 45, 255), 'belly': (255, 245, 205, 255), 'accent': (215, 170, 55, 255), 'eye': (60, 45, 15, 255), 'blush': (255, 215, 150, 255)}}, {'name': 'sombra', 'label': 'Sombra — noche', 'type': 'dragon', 'nice': 'Sombra', 'P': {'body': (70, 60, 95, 255), 'dark': (45, 38, 65, 255), 'belly': (130, 120, 160, 255), 'accent': (55, 48, 80, 255), 'eye': (200, 180, 255, 255), 'blush': (110, 90, 140, 255)}}, {'name': 'rosa', 'label': 'Rosa — pétalo', 'type': 'dragon', 'nice': 'Rosa', 'P': {'body': (240, 140, 185, 255), 'dark': (200, 95, 145, 255), 'belly': (255, 225, 240, 255), 'accent': (225, 115, 165, 255), 'eye': (70, 30, 55, 255), 'blush': (255, 175, 205, 255)}}, {'name': 'nieve', 'label': 'Nieve — hielo', 'type': 'dragon', 'nice': 'Nieve', 'P': {'body': (220, 235, 245, 255), 'dark': (170, 195, 215, 255), 'belly': (245, 250, 255, 255), 'accent': (200, 220, 238, 255), 'eye': (80, 110, 140, 255), 'blush': (200, 225, 240, 255)}}, {'name': 'lava', 'label': 'Lava — magma', 'type': 'dragon', 'nice': 'Lava', 'P': {'body': (60, 40, 45, 255), 'dark': (40, 25, 30, 255), 'belly': (255, 140, 60, 255), 'accent': (90, 50, 45, 255), 'eye': (255, 150, 40, 255), 'blush': (200, 90, 60, 255)}}, {'name': 'menta', 'label': 'Menta — fresco', 'type': 'dragon', 'nice': 'Menta', 'P': {'body': (140, 225, 205, 255), 'dark': (95, 180, 160, 255), 'belly': (230, 255, 248, 255), 'accent': (120, 205, 185, 255), 'eye': (30, 70, 60, 255), 'blush': (180, 235, 220, 255)}}, {'name': 'cat_orange', 'label': 'Gato — Naranja atigrado', 'type': 'cat', 'nice': 'Gato', 'P': {'body': (240, 155, 70, 255), 'dark': (160, 80, 20, 255), 'belly': (255, 225, 185, 255), 'accent': (210, 100, 35, 255), 'eye': (50, 35, 20, 255), 'blush': (255, 175, 175, 255)}}, {'name': 'cat_gray', 'label': 'Gato — Gris plateado', 'type': 'cat', 'nice': 'Gato', 'P': {'body': (175, 185, 205, 255), 'dark': (95, 105, 125, 255), 'belly': (230, 235, 245, 255), 'accent': (140, 150, 170, 255), 'eye': (55, 120, 55, 255), 'blush': (225, 180, 195, 255)}}, {'name': 'fox_classic', 'label': 'Zorro — Zorro Rojo', 'type': 'fox', 'nice': 'Zorro', 'P': {'body': (220, 95, 28, 255), 'dark': (100, 35, 10, 255), 'belly': (245, 215, 165, 255), 'accent': (185, 55, 12, 255), 'eye': (45, 20, 5, 255), 'blush': (240, 130, 100, 255)}}, {'name': 'fox_arctic', 'label': 'Zorro — Zorro Ártico', 'type': 'fox', 'nice': 'Zorro', 'P': {'body': (210, 222, 235, 255), 'dark': (75, 90, 110, 255), 'belly': (238, 245, 255, 255), 'accent': (165, 182, 200, 255), 'eye': (55, 75, 110, 255), 'blush': (210, 165, 185, 255)}}, {'name': 'slime_forest', 'label': 'Slime — Forest Slime', 'type': 'slime', 'nice': 'Slime', 'P': {'body': (100, 205, 80, 225), 'dark': (40, 110, 30, 255), 'belly': (175, 238, 145, 210), 'accent': (60, 165, 48, 255), 'eye': (30, 75, 20, 255), 'blush': (255, 160, 155, 200)}}, {'name': 'slime_ocean', 'label': 'Slime — Ocean Slime', 'type': 'slime', 'nice': 'Slime', 'P': {'body': (70, 185, 225, 225), 'dark': (25, 100, 160, 255), 'belly': (155, 225, 248, 210), 'accent': (45, 140, 195, 255), 'eye': (20, 65, 125, 255), 'blush': (255, 165, 195, 200)}}, {'name': 'bunny_white', 'label': 'Conejito — Conejito Blanco', 'type': 'bunny', 'nice': 'Conejito', 'P': {'body': (240, 238, 242, 255), 'dark': (88, 62, 78, 255), 'belly': (255, 245, 250, 255), 'accent': (255, 172, 194, 255), 'eye': (54, 34, 64, 255), 'blush': (255, 162, 184, 255)}}, {'name': 'bunny_caramel', 'label': 'Conejito — Conejito Caramelo', 'type': 'bunny', 'nice': 'Conejito', 'P': {'body': (210, 168, 122, 255), 'dark': (100, 62, 32, 255), 'belly': (245, 220, 182, 255), 'accent': (200, 118, 112, 255), 'eye': (70, 40, 18, 255), 'blush': (226, 148, 128, 255)}}, {'name': 'bear_caramel', 'label': 'Osito — Osito Caramelo', 'type': 'bear', 'nice': 'Osito', 'P': {'body': (185, 115, 65, 255), 'dark': (90, 50, 20, 255), 'belly': (235, 195, 145, 255), 'accent': (215, 155, 90, 255), 'eye': (35, 15, 5, 255), 'blush': (255, 160, 155, 255)}}, {'name': 'bear_panda', 'label': 'Osito — Osito Panda', 'type': 'bear', 'nice': 'Osito', 'P': {'body': (240, 240, 240, 255), 'dark': (30, 30, 30, 255), 'belly': (255, 255, 255, 255), 'accent': (40, 40, 40, 255), 'eye': (20, 20, 20, 255), 'blush': (255, 180, 180, 255)}}, {'name': 'chick_amarillo', 'label': 'Pollito — Pollito Clásico', 'type': 'chick', 'nice': 'Pollito', 'P': {'body': (255, 220, 50, 255), 'dark': (150, 90, 0, 255), 'belly': (255, 248, 190, 255), 'accent': (240, 170, 20, 255), 'eye': (40, 25, 10, 255), 'blush': (255, 170, 180, 255)}}, {'name': 'chick_pastel', 'label': 'Pollito — Pollito Pascua', 'type': 'chick', 'nice': 'Pollito', 'P': {'body': (255, 235, 120, 255), 'dark': (180, 120, 30, 255), 'belly': (255, 255, 220, 255), 'accent': (255, 195, 65, 255), 'eye': (50, 35, 20, 255), 'blush': (255, 180, 200, 255)}}, {'name': 'ghost_white', 'label': 'Fantasma — Fantasma Blanco', 'type': 'ghost', 'nice': 'Fantasma', 'P': {'body': (235, 240, 255, 255), 'dark': (90, 100, 140, 255), 'belly': (255, 255, 255, 255), 'accent': (200, 210, 250, 255), 'eye': (40, 50, 90, 255), 'blush': (255, 190, 210, 255)}}, {'name': 'ghost_lavender', 'label': 'Fantasma — Fantasma Lavanda', 'type': 'ghost', 'nice': 'Fantasma', 'P': {'body': (210, 185, 245, 255), 'dark': (80, 50, 120, 255), 'belly': (240, 225, 255, 255), 'accent': (175, 140, 230, 255), 'eye': (50, 30, 90, 255), 'blush': (255, 170, 205, 255)}}, {'name': 'axolotl_leucistic', 'label': 'Ajolote — Leucistico (Rosa clasico)', 'type': 'axolotl', 'nice': 'Ajolote', 'P': {'body': (255, 178, 196, 255), 'dark': (190, 90, 120, 255), 'belly': (255, 228, 235, 255), 'accent': (255, 130, 160, 255), 'eye': (70, 30, 50, 255), 'blush': (255, 160, 180, 255)}}, {'name': 'axolotl_golden', 'label': 'Ajolote — Dorado Albino', 'type': 'axolotl', 'nice': 'Ajolote', 'P': {'body': (255, 215, 120, 255), 'dark': (190, 140, 40, 255), 'belly': (255, 245, 200, 255), 'accent': (255, 175, 60, 255), 'eye': (60, 40, 10, 255), 'blush': (255, 200, 140, 255)}}]


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
    P = sk["P"]
    draw = TYPES[sk["type"]]
    C = FRAME // 2
    bob = [0, -2, -3, -2, 0, 1]
    sheet(out, "idle", 6, lambda d, i: draw(d, C, C + bob[i], P, blink=(i == 3)))
    sheet(out, "talking", 6, lambda d, i: draw(d, C, C, P, mouth=[0, .5, 1, .6, .2, .8][i]))
    sheet(out, "typing", 6, lambda d, i: (draw(d, C, C + (i % 2), P), draw_keyboard(d, C, C + (i % 2), P, 1 if i % 2 else -1))[0])
    sheet(out, "gaming", 6, lambda d, i: (draw(d, C, C + (i % 2) - 1, P), draw_console(d, C, C + (i % 2) - 1, P, press=i % 2))[0])
    scan = [-1, -1, 0, 1, 1, 0]
    sheet(out, "browsing", 6, lambda d, i: draw(d, C, C, P, eye_dir=scan[i]))
    sheet(out, "sleeping", 6, lambda d, i: (draw(d, C, C + [0, 1, 2, 2, 1, 0][i], P, blink=True), draw_zzz(d, C, C, [0, 2, 4, 6, 3, 1][i]))[0])
    wp = [0, 1, 2, 1, 0, 0]
    sheet(out, "watching", 6, lambda d, i: (draw(d, C, C, P, blink=(i == 5)), draw_popcorn(d, C, C, P, wp[i]))[0])
    sway = [-3, -1, 1, 3, 1, -1]
    sheet(out, "music", 6, lambda d, i: (draw(d, C + sway[i], C, P, mouth=[0, .3, 0, .3, 0, .2][i]), draw_headphones(d, C + sway[i], C), draw_notes(d, C, C, i))[0])

    states = ["idle", "typing", "gaming", "browsing", "talking", "sleeping", "watching", "music"]
    fps = {"idle": 8, "typing": 10, "gaming": 8, "browsing": 6, "talking": 12, "sleeping": 4, "watching": 6, "music": 8}
    anims = {s: {"source": f"sprites/{s}.png", "frameCount": 6, "frameWidth": 128, "frameHeight": 128, "fps": fps[s]} for s in states}
    manifest = {
        "name": sk["nice"], "backend": "sprite", "scale": 2.0, "defaultState": "idle",
        "animations": anims,
        "voice": {"tts": "piper", "voice": "es_ES-sharvard-medium"},
        "persona": f"Eres {sk['nice']}, una criatura virtual juguetona y curiosa que vive en la pantalla y acompana a tu humano. Hablas espanol dominicano, calida, breve (1-2 frases). Si algo no se entiende, pregunta con carino en vez de inventar.",
    }
    (CHARS / sk["name"] / f"{sk['name']}.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))


def main():
    print(f"Generando {len(SKINS)} skins en {CHARS}")
    # MERGE con el índice existente: este script solo "posee" las skins procedurales.
    # Antes sobrescribía skins.json entero y borraba del menú las skins reales
    # (dragón, kawaii, waifu 3D...) si alguien lo corría después de instalarlas.
    index_path = CHARS / "skins.json"
    try:
        index = json.loads(index_path.read_text(encoding="utf-8"))
    except Exception:
        index = []
    ids = {e.get("id") for e in index}
    for sk in SKINS:
        gen_skin(sk)
        if sk["name"] not in ids:
            index.append({"id": sk["name"], "label": sk["label"]})
        print(f"  ok {sk['name']}")
    index_path.write_text(json.dumps(index, ensure_ascii=False, indent=2))
    print(f"indice: {len(index)} skins -> {index_path}")


if __name__ == "__main__":
    main()
