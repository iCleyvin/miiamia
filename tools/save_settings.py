#!/usr/bin/env python3
"""Escribe ~/.config/miiamia/settings.json. Recibe el JSON completo por stdin.

Por stdin y no por argv: settings puede contener API keys y argv es visible en
/proc/<pid>/cmdline para cualquier usuario local. Escritura atómica (tmp+rename,
un lector concurrente nunca ve JSON truncado) y permisos 0600.
"""
import json
import os
import sys

d = os.path.expanduser("~/.config/miiamia")
os.makedirs(d, exist_ok=True)
data = sys.stdin.read()
if not data.strip() and len(sys.argv) > 1:
    data = sys.argv[1]  # compat: forma vieja por argv
json.loads(data)  # valida antes de escribir
dest = os.path.join(d, "settings.json")
tmp = dest + ".tmp"
fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as f:
    f.write(data)
os.replace(tmp, dest)
print("ok")
