#!/usr/bin/env python3
"""Pipeline COMPLETO de skins anime: cada estado con su POSE auténtica, misma criatura.

Toma la idle base ya generada de cada criatura y, vía IP-Adapter (identidad consistente),
genera las 7 poses restantes (typing/gaming/browsing/talking/sleeping/watching/music),
cada una con su acción. Recorta fondo, encuadra y reescribe los sprites del skin.

  ~/miiamia-art/.venv/bin/python tools/art/generar_skin_full.py            # todas
  ~/miiamia-art/.venv/bin/python tools/art/generar_skin_full.py drag_kawaii # solo una
  ... generar_skin_full.py --scale 0.55 gato_kawaii                         # ajustar identidad

Carga el modelo UNA vez. ~17s por pose (7 poses/criatura).
"""
from __future__ import annotations

import sys
from pathlib import Path

import torch
from diffusers import StableDiffusionXLPipeline
from PIL import Image
from rembg import new_session, remove
from transformers import CLIPVisionModelWithProjection

REPO = Path(__file__).resolve().parents[2]
CHARS = REPO / "characters"
SIZE = 256

# Descripción base de cada criatura (identidad textual; el IP-Adapter aporta la visual).
BASE = {
    "drag_kawaii":    "a cute kawaii baby dragon, pastel purple, big sparkly eyes, tiny wings",
    "gato_kawaii":    "a fluffy kitten, cream and peach fur, big round eyes",
    "zorro_kawaii":   "a baby fox, orange and white fur, fluffy tail",
    "conejo_kawaii":  "a chubby bunny, white and soft pink, long ears",
    "slime_kawaii":   "a cute slime blob creature, translucent mint green, sparkles, tiny happy face",
    "ajolote_kawaii": "a smiling axolotl, pastel pink, frilly gills",
    "pingu_kawaii":   "a round baby penguin, navy blue and white, rosy cheeks",
    "panda_kawaii":   "a baby red panda, rust orange and cream, fluffy striped tail",
    "fenix_kawaii":   "a baby phoenix chick, warm orange and yellow, tiny flame crest, soft feathers",
}

# Acción por estado (idle NO se regenera: se reusa la base). seed-offset por estado -> variedad.
ACTIONS = {
    "typing":   ("sitting at a tiny laptop computer, typing on the keyboard, focused happy expression", 101),
    "gaming":   ("holding a handheld game console with both hands, playing video games, excited", 102),
    "browsing": ("holding a small tablet, looking at the screen curiously", 103),
    "talking":  ("mouth open talking cheerfully, one paw raised, expressive happy", 104),
    "sleeping": ("sleeping, eyes closed, curled up, peaceful, little zzz floating above", 105),
    "watching": ("sitting with a bucket of popcorn, watching a screen, cozy and relaxed", 106),
    "music":    ("wearing big headphones, listening to music, eyes closed happily, music notes floating", 107),
}

NEG = ("lowres, bad anatomy, bad hands, text, error, watermark, signature, username, blurry, realistic, "
       "3d, photo, multiple views, border, frame, cropped, extra limbs")
SUFFIX = (", kawaii, big sparkly eyes, soft pastel, full body, centered, plain white background, "
          "masterpiece, best quality, very aesthetic, clean lineart, soft shading")


def frame(cut: Image.Image) -> Image.Image:
    bbox = cut.getbbox()
    if bbox:
        cut = cut.crop(bbox)
    w, h = cut.size
    s = int(max(w, h) * 1.10)
    canvas = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    canvas.paste(cut, ((s - w) // 2, (s - h) // 2), cut)
    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


def ref_on_white(name: str) -> Image.Image:
    """La idle recortada (transparente) compuesta sobre blanco -> referencia de identidad."""
    idle = Image.open(CHARS / name / "sprites" / "idle.png").convert("RGBA")
    white = Image.new("RGBA", idle.size, (255, 255, 255, 255))
    return Image.alpha_composite(white, idle).convert("RGB")


def main():
    argv = sys.argv[1:]
    scale = 0.6
    if "--scale" in argv:
        i = argv.index("--scale")
        scale = float(argv[i + 1])
        del argv[i:i + 2]
    names = argv if argv else list(BASE.keys())

    print("cargando image encoder (ViT-H) …", flush=True)
    enc = CLIPVisionModelWithProjection.from_pretrained(
        "h94/IP-Adapter", subfolder="models/image_encoder", torch_dtype=torch.float16)
    print("cargando SDXL + IP-Adapter …", flush=True)
    pipe = StableDiffusionXLPipeline.from_pretrained(
        "cagliostrolab/animagine-xl-3.1", image_encoder=enc,
        torch_dtype=torch.float16, use_safetensors=True)
    pipe.load_ip_adapter("h94/IP-Adapter", subfolder="sdxl_models",
                         weight_name="ip-adapter-plus_sdxl_vit-h.safetensors")
    pipe.set_ip_adapter_scale(scale)
    pipe.enable_model_cpu_offload()
    pipe.vae.enable_slicing()
    sess = new_session("isnet-anime")

    for name in names:
        if name not in BASE:
            print("SKIP (sin descripción base):", name, flush=True)
            continue
        try:
            ref = ref_on_white(name)
        except Exception as e:
            print("SKIP (sin idle base):", name, e, flush=True)
            continue
        out = CHARS / name / "sprites"
        for state, (action, seed) in ACTIONS.items():
            try:
                p = f"no humans, chibi, {BASE[name]}, {action}{SUFFIX}"
                im = pipe(p, negative_prompt=NEG, ip_adapter_image=ref,
                          width=1024, height=1024, num_inference_steps=28, guidance_scale=6.5,
                          generator=torch.Generator("cpu").manual_seed(seed)).images[0]
                cut = remove(im.convert("RGBA"), session=sess, post_process_mask=True)
                frame(cut).save(out / f"{state}.png")
                print("OK", name, state, flush=True)
            except Exception as e:
                print("FAIL", name, state, repr(e)[:120], flush=True)
    print("FULL PIPELINE DONE", flush=True)


if __name__ == "__main__":
    main()
