#!/usr/bin/env python3
"""Pipeline de skins ANIME (AI local): descripción -> genera (Animagine XL) -> recorta fondo
(isnet-anime) -> encuadra -> monta como skin de miiamia + lo añade a characters/skins.json.

Requiere el venv de ~/miiamia-art (torch+diffusers+rembg). Ejemplos:
  ~/miiamia-art/.venv/bin/python tools/art/generar_skin.py gato_anime "Gatito anime" --prompt "a fluffy kitten"
  ... generar_skin.py drag_anime "Dragoncita" --from /ruta/recorte_transparente.png   # sin generar

El arte es 1 imagen pulida por estado (la misma); la VIDA la da el QML (respiración/bob).
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[2]
CHARS = REPO / "characters"
SIZE = 256
STATES = ["idle", "typing", "gaming", "browsing", "talking", "sleeping", "watching", "music"]


def frame(cut: Image.Image) -> Image.Image:
    """Recorta al contenido, centra en lienzo cuadrado con margen, escala a SIZE."""
    bbox = cut.getbbox()
    if bbox:
        cut = cut.crop(bbox)
    w, h = cut.size
    s = int(max(w, h) * 1.10)
    canvas = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    canvas.paste(cut, ((s - w) // 2, (s - h) // 2), cut)
    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


def generate(prompt: str, seed: int) -> Image.Image:
    import torch
    from diffusers import StableDiffusionXLPipeline
    from rembg import new_session, remove

    pipe = StableDiffusionXLPipeline.from_pretrained(
        "cagliostrolab/animagine-xl-3.1", torch_dtype=torch.float16, use_safetensors=True)
    pipe.enable_model_cpu_offload()
    pipe.vae.enable_slicing()
    neg = ("lowres, bad anatomy, text, error, watermark, signature, username, blurry, realistic, "
           "3d, photo, multiple views, border, frame, cropped")
    p = (f"no humans, chibi, {prompt}, kawaii, big sparkly eyes, soft pastel, full body, centered, "
         f"plain white background, masterpiece, best quality, very aesthetic, clean lineart, soft shading")
    im = pipe(p, negative_prompt=neg, width=1024, height=1024, num_inference_steps=28,
              guidance_scale=6.5, generator=torch.Generator("cpu").manual_seed(seed)).images[0]
    return remove(im.convert("RGBA"), session=new_session("isnet-anime"), post_process_mask=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("label")
    ap.add_argument("--prompt", default="")
    ap.add_argument("--from", dest="src", default="", help="usar un PNG transparente ya hecho (sin generar)")
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()

    cut = Image.open(a.src).convert("RGBA") if a.src else generate(a.prompt, a.seed)
    framed = frame(cut)

    out = CHARS / a.name / "sprites"
    out.mkdir(parents=True, exist_ok=True)
    for st in STATES:            # v1: misma ilustración para todos los estados; la vida la da el QML
        framed.save(out / f"{st}.png")

    anims = {st: {"source": f"sprites/{st}.png", "frameCount": 1,
                  "frameWidth": SIZE, "frameHeight": SIZE, "fps": 1} for st in STATES}
    manifest = {
        "name": a.label, "backend": "sprite", "scale": 2.0, "defaultState": "idle", "animated": False,
        "animations": anims, "voice": {"tts": "piper", "voice": "es_ES-sharvard-medium"},
        "persona": (f"Eres {a.label}, una criatura kawaii anime, juguetona y curiosa que vive en tu "
                    f"pantalla y acompana a tu humano. Hablas espanol dominicano, calida, breve (1-2 frases). "
                    f"Si algo no se entiende, pregunta con carino en vez de inventar."),
    }
    (CHARS / a.name / f"{a.name}.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))

    idx = json.loads((CHARS / "skins.json").read_text())
    idx = [e for e in idx if e["id"] != a.name] + [{"id": a.name, "label": a.label + " ✨"}]
    (CHARS / "skins.json").write_text(json.dumps(idx, ensure_ascii=False, indent=2))
    print("SKIN", a.name, "->", out)


if __name__ == "__main__":
    main()
