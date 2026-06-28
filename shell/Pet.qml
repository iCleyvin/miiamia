// Pet.qml — ventana overlay de la mascota (capa layer-shell sobre TODO, incl. juegos fullscreen).
//
// Patron verificado contra Quickshell 0.3.0 + Hyprland 0.55.4 (ref: qs-vpets):
//  - WlrLayershell.layer = Overlay  -> se dibuja por encima de ventanas fullscreen.
//  - keyboardFocus = None (PERMANENTE) -> evita el bug Hyprland #14136 (Exclusive + region
//    vacia captura todo el puntero). El chat (M3) ira en OTRA PanelWindow, nunca aqui.
//  - mask = Region limitada al rect del sprite -> click-through: solo el avatar es clickeable,
//    el resto de la pantalla recibe los clicks normalmente (escritorio/juego/editor).
import QtQuick
import Quickshell
import Quickshell.Wayland
import "backends"

PanelWindow {
    id: root

    required property var petData       // manifest del personaje (kira.json parseado)
    required property url characterDir  // file:// del directorio del personaje
    property string contextState: "idle" // estado calculado por ContextEngine (M2)
    property bool talking: false          // true mientras el chat streamea la respuesta (M3)
    property string voiceState: "idle"    // idle | listening | thinking | speaking (M4)
    property real voiceAmplitude: 0.0     // 0..1 para el lip-sync
    property real scaleOverride: 0        // tamaño desde el menú (0 = usar el del manifest)
    property string monitorName: ""       // monitor donde vive (vacío = el default de Quickshell)
    signal petClicked()                   // click izquierdo -> abre/cierra el chat
    signal voicePttStart()                // click DERECHO mantenido -> hablarle (push-to-talk)
    signal voicePttStop()

    // Estado efectivo del sprite: hablar (voz o texto) > override > contexto.
    property string _override: ""
    readonly property string state:
        (voiceState === "speaking" || talking) ? "talking"
        : (_override !== "" ? _override : contextState)

    // --- Configuracion de capa (wlr-layer-shell) ---
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "miiamia"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    // Monitor donde aparece la mascota. Si monitorName casa con una pantalla, la usa; si no, default.
    function _applyScreen() {
        if (root.monitorName === "") return;
        var ss = Quickshell.screens;
        for (var i = 0; i < ss.length; i++)
            if (ss[i].name === root.monitorName) { root.screen = ss[i]; return; }
    }
    Component.onCompleted: _applyScreen()
    onMonitorNameChanged: _applyScreen()

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    // Click-through: solo el rect del avatar captura input; null mientras se arrastra.
    mask: dragArea.dragging ? null : petRegion

    Region {
        id: petRegion
        x: avatar.x
        y: avatar.y
        width: avatar.width
        height: avatar.height
    }

    SpriteBackend {
        id: avatar
        characterDir: root.characterDir
        animations: root.petData.animations
        currentState: root.state
        scale: root.scaleOverride > 0 ? root.scaleOverride
               : (root.petData.scale !== undefined ? root.petData.scale : 2.0)

        // Posicion inicial: abajo-derecha, sobre el "suelo" de la pantalla.
        x: root.width - width - 48
        y: root.height - height - 48

        MouseArea {
            id: dragArea
            anchors.fill: parent
            property bool dragging: drag.active
            cursorShape: dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            drag.target: avatar
            drag.axis: Drag.XAndYAxis
            // Límites: la mascota no puede salirse de la pantalla (no se pierde al arrastrar).
            drag.minimumX: 0
            drag.maximumX: Math.max(0, root.width - avatar.width)
            drag.minimumY: 0
            drag.maximumY: Math.max(0, root.height - avatar.height)
            onClicked: root.petClicked()   // abre/cierra el chat (M3)
        }

        // Click DERECHO mantenido = hablarle (push-to-talk). Solo acepta el boton derecho,
        // asi el izquierdo (arrastrar / abrir chat) pasa al dragArea de abajo.
        MouseArea {
            id: voiceArea
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onPressed: root.voicePttStart()
            onReleased: root.voicePttStop()
        }

        // --- Overlays de voz (decorativos; no capturan input) ---
        // Anillo "escuchando"
        Rectangle {
            id: listenRing
            anchors.centerIn: parent
            width: parent.width * 0.92; height: width; radius: width / 2
            color: "transparent"; border.color: "#a78cff"; border.width: 3
            visible: root.voiceState === "listening"
            SequentialAnimation on opacity {
                running: listenRing.visible; loops: Animation.Infinite
                NumberAnimation { to: 0.9; duration: 600 }
                NumberAnimation { to: 0.2; duration: 600 }
            }
        }
        // Lip-sync: barrita que crece con la amplitud, cerca de la boca
        Rectangle {
            visible: root.voiceState === "speaking"
            width: 14; radius: 3; color: "#ff8db4"
            height: 4 + root.voiceAmplitude * 22
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: parent.height * 0.12
            Behavior on height { NumberAnimation { duration: 40 } }
        }
        // "Pensando": puntito que late sobre la cabeza
        Rectangle {
            id: thinkDot
            visible: root.voiceState === "thinking"
            width: 12; height: 12; radius: 6; color: "#a78cff"
            anchors.horizontalCenter: parent.horizontalCenter
            y: -10
            SequentialAnimation on scale {
                running: thinkDot.visible; loops: Animation.Infinite
                NumberAnimation { to: 1.4; duration: 400 }
                NumberAnimation { to: 0.8; duration: 400 }
            }
        }
    }
}
