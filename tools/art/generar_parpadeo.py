#!/usr/bin/env python3
"""Genera la variante 'ojos cerrados' (blink.png) por INPAINTING SOLO de los ojos, manteniendo
el resto de la imagen IDENTICO y ALINEADO con idle.png (mismo encuadre, sin recrop). El QML hace
crossfade idle<->blink = parpadeo limpio (NO cambio de cara).

Claves vs la version vieja (que daba 'cambio de cara brusco'):
  - NO se hace rembg+recrop+rescale -> blink queda pixel-alineado con idle.
  - Mascara CEÑIDA a los ojos (2 blobs saturados mas grandes), nunca la boca/mejillas.
  - prompt neutro 'closed eyes' (sin sonrisa/rubor) + strength bajo -> solo cierra los ojos.
  - Se compone de vuelta SOLO la zona de los ojos sobre el idle original (resto identico).

  ~/miiamia-art/.venv/bin/python tools/art/generar_parpadeo.py [skin ...]   # default: todas
PARAR la pet antes (compite por la VRAM de 8GB)."""
from __future__ import annotations

import sys
from pathlib import Path

import cv2
import numpy as np
import torch
from diffusers import AutoPipelineForInpainting
from PIL import Image, ImageFilter

REPO = Path(__file__).resolve().parents[2]
CHARS = REPO / "characters"
SIZE = 256
HI = 1024  # resolucion de inpaint (SDXL rinde a 1024)

pipe = AutoPipelineForInpainting.from_pretrained(
    "cagliostrolab/animagine-xl-3.1", torch_dtype=torch.float16, use_safetensors=True)
pipe.enable_model_cpu_offload()
pipe.vae.enable_slicing()


def eye_mask(idle_rgba: Image.Image, size: int) -> Image.Image:
    """Mascara (L, size) ceñida a los ojos. Los ojos son pixeles SALIENTES sobre la cara clara:
    iris de color saturado O lineart/pupila oscura (cubre ojos de color Y ojos oscuros tipo panda).
    Toma los 2 blobs mas grandes en la franja central-superior; si solo halla 1 ojo, lo ESPEJA."""
    rgb = np.array(idle_rgba.convert("RGB").resize((size, size), Image.LANCZOS))
    a = np.array(idle_rgba.split()[-1].resize((size, size), Image.LANCZOS))
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)
    sat, val = hsv[:, :, 1], hsv[:, :, 2]
    H = W = size
    roi = np.zeros((H, W), bool)
    roi[int(H * 0.32):int(H * 0.57), int(W * 0.20):int(W * 0.80)] = True   # sobre la boca (~0.60H)
    sal = (roi & (a > 40) & ((sat > 80) | (val < 110))).astype(np.uint8)   # color saturado O oscuro
    sal = cv2.morphologyEx(sal, cv2.MORPH_CLOSE,
                           cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (max(3, size // 90),) * 2))

    n, _, stats, _ = cv2.connectedComponentsWithStats(sal, 8)
    minarea = size * size * 0.0007
    blobs = sorted((stats[i] for i in range(1, n) if stats[i, cv2.CC_STAT_AREA] > minarea),
                   key=lambda s: s[cv2.CC_STAT_AREA], reverse=True)[:2]
    boxes = [(s[0] + s[2] / 2, s[1] + s[3] / 2, s[2], s[3]) for s in blobs]
    if len(boxes) == 1:                                   # un solo ojo -> espejar al otro lado
        cx, cy, w, h = boxes[0]
        boxes.append((W - cx, cy, w, h))

    m = np.zeros((H, W), np.uint8)
    pad = int(size * 0.05)
    if boxes:
        for cx, cy, w, h in boxes:
            cv2.ellipse(m, (int(cx), int(cy)), (int(w / 2) + pad, int(h / 2) + pad), 0, 0, 360, 255, -1)
    else:                                                 # fallback: 2 ojos en posicion estandar
        for fx in (0.38, 0.62):
            cv2.ellipse(m, (int(W * fx), int(H * 0.47)), (int(W * 0.12), int(H * 0.09)), 0, 0, 360, 255, -1)
    return Image.fromarray(m)


names = sys.argv[1:] or [d.name for d in sorted(CHARS.glob("*_kawaii"))
                         if (d / "sprites" / "idle.png").exists()]

for idx, name in enumerate(names):
    idle_p = CHARS / name / "sprites" / "idle.png"
    if not idle_p.exists():
        print("SKIP", name, "(sin idle)"); continue
    idle = Image.open(idle_p).convert("RGBA")
    W0, H0 = idle.size

    # Inpaint a HI sobre fondo blanco (SDXL no maneja alfa), MISMO encuadre (solo escala).
    base = Image.new("RGBA", (HI, HI), (255, 255, 255, 255))
    base.alpha_composite(idle.resize((HI, HI), Image.LANCZOS))
    mask_hi = eye_mask(idle, HI).filter(ImageFilter.GaussianBlur(HI // 200))
    try:
        out = pipe(
            prompt="both eyes closed, eyes closed gently, eyes shut, calm sleepy expression, "
                   "anime, masterpiece, best quality, very aesthetic",
            negative_prompt="open eyes, wide eyes, eyeball, iris, pupil, winking, wink, one eye open, "
                            "asymmetric eyes, smile, grin, open mouth, teeth, tongue, blush, "
                            "different face, realistic, 3d, blurry, extra eyes",
            image=base.convert("RGB"), mask_image=mask_hi, strength=0.9,
            num_inference_steps=30, guidance_scale=7.0,
            generator=torch.Generator("cpu").manual_seed(7 + idx)).images[0]

        # Volver al tamaño original y componer SOLO la zona de los ojos sobre el idle original.
        out_rgba = out.resize((W0, H0), Image.LANCZOS).convert("RGBA")
        m = eye_mask(idle, W0).filter(ImageFilter.GaussianBlur(max(1, W0 // 160)))
        blink = idle.copy()
        blink.paste(out_rgba, (0, 0), m)        # solo los ojos (feather), resto = idle
        blink.putalpha(idle.split()[-1])        # conserva la silueta/alfa original (sin fondo)
        blink.save(idle_p.parent / "blink.png")
        print("OK", name, flush=True)
    except Exception as e:
        print("FAIL", name, repr(e)[:120], flush=True)
print("PARPADEO DONE", flush=True)
