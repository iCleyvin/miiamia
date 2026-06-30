#!/usr/bin/env python3
"""Genera un LOTE de skins anime cargando el modelo UNA sola vez (eficiente).
Cada criatura: genera (Animagine XL) -> recorta fondo (isnet-anime) -> encuadra -> monta skin.

  ~/miiamia-art/.venv/bin/python tools/art/generar_lote.py

Editá la lista CRIATURAS para añadir/quitar. Reusa la misma lógica de encuadre/manifest
que generar_skin.py.
"""
from __future__ import annotations

import json
from pathlib import Path

import torch
from diffusers import StableDiffusionXLPipeline
from PIL import Image
from rembg import new_session, remove

REPO = Path(__file__).resolve().parents[2]
CHARS = REPO / "characters"
SIZE = 256
STATES = ["idle", "typing", "gaming", "browsing", "talking", "sleeping", "watching", "music"]

# (id, etiqueta, descripción en inglés para el modelo, seed)
CRIATURAS = [
    ("gato_kawaii",   "Gatito",     "a fluffy kitten, cream and peach fur, big round eyes", 11),
    ("zorro_kawaii",  "Zorrito",    "a baby fox, orange and white fur, fluffy tail", 5),
    ("conejo_kawaii", "Conejito",   "a chubby bunny, white and soft pink, long ears", 8),
    ("slime_kawaii",  "Slime",      "a cute slime blob creature, translucent mint green, sparkles, tiny happy face", 3),
    ("ajolote_kawaii","Ajolote",    "a smiling axolotl, pastel pink, frilly gills", 7),
    ("pingu_kawaii",  "Pinguino",   "a round baby penguin, navy blue and white, rosy cheeks", 9),
    ("panda_kawaii",  "Panda rojo", "a baby red panda, rust orange and cream, fluffy striped tail", 4),
    ("fenix_kawaii",  "Fenix",      "a baby phoenix chick, warm orange and yellow, tiny flame crest, soft feathers", 6),
]

NEG = ("lowres, bad anatomy, text, error, watermark, signature, username, blurry, realistic, "
       "3d, photo, multiple views, border, frame, cropped")


def frame(cut: Image.Image) -> Image.Image:
    bbox = cut.getbbox()
    if bbox:
        cut = cut.crop(bbox)
    w, h = cut.size
    s = int(max(w, h) * 1.10)
    canvas = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    canvas.paste(cut, ((s - w) // 2, (s - h) // 2), cut)
    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


def build_skin(name: str, label: str, framed: Image.Image):
    out = CHARS / name / "sprites"
    out.mkdir(parents=True, exist_ok=True)
    for st in STATES:
        framed.save(out / f"{st}.png")
    anims = {st: {"source": f"sprites/{st}.png", "frameCount": 1,
                  "frameWidth": SIZE, "frameHeight": SIZE, "fps": 1} for st in STATES}
    manifest = {
        "name": label, "backend": "sprite", "scale": 2.0, "defaultState": "idle", "animated": False,
        "animations": anims, "voice": {"tts": "piper", "voice": "es_ES-sharvard-medium"},
        "persona": (f"Eres {label}, una criatura kawaii anime, juguetona y curiosa que vive en tu "
                    f"pantalla. Hablas espanol dominicano, calida, breve (1-2 frases)."),
    }
    (CHARS / name / f"{name}.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))


def main():
    print("cargando Animagine XL …", flush=True)
    pipe = StableDiffusionXLPipeline.from_pretrained(
        "cagliostrolab/animagine-xl-3.1", torch_dtype=torch.float16, use_safetensors=True)
    pipe.enable_model_cpu_offload()
    pipe.vae.enable_slicing()
    sess = new_session("isnet-anime")

    idx = json.loads((CHARS / "skins.json").read_text())
    for name, label, desc, seed in CRIATURAS:
        p = (f"no humans, chibi, {desc}, kawaii, big sparkly eyes, soft pastel, full body, centered, "
             f"plain white background, masterpiece, best quality, very aesthetic, clean lineart, soft shading")
        im = pipe(p, negative_prompt=NEG, width=1024, height=1024, num_inference_steps=28,
                  guidance_scale=6.5, generator=torch.Generator("cpu").manual_seed(seed)).images[0]
        cut = remove(im.convert("RGBA"), session=sess, post_process_mask=True)
        build_skin(name, label, frame(cut))
        idx = [e for e in idx if e["id"] != name] + [{"id": name, "label": label + " ✨"}]
        print("OK", name, flush=True)

    (CHARS / "skins.json").write_text(json.dumps(idx, ensure_ascii=False, indent=2))
    print("LOTE LISTO:", len(CRIATURAS), "criaturas", flush=True)


if __name__ == "__main__":
    main()
