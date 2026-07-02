# GUÍA MAESTRA DE DISEÑO DE PETS — miiamia

> **Para el agente que va a diseñar o rediseñar una pet.** Este archivo es el punto de
> entrada único: qué técnica elegir, la receta paso a paso de cada una, los contratos que
> NO se rompen, y cómo verificar. Los detalles finos viven en los docs enlazados.
> Léelo entero antes de tocar nada.

---

## 0. Las tres reglas de oro (no negociables)

1. **No hay "animaciones de estado": hay un ser con estado interno.** Toda pet viva usa el
   *motor de humor* (§7): dos ejes continuos `arousal` (calma→alerta) y `pleasure`
   (molesto→encantado) con decaimiento exponencial, y TODO lo visible se **deriva** de ahí
   (colores, respiración, postura, sonidos). Si te encuentras escribiendo
   `if (estado == "feliz") playAnimation(...)`, para y rediseña.
2. **Nada 2D encima de la pet.** El usuario rechaza props/imágenes/glifos superpuestos.
   La reacción sale del propio cuerpo (postura, color, expresión). Los objetos, si existen,
   viven DENTRO del render (View3D, capa del rig). Ver memoria `no-image-overlays-on-pet`.
3. **Una sola escritura de pose por tick.** Todo movimiento se compone en una única función
   `_compose(dt)` disparada por `FrameAnimation` — una intención corporal coherente. Timers
   sueltos escribiendo partes = pet rota (lección de Vivi, ver CLAUDE.md).

---

## 1. Elegir técnica (tabla de decisión)

| Técnica | Ejemplo vivo | Elegir cuando… | Doc detallado |
|---|---|---|---|
| **A. Sprite kawaii** | gato/zorro/ajolote | criatura chibi simple, 30 min de trabajo | (receta §2) |
| **B. Rig 2.5D por partes** | Averno v3 (dragón) | criatura realista NO humana con anatomía articulable | `docs/DRAGON_RIGS.md` |
| **C. 3D modelo (VRM/glTF)** | Vivi (waifu anime) | existe un modelo 3D con licencia limpia (CC0) | `docs/WAIFU_3D_PLAN.md` |
| **D. 3D procedural** | Otto (pulpo LEGO) | estética construible por primitivas (LEGO, voxel, low-poly) — cero assets externos | `docs/OTTO_PULPO.md` |
| **E. Hiperreal de parches** | Nyx (cyberpunk) | fotorrealismo (humanos/retratos); expresión facial rica | `docs/NYX_CYBER.md` |

Regla rápida: ¿humano/rostro realista? → E. ¿Se puede construir con cubos/esferas? → D
(la más controlable y sin problemas de licencia). ¿Hay VRM CC0 que encaje? → C.
¿Criatura realista con partes? → B. ¿Chibi rápido? → A.

---

## 2. Receta A — Sprite kawaii (SDXL anime)

1. Generar con el pipeline de arte (`~/miiamia-art/.venv`, **parar la pet o usar
   sequential offload si hay juego abierto** — ver §11-VRAM): Animagine XL 3.1, prompt
   `no humans, chibi, <criatura>, kawaii, big sparkly eyes, ... plain white background,
   masterpiece, best quality, clean lineart`; recorte con rembg **isnet-anime**.
2. Identidad entre poses: IP-Adapter `ip-adapter-plus_sdxl_vit-h`, scale 0.6 (validado).
   NO intentes separar partes del cuerpo por color ni generar "partes sueltas" (fracasó, ver CLAUDE.md).
3. Parpadeo: variante ojos-cerrados por inpainting local (`tools/art/generar_parpadeo.py`).
4. Manifest: `backend: "sprite"`, `animations.<estado>.{source,frameCount,frameWidth,frameHeight,fps}`,
   `blink`. Los skins de 1 frame reciben respiración/bob automáticos del SpriteBackend.

## 3. Receta B — Rig 2.5D por partes (contrato multipart-dragon-v1)

Resumen (detalle en `docs/DRAGON_RIGS.md`, anexo del handoff 2026-06-30):
1. Imagen base en 3/4 con **todas las extremidades visibles** y espacio para solapamientos.
2. Separar piezas CON MARGEN: cuerpo, cabeza, patas, cola, alas/orejas, ojos, boca, glows,
   efectos (p.ej. 8 frames de fuego). Pivotes normalizados en el manifest.
3. Copiar el contrato de `characters/dragon_inframundo_v3/` (manifest `rig.parts` +
   `rig.pivots` + `rig.fire`) y `shell/backends/DragonRigV3Backend.qml`. Para otra anatomía,
   crear backend hermano con la MISMA API (§6), no mutar el del dragón.
4. Truco anti-costuras (Averno v2): base completa + overlays de baja opacidad con
   parallax/respiración — nunca cortar sin margen.
5. Priorizar 3-4 acciones memorables por especie (mirar, respirar, reaccionar al cursor,
   aburrirse) antes que muchos estados toscos. **Verificar en VIDEO (wf-recorder), no por screenshot.**

## 4. Receta C — 3D modelo VRM/glTF (Vivi)

Resumen (detalle en `docs/WAIFU_3D_PLAN.md` y CLAUDE.md § modelos 3D):
1. Modelo con **licencia verificada en la metadata VRM** (CC0: `meta.licenseName`); los
   AvatarSample/Alicia NO son redistribuibles. Fuente validada: `madjin/vrm-samples/vroid/beta`.
2. `RuntimeLoader` NO da nombres de huesos → **direccionar por índices** en el manifest
   (`model3d.jointIdx`, `hairChains`, `bustChains`, morphs con su stride). Calibrar por modelo.
3. TODA la pose por `_composePose()` (cadena axial hips→spine→chest→neck→head reparte la
   intención). Ajustes en `manifest.model3d.motion`, NO hardcodear timers.
4. NO implementar saludo de brazo sin calibrar ejes (terminaba mano-en-nuca). Seguras:
   mirada, sonrisa, ladeo, respiración, torso.
5. Props = nodos DENTRO del View3D (phone3d/headphones3d), jamás Image 2D.
6. Fases continuas sin wrap: acumular con `FrameAnimation` (`_sway += frameTime * k`);
   un loop 0→2π con multiplicadores no enteros da tirones periódicos.

## 5. Receta D — 3D procedural (Otto)

Detalle completo en `docs/OTTO_PULPO.md`. Esqueleto de la receta:
1. **Estudiar la etología real del animal** y escribir la tabla comportamiento→código ANTES
   de programar. Cada comportamiento existe porque el animal real lo hace.
2. Construir con primitivas de Qt Quick 3D (`#Cube/#Sphere/#Cylinder`) vía
   `createObject` en `_build()` (guardar refs en arrays JS para escribirles pose/color).
   Material "plástico": `PrincipledMaterial` con `clearcoatAmount`.
3. Cadenas orgánicas (brazos/colas): colocación por **curva paramétrica** en `_compose()`
   (curvatura base + rizo concentrado en la punta + onda viajera con fase por miembro),
   con clamp de suelo. NO parenting anidado de nodos.
4. Color emocional por elemento: paleta derivada del humor + onda de fase por índice
   (actualizar materiales cada 2 frames, no cada frame).
5. Partículas = `ModelParticle3D` con delegate temático (la tinta de Otto son esferas LEGO).
6. Verificación de proporciones SOLO visual (harness + grim, §10): 3 iteraciones mínimo.

## 6. Receta E — Hiperreal de parches (Nyx)

Detalle completo en `docs/NYX_CYBER.md`. La esencia:
1. Base fotorrealista: **RealVisXL V5** local (832×1216), 4 candidatas, elegir a ojo.
2. **La clave**: variantes por **inpainting local** (ojos cerrados/half/mirada L-R,
   2 visemas, sonrisa). Fuera de la máscara los píxeles son idénticos → parches recortados
   con pluma encajan sin costura, identidad garantizada. Medir cajas con rejilla
   (`tools/art/gen_nyx.py` BOXES) sobre la candidata elegida.
3. rembg `isnet-general-use` (foto) + limpieza de islas (componente conexa mayor) +
   **desvanecido del borde inferior** (oculta el corte del busto; estética holograma).
4. Glow por umbral de color gateado por alfa → late lub-dub (bpm = f(arousal)) con bloom
   `MultiEffect`. Que capture luz reflejada en la piel es CORRECTO (late con la fuente).
5. Micro-etología humana: parpadeo estadístico (media ~4s, 12% dobles, cierre 55ms/apertura
   95ms), sacádicos instantáneos con histéresis, sway de 2 frecuencias, fidgets cada 20-50s.
6. Los límites técnicos se convierten en estética (glitch RGB, scanlines ENMASCARADAS a la
   silueta, boot, teletransporte).

---

## 7. El motor de humor (patrón compartido — copiar de Otto/Nyx)

```
arousal  (0..1): sube con sustos/manoseo brusco; decae expo hacia ~0.25 (tau ~8s)
pleasure (0..1): sube con caricia suave; decae hacia ~0.45 (tau ~20s)
_roughMeter: acumula brusquedad; >1.0 => _startle()
```
Derivaciones estándar: respiración = f(arousal) · color/glow = mix(paletas, pleasure/arousal)
· amplitud de movimiento = f(estado+humor) · huida (susto) → señal `jetEscape()` que Pet.qml
convierte en dash de ventana (`_dashAway`).

**Entradas de caricia** (ya cableadas en Pet.qml, hover sin robar clicks):
`petActive`, `petX/petY` (0..1), `petSpeed` (anchos/segundo, suavizada; <1.5 = caricia,
>1.5 = brusco), `held` (arrastre → aferrarse/estrés leve).

**Interacciones estándar de toda pet nueva**: caricia→gusto visible · brusco→susto+huida ·
arrastre→reacción física · dormir (contexto `sleeping`)→algo especial (Otto sueña en colores,
Nyx baja el neón) · música→ritmo · saludo al acercarse el cursor (manifest `greetings`) ·
reacciones por contexto (manifest `reactions.<estado>`, ver Reactions.qml).

## 8. Contrato de integración (checklist EXACTA para cablear una pet nueva)

**API uniforme del backend** (properties que Pet.qml inyecta):
`characterDir(url) · config(var, bloque del manifest) · currentState · talking ·
voiceAmplitude · voiceState · headYaw/headPitch(-1..1) · cursorNear/cursorProximity ·
scale · monitorName · petActive/petX/petY/petSpeed/held` + señal `jetEscape()`.

**Manifest** `characters/<id>/<id>.json`:
```json
{ "name": "...", "backend": "<tipo>", "scale": 2.0,
  "view": {"w":..., "h":...},          // tamaño del avatar (base escala 2.0)
  "<bloque-propio>": { "sounds": true, "volume": 0.35, ... },
  "greetings": [...], "reactions": { "gaming": [...], ... },
  "voice": { "tts": "piper", "voice": "<voz>", "fx": "<perfil>", "length_scale": 1.0 },
  "persona": "Eres <nombre>, ... español dominicano, breve." }
```

**Pet.qml** (7 toques, buscar cómo lo hacen `isOctopus`/`isCyber`):
flag `is<Nuevo>` · sizing con `petData.view` · Component en el Loader · `hoverEnabled` del
petTouch · `cursorProximity`/greeting/polling · lista de backends conocidos (warning) ·
gate del prop 2D (`actProp.shown`). Y la entrada en `characters/skins.json`.

## 9. Sonido (regla: CERO Atari) y voz

- **Todo sonido nuevo usa `tools/art/sfx_kit.py`** (numpy+scipy; correr con
  `~/miiamia-art/.venv/bin/python`). Un evento = 2-4 CAPAS (sub saturado + aire/ruido
  barrido + tono/pad desafinado + brillo FM) fundidas con **reverb Schroeder con cola**.
  Ondas crudas sin reverb = rechazado por el usuario ("muy de Atari").
- Acústica del MUNDO de la pet: Otto = agua (paso-bajo global <4kHz, burbujas Minnaert,
  reverb de tanque — `gen_otto_sounds.py`); Nyx = holo-tech (cristal FM, subs, colas
  largas — `gen_nyx_sounds.py`). Definir la acústica del mundo ANTES de sintetizar.
- Verificar SIN oídos: análisis espectral (peak sin clipping, % energía sub<100Hz o
  >4kHz según el mundo, centroide inicio/fin, cola en dB) + reproducir con
  `pw-play --volume 0.5` para el usuario.
- Reproducción: Process `pw-play --volume` con cooldowns (`_sfxCooldown`), gate
  `manifest.<bloque>.sounds`; el daemon NO (los SFX son del backend).
- **Voz TTS per-pet**: gate `manifest.voice.fx`. Perfiles en `voice/tts.py`:
  `infernal, cute, sweet, ghost, bubble, cyber` — añadir nuevos ahí y VALIDAR el
  filtergraph con ffmpeg + sine antes de shippear. Voces faltantes se auto-descargan.

## 10. Verificación (obligatoria antes de dar por buena una pet)

1. **Estática**: `qmllint` sobre todo QML tocado · `python -m json.tool` del manifest ·
   py_compile de scripts.
2. **Visual (el loop del proyecto)**: harness en scratchpad con symlinks a `Pet.qml` +
   `backends/` reales + shell.qml mínimo → `quickshell -p .` en la sesión Wayland real →
   `grim -o <monitor>` → **MIRAR la imagen** → corregir → repetir (mínimo 3 iteraciones).
   OJO: la pet del harness sale en el monitor DEFAULT (HDMI si está conectado).
   Para movimiento, `wf-recorder` unos segundos y revisar frames.
3. **Comportamiento**: harness standalone del backend manejando `petActive/petSpeed/...`
   con Timers (caricia suave → señal de gusto; brusco → susto+`jetEscape` en el log).
   `hyprctl dispatch movecursor` NO funciona (config Lua de Omarchy) — no intentes mover
   el mouse real.
4. **En vivo**: `active_character` en `~/.config/miiamia/settings.json` (escritura atómica
   0600) → `systemctl --user restart miiamia` → journal sin errores → grim del monitor
   del usuario (eDP-2).

## 11. Gotchas duros (te van a morder si los ignoras)

- **VRAM 8GB compartida**: parar miiamia antes de generar arte. Si hay un JUEGO abierto:
  `enable_sequential_cpu_offload()` + `enable_vae_tiling()` **forzando**
  `tile_sample_min_size=448` (el umbral por defecto del VAE SDXL es 1024px y no tesela).
- **Venv de arte**: lo gestiona `uv`. torchvision DEBE ser `+cu128` con
  `--index-url .../whl/cu128` SIN extra-index de pypi (si no, uv instala cu130 y rompe).
- **FileView en vivo**: `blockAllReads: true` y derivar rutas localmente en la función
  (properties encadenadas se leen STALE en handlers).
- **MultiEffect**: `anchors.fill` PISA el offset `x/y` (usar width/height + x).
  Scanlines/overlays de efecto SIEMPRE enmascarados a la silueta (`maskSource`).
- **QML**: fases sin wrap (FrameAnimation acumulando) · timers gateados por `visible` ·
  defaults al leer el manifest (`x || fallback`) · `Date.now()` sí existe en QML (no en
  workflows).
- Assets: verificar LICENCIA antes de commitear (VRM: metadata embebida; SDXL: outputs OK).
  Nada de rutas `/home/<user>` ni datos personales en archivos trackeados.
- El commit final: mensaje descriptivo + `Co-Authored-By`, merge a main, push. Actualizar
  la memoria del agente y este doc si la receta cambió.

## 12. Checklist de shipping (copiar y tachar)

```
[ ] Doc de diseño/etología escrito ANTES del código (docs/<PET>.md)
[ ] Assets generados y verificados a ojo (grid de candidatas/variantes)
[ ] Backend con API uniforme + motor de humor + _compose único
[ ] Sonidos sfx_kit (capas+reverb) + análisis espectral + escuchados
[ ] Voz per-pet (fx validado con ffmpeg) en el manifest
[ ] Manifest completo (view, greetings, reactions, persona) + skins.json
[ ] Pet.qml: los 7 toques del §8
[ ] qmllint + JSON + harness visual (3+ iteraciones) + harness de comportamiento
[ ] En vivo sin errores en journal + screenshot final
[ ] Commit + push + memoria actualizada
```
