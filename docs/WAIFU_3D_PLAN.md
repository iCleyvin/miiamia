# Waifu Anime 3D con vida — plan de implementación

> Documento de diseño para `docs/WAIFU_3D_PLAN.md`. Añadir una **pet nueva** a miiamia: una **waifu anime 3D** (personaje femenino anime estilizado, **SFW / vestida / apta para app pública**) con vida real (parpadeo, respiración, mirada al cursor, lip-sync, poses por estado), cargada como un modelo **VRM/glTF** en **Qt Quick 3D** dentro del overlay de Quickshell y cableada como un backend más en `Pet.qml`.
>
> Estado: **de-risk técnico ya superado** (ver Resumen). Fecha: 2026-07-01. Hardware objetivo: RTX 5060 Laptop 8GB, NVIDIA propietario, Wayland, CachyOS/Arch. Verificado localmente sobre Qt 6.11.1 + Quickshell 0.3.0 + assimp 6.0.5.

---

## 1. Resumen ejecutivo

**¿Es viable? Sí.** Los dos pilares técnicos están **verificados empíricamente en este equipo** (no de oídas), con veredicto **CONFIRMED** de los verificadores:

- **Carga + render**: `View3D` de Qt Quick 3D embebido en un `PanelWindow` de Quickshell (WlrLayer.Overlay, `color: transparent`) **renderiza 3D transparente sobre el escritorio en NVIDIA/Wayland** usando `SceneEnvironment.backgroundMode: Transparent` + `renderMode: Offscreen`. `RuntimeLoader` (módulo `QtQuick3D.AssetUtils`, apoyado en el plugin de sistema `assimp`) **carga y renderiza un glTF/GLB** (validado con `Fox.glb` y con un VRM real). Fuentes: [RuntimeLoader](https://doc.qt.io/qt-6/qml-qtquick3d-assetutils-runtimeloader.html), [SceneEnvironment](https://doc.qt.io/qt-6/qml-qtquick3d-sceneenvironment.html), [glTF2Importer.cpp de assimp](https://github.com/assimp/assimp/blob/master/code/AssetLib/glTF2/glTF2Importer.cpp).
- **Sistema de vida**: en un VRM real cargado por RuntimeLoader, `Model.morphTargets[i].weight` (real 0..1) es **leíble y escribible en runtime** (cara = 410 morphs) y `Model.skin.joints[i].eulerRotation` es **escribible y deforma el mesh skinneado** (skin.joints = 148–152; `skeleton = null` → se usa el path moderno `Skin`). Verificado escribiendo y releyendo. Fuentes: [Model](https://doc.qt.io/qt-6/qml-qtquick3d-model.html), [MorphTarget](https://doc.qt.io/qt-6/qml-qtquick3d-morphtarget.html), [Skin](https://doc.qt.io/qt-6/qml-qtquick3d-skin.html).

**Qué se logra HOY (esta sesión, con RuntimeLoader + índices):** cargar la waifu VRM ya descargada, encuadrarla busto-arriba con transparencia, y darle vida completa (parpadeo por morph, respiración por hueso de torso, mirada por rotación de cuello/ojos con `headYaw/headPitch`, lip-sync `voiceAmplitude → visema `aa``, poses por estado, sway de pelo aproximado). Todo **por índice**, no por nombre.

**Qué es de semanas / trabajo posterior:** (a) el pase a **Balsam offline** para producción (acceso por nombre estable + más eficiente); (b) el **look anime real** (MToon se pierde → se degrada a PBR/unlit sin outline; recuperar toon requiere `CustomMaterial` o pre-horneado en Blender); (c) **spring-bones reales** (pelo/falda/busto): Qt no ejecuta `VRMC_springBone`, hay que aproximar por seno o portar Verlet.

**El "pero" crítico y no negociable (verificado):** con **RuntimeLoader los nodos NO conservan el nombre glTF** → `objectName` sale **vacío en todo el árbol** (probe: `NAMED_NODES=0 / TOTAL=637`), confirmando el [bug del foro Qt 156984](https://forum.qt.io/topic/156984/). Consecuencia: **se direcciona TODO por ÍNDICE** (mapa `{nombre_lógico: índice}` guardado en el manifest, obtenido una vez con un dump). Si más adelante se quiere acceso por nombre, **Balsam** sí preserva `objectName` (probe: convirtió `shino.vrm` → `Shino.qml` con 581 `objectName`, huesos `J_Bip_*` y morphs `Fcl_*` estables). `balsam` está **instalado** en `/usr/lib/qt6/bin/balsam`.

**Veredicto de los verificadores:** ambas afirmaciones núcleo → **CONFIRMED**, con estas correcciones obligatorias: (1) direccionar por índice con RuntimeLoader (no por nombre); (2) añadir **luz** siempre (PBR sin `DirectionalLight`/IBL = escena negra); (3) esperar perder MToon/outline; (4) probar el `.glb` concreto (assimp falla en *algunos* VRM con `Missing section "meshes"`, [VRM4U #4](https://github.com/ruyo/VRM4U/issues/4)) — el nuestro ya cargó bien.

---

## 2. Decisión de asset

### Modelo recomendado: **Vivi** (preset beta de VRoid) — **CC0**

- **Formato**: VRM 0.x (glTF 2.0 binario, GLB). `generator=UniGLTF-1.24`, `exporterVersion=VRoidStudio-0.8.1`; extensión top-level `VRM` (NO `VRMC_vrm`, o sea VRM 0.0 clásico). Contenedor GLB íntegro verificado (magic `glTF`, `declared length == actual`, 18 089 136 bytes).
- **Licencia — CC0, VERIFICADA en la metadata VRM embebida** (fuente autoritativa que lee cualquier loader): `meta.licenseName="CC0"`, `allowedUserName="Everyone"`, `commercialUssageName="Allow"`, `otherLicenseUrl=""`. La [spec VRM 0.0](https://github.com/vrm-c/vrm-specification/blob/master/specification/0.0/README.md) define `CC0` como *"copyright waiver"* → **uso irrestricto / dominio público**. **Es redistribuible en el repo OSS público** sin atribución y con uso comercial permitido.
- **Descarga (curl HTTP 200, sin login, 17.25 MB)**: `https://raw.githubusercontent.com/madjin/vrm-samples/master/vroid/beta/Vivi.vrm`. Página origen: [madjin/vrm-samples](https://github.com/madjin/vrm-samples) (dir `vroid/beta`) + [OpenGameArt CC0 VRoid](https://opengameart.org/content/vroid-studio-cc0-models).
- **Femenino anime + vida lista**: 3 meshes (`Face.baked`, `Body.baked`, `Hair001.baked`), 157 nodos, **54 humanBones**, **41 morph targets** en `Face.baked`, 28 texturas PNG **embebidas** (archivo autocontenido, `KHR_materials_unlit` estilo toon plano). Contiene exactamente los blendshapes que el sistema de vida necesita (visemas + blink + expresiones; ver §5) **y** física de busto (`J_Sec_L/R_Bust1/Bust2`), 22 spring groups y 12 collider groups.
- **SFW**: el modelo tal cual es una waifu VRoid vestida (estilo colegiala), SFW. La metadata trae `sexualUssageName="Allow"`, pero eso es solo un **flag de permiso del autor**, no implica contenido explícito. **Scope del proyecto: personaje anime vestido, apto para app pública.**

### Skins alternas (todas CC0, mismo pipeline)
`Victoria_Rubin.vrm` (14.8 MB), `Sendagaya_Shino.vrm` (14.4 MB, 54 humanBones, ya validado con Balsam), `Vita.vrm` (13.7 MB, el más ligero) — todas en `madjin/vrm-samples/vroid/beta/`, todas con CC0 en su metadata.

### NO embarcar (licencia incompatible)
- **AvatarSample_A/B/C** (VRoid stable): `licenseName=Other`; el [FAQ oficial de VRoid](https://vroid.pixiv.help/hc/en-us/articles/4402614652569) confirma que **NO son CC0**, tienen *conditions of use*, y está **prohibido** redistribuirlos como CC0 o por dinero.
- **AliciaSolid** (Dwango): `licenseName=Other`, gobernado por [3d.nicovideo.jp/alicia/rule.html](https://3d.nicovideo.jp/alicia/rule.html). Técnicamente atractivo (tiene blendshapes `lookUp/Down/Left/Right`), pero **INCIERTO** para re-hosting → solo referencia de QA, no asset embarcado.
- **ToxSam / MoonGirl**: CC0 real pero descarga Arweave devolvió `size=0` (no fiable) y el catálogo no es anime-waifu. Descartado.

### Distribución en el repo
Dos opciones, ambas válidas por ser CC0:

1. **Embarcar `Vivi.vrm` directo en el repo** bajo `characters/waifu_vivi/model/vivi.vrm` (~17 MB). Ventaja: funciona sin red. Es lo recomendado dado que CC0 lo permite y el tamaño es asumible (comparable a un sprite sheet grande).
2. **Bajar en instalación estilo GGUF** (via `install.sh`/`provision.sh`): si se prefiere no inflar el repo. La URL raw responde HTTP 200 sin auth, apta para `curl` en install-time.

**Recomendación:** embarcar `Vivi.vrm` como skin 3D por defecto + ofrecer Victoria/Shino/Vita como descargas opcionales. **Conservar intacta la metadata CC0** y añadir un `CREDITS`/`NOTICE` mencionando *"VRoid Studio sample models, CC0"* con enlaces a origen (buena práctica, aunque CC0 no lo exija). Dejar la puerta abierta a que el usuario cargue su propio VRM.

---

## 3. Pipeline de carga

```
Vivi.vrm  ──(copiar/renombrar a .glb, opcional)──►  RuntimeLoader (in-process)  ──►  View3D transparente
   │                                                        │
   └─ CC0, GLB íntegro, texturas embebidas                  └─ source: URL file:// ABSOLUTA
```

### Camino de esta sesión: RuntimeLoader in-process (el ya validado)
- `source: file://` **ABSOLUTO**. **Gotcha del equipo confirmado**: `Qt.resolvedUrl` devuelve `qrc:/` y RuntimeLoader falla en Quickshell → construir la URL como `("" + characterDir) + modelPath` (usar `Quickshell.shellDir`/`characterDir`, no `Qt.resolvedUrl`).
- **`.vrm` vs `.glb`**: el reporte de compat recomendaba renombrar `.vrm → .glb` por si el sniff de extensión de Qt rechaza `.vrm`. **Empíricamente el `.vrm` cargó directo sin renombrar** (assimp registra `"gltf glb vrm"` en su descriptor y detecta GLB por magic number). Renombrar es **inocuo** y elimina el riesgo → **renombrar a `.glb` por seguridad** al embarcar.
- El asset se crea como **hijos del `importNode`** (el propio `loader`). Para llegar a `Model.morphTargets` y `Model.skin.joints` hay que **recorrer `loader.children` recursivamente** (no hay propiedad directa; RuntimeLoader solo expone `source/status/errorString/bounds/instancing`).

### Gotchas de carga (todos verificados o citados)
- **`objectName` vacío** → direccionar por índice (§1, §5). [Qt Forum 156984](https://forum.qt.io/topic/156984/).
- **Luz obligatoria**: sin `DirectionalLight`/`PointLight`/IBL, el material PBR sale **negro**. [quick3d-asset-intro](https://doc.qt.io/qt-6/quick3d-asset-intro.html).
- **MToon → PBR/unlit**: assimp no interpreta `VRMC_materials_mtoon`; se degrada usando el `baseColor`/textura base. Se conserva el color/albedo pero **se pierde el look plano toon y el outline**. Como Vivi usa `KHR_materials_unlit`, el fallback queda bastante plano (Balsam en Shino dio `NoLighting`/flat), pero sin contorno. Para look anime con outline: `CustomMaterial` toon o pre-horneado en Blender (trabajo posterior).
- **Ejes/orientación**: VRM 0.x mira **−Z** (VRM 1.0 mira +Z). Afecta el **signo** de yaw de cabeza/ojos y del lookAt. Calibrar una vez por modelo.
- **`bounds` no fiable**: en offscreen `RuntimeLoader.bounds` volvió `(0,0,0)` → **no encuadrar solo por bounds**; posicionar la cámara a mano (§4).
- **Probar el `.glb` concreto**: assimp lanza `DeadlyImportError "Missing section meshes"` en *algunos* VRM ([VRM4U #4](https://github.com/ruyo/VRM4U/issues/4)). El nuestro (Vivi/Shino) ya cargó → riesgo bajo, pero el de-risk de §8 lo confirma.

### Fallback de producción: Balsam offline
`cp modelo.vrm modelo.glb && /usr/lib/qt6/bin/balsam --generateMipMaps modelo.glb` → genera un **Componente `.qml` + `.mesh` + texturas** con `objectName` **preservado** (huesos `J_Bip_C_Head/_Neck/_Chest/...`, morphs `Fcl_*` accesibles **por nombre**) y es **"significantly less efficient"** menos costoso en runtime que RuntimeLoader ([quick3d-asset-intro](https://doc.qt.io/qt-6/quick3d-asset-intro.html), [tool-balsam](https://doc.qt.io/qt-6/qtquick3d-tool-balsam.html)). Se instancia el Componente y se accede por `id`/`objectName`. **Recomendado para la pet final**; opcional para el prototipo.

---

## 4. Arquitectura del backend

`Model3DBackend.qml` vive en `shell/backends/` y es **un backend más**, análogo a `DragonRigV3Backend.qml`. El cableado existente en `Pet.qml` **no cambia**: drag mueve la ventana, click abre el chat, push-to-talk alimenta `voiceAmplitude`, y `headYaw/headPitch` ya se calculan desde `hyprctl cursorpos`.

### Props que hereda (idénticas a los otros backends, ver `Pet.qml`)
`Pet.qml` ya expone y pasa: `characterDir` (url file://), `scale`, `currentState` (= `root.state`), `talking`, `voiceAmplitude` (0..1), `headYaw` (−1..1), `headPitch` (−1..1). El backend nuevo consume las mismas y añade `modelPath` + los mapas de índices del manifest (`morphIdx`, `jointIdx`, `hairChains`) + parámetros de cámara (`camY`, `camZ`, `camFov`, `camPitch`).

### Wiring en `Pet.qml` (mínimo, siguiendo el patrón existente)
Hoy `Pet.qml` tiene un `avatar` con flags `isRig/isDragonRig/isDragonRigV2/isDragonRigV3` y un bloque por backend. Añadir:

```qml
// en el item "avatar":
readonly property bool isModel3d: root.petData.backend === "model3d"

// nuevo bloque, junto a DragonRigV3Backend:
Model3DBackend {
    anchors.fill: parent
    visible: avatar.isModel3d && !root.isLive2d
    characterDir: root.characterDir
    modelPath:    root.petData.model !== undefined ? root.petData.model : ""
    scale:        avatar.scaleFactor
    currentState: root.state
    talking:      root.state === "talking"
    voiceAmplitude: root.voiceAmplitude
    headYaw:      root.headYaw
    headPitch:    root.headPitch
    morphIdx:     root.petData.morphIdx  !== undefined ? root.petData.morphIdx  : ({})
    jointIdx:     root.petData.jointIdx  !== undefined ? root.petData.jointIdx  : ({})
    hairChains:   root.petData.hairChains !== undefined ? root.petData.hairChains : []
    camY:  root.petData.camY  !== undefined ? root.petData.camY  : 1.35
    camZ:  root.petData.camZ  !== undefined ? root.petData.camZ  : 1.15
    camFov: root.petData.camFov !== undefined ? root.petData.camFov : 28
    camPitch: root.petData.camPitch !== undefined ? root.petData.camPitch : -4
}
```

Y excluir el backend nuevo de los flags de visibilidad del `SpriteBackend` (que hoy es `visible: !isRig && !isDragonRig && ...`), añadiendo `&& !avatar.isModel3d`. Igual que los dragones, `Model3DBackend` **desactiva** la respiración/bob de QML que `Pet.qml` aplica a sprites de 1 frame (la vida la da el propio backend 3D).

### View3D, cámara/encuadre y máscara
- **View3D**: `renderMode: View3D.Offscreen` (único que garantiza transparencia, verificado), `SceneEnvironment.backgroundMode: Transparent`, `antialiasingMode: MSAA` (bajar a `Medium` en `gaming`). Sin SSAA. [View3D](https://doc.qt.io/qt-6/qml-qtquick3d-view3d.html).
- **Cámara**: `PerspectiveCamera` posicionada a mano hacia la parte alta del modelo (VRM en metros, cabeza ≈ y 1.5), encuadre busto-arriba: `position ≈ (0, camY≈1.35, camZ≈1.15)`, `eulerRotation.x ≈ camPitch≈−4`, `fieldOfView ≈ camFov≈28` (tele-ish → sin distorsión de gran angular). `bounds` no fiable → estos valores se exponen como props del backend y se **leen del manifest** para calibrar por modelo.
- **Luces**: 1 `DirectionalLight` principal (`eulerRotation.x:-30, y:-20`) + 1 de relleno tenue. Sin luz = negro.
- **Máscara / click-through**: el `View3D` llena el `Item` del avatar (`128*scale`) y **solo ese rect** capta input, **exactamente como hoy con SpriteBackend** → el cableado de mask/Region de `Pet.qml` **no cambia**.

---

## 5. Sistema de VIDA

Reutiliza el **mismo patrón que el sistema de vida Inochi2D/DragonRigV3** del equipo: un **tick por frame que interpola (lerp) parámetros del rig** hacia un objetivo. Aquí los "parámetros" son **pesos de morph** (cara) y **rotaciones de joints** (huesos). Todo se escribe en **una sola función `_composePose()`** por tick (evita que un handler pise a otro).

**Regla no negociable para Claude/devs:** aunque el modelo sea 3D real, si animas cabeza, ojos, brazos, pelo y torso como señales separadas se ve como una marioneta rota. El backend actual usa un controlador axial: primero calcula intención global (`lookYaw/lookPitch`, respiración, sway, estado, voz), luego la reparte por `hips -> spine -> chest -> upperChest -> neck -> head`; los brazos heredan micro-movimiento del torso; pelo/busto reaccionan con retraso a la misma velocidad suavizada. Los tunings van en `manifest.model3d.motion`, no en timers independientes.

### Direccionamiento: POR ÍNDICE (RuntimeLoader)
Como `objectName` está vacío, tras `onStatusChanged == Success` se recorre `loader.children` **una vez**, se cachea: (a) el `Model` con **más `morphTargets`** = la **cara** (`_faceModel`, 41–410 morphs), (b) `Model.skin` (`_skin`, `.joints` = lista de Nodes). Los índices lógicos vienen del **manifest** (obtenidos con un dump una vez).

### Mapa concreto de blendshapes (Vivi, VRM 0.0 — índices reales del probe sobre `Face.baked`)
De `blendShapeMaster` → índice de morph target:

| Función | Preset VRM 0.x | Nombre real morph | Índice |
|---|---|---|---|
| **Lip-sync** | `a` | `Fcl_MTH_A` | **29** |
| | `i` | `Fcl_MTH_I` | **30** |
| | `u` | `Fcl_MTH_U` | **31** |
| | `e` | `Fcl_MTH_E` | **32** |
| | `o` | `Fcl_MTH_O` | **33** |
| **Parpadeo** | `blink` | `Fcl_EYE_Close` | **12** |
| | `blink_l` | `Fcl_EYE_Close_L` | **14** |
| | `blink_r` | `Fcl_EYE_Close_R` | **13** |
| **Expresión** | `angry` | `Fcl_ALL_Angry` | **0** |
| | `fun` | `Fcl_ALL_Fun` | **1** |
| | `joy` | `Fcl_ALL_Joy` | **2** |
| | `sorrow` | `Fcl_ALL_Sorrow` | **3** |
| | `surprised` | `Fcl_ALL_Surprised` | **4** |

> Nota de versión: este VRM 0.0 **no** tiene los blendshapes `lookUp/Down/Left/Right` (esos están en AliciaSolid). Aquí la **mirada se hace por rotación de huesos de ojo/cabeza**, que además es más preciso para seguir el cursor. VRM 1.0 usaría camelCase (`aa/ih/ou/ee/oh`, `blink`, `happy/angry/sad/relaxed/surprised`) — mantener un **alias map** en el manifest para ser agnóstico de versión. Refs: [expressions VRM1](https://github.com/vrm-c/vrm-specification/blob/master/specification/VRMC_vrm-1.0/expressions.md), [VRoid blendshapes](https://github.com/hinzka/52blendshapes-for-VRoid-face).

### Mapa de huesos humanoides (Vivi tiene los 54; los relevantes para vida)
`head`, `neck`, `chest`, `upperChest`, `spine`, `leftEye`, `rightEye`, `hips`, `leftShoulder/rightShoulder`, `leftUpperArm/...`. Sus **índices** dentro de `_skin.joints` se vuelcan una vez al manifest (`jointIdx`). Refs: [humanoid VRM1](https://github.com/vrm-c/vrm-specification/blob/master/specification/VRMC_vrm-1.0/humanoid.md).

### Comportamientos

- **PARPADEO** — Timer esporádico (cada ~2.6–5.4 s) dispara una animación de `_blink` 0→1→0 en ~90 ms; `_composePose` escribe `setMorph("blink", _blink)`. En `sleeping`: `blink` fijo a 1.0 (ojos cerrados), Timer parado.

- **RESPIRACIÓN** — `SequentialAnimation` sinusoidal (`InOutSine`) mueve `_breath` (−1..1); `_composePose` la reparte por `hips/spine/chest/upperChest/head` y añade micro-`position.y` al `RuntimeLoader` (`rootBob`). `_breathDur`: ~2000 ms idle, ~1500 ms gaming/music, ~3200 ms sleeping (respiración lenta y profunda).

- **MIRADA / CUERPO COMPLETO** (`headYaw/headPitch` −1..1, ya siguen el cursor) — suavizar con `_lookYaw/_lookPitch`, derivar `lookYawDeg/lookPitchDeg`, y distribuir por el esqueleto. El torso sigue con menor peso (`bodyFollow`) y retraso (`bodyLag`); cuello/cabeza completan lo que el torso ya empezó; ojos solo corrigen fino.
  - `hips/spine/chest/upperChest`: reciben fracciones de `_bodyYaw/_bodyPitch/_bodyRoll`.
  - `neck/head`: mezclan mirada, pitch por estado, respiración y tilt.
  - `eyeL/eyeR`: micro-seguimiento extra si existen los huesos de ojo — Vivi los tiene.
  - **Signo**: VRM 0.x mira −Z; si mira al lado contrario, negar `headYaw`. Clamp para que no sobre-rote en las esquinas de pantalla. `Node.eulerRotation` es vector3d orden **ZXY** ([Node](https://doc.qt.io/qt-6/qml-qtquick3d-node.html)). `Node` **no** tiene método `lookAt` — se rota el hueso a mano.

- **LIP-SYNC** (`voiceAmplitude` 0..1) — suavizar primero (`ampSmoothed += (raw-ampSmoothed)*0.3` anti-chatter), luego `setMorph("aa", clamp(ampSmoothed,0,1)*0.85)` (el `*0.85` evita que la boca se abra del todo), resto de visemas a 0. Solo cuando `talking` o `voiceAmplitude>0`. Para más vida: elegir pseudo-vocal por bandas de energía (baja→`ou`, media→`ee`, alta→`aa`) e interpolar entre las dos visemas vecinas.

- **IDLE / POSES POR ESTADO** — mapear `state` a expresión + movimiento procedural, con blend suave (lerp de pesos al cambiar de estado):
  - `idle` → neutral + auto-blink cada 3–6 s + respiración.
  - `typing`/`browsing` → neutral, blink normal, ligera inclinación de cabeza (`stateHeadPitch≈8`).
  - `gaming` → `fun`/`surprised` leve, idle más rápido, AA `Medium` para ceder GPU.
  - `music` → head-bob suave sincronizado a un seno.
  - `watching` → cabeza levemente arriba (`stateHeadPitch≈-6`).
  - `talking` → lip-sync activo + `joy`/`fun` base ~0.2.
  - `sleeping` → `blink=1.0`, `relaxed`≈0.3, respiración lenta, cabeza abajo, mirada y sway desactivados.

- **BRAZOS** — no dejarlos congelados ni animarlos aparte. En reposo leen `armPose` del manifest y suman respiración, sway y roll del torso. No levantar brazos para saludar sin calibrar ejes por modelo: en Victoria/Vivi el intento de wave terminaba como mano detrás de la nuca. El saludo actual es visual/facial: mirada, sonrisa y ladeo.

- **MOVIMIENTO SECUNDARIO (spring-bone aproximado)** — Qt **no ejecuta** `VRMC_springBone`. Las cadenas de pelo/falda son joints hijos en `skin.joints` (por eso hay 148–152). Se listan sus índices raíz→punta en `hairChains` (manifest) y se les mete un **seno con desfase creciente por segmento** + una **respuesta a la velocidad suavizada del giro del cuerpo** (`_yawVel`, calculada dentro de `_composePose()`) para que "coleen". La punta oscila más (`amp` crece con la profundidad). No es Verlet real pero da sensación de inercia. En `sleeping`: baja amplitud y frena `_sway`. **Busto**: `J_Sec_L/R_Bust1/Bust2` existen — mismo tratamiento (seno suave + respuesta a arrastre), amplitud discreta y SFW. Refs: [springBone](https://github.com/vrm-c/vrm-specification/blob/master/specification/VRMC_springBone-1.0/README.md).

### API verificada (snippets núcleo)
```qml
function setMorph(name, w) {                       // escritura de morph por índice — VERIFICADA
    if (!backend._faceModel) return;
    var i = backend.morphIdx[name]; if (i === undefined || i < 0) return;
    var mts = backend._faceModel.morphTargets;
    if (mts && i < mts.length) mts[i].weight = Math.max(0, Math.min(1, w));
}
function rotJoint(name, x, y, z) {                  // rotación de joint por índice — VERIFICADA
    var i = backend.jointIdx[name]; if (i === undefined || i < 0) return;
    var js = backend._skin ? backend._skin.joints : null;
    if (js && i < js.length) js[i].eulerRotation = Qt.vector3d(x, y, z);
}
```
El `_composePose()` completo (controlador axial + look-at + respiración + brazos + pelo + parpadeo/lip-sync en un solo punto de escritura por joint por tick) sigue el backend real. Tick de vida a **~30 fps** (Timer 33 ms, 66 ms en sleeping); las `SequentialAnimation`/`NumberAnimation` solo mueven props `_breath/_sway/_blink/_tilt/_idleJoy`.

---

## 6. Manifest del personaje

Nuevo skin `characters/waifu_vivi/` con `waifu_vivi.json`. Mismo formato JSON que los demás (ver `ajolote_kawaii.json` / `dragon_inframundo_v3.json`), pero `backend: "model3d"`:

```json
{
  "name": "Vivi",
  "backend": "model3d",
  "scale": 2.4,
  "defaultState": "idle",
  "model": "model/vivi.glb",
  "vrmVersion": "0.x",
  "yawSign": 1,
  "cam":  { "camY": 1.35, "camZ": 1.15, "camFov": 28, "camPitch": -4 },
  "motion": {
    "lookYaw": 24,
    "lookPitch": 16,
    "bodyFollow": 0.34,
    "bodyLag": 0.11,
    "idleSway": 0.9,
    "breathTorso": 1.1,
    "armLife": 0.85,
    "rootBob": 0.005
  },
  "morphIdx": {
    "blink": 12, "blink_l": 14, "blink_r": 13,
    "aa": 29, "ih": 30, "ou": 31, "ee": 32, "oh": 33,
    "angry": 0, "fun": 1, "joy": 2, "sorrow": 3, "surprised": 4
  },
  "jointIdx": {
    "head": -1, "neck": -1, "chest": -1, "upperChest": -1,
    "spine": -1, "eyeL": -1, "eyeR": -1
  },
  "hairChains": [],
  "voice": { "tts": "piper", "voice": "es_AR-daniela-high", "fx": "cute" },
  "persona": "Eres Vivi, una waifu anime kawaii y coqueta pero educada que vive en tu pantalla. Hablas espanol, calida y breve (1-2 frases). SFW."
}
```

- Los `morphIdx` ya están **resueltos** (índices reales del probe). Los `jointIdx` y `hairChains` van a `-1`/`[]` hasta el **dump** del de-risk (§8) que los llena leyendo `_skin.joints` del modelo cargado.
- **`cam*`** se calibran por modelo (VRoid vs otro exportador cambia escala/altura).
- Índice en `skins.json` (formato `{id, label}` como los demás):
```json
{ "id": "waifu_vivi", "label": "Vivi — Waifu Anime 3D 🌸" }
```
- **Nota de campo**: `Pet.qml` pasa `modelPath` desde `root.petData.model` (el sketch usa `petData.model`), así que el manifest usa la clave `model`. Mantener consistencia con el nombre elegido en el wiring de §4.

---

## 7. Riesgos y fallbacks

| Riesgo | Estado | Mitigación / fallback |
|---|---|---|
| `objectName` vacío (RuntimeLoader no propaga nombres) | **Confirmado** (probe: 0/637) | Direccionar por **índice** (mapas en manifest). Para producción por nombre: **Balsam offline** (581 objectName, ya validado). |
| **Morph/joint no drivables** | **Refutado** — son escribibles (verificado leyendo de vuelta) | N/A. Si alguna vez fallara: fallback mínimo = animar solo **cámara + transform/scale del nodo raíz** (respiración por micro-scale Y, "mirada" girando el importNode entero) → da vida sin parpadeo/lip-sync. |
| assimp `DeadlyImportError` en *algunos* VRM | Posible; **el nuestro carga bien** | Probar el `.glb` concreto (de-risk §8). Si falla: limpiar/re-exportar con UniVRM / gltf-transform / VRM-Addon-for-Blender, o abrir en Blender y re-exportar glTF2 estándar. |
| **MToon → PBR/unlit**, outline perdido | Confirmado | Aceptar look plano para v1 (Vivi es `unlit`, queda decente). Look toon con contorno: `CustomMaterial` toon o pre-horneado en Blender (posterior). |
| Escena **negra** (PBR sin luz) | Confirmado | Siempre `DirectionalLight`(s)/IBL en el View3D. |
| Signo/escala de ejes (VRM0 −Z) | Conocido | `yawSign` en manifest; calibrar una vez. |
| **SpringBones** no ejecutados por Qt | Confirmado | Aproximar por seno+desfase+respuesta a arrastre (§5). Verlet real = posterior. |
| **Rendimiento NVIDIA/Wayland** | Manejable | `Offscreen`+MSAA moderado; **si nada anima, Qt no repinta** → gatear `running:` de animaciones por estado, tick a 30 fps, tocar solo huesos necesarios (no los 148), bajar AA en gaming, frenar todo en sleeping. No hay API de cap de fps en View3D. |
| **VRAM 8GB** (¿convive con llama-server?) | A validar | El modelo VRM (150 joints, 410 morphs) es ligero en GPU al encuadre busto; **no** es como el pipeline SDXL. A diferencia del **arte** (que sí exige parar la pet), aquí la pet 3D corre continua. Riesgo real solo si el juego + llama-server + View3D saturan: mitigar bajando AA en gaming y con el auto-unload por idle de llama-server (ya existe, `idle_unload_secs=180`). **Medir** en el de-risk; si hay presión, exponer un toggle de calidad. |
| `bounds=(0,0,0)` offscreen | Confirmado | No encuadrar por bounds; cámara a mano vía manifest. |

---

## 8. Plan paso a paso (esta sesión)

Checklist ordenada, empezando por el **de-risk empírico** con el VRM **ya descargado** por el probe (`/tmp/.../scratchpad/vrm_test/waifu.vrm`, 17.25 MB, CC0 confirmado):

1. **De-risk de carga real** — crear un `.qml` mínimo (View3D + RuntimeLoader + luz + cámara) apuntando por `file://` absoluto al `waifu.vrm` (copiado a `.glb`). Correr con `quickshell -p` o probe offscreen. Confirmar: `status==Success`, `errorString` vacío, y que **se ve** la waifu transparente sobre el escritorio (no negra → validar luz). Ajustar `camY/camZ/camFov/camPitch` hasta encuadre busto-arriba.

2. **Dump de índices** — recorrer `loader.children`, imprimir por cada `Model`: `morphTargets.length` (identificar la cara) y, del `_skin`, listar `joints` con su índice. Como `objectName` está vacío, identificar `head/neck/chest/upperChest/spine/eyeL/eyeR` por **inspección/heurística** (posición Y relativa, jerarquía) y **volcar los índices al manifest** (`jointIdx`). Volcar también las cadenas de pelo/busto → `hairChains`. (Los `morphIdx` ya están resueltos, §5.)

3. **Escribir `Model3DBackend.qml`** en `shell/backends/` con la API del §4 y el `_composePose()` del §5: `_scan`, `setMorph`, `rotJoint`, tick 30 fps, animaciones `_breath/_sway/_blink` gateadas por estado, `onModelUrlChanged` recarga limpia.

4. **Crear el skin** `characters/waifu_vivi/` — copiar `waifu.vrm` → `model/vivi.glb`, escribir `waifu_vivi.json` (§6) con los índices del dump, añadir entrada a `skins.json`.

5. **Wire en `Pet.qml`** — flag `avatar.isModel3d`, bloque `Model3DBackend` (§4), excluirlo de la visibilidad del `SpriteBackend`, y del bob/respiración de sprites de 1 frame.

6. **Probar la vida** — `systemctl --user restart miiamia`, seleccionar Vivi desde el menú. Verificar: parpadeo, respiración, **mirada sigue el cursor** (calibrar signo `yawSign` si mira al revés), lip-sync al hablar (PTT), poses por estado (typing/gaming/sleeping), sway de pelo al arrastrar.

7. **Medir rendimiento/VRAM** — con `journalctl --user -u miiamia -f` + `nvidia-smi`: FPS, uso GPU/VRAM en idle vs talking vs gaming, y **convivencia con llama-server** activo. Ajustar AA/tick por estado; si hay presión de VRAM, decidir toggle de calidad.

8. **(Posterior, no bloquea v1) Balsam para producción** — `cp vivi.vrm vivi.glb && /usr/lib/qt6/bin/balsam vivi.glb`, migrar a acceso por `objectName` (huesos `J_Bip_*` / morphs `Fcl_*`) para robustez y eficiencia, y explorar `CustomMaterial` toon + Verlet real de spring-bones para el look/vida definitivos.

---

### Fuentes clave
Qt: [RuntimeLoader](https://doc.qt.io/qt-6/qml-qtquick3d-assetutils-runtimeloader.html) · [Model](https://doc.qt.io/qt-6/qml-qtquick3d-model.html) · [MorphTarget](https://doc.qt.io/qt-6/qml-qtquick3d-morphtarget.html) · [Skin](https://doc.qt.io/qt-6/qml-qtquick3d-skin.html) · [Node](https://doc.qt.io/qt-6/qml-qtquick3d-node.html) · [View3D](https://doc.qt.io/qt-6/qml-qtquick3d-view3d.html) · [vertex-skinning](https://doc.qt.io/qt-6/quick3d-vertex-skinning.html) · [Balsam](https://doc.qt.io/qt-6/qtquick3d-tool-balsam.html) · [bug objectName #156984](https://forum.qt.io/topic/156984/). VRM/assimp: [spec VRM 0.0](https://github.com/vrm-c/vrm-specification/blob/master/specification/0.0/README.md) · [expressions 1.0](https://github.com/vrm-c/vrm-specification/blob/master/specification/VRMC_vrm-1.0/expressions.md) · [humanoid 1.0](https://github.com/vrm-c/vrm-specification/blob/master/specification/VRMC_vrm-1.0/humanoid.md) · [springBone](https://github.com/vrm-c/vrm-specification/blob/master/specification/VRMC_springBone-1.0/README.md) · [glTF2Importer.cpp](https://github.com/assimp/assimp/blob/master/code/AssetLib/glTF2/glTF2Importer.cpp) · [VRM4U #4](https://github.com/ruyo/VRM4U/issues/4). Licencia: [madjin/vrm-samples](https://github.com/madjin/vrm-samples) · [VRoid FAQ samples](https://vroid.pixiv.help/hc/en-us/articles/4402614652569) · [OpenGameArt CC0 VRoid](https://opengameart.org/content/vroid-studio-cc0-models).

Verificación empírica local (Qt 6.11.1, Quickshell 0.3.0, assimp 6.0.5): VRM cargado por RuntimeLoader → cara `morphTargets=410`, `skin.joints=148–152`, `skeleton=null`; escritura de `morphTargets[i].weight` y `joints[i].eulerRotation` OK (releída); `objectName=""` en 637/637 nodos; Balsam (`/usr/lib/qt6/bin/balsam`) convirtió a `.qml` con 581 `objectName`. Asset embarcable: `Vivi.vrm` CC0, 17.25 MB, GLB íntegro, texturas embebidas.
