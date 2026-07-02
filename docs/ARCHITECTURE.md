# Arquitectura de miiamia

Documento de diseño. Resume la investigación (overlay/avatar/contexto/IA-voz), las decisiones
verificadas adversarialmente, el roadmap y el presupuesto de VRAM. Entorno objetivo:
**CachyOS · Hyprland 0.55.4 · Wayland · NVIDIA RTX 5060 Laptop 8GB · Ollama local**.

---

## 1. Enfoque elegido

**Quickshell-nativo primario + (renderer web opcional, en pausa).**

Un overlay 100% nativo en Quickshell/QML con avatar por **sprite sheets** (`AnimatedSprite`).
Dos daemons Python independientes (contexto y IA/voz) se comunican con el overlay por **D-Bus**.
El renderer web para Live2D/VRM se diseñó pero está **bloqueado** por falta de soporte estable
(ver §6), así que NO es parte del MVP. Para criaturas hiperrealistas, el camino actual es un rig
2D por partes documentado en [`docs/DRAGON_RIGS.md`](DRAGON_RIGS.md).

### Por qué (resumen de la investigación)
- **Overlay:** el protocolo `wlr-layer-shell` es la única vía correcta en Hyprland. La capa
  `overlay` es la única que dibuja sobre ventanas fullscreen (juegos). Quickshell expone esto
  nativamente (`WlrLayershell`) y permite click-through pixel-preciso con `Region` (máscara de
  input). Referencia real funcionando: proyecto `qs-vpets`.
- **Descartados:** Godot 4 (sin layer-shell + bugs de transparencia/freeze con NVIDIA+Wayland),
  Tauri/WebView (no expone layer-shell), SDL3 (always-on-top WONTFIX en Wayland),
  `wl_shimeji` (bug de subsurface en bordes en Hyprland, #9117).
- **Avatar:** `AnimatedSprite` nativo cubre TODOS los tipos de personaje (dragón, criatura,
  humanoide) sin proceso extra. Live2D/VRM dan más calidad para humanoides pero hoy solo se
  servirían vía Qt WebEngine, que no es estable aquí (§6).

---

## 2. Componentes

| Componente | Responsabilidad | Tech |
|-----------|-----------------|------|
| `shell/shell.qml` | Entry: lee personaje activo, carga manifest, monta la mascota | Quickshell/QML |
| `shell/Pet.qml` | Ventana layer-shell overlay; click-through; posición/drag; recibe el estado | QML `PanelWindow` + `WlrLayershell` + `Region` |
| `shell/backends/SpriteBackend.qml` | Render de la animación según el estado actual | Qt Quick `AnimatedSprite` |
| `shell/backends/DragonRigV3Backend.qml` | Rig hiperreal por partes para Averno v3 | Qt Quick `Image` + pivotes declarados |
| `shell/ChatBubble.qml` *(M3)* | Ventana de chat **separada** (foco de teclado), abre con `SUPER+M` | QML `PanelWindow` `keyboardFocus=OnDemand` |
| `shell/ContextEngine.qml` ✅ | Detecta la ventana activa y calcula el estado | **QML nativo**: `Quickshell.Hyprland` `rawEvent` (socket2) + idle timer |
| `context/` *(M4+, opcional)* | Solo lo que QML no ve: GameMode D-Bus, tecleo real (evdev), idle real (ext-idle-notify) | Python asyncio |
| `ai/` *(M3-M4)* | Chat (Ollama) + STT (faster-whisper) + TTS (Piper) | Python asyncio |
| `renderer/` *(I+D)* | Live2D/VRM en web — **en pausa** (§6) | TS + Vite |

### Máquina de estados (la consume el avatar)
`GAMING > TALKING > LISTENING > TYPING > BROWSING > IDLE > SLEEPING`
(prioridad descendente; la calcula `context/state_machine.py`).

---

## 3. Cómo se logra el overlay (claves técnicas verificadas)

```qml
PanelWindow {
    WlrLayershell.layer: WlrLayer.Overlay        // sobre fullscreen
    WlrLayershell.namespace: "miiamia"           // identificable con `hyprctl layers`
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None   // PERMANENTE (ver bug #14136)
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    anchors { top:true; bottom:true; left:true; right:true }
    color: "transparent"
    mask: dragging ? null : Region { /* rect del sprite */ }  // click-through
}
```
- Refuerzo opcional en Lua: `hl.layerrule('noinput', { namespace = 'miiamia' })`.
- Rutas de archivo en QML: usar **`Quickshell.shellDir`** (ruta real), NO `Qt.resolvedUrl`
  (que devuelve el FS virtual `qrc:/qs-blackhole`).
- Leer archivos locales: **`FileView`** de `Quickshell.Io` (XMLHttpRequest sobre `file://`
  está deshabilitado por seguridad).

---

## 4. Roadmap por milestones

| Milestone | Entregable | Esfuerzo |
|-----------|-----------|----------|
| **M1 ✅** | Overlay funcional: avatar sprite (Kira) sobre Hyprland y juegos, click-through, drag, servicio systemd | hecho |
| **M2 ✅** | Reacción a actividad: 6 estados (idle/typing/gaming/browsing/talking/sleeping) + `ContextEngine.qml` (Hyprland `rawEvent` → clasificador → estado). **Nativo en QML, sin Python/D-Bus.** Verificado en vivo: Alacritty→typing | hecho |
| **M3** | Chat por texto: `ChatBubble.qml` (`SUPER+M`), `ollama create kira`, streaming token a token; swap a `llama3.2:3b` en gaming | 5-7 días |
| **M4** | Voz: PTT (`SUPER+V`) → faster-whisper (es) → Ollama → Piper. Animaciones listening/thinking/talking. Latencia objetivo <800ms | 7-10 días |
| **M5** | *(opcional/I+D)* Avatar premium para humanoides: evaluar Lottie/`rlottie` o Canvas2D (NO Qt WebEngine) | — |
| **M6** | Multi-monitor (roaming), selector de personajes, `install.sh` completo, doc de formato de personaje | 2 semanas |

---

## 5. Presupuesto de VRAM (8151 MiB)

**Modo normal (sin juego):**
`qwen2.5:7b` Q4 (num_ctx=2048) 4.4 GB · faster-whisper turbo int8 1.5 GB · Piper CPU 0 GB ·
overlay 0.3 GB → **~6.2 GB, margen 1.9 GB**.

**Modo gaming** (detecta `steam_app_*`/GameMode): LLM descargado (`OLLAMA_KEEP_ALIVE=0`) ·
STT pasa a whisper `small` en CPU · overlay 0.1 GB → **2.6-4.6 GB**, dejando 3.5-5.5 GB al juego.

**Reglas críticas:**
- `num_ctx` máximo seguro para `qwen2.5:7b` = **2048**. Subirlo derrama a RAM y colapsa 5-20×.
- `OLLAMA_KEEP_ALIVE=0` libera VRAM al detectar gaming **antes** de que el juego cargue.
- El `context/` debe emitir `GAMING` al ver la clase `steam_app_*`/GameMode, sin esperar fullscreen.

---

## 6. Correcciones de la verificación adversarial (no ignorar)

1. **Qt WebEngine para Live2D/VRM — REFUTADO.** El soporte WebView en Quickshell no está
   mergeado (crashea) y Qt6 WebEngine + Wayland + NVIDIA tiene la transparencia rota
   (QTBUG-135786, regresión 6.9). → **No usar WebBackend** en el MVP. Alternativa para humanoides
   premium: `rlottie`/Lottie o Canvas2D nativo en QML.
2. **Instalación de Quickshell — usar repos, NO el AUR.** El AUR fue comprometido el 11-jun-2026
   (~2000 paquetes). Quickshell está en `extra`/`cachyos`: `pacman -S quickshell`. (Ya estaba
   instalado 0.3.0 en esta máquina.)
3. **faster-whisper usa `ctranslate2`, no PyTorch.** Necesita `python-ctranslate2-bin ≥4.7.0`
   (fix INT8 para Blackwell sm_120; v4.6.2 lo deshabilitaba). Verificar con
   `ctranslate2.get_supported_compute_types('cuda')`, NO con `torch.cuda`.
   ⚠️ El sistema tiene **Python 3.14**; faster-whisper/ctranslate2 probablemente requieran un
   **venv con Python 3.11-3.12** (varios paquetes de voz aún no soportan 3.14).
4. **Bug Hyprland #14136** (abierto, sin fix en 0.55.4): `keyboard_interactivity=Exclusive` +
   región vacía captura TODO el puntero. → El overlay usa `keyboardFocus=None` **permanente**; el
   chat va en ventana separada. Nunca cambiar el keyboardFocus del overlay.
5. **`OLLAMA_KEEP_ALIVE=0`** cambia el default futuro, no descarga lo ya cargado. Para liberar:
   `ollama stop <modelo>` o `POST /api/generate {keep_alive:0}` (el endpoint `/v1` **ignora**
   keep_alive). Verificar el unload con `ollama ps`, no con el timing de `nvidia-smi`.

---

## 7. Dependencias (por fase)

- **M1 (hecho):** `quickshell qt6-declarative qt6-wayland` (repos), Pillow (sprites placeholder).
- **M2 (hecho):** nada extra — QML nativo (`Quickshell.Hyprland`). El daemon Python solo hará falta más adelante para GameMode/evdev/idle real.
- **M3:** `ollama pull qwen2.5:7b llama3.2:3b`; `ollama create kira -f ai/personas/kira.modelfile`.
- **M4:** `python-ctranslate2-bin python-faster-whisper piper-tts-bin` + voz
  `es_MX-claude-high`; venv Python 3.11/3.12 para la voz.
- **M5+ (opcional):** Steam VRoid Studio (appid 1486350); `rlottie` si se va por Lottie.

> Live2D Cubism Core (`renderer/src/lib/live2dcubismcore.min.js`) es propietario y NO se
> redistribuye — se descarga manual de live2d.com (gratis uso personal). Ya está en `.gitignore`.
