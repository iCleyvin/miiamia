#!/usr/bin/env python3
"""Genera a Nyx — humana cyberpunk HIPERREALISTA (RealVisXL V5) como rig de parches.

La técnica: una imagen base fotorrealista + variantes por INPAINTING LOCAL (ojos cerrados,
mirada izq/der, entreabiertos, visemas de boca, sonrisa). El inpainting solo cambia píxeles
DENTRO de la máscara -> los parches recortados encajan sin costura alguna sobre la base.
Las capas de neón (implantes) se extraen por color para el latido de luz.

Uso (parar miiamia antes — VRAM):
  gen_nyx.py base                 # 4 candidatas -> nyx_c0..3.png (elegir a ojo)
  gen_nyx.py variants nyx_c2.png  # variantes de ojos/boca (edita las cajas abajo)
  gen_nyx.py cut nyx_c2.png       # rembg + parches + glow -> characters/nyx_cyber/layers/
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "characters" / "nyx_cyber" / "layers"
WORK = Path.home() / "miiamia-art" / "nyx"
WORK.mkdir(parents=True, exist_ok=True)

MODEL = "SG161222/RealVisXL_V5.0"
W, H = 832, 1216

PROMPT = (
    "raw photo, stunning young woman, cyberpunk netrunner, waist-up portrait, "
    "facing camera, glowing cyan cybernetic implant lines on neck and left cheekbone, "
    "small chrome port below ear, dark techwear jacket with glowing seams, "
    "short dark hair with a few neon cyan strands, calm confident expression, "
    "subtle smile, looking at viewer, neon magenta and cyan rim lighting, "
    "plain very dark background, hyperrealistic, sharp focus, detailed skin pores, "
    "cinematic still, 8k uhd"
)
NEG = ("anime, cartoon, illustration, painting, 3d render, doll, deformed, disfigured, "
       "extra fingers, bad hands, blurry, lowres, watermark, text, logo, oversaturated")

# Cajas de inpaint (x, y, w, h) sobre 832x1216 — medidas sobre nyx_c2.png con rejilla.
BOXES = {
    "eyes":  (225, 480, 370, 110),
    "mouth": (325, 695, 225, 125),
}
VARIANTS = {
    "eyes_closed": ("eyes",  "closed eyes, relaxed closed eyelids, long eyelashes, serene"),
    "eyes_half":   ("eyes",  "half-closed sleepy heavy eyelids, drowsy gaze"),
    "eyes_left":   ("eyes",  "eyes looking far to her right side, iris turned sideways"),
    "eyes_right":  ("eyes",  "eyes looking far to her left side, iris turned sideways"),
    "mouth_open":  ("mouth", "mouth slightly open, speaking mid-word, teeth slightly visible"),
    "mouth_wide":  ("mouth", "mouth open wide, speaking emphatically"),
    "smile":       ("mouth", "warm delighted smile, joyful"),
}


def _pipe(cls):
    import torch
    p = cls.from_pretrained(MODEL, torch_dtype=torch.float16, variant="fp16",
                            use_safetensors=True)
    free = torch.cuda.mem_get_info()[0] / 1e9
    if free > 6.5:
        p.enable_model_cpu_offload()
    else:
        # VRAM compartida (¿juego abierto?): capa a capa en GPU — lento pero convive
        print(f"VRAM libre {free:.1f}GB -> sequential offload")
        p.enable_sequential_cpu_offload()
        p.enable_vae_slicing()
        p.enable_vae_tiling()
        # OJO: el umbral de tiling por defecto del VAE SDXL es 1024px -> a 832x1216 NO tesela
        # y el decode entero pide ~800MB que el juego no deja libres. Forzar teselas chicas.
        vae = p.vae
        for attr, val in (("tile_sample_min_size", 448), ("tile_sample_min_height", 448),
                          ("tile_sample_min_width", 448), ("tile_latent_min_size", 56),
                          ("tile_overlap_factor", 0.2)):
            if hasattr(vae, attr):
                setattr(vae, attr, val)
        p.enable_attention_slicing()
    return p


def gen_base():
    import torch
    from diffusers import StableDiffusionXLPipeline
    pipe = _pipe(StableDiffusionXLPipeline)
    for i, seed in enumerate([2077, 1337, 808, 42]):
        g = torch.Generator("cuda").manual_seed(seed)
        img = pipe(PROMPT, negative_prompt=NEG, width=W, height=H,
                   num_inference_steps=30, guidance_scale=5.5, generator=g).images[0]
        img.save(WORK / f"nyx_c{i}.png")
        print(f"✓ nyx_c{i}.png (seed {seed})")


def gen_variants(base_name: str):
    import torch
    from PIL import Image, ImageDraw, ImageFilter
    from diffusers import StableDiffusionXLInpaintPipeline
    base = Image.open(WORK / base_name).convert("RGB")
    pipe = _pipe(StableDiffusionXLInpaintPipeline)
    for name, (box_id, prompt) in VARIANTS.items():
        x, y, w, h = BOXES[box_id]
        mask = Image.new("L", base.size, 0)
        d = ImageDraw.Draw(mask)
        d.ellipse([x, y, x + w, y + h], fill=255)
        mask = mask.filter(ImageFilter.GaussianBlur(8))
        g = torch.Generator("cuda").manual_seed(7)
        img = pipe(prompt=f"raw photo, {prompt}, hyperrealistic, sharp focus",
                   negative_prompt=NEG, image=base, mask_image=mask,
                   width=W, height=H, strength=0.92,
                   num_inference_steps=30, guidance_scale=5.5, generator=g).images[0]
        img.save(WORK / f"nyx_{name}.png")
        print(f"✓ nyx_{name}.png")


def cut(base_name: str):
    """rembg de la base + parches recortados de las variantes + capa de neón por color."""
    from PIL import Image
    from rembg import remove, new_session
    import numpy as np

    base = Image.open(WORK / base_name).convert("RGB")
    print("rembg (isnet-general-use)…")
    cutout = remove(base, session=new_session("isnet-general-use"),
                    post_process_mask=True)
    OUT.mkdir(parents=True, exist_ok=True)

    arr = np.array(cutout)
    a = arr[:, :, 3]
    # limpiar islas: conservar solo la componente conexa más grande del alfa (adiós manchas)
    binm = (a > 40).astype(np.uint8)
    lab = np.zeros_like(binm, dtype=np.int32)
    cur, sizes = 0, {}
    hgt, wdt = binm.shape
    for sy in range(0, hgt, 4):
        for sx in range(0, wdt, 4):
            if binm[sy, sx] and not lab[sy, sx]:
                cur += 1
                stack = [(sy, sx)]
                lab[sy, sx] = cur
                n = 0
                while stack:
                    y0, x0 = stack.pop()
                    n += 1
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        yy, xx = y0 + dy, x0 + dx
                        if 0 <= yy < hgt and 0 <= xx < wdt and binm[yy, xx] and not lab[yy, xx]:
                            lab[yy, xx] = cur
                            stack.append((yy, xx))
                sizes[cur] = n
    if sizes:
        main = max(sizes, key=sizes.get)
        a = np.where(lab == main, a, 0).astype(np.uint8)
    # borde inferior: desvanecido holográfico (oculta el corte de la chaqueta y se ve proyección)
    fade_px = 64
    ramp = np.linspace(1.0, 0.22, fade_px)
    a[-fade_px:, :] = (a[-fade_px:, :].astype(np.float32) * ramp[:, None]).astype(np.uint8)
    arr[:, :, 3] = a
    cutout = Image.fromarray(arr, "RGBA")
    cutout.save(OUT / "base.png")
    alpha = a

    # parches: recorte del bbox (+margen) de cada variante, con el alfa de la base
    manifest_patches = {}
    margin, feather = 26, 18
    for name, (box_id, _) in VARIANTS.items():
        p = WORK / f"nyx_{name}.png"
        if not p.exists():
            print(f"  ! falta {p.name}, salto"); continue
        x, y, w, h = BOXES[box_id]
        x0, y0 = max(0, x - margin), max(0, y - margin)
        x1, y1 = min(W, x + w + margin), min(H, y + h + margin)
        var = np.array(Image.open(p).convert("RGB"))[y0:y1, x0:x1]
        a = alpha[y0:y1, x0:x1].astype(np.float32)
        # pluma en los bordes del parche para fundir con la base
        fh, fw = a.shape
        yy, xx = np.mgrid[0:fh, 0:fw]
        edge = np.minimum(np.minimum(xx, fw - 1 - xx), np.minimum(yy, fh - 1 - yy))
        a *= np.clip(edge / feather, 0, 1)
        out = np.dstack([var, a.astype(np.uint8)])
        Image.fromarray(out, "RGBA").save(OUT / f"{name}.png")
        manifest_patches[name] = {"x": x0, "y": y0, "w": x1 - x0, "h": y1 - y0}
        print(f"  ✓ {name}.png @{x0},{y0} {x1-x0}x{y1-y0}")

    # capa de neón: píxeles cian/magenta saturados y brillantes -> glow.png (aditiva)
    rgb = np.array(base).astype(np.float32)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = rgb.max(2); mn = rgb.min(2)
    sat = (mx - mn) / np.maximum(mx, 1)
    cyan = (b > 140) & (g > 120) & (r < g * 0.75) & (sat > 0.35)
    magenta = (r > 140) & (b > 120) & (g < r * 0.72) & (sat > 0.35)
    m = ((cyan | magenta) & (alpha > 100)).astype(np.uint8) * 255
    from PIL import ImageFilter
    m = np.array(Image.fromarray(m, "L").filter(ImageFilter.GaussianBlur(3)))
    glow = np.dstack([rgb.astype(np.uint8), m])
    Image.fromarray(glow, "RGBA").save(OUT / "glow.png")
    print("  ✓ glow.png")

    (OUT / "patches.json").write_text(json.dumps(
        {"size": [W, H], "patches": manifest_patches}, indent=2))
    print("  ✓ patches.json")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "base"
    if cmd == "base":
        gen_base()
    elif cmd == "variants":
        gen_variants(sys.argv[2])
    elif cmd == "cut":
        cut(sys.argv[2])
