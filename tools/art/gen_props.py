#!/usr/bin/env python3
"""Genera los PROPS (objetos) que la mascota 'usa' por actividad, como assets INDEPENDIENTES del
skin (se superponen sobre la criatura real -> identidad 100% intacta, reutilizables por todas las
skins). Recorta fondo y guarda en characters/_props/.

IMPORTANTE: usa **SDXL base 1.0** (no Animagine). El modelo anime de personajes dibuja una chibi
sosteniendo el objeto en vez del objeto solo; SDXL base sí hace objetos aislados estilo sticker.

  ~/miiamia-art/.venv/bin/python tools/art/gen_props.py            # todos
  ~/miiamia-art/.venv/bin/python tools/art/gen_props.py keyboard popcorn
PARAR la pet antes (VRAM)."""
from __future__ import annotations

import sys
from pathlib import Path

import cv2
import numpy as np
import torch
from diffusers import StableDiffusionXLPipeline
from PIL import Image
from rembg import new_session, remove

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "characters" / "_props"
SIZE = 220
MODEL = "stabilityai/stable-diffusion-xl-base-1.0"

# Frase-objeto por prop (sustantivo claro; el estilo lo dan SUFFIX/NEG).
PROPS = {
    "keyboard":   "a computer keyboard",
    "controller": "a video game controller gamepad",
    "popcorn":    "a red and white striped bucket full of popcorn",
    "headphones": "a pair of over-ear headphones",
    "tablet":     "a tablet device with a colorful screen",
    "laptop":     "an open laptop computer",
}
SUFFIX = (", kawaii, cute, soft pastel colors, bold clean black outline, flat cartoon sticker, "
          "simple, single object, centered, isolated on a plain solid white background")
NEG = ("person, people, human, girl, boy, child, character, mascot, animal, creature, pet, face, "
       "eyes, hands, fingers, arms, text, words, letters, watermark, logo, signature, "
       "photo, photograph, realistic, 3d render, busy background, scenery, pattern, "
       "multiple objects, collage, frame, border, drop shadow")


def frame(cut: Image.Image) -> Image.Image:
    bbox = cut.getbbox()
    if bbox:
        cut = cut.crop(bbox)
    w, h = cut.size
    s = int(max(w, h) * 1.06)
    canvas = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    canvas.paste(cut, ((s - w) // 2, (s - h) // 2), cut)
    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    names = sys.argv[1:] or list(PROPS.keys())
    OUT.mkdir(parents=True, exist_ok=True)
    print("cargando SDXL base 1.0 …", flush=True)
    pipe = StableDiffusionXLPipeline.from_pretrained(
        MODEL, torch_dtype=torch.float16, use_safetensors=True, variant="fp16")
    pipe.enable_model_cpu_offload()
    pipe.vae.enable_slicing()
    sess = new_session("isnet-general-use")

    for i, name in enumerate(names):
        desc = PROPS.get(name)
        if not desc:
            print("SKIP (sin desc):", name, flush=True); continue
        try:
            p = f"a flat sticker illustration of {desc}{SUFFIX}"
            im = pipe(p, negative_prompt=NEG, width=1024, height=1024,
                      num_inference_steps=30, guidance_scale=7.0,
                      generator=torch.Generator("cpu").manual_seed(20 + i)).images[0]
            cut = remove(im.convert("RGBA"), session=sess, post_process_mask=True)
            frame(cut).save(OUT / f"{name}.png")
            print("OK", name, flush=True)
        except Exception as e:
            print("FAIL", name, repr(e)[:140], flush=True)
    print("PROPS DONE", flush=True)


if __name__ == "__main__":
    main()
