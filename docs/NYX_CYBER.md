# Nyx — humana cyberpunk hiperrealista · Cómo se hace hiperrealismo en un overlay

> El problema: no puedes correr un MetaHuman en una layer-shell, y el 3D realtime de humanos
> cae en el valle inquietante. La solución de Nyx: **fotografía generada** (SDXL fotorrealista
> en la GPU local) + **rig de parches inpainted** + **micro-etología humana** + estética
> holográfica que convierte cada límite técnico en identidad.

## 1. La técnica de los parches sin costura (la clave)

Una imagen base fotorrealista (RealVisXL V5, 832×1216) y variantes generadas por
**inpainting local**: ojos cerrados, ojos entrecerrados, mirada izquierda/derecha, boca
entreabierta, boca abierta, sonrisa. El inpainting **solo cambia píxeles dentro de la
máscara** → recortando el bbox de cada variante se obtienen parches que encajan sobre la
base **píxel-perfectos, sin costura alguna**. Identidad 100% garantizada (no hay "otra cara",
es LA MISMA foto con los ojos cerrados).

Con 7 parches, una foto se convierte en una persona:
parpadeo + mirada sacádica + 2 visemas + sonrisa + ojos de sueño.

## 2. Micro-etología humana (lo que la hace sentir VIVA)

| Comportamiento real | En Nyx |
|---|---|
| Parpadeo: 12-20/min, irregular, ~12% dobles | Timer gaussiano (media ~4 s) con dobles; cierre 55 ms, apertura 95 ms (asimetría real) |
| Sacádicos: la mirada salta, no se desliza | Parches de mirada con cambio de 40 ms e histéresis (no aletea) |
| Respiración: 12-16/min, sube con activación | Escala sutil del torso; frecuencia = f(arousal) |
| Sway postural: nadie está quieto de pie | Rotación ±0.8° con 2 frecuencias superpuestas |
| Fidgets: mirar a un lado, parpadear, volver | Secuencia cada 20-50 s cuando está sola |
| Atención al tacto: inclinarse hacia el contacto | Caricia suave → lean hacia el cursor + sonrisa + neón cálido |
| Ritmo cardíaco visible (aquí: en el neón) | Implantes laten lub-dub a 62-120 bpm = f(arousal) |

## 3. Vida cyberpunk (los límites → estética)

- **Boot de sistema** al aparecer: flickers + neón que enciende + arpegio synth.
- **Glitch RGB** (dos copias colorizadas cian/magenta desplazadas): molestia y susto.
- **Susto = teletransporte**: glitch total → latido → *whoosh* → rematerializa en otra
  esquina de la pantalla (la respuesta cyberpunk a la tinta de Otto).
- **Scanlines** holográficas al 5%: presencia de proyección, respiran con el neón.
- Sonidos 100% sintetizados (stdlib): boot, blips, glitch, teleport, latido, apagado.
- Voz TTS con fx `cyber` (AM metálica 65 Hz + doble voz + brillo digital).

## 4. Pipeline de assets (reproducible)

```
systemctl --user stop miiamia                       # VRAM (o convive con sequential offload)
~/miiamia-art/.venv/bin/python tools/art/gen_nyx.py base          # 4 candidatas
#   -> elegir a ojo; medir cajas de ojos/boca; ajustar BOXES en gen_nyx.py
~/miiamia-art/.venv/bin/python tools/art/gen_nyx.py variants nyx_cN.png
~/miiamia-art/.venv/bin/python tools/art/gen_nyx.py cut nyx_cN.png
#   -> characters/nyx_cyber/layers/{base,eyes_*,mouth_*,smile,glow}.png + patches.json
#   -> copiar patches.json al bloque `human` del manifest
python tools/art/gen_nyx_sounds.py                  # sonidos synth
```

- Capa de neón (`glow.png`): extracción por color (cian/magenta saturados) de la base;
  en el backend recibe bloom real (MultiEffect) y late con el corazón.
- Recorte de fondo: rembg `isnet-general-use` (fotográfico, no el anime).
- Con juego abierto: `sequential_cpu_offload` genera con ~1.6 GB de VRAM libres.

## 5. Integración

Backend `shell/backends/CyberHumanBackend.qml` con la API uniforme + caricias
(petX/petY/petSpeed/held) + `jetEscape()`. Manifest `characters/nyx_cyber/nyx_cyber.json`
(backend `cyberHuman`, bloque `human` con `size`/`patches`). Mismo motor de humor
(arousal/pleasure) que Otto: **no hay animaciones de estado, hay una persona con estado
interno del que todo se deriva**.
