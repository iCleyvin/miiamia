#!/usr/bin/env python3
"""Genera las capas del RIG por huesos (cabeza + cuerpo) con SAM y marca el manifest backend="rig".
  ~/miiamia-art/.venv/bin/python tools/art/gen_rig.py drag_kawaii
Capas en sprites/rig/: head_open.png, head_closed.png (parpadeo), body.png. Pivote = cuello (neckY)."""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from ultralytics import SAM

CHARS = Path(__file__).resolve().parents[2] / "characters"
NECK = 0.54
model = SAM("mobile_sam.pt")


def build(name: str):
    sp = CHARS / name / "sprites"
    if not (sp / "idle.png").exists():
        print("SKIP", name); return
    idle = Image.open(sp / "idle.png").convert("RGBA")
    W, H = idle.size
    bp = sp / "blink.png"
    blink = Image.open(bp).convert("RGBA").resize((W, H)) if bp.exists() else idle

    res = model(np.array(idle.convert("RGB")), points=[[int(W * 0.5), int(H * 0.26)]],
                labels=[1], verbose=False)
    hm = res[0].masks.data[0].cpu().numpy() > 0.5
    ia, ba = np.array(idle), np.array(blink)
    yn = int(H * NECK)

    ha = ia.copy(); ha[~(hm & (ia[:, :, 3] > 20)), 3] = 0          # cabeza, ojos abiertos
    hb = ba.copy(); hb[~(hm & (ba[:, :, 3] > 20)), 3] = 0          # cabeza, ojos cerrados
    bo = ia.copy(); rm = hm.copy(); rm[yn:, :] = False
    bo[rm & (ia[:, :, 3] > 20), 3] = 0                             # cuerpo (sin la cabeza)

    out = sp / "rig"; out.mkdir(exist_ok=True)
    Image.fromarray(ha).save(out / "head_open.png")
    Image.fromarray(hb).save(out / "head_closed.png")
    Image.fromarray(bo).save(out / "body.png")

    mp = CHARS / name / f"{name}.json"
    man = json.loads(mp.read_text())
    man["backend"] = "rig"
    man["rig"] = {"body": "sprites/rig/body.png", "head_open": "sprites/rig/head_open.png",
                  "head_closed": "sprites/rig/head_closed.png", "neckY": NECK, "size": W}
    mp.write_text(json.dumps(man, ensure_ascii=False, indent=2))
    print("RIG OK", name, "| head px", int(hm.sum()))


for n in (sys.argv[1:] or ["drag_kawaii"]):
    build(n)
