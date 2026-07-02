# Averno v3

Skin de Averno con rig por partes (`multipart-dragon-v1`).

## Archivos principales

- `dragon_inframundo_v3.json`: manifest de la skin y pivotes.
- `sprites/idle.png`: referencia completa usada como fallback visual y base de extraccion.
- `sprites/dragon_rig/`: piezas anatomicas renderizadas por `DragonRigV3Backend.qml`.
- `source_chroma.png`: fuente generada original, conservada para futuras extracciones.
- `source_fire_chroma_v2.png`: fuente chroma del fuego actual.

## Piezas

- `body.png`: torso, cuello y pelvis.
- `head.png`: cabeza, cuernos y nuca.
- `wing_l.png`: ala trasera/izquierda.
- `wing_r.png`: ala frontal/derecha.
- `front_legs.png`: patas delanteras.
- `hind_legs.png`: patas traseras.
- `tail.png`: cola.
- `chest_glow.png`, `eye_glow.png`, `mouth_glow.png`: efectos de luz.
- `fire_breath.png`: fallback de la respiracion de fuego actual, mas turbulenta y organica.
- `fire_breath_0.png` ... `fire_breath_7.png`: frames animados de fuego. Mantienen la punta
  derecha estable para que la llama salga de la boca y no de la nariz/frente.
- `fire_breath_v1.png`: respaldo del primer fuego, mas recto y tipo lanza.

## Regla de mantenimiento

No edites una pieza sin revisar video despues. En este rig, un cambio pequeño de mascara o pivote
puede verse bien quieto y romperse al respirar, aletear o escupir fuego.
