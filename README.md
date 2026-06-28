# miiamia 🐉

Una **mascota virtual de escritorio con IA local** para **Hyprland / Wayland**. Vive sobre tu pantalla,
reacciona a lo que haces y conversa contigo por **texto y voz** — todo **100% local**, sin nube, sin cuentas.

- 🎭 **Reacciona a tu actividad:** escribes, juegas (saca su consola portátil 🎮), ves un video 🍿,
  escuchas música 🎧, navegas o descansas 😴 — cada cosa con su animación.
- 💬 **Habla contigo:** chat por texto (clic) y por **voz** (mantén clic derecho y háblale).
- 🧠 **IA local embebida:** corre un modelo pequeño en tu equipo (no necesitas Ollama ni internet tras la instalación).
- 🎨 **Todo configurable:** personalidad (tierna, juguetona, grosera, coqueta… o la que tú escribas),
  voz, idioma, tamaño, monitor y modelo — desde un menú ⚙.
- 🔒 **Privado por diseño:** nada sale de tu máquina. Sin telemetría.

## Requisitos

- **Hyprland** sobre **Wayland** (usa el protocolo `wlr-layer-shell`).
- **~4 GB de RAM** mínimo (escala solo: usa modelos más grandes si tienes más RAM/GPU).
- GPU opcional (NVIDIA/AMD/Intel vía Vulkan) — acelera IA y voz; si no, corre en CPU.

## Instalación

De una línea (clona, instala dependencias, descarga el modelo y la voz, y deja la mascota corriendo):

```bash
curl -fsSL https://raw.githubusercontent.com/iCleyvin/miiamia/main/install.sh | bash
```

O manual:

```bash
git clone https://github.com/iCleyvin/miiamia.git ~/miiamia
cd ~/miiamia && bash install.sh
```

> El instalador automatiza por completo **Arch / CachyOS / Manjaro** (todo en repos oficiales, sin AUR).
> En otras distros instala lo disponible y te guía para **Quickshell**, **llama.cpp** y **whisper.cpp**.

## Uso

| Acción | Qué hace |
|---|---|
| **Clic izquierdo** en la mascota | abre/cierra el chat de texto |
| **⚙** (en el chat) | menú de configuración (personalidad, voz, idioma, modelo, pantalla, tamaño) |
| **Clic derecho mantenido** | hablarle por voz (push-to-talk) — suelta para enviar |
| **Arrástrala** | moverla por la pantalla |

Control del servicio: `systemctl --user restart|stop miiamia` · logs: `journalctl --user -u miiamia -f`.

## Cómo funciona

| Capa | Tecnología |
|------|-----------|
| Overlay | [Quickshell](https://quickshell.org) (Qt6/QML) + `wlr-layer-shell` |
| Avatar | Qt Quick sprites (cualquier personaje; manifiesto en `characters/`) |
| Contexto | Hyprland IPC (`socket2`) + MPRIS (`playerctl`) |
| Chat (LLM) | [llama.cpp](https://github.com/ggml-org/llama.cpp) + Qwen3 (Apache-2.0), o cualquier GGUF |
| Voz | [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (STT) + [Piper](https://github.com/rhasspy/piper) (TTS) |

El modelo de IA y la voz se **cargan bajo demanda** y se **descargan solos** al estar inactivos o al jugar,
para no consumir recursos de más. Detalle técnico en [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Personajes

El personaje por defecto es **Kira** (una dragona), con sprites placeholder generados por
`tools/make_placeholder_sprites.py`. Para crear el tuyo, copia `characters/kira/` a
`characters/<tu-personaje>/`, renombra y edita el `.json` (animaciones, voz, personalidad),
reemplaza los sprites por tu arte y apunta `active_character` en `config/miiamia.toml`.

## Licencia

MIT — ve [`LICENSE`](LICENSE). Los modelos descargados tienen sus propias licencias (Qwen3: Apache-2.0;
voces de Piper: ver cada voz).
