#!/usr/bin/env python3
"""Escribe ~/.config/miiamia/settings.json. Recibe el JSON completo como argv[1]."""
import json
import os
import sys

d = os.path.expanduser("~/.config/miiamia")
os.makedirs(d, exist_ok=True)
data = sys.argv[1] if len(sys.argv) > 1 else "{}"
json.loads(data)  # valida antes de escribir
with open(os.path.join(d, "settings.json"), "w", encoding="utf-8") as f:
    f.write(data)
print("ok")
