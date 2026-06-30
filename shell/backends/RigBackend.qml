// RigBackend.qml — rig 2D por huesos (estilo Live2D ligero). Camino de "calidad suprema".
//
// Capas separadas con SAM (gen_rig.py): cuerpo + cabeza (ojos abiertos / cerrados).
//   - cuerpo: respira (escala anclada a los pies)
//   - cabeza: rota en el CUELLO siguiendo el cursor (head-tracking) + bob + sway suave
//   - parpadeo: cross-fade abierta<->cerrada (NO salto)
// headYaw/headPitch (-1..1) los setea Pet.qml desde la posición global del cursor.
import QtQuick

Item {
    id: backend

    required property url characterDir
    property var rig: null                 // {body, head_open, head_closed, neckY, size}
    property real scale: 2.0
    property string currentState: "idle"
    property real headYaw: 0               // -1 (izq) .. 1 (der)
    property real headPitch: 0             // -1 (arriba) .. 1 (abajo)
    property bool talking: false

    readonly property bool _ok: rig !== null && rig !== undefined
    implicitWidth: 128 * scale
    implicitHeight: 128 * scale

    // bob vertical compartido (respiración de la cabeza)
    property real _bobY: 0
    SequentialAnimation on _bobY {
        running: backend._ok; loops: Animation.Infinite
        NumberAnimation { from: 0; to: -3; duration: 1500; easing.type: Easing.InOutSine }
        NumberAnimation { from: -3; to: 0; duration: 1500; easing.type: Easing.InOutSine }
    }

    // --- CUERPO (respira) ---
    Image {
        id: body
        anchors.fill: parent
        visible: backend._ok
        source: backend._ok ? backend.characterDir + backend.rig.body : ""
        fillMode: Image.PreserveAspectFit
        smooth: true; mipmap: true
        transformOrigin: Item.Bottom
        SequentialAnimation on scale {
            running: backend._ok; loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 1.022; duration: 1700; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.022; to: 1.0; duration: 1700; easing.type: Easing.InOutSine }
        }
    }

    // --- CABEZA (rota en el cuello: tracking + bob + sway) ---
    Item {
        id: headRig
        anchors.fill: parent
        visible: backend._ok
        property real swayRot: 0
        SequentialAnimation on swayRot {
            running: backend._ok; loops: Animation.Infinite
            NumberAnimation { from: -2.0; to: 2.0; duration: 2700; easing.type: Easing.InOutSine }
            NumberAnimation { from: 2.0; to: -2.0; duration: 2700; easing.type: Easing.InOutSine }
        }
        transform: [
            Rotation {
                origin.x: backend.width / 2
                origin.y: backend.height * (backend._ok ? backend.rig.neckY : 0.54)
                angle: backend.headYaw * 12 + headRig.swayRot
                Behavior on angle { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            },
            Translate {
                x: backend.headYaw * 6
                y: backend._bobY + backend.headPitch * 5
                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }
        ]
        Image {
            id: headOpen
            anchors.fill: parent
            source: backend._ok ? backend.characterDir + backend.rig.head_open : ""
            fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true
        }
        Image {
            id: headClosed
            anchors.fill: parent
            source: backend._ok ? backend.characterDir + backend.rig.head_closed : ""
            fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true
            opacity: backend.currentState === "sleeping" ? 1 : 0   // dormido = ojos cerrados fijos
        }
    }

    // --- PARPADEO (cross-fade suave; no cuando duerme) ---
    Timer {
        running: backend._ok && backend.currentState !== "sleeping"
        interval: 2800 + Math.round(Math.random() * 2600)
        repeat: true
        onTriggered: blinkAnim.restart()
    }
    SequentialAnimation {
        id: blinkAnim
        NumberAnimation { target: headClosed; property: "opacity"; to: 1; duration: 70; easing.type: Easing.InQuad }
        PauseAnimation { duration: 75 }
        NumberAnimation { target: headClosed; property: "opacity"; to: 0; duration: 110; easing.type: Easing.OutQuad }
    }
}
