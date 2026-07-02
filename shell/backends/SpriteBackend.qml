// SpriteBackend.qml — render del avatar por sprite sheets (backend PRIMARIO de miiamia).
//
// Cubre TODOS los tipos de personaje (dragones, criaturas, humanoides) sin overhead:
// AnimatedSprite es nativo de Qt Quick sobre Wayland+NVIDIA, sin proceso extra.
// (El WebBackend para Live2D/VRM via Qt WebEngine quedó descartado por la verificación:
//  PR de WebView en Quickshell sin mergear + transparencia rota en Wayland+NVIDIA.)
//
// Lee la animacion activa desde `animations[currentState]` (cae a `idle` si falta).
// Vida (skins de 1 ilustracion AI): respiracion + bob + PARPADEO (crossfade idle<->blink),
// sin separar capas -> funciona en cualquier skin (incluidas las "bola" sin cuello).
// REACCION por actividad: el ritmo de bob/respiracion cambia con el estado (musica rebota y
// "baila", pelis = calmado, dormir = lento) sin cambiar el arte de la criatura.
import QtQuick

Item {
    id: backend

    // --- API que consume Pet.qml ---
    required property url characterDir          // file:// del directorio del personaje
    required property var animations            // objeto { estado: {source, frameCount, frameWidth, frameHeight, fps} }
    property string currentState: "idle"
    property real scale: 2.0
    property url blinkSource: ""                // ojos cerrados (sprites/blink.png). "" = sin parpadeo.
    property bool talking: false
    property real voiceAmplitude: 0.0            // 0..1, usado como pulso corporal cuando habla.

    // Animacion resuelta (con fallback a idle)
    readonly property var _anim: animations[currentState] !== undefined
        ? animations[currentState]
        : animations["idle"]

    // Skins de 1 sola ilustracion (arte AI anime): la vida la da el QML (respira/flota/parpadea),
    // no los frames. Los procedurales (frameCount>1) se animan por sprite sheet.
    readonly property bool _single: backend._anim ? (backend._anim.frameCount <= 1) : false
    // El parpadeo (overlay blink.png) es la pose IDLE con ojos cerrados -> solo aplica cuando se
    // muestra la pose idle. En poses de acción (typing/gaming/...) la expresión la da la propia pose.
    readonly property bool _canBlink: backend._single && backend.blinkSource != ""
        && backend._anim !== undefined && backend.animations["idle"] !== undefined
        && backend._anim.source === backend.animations["idle"].source

    readonly property string _poseSourceKey: (backend._single && backend._anim)
        ? ("" + backend.characterDir + backend._anim.source)
        : ""
    property string _frontPoseSource: ""
    property string _backPoseSource: ""
    property real _microX: 0
    property real _microRot: 0
    property real _squash: 0
    property real _typingTap: 0
    property int _typingBeat: 0

    function _syncPoseSource() {
        if (!backend._single || backend._poseSourceKey === "")
            return;

        if (backend._frontPoseSource === "") {
            backend._frontPoseSource = backend._poseSourceKey;
            poseCurrent.opacity = 1;
            posePrevious.opacity = 0;
            return;
        }

        if (backend._frontPoseSource === backend._poseSourceKey)
            return;

        backend._backPoseSource = backend._frontPoseSource;
        backend._frontPoseSource = backend._poseSourceKey;
        poseCurrent.opacity = 0;
        posePrevious.opacity = 1;
        poseCrossfade.restart();
    }

    Component.onCompleted: _syncPoseSource()
    on_PoseSourceKeyChanged: _syncPoseSource()

    // Al cambiar de SKIN en vivo (no solo de estado), el front/back y el crossfade pueden quedar a
    // medias y mostrarse una "mancha" en vez de la nueva pet (p.ej. al pasar del dragón al ajolote).
    // Forzamos un reset limpio a la pose correcta una vez que todos los bindings se asentaron.
    onCharacterDirChanged: Qt.callLater(_resetPoseForSkin)
    function _resetPoseForSkin() {
        if (poseCrossfade.running)
            poseCrossfade.stop();
        backend._backPoseSource = "";
        backend._frontPoseSource = backend._poseSourceKey;
        posePrevious.opacity = 0;
        poseCurrent.opacity = 1;
    }

    // Ritmo de la vida segun la actividad (reaccion sin cambiar el arte):
    //  musica = rapido y reboton ("bailando"); juego = animado; pelis = tranquilo; dormir = lento.
    readonly property int _bobDur: {
        switch (backend.currentState) {
        case "music":    return 360;
        case "typing":   return 720;
        case "gaming":   return 520;
        case "watching": return 2200;
        case "sleeping": return 2600;
        default:         return 1500;   // typing / browsing / idle
        }
    }
    readonly property real _bobAmp: {
        switch (backend.currentState) {
        case "music":    return 11;
        case "gaming":   return 9;
        case "talking":  return 8;
        case "typing":   return 3;
        case "watching": return 4;
        case "sleeping": return 3;
        default:         return 7;
        }
    }
    readonly property real _squashAmp: {
        switch (backend.currentState) {
        case "music":    return 0.032;
        case "gaming":   return 0.025;
        case "talking":  return 0.022;
        case "typing":   return 0.010;
        case "sleeping": return 0.008;
        case "watching": return 0.010;
        default:         return 0.016;
        }
    }
    readonly property real _voicePulse: Math.max(0, Math.min(1, backend.voiceAmplitude))

    // Tamano en pantalla normalizado a una base de 128px: asi un frame anime de 256px
    // se ve igual de grande que uno procedural de 128px para un mismo `scale`.
    implicitWidth: 128 * scale
    implicitHeight: 128 * scale

    // Grupo "vida": sprite + overlay de parpadeo comparten bob (Translate), respiracion (scale)
    // y un leve balanceo de baile (Rotation), asi el overlay se mueve EXACTO igual que el cuerpo.
    Item {
        id: lifeGroup
        anchors.fill: parent
        transformOrigin: Item.Bottom    // respira/flota "parado", anclado a los pies
        transform: [
            Translate { id: bobT },
            Translate {
                id: microT
                x: backend._microX
                Behavior on x { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }
            },
            Rotation {
                id: microRot
                origin.x: lifeGroup.width / 2
                origin.y: lifeGroup.height
                angle: backend._microRot
                Behavior on angle { NumberAnimation { duration: 620; easing.type: Easing.OutCubic } }
            },
            Rotation { id: danceRot; origin.x: lifeGroup.width / 2; origin.y: lifeGroup.height; angle: 0 },
            Scale {
                id: bodySquash
                origin.x: lifeGroup.width / 2
                origin.y: lifeGroup.height
                xScale: 1.0 + backend._squash + (backend.talking ? backend._voicePulse * 0.018 : 0)
                yScale: 1.0 - backend._squash * 0.72 + (backend.talking ? backend._voicePulse * 0.024 : 0)
                Behavior on xScale { NumberAnimation { duration: 48; easing.type: Easing.OutQuad } }
                Behavior on yScale { NumberAnimation { duration: 48; easing.type: Easing.OutQuad } }
            }
        ]

        // Pose anterior durante cambios de estado. El crossfade evita que dos ilustraciones IA
        // parezcan un teletransporte cuando ComfyUI cambia detalles de silueta/volumen.
        Image {
            id: posePrevious
            anchors.fill: parent
            visible: backend._single && backend._backPoseSource !== ""
            source: backend._backPoseSource
            fillMode: Image.PreserveAspectFit
            smooth: true
            cache: false
            opacity: 0
        }
        // Pose activa de 1 ilustracion (arte AI por estado): Image recarga de forma FIABLE al cambiar
        // source (AnimatedSprite NO refresca al reasignar source -> se quedaba pegado en idle).
        Image {
            id: poseCurrent
            anchors.fill: parent
            visible: backend._single && backend._frontPoseSource !== ""
            source: backend._frontPoseSource
            fillMode: Image.PreserveAspectFit
            smooth: true
            cache: false
            opacity: 1
        }
        // Sprite sheets procedurales (frameCount>1): animacion por frames.
        AnimatedSprite {
            id: sprite
            anchors.fill: parent
            visible: backend._anim !== undefined && !backend._single
            smooth: true
            source: (backend._anim && !backend._single) ? backend.characterDir + backend._anim.source : ""
            frameCount: backend._anim ? backend._anim.frameCount : 1
            frameWidth: backend._anim ? backend._anim.frameWidth : 128
            frameHeight: backend._anim ? backend._anim.frameHeight : 128
            frameDuration: backend._anim ? Math.round(1000 / (backend._anim.fps || 8)) : 125
            loops: AnimatedSprite.Infinite
            interpolate: true
            running: visible
        }

        // Overlay ojos-cerrados (parpadeo): encima del sprite, normalmente invisible.
        Image {
            id: blinkImg
            anchors.fill: parent
            visible: backend._canBlink
            source: backend._canBlink ? backend.blinkSource : ""
            fillMode: Image.PreserveAspectFit
            smooth: true; mipmap: true
            opacity: backend._canBlink && backend.currentState === "sleeping" ? 1 : 0  // dormido = ojos cerrados fijos
        }

        Item {
            id: typingPad
            visible: backend._single && backend.currentState === "typing"
            opacity: visible ? 1 : 0
            width: parent.width * 0.56
            height: parent.height * 0.17
            x: parent.width * 0.5 - width / 2
            y: parent.height * 0.76
            transform: [
                Rotation {
                    origin.x: typingPad.width / 2
                    origin.y: typingPad.height / 2
                    angle: 180
                    axis { x: 1; y: 0; z: 0 }
                }
            ]

            Rectangle {
                x: parent.width * 0.02
                y: parent.height * 0.04
                width: parent.width * 0.96
                height: parent.height * 0.88
                radius: Math.max(4, height * 0.16)
                color: "#1d2630"
                opacity: 0.88
                border.color: "#d5f3ff"
                border.width: Math.max(1, parent.width * 0.012)
            }
            Rectangle {
                width: parent.width * 0.44
                height: parent.height * 0.095
                radius: height * 0.4
                x: parent.width * 0.28
                y: parent.height * 0.20
                color: "#e7f5fb"
                opacity: 0.34
            }
            Repeater {
                model: 30
                Rectangle {
                    readonly property int row: Math.floor(index / 10)
                    readonly property int col: index % 10
                    readonly property real rowInset: row === 0 ? 0.095 : row === 1 ? 0.060 : 0.025
                    width: typingPad.width * (row === 0 ? 0.068 : row === 1 ? 0.074 : 0.080)
                    height: typingPad.height * (row === 0 ? 0.112 : row === 1 ? 0.128 : 0.145)
                    radius: Math.max(1, height * 0.22)
                    x: typingPad.width * (rowInset + col * 0.083)
                    y: typingPad.height * (0.58 - row * 0.18)
                    color: "#eef8ff"
                    opacity: 0.22 + row * 0.035
                }
            }
            Repeater {
                model: 4
                Rectangle {
                    readonly property int keyIndex: (backend._typingBeat * 7 + index * 11) % 30
                    readonly property int row: Math.floor(keyIndex / 10)
                    readonly property int col: keyIndex % 10
                    readonly property real rowInset: row === 0 ? 0.095 : row === 1 ? 0.060 : 0.025
                    readonly property bool active: index < 2 ? backend._typingTap >= 0 : backend._typingTap <= 0
                    width: typingPad.width * (row === 0 ? 0.070 : row === 1 ? 0.076 : 0.082)
                    height: typingPad.height * (row === 0 ? 0.118 : row === 1 ? 0.134 : 0.152)
                    radius: Math.max(1, height * 0.22)
                    x: typingPad.width * (rowInset + col * 0.083)
                    y: typingPad.height * (0.58 - row * 0.18 + (active ? Math.abs(backend._typingTap) * 0.035 : 0))
                    color: index % 2 === 0 ? "#ffd6df" : "#bdf4f0"
                    opacity: active ? 0.44 + Math.abs(backend._typingTap) * 0.28 : 0.16
                    Behavior on opacity { NumberAnimation { duration: 55 } }
                }
            }
        }
    }

    // Bob (sube/baja) y respiracion (escala sutil): solo skins de 1 ilustracion. Ritmo = estado.
    SequentialAnimation {
        running: backend._single
        loops: Animation.Infinite
        NumberAnimation { target: bobT; property: "y"; from: 0; to: -backend._bobAmp; duration: backend._bobDur; easing.type: Easing.InOutSine }
        NumberAnimation { target: bobT; property: "y"; from: -backend._bobAmp; to: 0; duration: backend._bobDur; easing.type: Easing.InOutSine }
    }
    SequentialAnimation {
        running: backend._single
        loops: Animation.Infinite
        NumberAnimation { target: lifeGroup; property: "scale"; from: 1.0; to: 1.03; duration: backend._bobDur; easing.type: Easing.InOutSine }
        NumberAnimation { target: lifeGroup; property: "scale"; from: 1.03; to: 1.0; duration: backend._bobDur; easing.type: Easing.InOutSine }
    }
    SequentialAnimation {
        running: backend._single
        loops: Animation.Infinite
        NumberAnimation { target: backend; property: "_squash"; from: -backend._squashAmp * 0.35; to: backend._squashAmp; duration: backend._bobDur; easing.type: Easing.InOutSine }
        NumberAnimation { target: backend; property: "_squash"; from: backend._squashAmp; to: -backend._squashAmp * 0.35; duration: backend._bobDur; easing.type: Easing.InOutSine }
    }

    SequentialAnimation {
        id: poseCrossfade
        NumberAnimation { target: poseCurrent; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
        ScriptAction { script: { posePrevious.opacity = 0; backend._backPoseSource = ""; } }
    }

    Timer {
        id: microMotion
        running: backend._single && backend.currentState !== "sleeping"
        interval: 1700 + Math.round(Math.random() * 2600)
        repeat: true
        onTriggered: {
            var mood = backend.currentState === "watching" ? 0.45
                     : backend.currentState === "typing" ? 0.35
                     : backend.currentState === "music" ? 1.45
                     : backend.currentState === "gaming" ? 1.2
                     : 1.0;
            backend._microX = (Math.random() * 2 - 1) * 2.2 * mood;
            backend._microRot = (Math.random() * 2 - 1) * 1.8 * mood;
            interval = 1600 + Math.round(Math.random() * 3200);
        }
        onRunningChanged: if (!running) { backend._microX = 0; backend._microRot = 0; }
    }

    SequentialAnimation {
        running: backend._single && backend.currentState === "typing"
        loops: Animation.Infinite
        ScriptAction { script: backend._typingBeat = (backend._typingBeat + 1) % 30 }
        NumberAnimation { target: backend; property: "_typingTap"; from: 0; to: 1; duration: 90; easing.type: Easing.InQuad }
        NumberAnimation { target: backend; property: "_typingTap"; from: 1; to: -1; duration: 120; easing.type: Easing.InOutQuad }
        ScriptAction { script: backend._typingBeat = (backend._typingBeat + 3) % 30 }
        NumberAnimation { target: backend; property: "_typingTap"; from: -1; to: 0.55; duration: 100; easing.type: Easing.InOutQuad }
        NumberAnimation { target: backend; property: "_typingTap"; from: 0.55; to: 0; duration: 130; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 180 }
        onRunningChanged: if (!running) backend._typingTap = 0
    }

    // Balanceo "baile" cuando hay musica (leve tilt izq/der). Fuera de musica, angulo 0.
    SequentialAnimation {
        id: danceAnim
        running: backend._single && backend.currentState === "music"
        loops: Animation.Infinite
        NumberAnimation { target: danceRot; property: "angle"; from: -6; to: 6; duration: 360; easing.type: Easing.InOutSine }
        NumberAnimation { target: danceRot; property: "angle"; from: 6; to: -6; duration: 360; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) danceRot.angle = 0
    }

    // Parpadeo: crossfade abierta -> cerrada -> abierta a intervalos aleatorios.
    // No mientras duerme (ahi los ojos ya estan cerrados fijos por el binding de opacity de arriba).
    Timer {
        running: backend._canBlink && backend.currentState !== "sleeping"
        interval: 2800 + Math.round(Math.random() * 2600)
        repeat: true
        onTriggered: {
            blinkAnim.restart();
            interval = 1800 + Math.round(Math.random() * 4200);
        }
    }
    SequentialAnimation {
        id: blinkAnim
        NumberAnimation { target: blinkImg; property: "opacity"; to: 1; duration: 70; easing.type: Easing.InQuad }
        PauseAnimation { duration: 75 }
        NumberAnimation { target: blinkImg; property: "opacity"; to: 0; duration: 110; easing.type: Easing.OutQuad }
    }
}
