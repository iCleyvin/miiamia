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
import Quickshell.Io
import "backends"

PanelWindow {
    id: root

    required property var petData       // manifest del personaje (kira.json parseado)
    required property url characterDir  // file:// del directorio del personaje
    // Un typo en manifest.backend cae en silencio al SpriteBackend (fallback); avisar en el log.
    onPetDataChanged: {
        var b = petData ? petData.backend : undefined;
        if (b !== undefined && ["sprite", "rig", "dragonRig", "dragonRigV2", "dragonRigV3", "model3d", "live2d"].indexOf(b) < 0)
            console.warn("miiamia[pet]: backend desconocido '" + b + "' en el manifest; uso sprite");
    }
    property string contextState: "idle" // estado calculado por ContextEngine (M2)
    property bool talking: false          // true mientras el chat streamea la respuesta (M3)
    property string voiceState: "idle"    // idle | listening | thinking | speaking (M4)
    property real voiceAmplitude: 0.0     // 0..1 para el lip-sync
    property real scaleOverride: 0        // tamaño desde el menú (0 = usar el del manifest)
    property string monitorName: ""       // monitor donde vive (vacío = el default de Quickshell)
    signal petClicked()                   // click izquierdo -> abre/cierra el chat
    signal voicePttStart()                // click DERECHO mantenido -> hablarle (push-to-talk)
    signal voicePttStop()
    signal petApproached()                // el cursor se acerca a la pet 3D -> saludo (voz + globo)
    property bool cursorNear: false       // el cursor esta cerca de la pet (para reaccion 3D)
    property real cursorProximity: 0.0     // 0..1: cercania continua del cursor para atencion/gestos 3D
    property string model3dIdleMode: ""    // "", "phone", "sit": pequenas rutinas autonomas
    readonly property string model3dLifeMode:
        state === "music" ? "dance"
        : (state === "browsing" || state === "typing") ? "phone"
        : (state === "watching" || state === "sleeping") ? "sit"
        : model3dIdleMode
    property bool _greetReady: true       // cooldown del saludo hablado
    Timer { id: greetCooldown; interval: 45000; onTriggered: root._greetReady = true }

    // Comentario espontáneo (vista automática): texto que aparece en un globo sobre la pet y se va solo.
    property string bubbleText: ""
    onBubbleTextChanged: if (bubbleText !== "") bubbleHide.restart()
    Timer { id: bubbleHide; interval: 9000; onTriggered: root.bubbleText = "" }

    // Estado efectivo del sprite: hablar (voz o texto) > override > contexto.
    property string _override: ""
    readonly property string state:
        (voiceState === "speaking" || talking) ? "talking"
        : (_override !== "" ? _override : contextState)

    // Directorio compartido de props (objetos por actividad), hermano del dir del personaje:
    //  .../characters/<skin>/  ->  .../characters/_props/
    readonly property url propsDir: ("" + characterDir).replace(/[^/]+\/$/, "_props/")

    // --- Live2D (Inochi2D vía proceso nativo live2d_overlay; Quickshell = cerebro) ---
    property string projectRoot: ""
    property var live2dConf: null
    readonly property bool isLive2d: petData.backend === "live2d" && live2dModel !== ""
    readonly property string live2dBin: projectRoot + "/native/live2d_overlay"
    readonly property string live2dModel: live2dConf ? projectRoot + "/" + live2dConf.model : ""

    function _l2dVal(k, def) { return (live2dConf && live2dConf[k] !== undefined) ? live2dConf[k] : def; }
    function _l2dPos() {
        if (live2dProc.running && root.width > 0 && root.height > 0 && avatar.width > 0 && avatar.height > 0 && avatar.x >= 0 && avatar.y >= 0)
            live2dProc.write("pos " + Math.round(avatar.x) + " " + Math.round(avatar.y)
                + " " + Math.round(avatar.width) + " " + Math.round(avatar.height) + "\n");
    }
    function _l2dCam() {
        if (live2dProc.running)
            live2dProc.write("cam " + _l2dVal("scale", 0.075) + " " + _l2dVal("camx", 0) + " " + _l2dVal("camy", 0) + "\n");
    }
    function _l2dState() { if (live2dProc.running) live2dProc.write("state " + root.state + "\n"); }
    function _l2dAmp() { if (live2dProc.running) live2dProc.write("amp " + root.voiceAmplitude.toFixed(3) + "\n"); }
    onStateChanged: _l2dState()
    onVoiceAmplitudeChanged: _l2dAmp()

    // Ícono que indica el estado SIN alterar el diseño (la criatura es siempre la misma).
    readonly property string _stateIcon: {
        switch (state) {
        case "typing":   return "⌨️";
        case "gaming":   return "🎮";
        case "browsing": return "🌐";
        case "watching": return "🍿";
        case "music":    return "🎵";
        case "sleeping": return "💤";
        default:         return "";
        }
    }

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
    Component.onCompleted: { _applyScreen(); monProc.running = true; }
    onMonitorNameChanged: { _applyScreen(); monProc.running = true; }

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    // Click-through: solo el rect del avatar captura input; null mientras se arrastra.
    //  El rect del avatar capta input (drag + clic->chat); el resto es click-through. En live2d el
    //  visual lo dibuja el proceso nativo en ese mismo rect, así que arrastrar/clicar sobre Aka funciona.
    mask: dragArea.dragging ? null : petRegion

    Region {
        id: petRegion
        item: avatar
    }

    Item {
        id: avatar
        readonly property bool isRig: root.petData.backend === "rig"
        readonly property bool isDragonRig: root.petData.backend === "dragonRig"
        readonly property bool isDragonRigV2: root.petData.backend === "dragonRigV2"
        readonly property bool isDragonRigV3: root.petData.backend === "dragonRigV3"
        readonly property bool isModel3d: root.petData.backend === "model3d"
        readonly property var _m3d: root.petData.model3d !== undefined ? root.petData.model3d : null
        readonly property real _scaleEff: root.scaleOverride > 0 ? root.scaleOverride
               : (root.petData.scale !== undefined ? root.petData.scale : 2.0)
        // model3d (waifu 3D): rect alto tipo persona (w/h del manifest, escalado por _scaleEff sobre base 2.0)
        width: root.isLive2d ? (root.live2dConf && root.live2dConf.w ? root.live2dConf.w : 360)
               : avatar.isModel3d ? ((avatar._m3d && avatar._m3d.w ? avatar._m3d.w : 380) * (_scaleEff / 2.0))
               : 128 * _scaleEff
        height: root.isLive2d ? (root.live2dConf && root.live2dConf.h ? root.live2dConf.h : 500)
               : avatar.isModel3d ? ((avatar._m3d && avatar._m3d.h ? avatar._m3d.h : 560) * (_scaleEff / 2.0))
               : 128 * _scaleEff

        // Posicion inicial: abajo-derecha, sobre el "suelo" de la pantalla.
        x: root.width - width - 48
        y: root.height - height - 48
        // Live2D: el visual lo dibuja el proceso nativo en la posición del avatar -> avisarle al moverse.
        onXChanged: root._l2dPos()
        onYChanged: root._l2dPos()
        onWidthChanged: { root._l2dCam(); root._l2dPos(); }
        onHeightChanged: root._l2dPos()

        // Física al arrastrar: se "levanta" un pelín al agarrarla y aterriza con rebote al soltar.
        transform: Scale {
            origin.x: avatar.width / 2; origin.y: avatar.height
            xScale: dragArea.dragging ? 1.06 : 1.0
            yScale: dragArea.dragging ? 1.06 : 1.0
            Behavior on xScale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
            Behavior on yScale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
        }

        // Render: UN solo backend vivo a la vez (Loader). Antes se instanciaban los 6 backends
        // siempre y se ocultaban con visible:false — el 3D cargaba su VRM completo aunque la skin
        // activa fuera un sprite, y al cambiar de skin el backend viejo podía quedar corriendo con
        // estado obsoleto (bug "mancha"). El Loader garantiza instancia FRESCA del backend correcto
        // en cada cambio de skin y cero coste de los demás.
        Loader {
            id: backendLoader
            anchors.fill: parent
            sourceComponent: root.isLive2d ? null
                : avatar.isModel3d ? model3dComp
                : avatar.isDragonRigV3 ? dragonRigV3Comp
                : avatar.isDragonRigV2 ? dragonRigV2Comp
                : avatar.isDragonRig ? dragonRigComp
                : avatar.isRig ? rigComp
                : spriteComp
        }
        Component {
            id: spriteComp
            SpriteBackend {
                characterDir: root.characterDir
                animations: root.petData.animations !== undefined ? root.petData.animations : ({})
                currentState: root.state
                scale: avatar._scaleEff
                blinkSource: root.petData.blink !== undefined ? root.characterDir + root.petData.blink : ""
                talking: root.talking || root.voiceState === "speaking"
                voiceAmplitude: root.voiceAmplitude
            }
        }
        Component {
            id: rigComp
            RigBackend {
                characterDir: root.characterDir
                rig: avatar.isRig && root.petData.rig !== undefined ? root.petData.rig : null
                scale: avatar._scaleEff
                currentState: root.state
                talking: root.talking || root.voiceState === "speaking"
                headYaw: root.headYaw
                headPitch: root.headPitch
            }
        }
        Component {
            id: dragonRigComp
            DragonRigBackend {
                characterDir: root.characterDir
                rig: avatar.isDragonRig && root.petData.rig !== undefined ? root.petData.rig : null
                scale: avatar._scaleEff
                currentState: root.state
                talking: root.talking || root.voiceState === "speaking"
                voiceAmplitude: root.voiceAmplitude
                headYaw: root.headYaw
                headPitch: root.headPitch
            }
        }
        Component {
            id: dragonRigV2Comp
            DragonRigV2Backend {
                characterDir: root.characterDir
                rig: avatar.isDragonRigV2 && root.petData.rig !== undefined ? root.petData.rig : null
                scale: avatar._scaleEff
                currentState: root.state
                talking: root.talking || root.voiceState === "speaking"
                voiceAmplitude: root.voiceAmplitude
                headYaw: root.headYaw
                headPitch: root.headPitch
            }
        }
        Component {
            id: dragonRigV3Comp
            DragonRigV3Backend {
                characterDir: root.characterDir
                rig: avatar.isDragonRigV3 && root.petData.rig !== undefined ? root.petData.rig : null
                scale: avatar._scaleEff
                currentState: root.state
                talking: root.talking || root.voiceState === "speaking"
                voiceAmplitude: root.voiceAmplitude
                headYaw: root.headYaw
                headPitch: root.headPitch
            }
        }
        // Waifu ANIME 3D (VRM/glTF via Qt Quick 3D). Config en manifest.model3d (índices por modelo).
        Component {
            id: model3dComp
            Model3DBackend {
                characterDir: root.characterDir
                scale: avatar._scaleEff
                currentState: root.state
                talking: root.talking || root.voiceState === "speaking"
                voiceAmplitude: root.voiceAmplitude
                voiceState: root.voiceState
                headYaw: root.headYaw
                headPitch: root.headPitch
                cursorNear: root.cursorNear    // reacciona (saluda/despierta) cuando el cursor se acerca
                cursorProximity: root.cursorProximity
                lifeMode: root.model3dLifeMode
                config: avatar._m3d            // objeto model3d completo del manifest (indices, cam, armPose...)
            }
        }

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
        // El lip-sync visual vive en el avatar (pulso corporal / Live2D). La barrita vieja se
        // mantiene desactivada porque se lee como UI superpuesta, no como una mascota viva.
        Rectangle {
            visible: false
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

        // --- Prop por actividad: objeto (PNG en characters/_props/) superpuesto sobre la criatura
        //     REAL -> identidad 100% intacta. Posiciones/tamaños (fracción del avatar) tuneados a drag.
        Image {
            id: actProp
            property var cfg: ({
                "gaming":   { p: "controller", x: 0.50, y: 0.76, s: 0.54 },
                "watching": { p: "popcorn",    x: 0.76, y: 0.74, s: 0.44 },
                "music":    { p: "headphones", x: 0.50, y: 0.30, s: 0.78 },
                "browsing": { p: "tablet",     x: 0.50, y: 0.76, s: 0.46 }
            }[root.state] || null)
            // Los props de cartón (mando/palomitas/audífonos/tablet) se ponen DELANTE de la pet y
            // tapan el cuerpo: chocan con el dragón realista (y ahora es redundante, el rig ya tiene
            // poses propias por estado). Se desactivan en los backends de dragón; se mantienen en las
            // skins sprite/kawaii, para las que fueron diseñados.
            property bool shown: cfg !== null && root.voiceState === "idle" && !root.talking && !root.isLive2d
                                 && !avatar.isDragonRig && !avatar.isDragonRigV2 && !avatar.isDragonRigV3 && !avatar.isModel3d
            visible: shown
            source: cfg ? root.propsDir + cfg.p + ".png" : ""
            width: cfg ? parent.width * cfg.s : 0
            height: width
            fillMode: Image.PreserveAspectFit
            smooth: true; mipmap: true
            x: cfg ? parent.width * cfg.x - width / 2 : 0
            y: (cfg ? parent.height * cfg.y - height / 2 : 0) + bobY
            property real bobY: 0
            onShownChanged: if (shown) propPop.restart()
            Connections { target: root; function onStateChanged() { if (actProp.shown) propPop.restart() } }
            SequentialAnimation {
                id: propPop
                NumberAnimation { target: actProp; property: "scale"; from: 0.5; to: 1.10; duration: 170; easing.type: Easing.OutBack }
                NumberAnimation { target: actProp; property: "scale"; to: 1.0; duration: 150 }
            }
            SequentialAnimation on bobY {
                running: actProp.shown; loops: Animation.Infinite
                NumberAnimation { from: 0; to: -3; duration: 1100; easing.type: Easing.InOutSine }
                NumberAnimation { from: -3; to: 0; duration: 1100; easing.type: Easing.InOutSine }
            }
        }

        // --- Globo de diálogo: comentario espontáneo de la pet (vista automática). Decorativo,
        //     no captura input; aparece sobre la criatura y se desvanece solo (bubbleHide). ---
        Item {
            id: speechBubble
            visible: opacity > 0.01
            opacity: root.bubbleText !== "" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            width: Math.min(280, bubbleLabel.implicitWidth + 24)
            height: bubbleLabel.implicitHeight + 18
            anchors.right: parent.right
            anchors.rightMargin: -6
            y: -height - 10
            transformOrigin: Item.Bottom
            scale: root.bubbleText !== "" ? 1 : 0.6
            Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }

            Rectangle {
                anchors.fill: parent
                radius: 14
                color: "#f2120a1e"
                border.color: "#80a78cff"
                border.width: 1
                Text {
                    id: bubbleLabel
                    anchors.fill: parent
                    anchors.margins: 10
                    text: root.bubbleText
                    color: "#f2eeff"
                    wrapMode: Text.Wrap
                    font.pixelSize: 13
                    verticalAlignment: Text.AlignVCenter
                }
            }
            // colita apuntando a la pet
            Rectangle {
                width: 12; height: 12; rotation: 45
                color: "#f2120a1e"
                border.color: "#80a78cff"; border.width: 1
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.bottom
                anchors.topMargin: -7
            }
        }
    }

    // --- Live2D: el renderer nativo se lanza como UNIDAD systemd hermana (NO hijo directo de
    //     Quickshell: como hijo, NVIDIA recorta el render a medio cuerpo — bug verificado). Bound a
    //     miiamia.service para que muera al parar/reiniciar la pet. Se auto-posiciona (abajo-derecha
    //     por márgenes) y tiene vida propia (tracking de cursor + respiración + parpadeo + dormir). ---
    Process {
        id: live2dProc
        running: root.isLive2d
        command: ["env",
            "MIIAMIA_W=" + root._l2dVal("w", 360), "MIIAMIA_H=" + root._l2dVal("h", 500),
            "MIIAMIA_INOX_SCALE=" + root._l2dVal("scale", 0.075),
            "MIIAMIA_INOX_X=" + root._l2dVal("camx", 0), "MIIAMIA_INOX_Y=" + root._l2dVal("camy", 0),
            root.live2dBin, root.live2dModel,
            (root.screen && root.screen.name ? root.screen.name : root.monitorName)]
        stdinEnabled: true
        onRunningChanged: if (running) l2dKick.restart()
    }
    Timer {
        id: l2dKick   // reenvía cam+pos+state unos segundos tras spawnear (cubre el init del proceso)
        interval: 450; repeat: true; property int n: 0
        onTriggered: { root._l2dCam(); root._l2dPos(); root._l2dState(); if (++n > 7) { n = 0; stop(); } }
    }

    // --- Head-tracking: la cabeza sigue el cursor (solo en rig). Lee la posición GLOBAL del
    //     cursor con `hyprctl cursorpos` y la convierte en un ángulo hacia la pet. ---
    property real headYaw: 0      // -1 (cursor a la izq) .. 1 (der)
    property real headPitch: 0    // -1 (arriba) .. 1 (abajo)
    property int monOffX: 0
    property int monOffY: 0

    Process {
        id: monProc
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            id: monColl
            onStreamFinished: {
                try {
                    var arr = JSON.parse(monColl.text);
                    var want = root.monitorName !== "" ? root.monitorName
                               : (root.screen ? root.screen.name : "");
                    var m = null;
                    for (var i = 0; i < arr.length; i++)
                        if (arr[i].name === want) { m = arr[i]; break; }
                    if (!m && arr.length) m = arr[0];
                    if (m) { root.monOffX = m.x; root.monOffY = m.y; }
                } catch (e) {}
            }
        }
    }
    Process {
        id: cursorProc
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            id: curColl
            onStreamFinished: {
                var mm = curColl.text.match(/(-?\d+)\s*,\s*(-?\d+)/);
                if (!mm) return;
                var rx = parseInt(mm[1]) - root.monOffX;
                var ry = parseInt(mm[2]) - root.monOffY;
                var pcx = avatar.x + avatar.width / 2;
                var pcy = avatar.y + avatar.height / 2;
                var dx = rx - pcx;
                var dy = ry - pcy;
                root.headYaw = Math.max(-1, Math.min(1, dx / 520));
                root.headPitch = Math.max(-1, Math.min(1, dy / 520));
                var nx = dx / Math.max(1, avatar.width * 1.15);
                var ny = dy / Math.max(1, avatar.height * 0.95);
                root.cursorProximity = avatar.isModel3d ? Math.max(0, Math.min(1, 1 - Math.sqrt(nx*nx + ny*ny))) : 0;
                // proximidad: el cursor esta "cerca" si cae sobre/junto al cuerpo de la pet
                var near = (Math.abs(dx) < avatar.width * 0.9)
                        && (dy > -avatar.height * 0.62) && (dy < avatar.height * 0.55);
                if (near && !root.cursorNear && avatar.isModel3d && root._greetReady) {
                    root._greetReady = false; greetCooldown.restart();
                    root.petApproached();          // -> saludo por voz + globo (shell.qml)
                }
                root.cursorNear = near;
            }
        }
    }
    Timer {
        interval: 110
        // model3d tambien sigue el cursor (mirada) y ademas cuando esta "sleeping" (para despertar al acercarse)
        running: ((avatar.isRig || avatar.isDragonRig || avatar.isDragonRigV2 || avatar.isDragonRigV3) && root.state !== "gaming" && root.state !== "sleeping")
                 || (avatar.isModel3d && root.state !== "gaming")
        repeat: true
        onTriggered: if (!cursorProc.running) cursorProc.running = true
        // Al parar el polling (p.ej. entra un juego), resetear: si no, la pet 3D se queda con la
        // pose de "atencion al cursor" congelada durante toda la partida.
        onRunningChanged: if (!running) {
            root.cursorNear = false;
            root.cursorProximity = 0;
            root.headYaw = 0;
            root.headPitch = 0;
        }
    }
    Timer {
        id: model3dIdleLife
        interval: 10000
        repeat: true
        running: avatar.isModel3d && root.state === "idle" && root.voiceState === "idle" && !root.talking
        onTriggered: {
            interval = 16000 + Math.round(Math.random() * 16000);
            var r = Math.random();
            root.model3dIdleMode = r < 0.34 ? "phone" : (r < 0.58 ? "sit" : "");
            if (root.model3dIdleMode !== "") idleLifeClear.restart();
        }
    }
    Timer {
        id: idleLifeClear
        interval: 8500
        onTriggered: root.model3dIdleMode = ""
    }
}
