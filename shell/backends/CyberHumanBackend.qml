// CyberHumanBackend.qml — Nyx, humana cyberpunk HIPERREALISTA (retrato SDXL + rig de parches).
//
// La técnica: una foto base + parches inpainted (ojos cerrados/mirada/medio, visemas, sonrisa)
// que encajan SIN costura (el inpainting solo cambió píxeles dentro de su máscara), una capa
// de neón aditiva (implantes) con bloom real, y efectos holográficos (boot, glitch RGB,
// scanlines) que son parte de ELLA, no adornos. El motor de humor (arousal/pleasure) deriva
// todo: ritmo cardíaco del neón, respiración, postura, sonrisa — micro-etología humana real:
// parpadeo estadístico (12-20/min, dobles), sacádicos instantáneos, sway postural, fidgets.
import QtQuick
import QtQuick.Effects
import Quickshell.Io

Item {
    id: backend

    // --- API uniforme (Pet.qml) ---
    property url characterDir
    property var config: null            // manifest.human: {size, patches, sounds, volume}
    property string currentState: "idle"
    property bool talking: false
    property real voiceAmplitude: 0
    property string voiceState: "idle"
    property real headYaw: 0
    property real headPitch: 0
    property real cursorProximity: 0
    property bool cursorNear: false
    property real scale: 2.0
    property string monitorName: ""

    // --- Caricias (Pet.qml) ---
    property bool petActive: false
    property real petX: 0.5
    property real petY: 0.5
    property real petSpeed: 0
    property bool held: false

    signal jetEscape()                   // glitch-teleport: Pet.qml mueve la ventana

    // --- Motor de humor ---
    property real arousal: 0.25
    property real pleasure: 0.5
    property real _roughMeter: 0
    property bool escaping: false
    property bool booted: false

    // fases / estado interno
    property real _t: 0
    property real _breathPhase: 0
    property real _heartPhase: 0
    property real _swayPhase: 0
    property real _blink: 0              // 1 = ojos cerrados (parche)
    property int _gaze: 0                // -1 izq, 0 centro, 1 der (parches de mirada)
    property real _lean: 0               // inclinación hacia el cursor (caricia)
    property real _glitch: 0             // 0..1 intensidad de glitch

    readonly property bool sleeping: currentState === "sleeping"
    readonly property bool dancing: currentState === "music"
    readonly property bool _speaking: talking || voiceState === "speaking"

    readonly property var _cfg: config !== null ? config : ({})
    readonly property bool soundsOn: _cfg.sounds !== undefined ? _cfg.sounds === true : true
    readonly property real volMaster: _cfg.volume !== undefined ? _cfg.volume : 0.35
    readonly property var _patches: _cfg.patches !== undefined ? _cfg.patches : ({})
    readonly property real srcW: _cfg.size !== undefined ? _cfg.size[0] : 832
    readonly property real srcH: _cfg.size !== undefined ? _cfg.size[1] : 1216

    function _p(name, key, def) {
        var p = _patches[name];
        return p !== undefined && p[key] !== undefined ? p[key] : def;
    }

    // sonrisa: caricia que gusta, o placer alto sostenido
    readonly property bool _smiling: !sleeping && !escaping
        && ((petActive && petSpeed < 1.4 && pleasure > 0.55) || pleasure > 0.78)
    // visemas por amplitud de voz (lip-sync de foto real)
    readonly property int _viseme: !_speaking ? 0 : (voiceAmplitude > 0.5 ? 2 : (voiceAmplitude > 0.15 ? 1 : 0))

    // ============================ ESCENARIO ============================
    // stage en píxeles FUENTE (832x1216): los parches usan coordenadas del PNG original.
    Item {
        id: stage
        width: backend.srcW
        height: backend.srcH
        readonly property real _fit: Math.min(backend.width / width, backend.height / height)
        // escala a encajar + centrado horizontal + alineado al fondo (los pies "pisan" el borde)
        transform: [
            Scale { xScale: stage._fit; yScale: stage._fit; origin.x: 0; origin.y: 0 },
            Translate { x: (backend.width - stage.width * stage._fit) / 2; y: backend.height - stage.height * stage._fit }
        ]

        // --- cuerpo (respiración + sway + lean se aplican aquí) ---
        Item {
            id: body
            width: parent.width
            height: parent.height
            transformOrigin: Item.Bottom

            Image { id: baseImg; source: backend.characterDir + "layers/base.png"; anchors.fill: parent; smooth: true; mipmap: true }

            // parches faciales (encajan por construcción; fundido corto)
            Image {
                id: smilePatch
                source: backend.characterDir + "layers/smile.png"
                x: backend._p("smile", "x", 0); y: backend._p("smile", "y", 0)
                opacity: backend._smiling && backend._viseme === 0 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220 } }
            }
            Image {
                id: mouthOpen
                source: backend.characterDir + "layers/mouth_open.png"
                x: backend._p("mouth_open", "x", 0); y: backend._p("mouth_open", "y", 0)
                opacity: backend._viseme === 1 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 55 } }
            }
            Image {
                id: mouthWide
                source: backend.characterDir + "layers/mouth_wide.png"
                x: backend._p("mouth_wide", "x", 0); y: backend._p("mouth_wide", "y", 0)
                opacity: backend._viseme === 2 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 55 } }
            }
            Image {
                id: eyesLeft
                source: backend.characterDir + "layers/eyes_left.png"
                x: backend._p("eyes_left", "x", 0); y: backend._p("eyes_left", "y", 0)
                opacity: backend._blink < 0.5 && backend._gaze === -1 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 40 } }   // sacádico: casi instantáneo
            }
            Image {
                id: eyesRight
                source: backend.characterDir + "layers/eyes_right.png"
                x: backend._p("eyes_right", "x", 0); y: backend._p("eyes_right", "y", 0)
                opacity: backend._blink < 0.5 && backend._gaze === 1 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 40 } }
            }
            Image {
                id: eyesHalf
                source: backend.characterDir + "layers/eyes_half.png"
                x: backend._p("eyes_half", "x", 0); y: backend._p("eyes_half", "y", 0)
                // ojitos entrecerrados de gusto (caricia que encanta); dormida gana "closed"
                opacity: !backend.sleeping && backend.petActive && backend.pleasure > 0.85 && backend._blink < 0.5 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 300 } }
            }
            Image {
                id: eyesClosed
                source: backend.characterDir + "layers/eyes_closed.png"
                x: backend._p("eyes_closed", "x", 0); y: backend._p("eyes_closed", "y", 0)
                opacity: backend.sleeping ? 1 : backend._blink
                Behavior on opacity { enabled: backend.sleeping; NumberAnimation { duration: 900 } }
            }

            // implantes de neón: laten como corazón (lub-dub) + bloom real
            Image {
                id: glowImg
                source: backend.characterDir + "layers/glow.png"
                anchors.fill: parent
                opacity: 0.55
            }
            MultiEffect {
                id: bloom
                source: glowImg
                anchors.fill: glowImg
                blurEnabled: true
                blur: 0.9
                blurMax: 40
                brightness: 0.25
                opacity: glowImg.opacity * 0.9
            }
        }

        // scanlines holográficas sutiles, ENMASCARADAS a su silueta (sin ellas se veía el
        // rectángulo del canvas alrededor; el holograma es ella, no una caja)
        Canvas {
            id: scan
            anchors.fill: parent
            visible: false
            onPaint: {
                var c = getContext("2d");
                c.clearRect(0, 0, width, height);
                c.fillStyle = "#7fdfff";
                for (var y = 0; y < height; y += 4) c.fillRect(0, y, width, 1);
            }
            Component.onCompleted: requestPaint()
        }
        MultiEffect {
            source: scan
            width: scan.width; height: scan.height
            opacity: 0.06 + glowImg.opacity * 0.03
            maskEnabled: true
            maskSource: baseImg
            maskThresholdMin: 0.3
        }

        // glitch RGB: dos copias colorizadas desplazadas, solo visibles durante el glitch
        // (sin anchors: el offset x ES el efecto)
        MultiEffect {
            id: splitC
            source: baseImg
            width: baseImg.width; height: baseImg.height
            visible: backend._glitch > 0.02
            colorization: 1; colorizationColor: "#00f7ff"
            opacity: backend._glitch * 0.4
            x: backend._glitch * 7; y: 0
        }
        MultiEffect {
            id: splitM
            source: baseImg
            width: baseImg.width; height: baseImg.height
            visible: backend._glitch > 0.02
            colorization: 1; colorizationColor: "#ff2470"
            opacity: backend._glitch * 0.4
            x: -backend._glitch * 7; y: 0
        }
    }

    // ============================ COMPOSICIÓN POR TICK ============================
    FrameAnimation {
        running: backend.visible
        onTriggered: backend._compose(frameTime)
    }

    function _compose(dt) {
        if (dt > 0.1) dt = 0.1;
        _t += dt;

        // humor: decaimiento hacia línea base
        arousal += ((sleeping ? 0.06 : 0.22) - arousal) * (dt / 9);
        pleasure += (0.45 - pleasure) * (dt / 25);
        _roughMeter = Math.max(0, _roughMeter - dt * 0.5);
        if (_glitch > 0 && !escaping) _glitch = Math.max(0, _glitch - dt * 3.5);

        // caricias: suave = gusto + se inclina hacia tu mano; brusco = glitch creciente
        if (petActive && !held && !escaping) {
            if (petSpeed < 1.4) {
                pleasure = Math.min(1, pleasure + dt * 0.26);
                arousal = Math.max(0.1, arousal - dt * 0.08);
                _lean += (((petX - 0.5) * 2) - _lean) * dt * 3;
                if (pleasure > 0.8) _sfxCooldown("happy", 0.8, 30000);
            } else {
                arousal = Math.min(1, arousal + dt * 0.5);
                _glitch = Math.min(0.5, _glitch + dt * 1.2);   // micro-glitches de molestia
                _roughMeter += dt * (petSpeed - 1.4) * 0.8;
                if (_roughMeter > 1.0) _startle();
            }
        } else {
            _lean += (0 - _lean) * dt * 2;
        }
        if (held) { arousal = Math.min(1, arousal + dt * 0.3); _glitch = Math.max(_glitch, 0.15); }

        // respiración (12-16/min; más rápida alterada) + sway postural + lean
        _breathPhase += dt * (sleeping ? 0.18 : (0.22 + arousal * 0.28)) * Math.PI * 2;
        _swayPhase += dt * 0.35;
        var breath = Math.sin(_breathPhase);
        var sway = Math.sin(_swayPhase) * (sleeping ? 0.15 : 0.8) + Math.sin(_swayPhase * 2.7) * 0.25;
        var nod = dancing ? Math.sin(_t * 3.6) * 1.0 : 0;                     // asiente con la música
        var speakBob = _speaking ? voiceAmplitude * 1.2 : 0;
        body.scale = 1 + breath * 0.004;
        body.rotation = sway + _lean * 3.5 + nod * 0.6;
        body.y = -Math.abs(nod) * 1.5 - speakBob;

        // mirada: sacádicos hacia el cursor (con histéresis, como los ojos reales)
        if (!sleeping) {
            if (_gaze === 0 && Math.abs(headYaw) > 0.34) _gaze = headYaw > 0 ? 1 : -1;
            else if (_gaze !== 0 && Math.abs(headYaw) < 0.16) _gaze = 0;
        } else _gaze = 0;

        // neón: latido lub-dub; frecuencia = f(arousal) (62-120 bpm)
        var bpm = sleeping ? 48 : (62 + arousal * 58);
        _heartPhase = (_heartPhase + dt * bpm / 60) % 1;
        var lub = Math.exp(-Math.pow((_heartPhase - 0.06) * 14, 2));
        var dub = Math.exp(-Math.pow((_heartPhase - 0.24) * 16, 2)) * 0.6;
        var beat = (lub + dub) * (0.22 + arousal * 0.25);
        var baseGlow = sleeping ? 0.22 : (0.45 + pleasure * 0.18 + (dancing ? 0.12 * Math.sin(_t * 3.6) : 0));
        glowImg.opacity = Math.min(1, baseGlow + beat + _glitch * 0.4 + (_speaking ? voiceAmplitude * 0.15 : 0));
    }

    // ---- susto -> glitch total + TELETRANSPORTE (la huida cyberpunk) ----
    function _startle() {
        if (escaping) return;
        _roughMeter = 0;
        arousal = 1;
        pleasure = Math.max(0, pleasure - 0.3);
        escaping = true;
        _glitch = 1;
        _sfx("glitch", 0.9);
        heartbeatSfx.restart();
        teleportGo.restart();
        console.log("miiamia[nyx]: ¡glitch! teletransporte");
    }
    Timer { id: heartbeatSfx; interval: 300; onTriggered: backend._sfx("heartbeat", 0.8) }
    Timer { id: teleportGo; interval: 420; onTriggered: { backend._sfx("teleport", 0.85); backend.jetEscape(); } }
    Timer { id: escapeEnd; interval: 1400; running: backend.escaping; onTriggered: { backend.escaping = false; backend._glitch = 0.3; } }

    // ---- parpadeo humano: media ~4 s, a veces doble ----
    Timer {
        id: blinkTimer
        running: backend.visible && !backend.sleeping && backend.booted
        interval: 3200; repeat: true
        onTriggered: {
            blinkAnim.restart();
            interval = (Math.random() < 0.12) ? 420 : 2200 + Math.round(Math.random() * 3800);
        }
    }
    SequentialAnimation {
        id: blinkAnim
        NumberAnimation { target: backend; property: "_blink"; to: 1; duration: 55 }
        PauseAnimation { duration: 70 }
        NumberAnimation { target: backend; property: "_blink"; to: 0; duration: 95 }
    }

    // ---- fidget: cada 20-50 s mira a un lado un instante y vuelve (vida idle) ----
    Timer {
        running: backend.visible && !backend.sleeping && !backend.petActive && backend.booted
        interval: 24000; repeat: true
        onTriggered: {
            interval = 20000 + Math.round(Math.random() * 30000);
            fidget.start();
        }
    }
    SequentialAnimation {
        id: fidget
        ScriptAction { script: backend._gaze = Math.random() < 0.5 ? -1 : 1 }
        PauseAnimation { duration: 700 }
        ScriptAction { script: blinkAnim.restart() }
        PauseAnimation { duration: 500 }
        ScriptAction { script: backend._gaze = 0 }
    }

    // ---- boot de sistema al aparecer (flickers + neón que enciende) ----
    SequentialAnimation {
        id: bootSeq
        ScriptAction { script: backend._sfx("boot", 0.8) }
        NumberAnimation { target: stage; property: "opacity"; from: 0; to: 0.4; duration: 130 }
        NumberAnimation { target: stage; property: "opacity"; to: 0.08; duration: 70 }
        NumberAnimation { target: stage; property: "opacity"; to: 0.75; duration: 120 }
        NumberAnimation { target: stage; property: "opacity"; to: 0.3; duration: 60 }
        NumberAnimation { target: stage; property: "opacity"; to: 1; duration: 350; easing.type: Easing.OutCubic }
        ScriptAction { script: { backend.booted = true; backend._glitch = 0; } }
    }
    Component.onCompleted: { stage.opacity = 0; _glitch = 0.6; bootSeq.start(); }

    onSleepingChanged: _sfxCooldown(sleeping ? "sleep" : "blip", 0.6, 5000)
    onCursorNearChanged: if (cursorNear && booted && !petActive) _sfxCooldown("blip", 0.5, 30000)

    // ---- sonidos ----
    property var _sfxLast: ({})
    function _sfx(name, vol) {
        if (!soundsOn || sfx.running) return;
        sfx.command = ["pw-play", "--volume", String(Math.min(1, vol * volMaster * 2.5)),
                       ("" + characterDir).replace("file://", "") + "sounds/" + name + ".wav"];
        sfx.running = true;
    }
    function _sfxCooldown(name, vol, cdMs) {
        var now = Date.now();
        if (now - (_sfxLast[name] || 0) < cdMs) return;
        _sfxLast[name] = now;
        _sfx(name, vol);
    }
    Process { id: sfx }
}
