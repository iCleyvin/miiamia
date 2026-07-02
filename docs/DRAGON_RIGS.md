# Rigs de dragon en miiamia

Este documento registra la evolucion de Averno y el formato actual para mascotas realistas por
partes. El objetivo es evitar que una pet hiperrealista sea solo una imagen quieta o una pila de
sprites que saltan.

## Estado actual

La skin activa de referencia es `dragon_inframundo_v3`.

- Manifest: `characters/dragon_inframundo_v3/dragon_inframundo_v3.json`
- Backend: `shell/backends/DragonRigV3Backend.qml`
- Assets: `characters/dragon_inframundo_v3/sprites/dragon_rig/`
- Formato de rig: `multipart-dragon-v1`

`v3` no reemplaza `v2`. `v2` queda como punto de retorno estable y `v3` es el salto hacia un modelo
por partes: cabeza, cuerpo, patas, alas, cola, brillos y fuego se renderizan como capas
independientes con pivotes.

## Evolucion

### `dragon_inframundo`

Primer Averno hiperrealista. Nacio como una imagen generada con fondo chroma, convertida a PNG con
alpha y luego cortada en capas. El resultado se veia bien quieto, pero la animacion podia romper
cuernos, alas o patas porque las capas salian de una sola imagen no pensada para rigging.

Backend: `DragonRigBackend.qml`.

### `dragon_inframundo_v2`

Version estable basada en overlays conservadores. El cuerpo completo se mantiene intacto y las capas
solo agregan parallax, tension, glow y fuego. Esto evita que al mover una pieza desaparezca otra.

Backend: `DragonRigV2Backend.qml`.

Ventaja: estable visualmente.
Limite: no es un rig real; la anatomia principal sigue siendo una imagen completa con overlays.

### `dragon_inframundo_v3`

Rig por partes. El cuerpo completo deja de ser la unica fuente visual y se separa en piezas
anatomicas:

- `tail.png`
- `wing_l.png`
- `wing_r.png`
- `hind_legs.png`
- `body.png`
- `front_legs.png`
- `head.png`
- `chest_glow.png`
- `eye_glow.png`
- `mouth_glow.png`
- `fire_breath.png`
- `fire_breath_0.png` ... `fire_breath_7.png`

Las piezas se dibujan con z-order fijo y cada una rota/escala desde un pivote declarado en el
manifest.

## Manifest `multipart-dragon-v1`

Ejemplo minimo:

```json
{
  "backend": "dragonRigV3",
  "rig": {
    "format": "multipart-dragon-v1",
    "size": 512,
    "parts": {
      "tail": "sprites/dragon_rig/tail.png",
      "wing_l": "sprites/dragon_rig/wing_l.png",
      "wing_r": "sprites/dragon_rig/wing_r.png",
      "hind_legs": "sprites/dragon_rig/hind_legs.png",
      "body": "sprites/dragon_rig/body.png",
      "front_legs": "sprites/dragon_rig/front_legs.png",
      "head": "sprites/dragon_rig/head.png",
      "chest_glow": "sprites/dragon_rig/chest_glow.png",
      "eye_glow": "sprites/dragon_rig/eye_glow.png",
      "mouth_glow": "sprites/dragon_rig/mouth_glow.png",
      "fire_breath": "sprites/dragon_rig/fire_breath.png"
    },
    "fire": {
      "fps": 18,
      "frames": [
        "sprites/dragon_rig/fire_breath_0.png",
        "sprites/dragon_rig/fire_breath_1.png"
      ]
    },
    "pivots": {
      "tail": { "x": 0.66, "y": 0.73 },
      "wing_l": { "x": 0.29, "y": 0.35 },
      "wing_r": { "x": 0.60, "y": 0.31 },
      "hind_legs": { "x": 0.60, "y": 0.78 },
      "body": { "x": 0.38, "y": 0.78 },
      "front_legs": { "x": 0.28, "y": 0.79 },
      "head": { "x": 0.30, "y": 0.42 }
    }
  }
}
```

Los pivotes son coordenadas normalizadas dentro del canvas de 512x512. `x=0.60`, `y=0.31` significa
60% del ancho y 31% del alto. El backend usa esos puntos como origen de rotacion/escala.

## Z-order

El orden de dibujo en `DragonRigV3Backend.qml` es:

1. cola
2. ala izquierda trasera
3. patas traseras
4. cuerpo
5. patas delanteras
6. ala derecha frontal
7. cabeza
8. brillos
9. fuego
10. particulas

Este orden evita que el ala frontal quede debajo del cuerpo y que las patas traseras tapen el torso.

## Animaciones

`DragonRigV3Backend.qml` mezcla cuatro tipos de movimiento:

- Respiracion: escala suave del cuerpo, pecho y criatura completa.
- Aleteo: rotacion independiente de `wing_l` y `wing_r` desde pivotes distintos.
- Atencion: la cabeza responde a `headYaw` y `headPitch`, calculados desde la posicion global del cursor.
- Evento infernal: crouch, snarl, apertura de alas y fuego por frames desde la boca.

Tambien hay sesgos por estado:

- `typing`: alas mas recogidas y cabeza mas baja.
- `gaming`: alas mas abiertas y glow mas intenso.
- `watching`: postura atenta con cabeza algo elevada.
- `music`: aleteo mas activo.
- `sleeping`: crouch alto, alas plegadas y glow bajo.

## Pipeline de assets

La fuente visual aprobada de v2 se conserva en:

```text
characters/dragon_inframundo_v3/source_chroma.png
characters/dragon_inframundo_v3/sprites/idle.png
```

Las partes v3 se extrajeron desde `idle.png` con mascaras suaves. Esto mantiene identidad visual,
textura y proporcion. El fuego es un asset separado generado en chroma y limpiado a alpha. La
version actual usa una bocanada mas turbulenta; `fire_breath.png` queda como fallback y
`fire_breath_0.png` ... `fire_breath_7.png` son frames deformados con la punta derecha estable para
que el nacimiento no baile sobre la nariz o la frente. El primer asset se conserva como respaldo:

```text
characters/dragon_inframundo_v3/sprites/dragon_rig/fire_breath.png
characters/dragon_inframundo_v3/sprites/dragon_rig/fire_breath_0.png
characters/dragon_inframundo_v3/sprites/dragon_rig/fire_breath_1.png
characters/dragon_inframundo_v3/sprites/dragon_rig/fire_breath_2.png
characters/dragon_inframundo_v3/sprites/dragon_rig/fire_breath_3.png
characters/dragon_inframundo_v3/sprites/dragon_rig/fire_breath_4.png
characters/dragon_inframundo_v3/sprites/dragon_rig/fire_breath_5.png
characters/dragon_inframundo_v3/sprites/dragon_rig/fire_breath_6.png
characters/dragon_inframundo_v3/sprites/dragon_rig/fire_breath_7.png
characters/dragon_inframundo_v3/sprites/dragon_rig/fire_breath_v1.png
characters/dragon_inframundo_v3/source_fire_chroma_v2.png
```

Para futuras versiones, el flujo recomendado es:

1. Generar o dibujar una referencia hiperrealista en pose neutra, 3/4, con todas las patas visibles.
2. Separar piezas con solapamiento generoso, no con cortes ajustados.
3. Declarar pivotes en el manifest.
4. Verificar en video, no solo con screenshot.
5. Ajustar pivotes/amplitudes antes de tocar arte otra vez.

## Verificacion

Comandos usados para revisar en vivo:

```bash
systemctl --user restart miiamia.service
wf-recorder -y -r 30 -f .cache/recordings/averno-v3-live-2.mp4
ffmpeg -y -i .cache/recordings/averno-v3-live-2.mp4 \
  -vf "fps=5,crop=600:410:1340:760,scale=2400:1640,tile=5x8" \
  -frames:v 1 .cache/recordings/averno-v3-live-2-close.jpg
```

Ultima verificacion del fuego por frames:

```bash
qmllint shell/backends/DragonRigV3Backend.qml
systemctl --user restart miiamia.service
wf-recorder -y -r 30 -f .cache/recordings/averno-v3-fireframes-mouth-2.mp4
ffmpeg -y -ss 3.6 -i .cache/recordings/averno-v3-fireframes-mouth-2.mp4 \
  -frames:v 1 .cache/recordings/averno-v3-fireframes-mouth-2-frame.jpg
```

La revision valida:

- fuego desde la boca, no desde frente/cuernos;
- cuatro patas visibles;
- alas sin postura de herida;
- cola completa;
- sin cambio automatico de skin;
- servicio `miiamia.service` activo tras reiniciar.

## Limitaciones actuales

`v3` es un rig por partes 2D, no un modelo Live2D/Cubism ni una malla deformable. Las piezas ya son
independientes, pero siguen viniendo de una ilustracion base. Para un salto adicional haria falta:

- arte fuente diseñado directamente por capas;
- deformadores de malla para alas/cuello/cola;
- interpolacion de poses o keyframes por estado;
- editor visual de pivotes para no ajustar coordenadas a mano.

La ventaja de `v3` es que ya separa el contrato: arte por partes en el manifest, animacion en el
backend, y verificacion por video.
