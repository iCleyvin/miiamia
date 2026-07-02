# Otto — Pulpo LEGO 3D 🐙 · Estudio etológico → diseño de la pet

> La pet más viva del proyecto se diseña al revés: primero la biología real del pulpo
> (*Octopus vulgaris* y parientes), después el código. Cada comportamiento de Otto existe
> porque el animal real lo hace.

## Etología real → comportamiento de Otto

| # | Comportamiento natural (real) | En Otto |
|---|---|---|
| 1 | **Cromatóforos**: el pulpo "habla" con la piel. Palidez = calma; rojo/oscuro = excitación o amenaza; oleadas oscuras ("passing cloud") al cazar; blanqueo súbito (display deimático) al asustarse. | Los ladrillos cambian de color en vivo según `arousal` (alerta) y `pleasure` (gusto). Ondas de color recorren cuerpo y brazos capa a capa. Susto = flash pálido + oscurecimiento. |
| 2 | **Brazos semi-autónomos**: 2/3 de sus ~500M de neuronas están EN los brazos; cada brazo explora por su cuenta. | Cada brazo tiene fase, rizo y "curiosidad" propios. De vez en cuando un brazo se va de expedición solo, sin que "la cabeza" haga nada. |
| 3 | **Curiosidad táctil**: explora todo tocándolo; las ventosas *saborean* lo que tocan. En acuarios extienden un brazo hacia manos amigas. | El cursor cerca = un brazo se estira hacia él. Caricia suave y sostenida = el brazo "toma tu mano" (la punta sigue al cursor), colores de calma, ojos entrecerrados. |
| 4 | **Respiración por sifón**: el manto se infla/desinfla bombeando agua; el ritmo se acelera con la excitación o el miedo. | El manto pulsa siempre (nunca está quieto). Frecuencia = f(arousal): lento dormido, rápido tras un susto. |
| 5 | **Propulsión a chorro + tinta**: ante una amenaza suelta un pseudomorfo de tinta y sale disparado por el sifón. | Frotarlo rápido/brusco = display deimático → nube de tinta (¡piezas LEGO negras!) → SE VA DE VERDAD a otra esquina de tu pantalla a chorro. Luego se calma poco a poco. |
| 6 | **Sueño activo (tipo REM)**: dormido cicla colores como si soñara (el pulpo "Heidi", y Nature 2021/iScience 2019 sobre estados de sueño activo/pasivo en cefalópodos). | Dormido (contexto `sleeping`): brazos recogidos, respiración lenta… y los colores ondulan suaves de vez en cuando: **Otto sueña en colores**. |
| 7 | **Camuflaje**: iguala color y textura del sustrato; lo rompe al moverse. | Tras ~3 min sin interacción muestrea el color medio de tu pantalla (grim) y se tiñe hacia él, mimetizándose con tu escritorio. Cualquier interacción lo rompe al instante. |
| 8 | **Ser sujetado**: al levantarlo se aferra con los brazos (y se estresa un poco). | Arrastrarlo = brazos que se enroscan hacia adentro (se agarra de tu cursor), leve oscurecimiento; al soltarlo, se recompone y aclara. |
| 9 | **Guarida**: descansa recogido en su refugio observando. | Viendo pelis/jugando: modo guarida — recogido, quieto, ojos atentos, colores neutros. |
| 10 | **Sin cuerdas vocales**: el pulpo es mudo; su mundo suena a agua: burbujas, el soplo del sifón, el golpe sordo de la tinta. | Sonidos 100% sintetizados de su mundo: burbujeo feliz al acariciarlo, *whoosh* del sifón al huir, *plof* de la tinta, blub lento al dormirse. Nada de voces falsas de animal. |

## Diseño visual: LEGO de verdad

- Construcción **ladrillo a ladrillo** en Qt Quick 3D con primitivas (#Cube/#Cylinder/#Sphere):
  manto = pila de placas redondeadas con **studs 2×2** arriba; ojos = cilindro blanco + stud
  negro (ojo LEGO clásico); 8 brazos = cadenas de piezas con taper, colocadas por curva
  paramétrica (rizo + onda viajera).
- Material plástico ABS: `PrincipledMaterial` con clearcoat (brillo de juguete).
- La **tinta son piezas**: burst de esferas LEGO negras (`ModelParticle3D`).
- Todo el movimiento se compone en **un solo `_compose()` por tick** (patrón probado del
  proyecto): respiración, brazos, mirada, colores — una sola intención corporal, nunca partes sueltas.

## Máquina de humor (el corazón)

Dos ejes continuos, como el animal:
- `arousal` (0 calma → 1 alerta): sube con sustos/manoseo brusco/juego; baja sola con calma exponencial.
- `pleasure` (0 mal → 1 encantado): sube con caricias suaves; baja con brusquedad.

Todo lo demás se DERIVA: paleta de cromatóforos, ritmo del sifón, amplitud/tempo de los brazos,
disposición a acercarse al cursor, probabilidad de camuflaje. No hay "animación de estado X":
hay un animal con un estado interno que se expresa igual que el real.

## Integración

Backend nuevo `shell/backends/OctopusLegoBackend.qml` con la API uniforme de Pet.qml
(characterDir/currentState/talking/voiceAmplitude/headYaw/headPitch/cursorProximity) +
entradas de caricia (petX/petY/petSpeed/petActive/held) + señal `jetEscape()` (Pet.qml
mueve la ventana). Manifest `characters/pulpo_lego/pulpo_lego.json` (backend `octopusLego`),
sonidos en `characters/pulpo_lego/sounds/` (generador: `tools/art/gen_otto_sounds.py`),
voz TTS con fx `bubble` (submarina). Reacciones y persona en personaje de pulpo.
