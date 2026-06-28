// SpriteBackend.qml — render del avatar por sprite sheets (backend PRIMARIO de miiamia).
//
// Cubre TODOS los tipos de personaje (dragones, criaturas, humanoides) sin overhead:
// AnimatedSprite es nativo de Qt Quick sobre Wayland+NVIDIA, sin proceso extra.
// (El WebBackend para Live2D/VRM via Qt WebEngine quedó descartado por la verificación:
//  PR de WebView en Quickshell sin mergear + transparencia rota en Wayland+NVIDIA.)
//
// Lee la animacion activa desde `animations[currentState]` (cae a `idle` si falta).
import QtQuick

Item {
    id: backend

    // --- API que consume Pet.qml ---
    required property url characterDir          // file:// del directorio del personaje
    required property var animations            // objeto { estado: {source, frameCount, frameWidth, frameHeight, fps} }
    property string currentState: "idle"
    property real scale: 2.0

    // Animacion resuelta (con fallback a idle)
    readonly property var _anim: animations[currentState] !== undefined
        ? animations[currentState]
        : animations["idle"]

    implicitWidth: (_anim ? _anim.frameWidth : 128) * scale
    implicitHeight: (_anim ? _anim.frameHeight : 128) * scale

    AnimatedSprite {
        id: sprite
        anchors.fill: parent
        visible: backend._anim !== undefined

        source: backend._anim ? backend.characterDir + backend._anim.source : ""
        frameCount: backend._anim ? backend._anim.frameCount : 1
        frameWidth: backend._anim ? backend._anim.frameWidth : 128
        frameHeight: backend._anim ? backend._anim.frameHeight : 128
        frameDuration: backend._anim ? Math.round(1000 / backend._anim.fps) : 125

        loops: AnimatedSprite.Infinite
        interpolate: false   // pixel-art crisp; true = transicion suave entre frames
        running: true
    }
}
