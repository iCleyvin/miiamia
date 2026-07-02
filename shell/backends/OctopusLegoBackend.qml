// OctopusLegoBackend.qml — Otto, pulpo LEGO 3D con etología real (ver docs/OTTO_PULPO.md).
//
// Construido ladrillo a ladrillo con primitivas de Qt Quick 3D (placas apiladas + studs).
// El corazón es una MÁQUINA DE HUMOR continua (arousal = alerta, pleasure = gusto) de la que
// se DERIVA todo, como en el animal real: color de la piel (cromatóforos), ritmo del sifón
// (respiración), amplitud y tempo de los 8 brazos semi-autónomos, camuflaje, sueño en colores.
// Toda escritura de pose/color pasa por _compose() como único punto por tick (patrón del
// proyecto: una sola intención corporal, nunca partes sueltas).
import QtQuick
import QtQuick3D
import QtQuick3D.Particles3D
import Quickshell.Io

Item {
    id: backend

    // --- API uniforme (Pet.qml) ---
    property url characterDir
    property var config: null            // manifest.octopus (volumen, camuflaje…)
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

    // --- Caricias (Pet.qml, hover del mouse sobre la pet) ---
    property bool petActive: false       // el cursor está posado sobre Otto
    property real petX: 0.5              // posición normalizada del cursor (0..1)
    property real petY: 0.5
    property real petSpeed: 0            // velocidad normalizada (anchos de pet / segundo)
    property bool held: false            // lo están arrastrando (se aferra)

    signal jetEscape()                   // sale disparado -> Pet.qml mueve la ventana

    // --- Máquina de humor (etología #1/#4: todo se deriva de aquí) ---
    property real arousal: 0.3           // 0 calma .. 1 alerta/miedo
    property real pleasure: 0.5          // 0 molesto .. 1 encantado
    property real _roughMeter: 0         // manoseo brusco acumulado -> susto
    property real _deimatic: 0           // display deimático (flash pálido) 1->0
    property bool escaping: false
    property real camoAmount: 0          // 0..1 mimetizado con el escritorio (etología #7)
    property color camoColor: "#7a7a8a"
    property real _idleFor: 0            // segundos sin interacción (dispara camuflaje)
    property real _reach: 0              // 0..1 brazo explorador extendido hacia el cursor
    property int _reachArm: 1

    // fases
    property real _t: 0
    property real _breathPhase: 0
    property real _wavePhase: 0
    property real _colorPhase: 0
    property real _blink: 0              // 0 abierto .. 1 cerrado
    property int _wanderArm: -1
    property real _wanderT: 0

    readonly property bool sleeping: currentState === "sleeping"
    readonly property bool denMode: currentState === "watching" || currentState === "gaming"   // etología #9
    readonly property bool dancing: currentState === "music"
    readonly property bool _speaking: talking || voiceState === "speaking"

    // --- Config con defaults ---
    readonly property var _cfg: config !== null ? config : ({})
    readonly property bool soundsOn: _cfg.sounds !== undefined ? _cfg.sounds === true : true
    readonly property real volMaster: _cfg.volume !== undefined ? _cfg.volume : 0.4
    readonly property real camoDelay: _cfg.camo_delay_secs !== undefined ? _cfg.camo_delay_secs : 180

    // --- Paleta cromatóforos (LEGO ABS) ---
    readonly property color cPale: "#ecc38b"      // arena cálida (relajado)
    readonly property color cCoral: "#e04c28"     // rojo coral LEGO (contento/activo)
    readonly property color cDark: "#571f14"      // marrón rojizo (alerta/miedo)
    readonly property color cFlash: "#f4ecdc"     // deimático (flash pálido)
    readonly property var cDream: ["#c99ec4", "#8fb6c9", "#d9b48a"]   // sueño activo (etología #6)

    function _mix(a, b, t) {
        t = Math.max(0, Math.min(1, t));
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }
    function _dim(c, d) { return Qt.rgba(c.r * (1 - d), c.g * (1 - d), c.b * (1 - d), 1); }

    // ============================ ESCENA 3D ============================
    View3D {
        id: view
        anchors.fill: parent
        renderMode: View3D.Offscreen
        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Transparent
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.High
        }
        PerspectiveCamera { id: cam; position: Qt.vector3d(0, 195, 560); eulerRotation.x: -10 }
        DirectionalLight { eulerRotation.x: -38; eulerRotation.y: -28; brightness: 1.35 }
        DirectionalLight { eulerRotation.x: -8; eulerRotation.y: 142; brightness: 0.5; color: "#cfe4ff" }

        Node {
            id: octo
            position: Qt.vector3d(0, 44, 0)

            Node { id: mantle }          // placas apiladas (se llenan en _build)
            Node { id: armsRoot }        // 8 raíces de brazo
            Node {
                id: face                 // ojos LEGO clásicos GRANDES en la cara frontal
                position: Qt.vector3d(0, 108, 0)
                Node {
                    id: eyeL; position: Qt.vector3d(-36, 0, 82)
                    Model { source: "#Cylinder"; scale: Qt.vector3d(0.56, 0.11, 0.56); eulerRotation.x: 90
                            materials: PrincipledMaterial { baseColor: "#f5f2ea"; roughness: 0.25; clearcoatAmount: 0.6 } }
                    Model { id: pupilL; source: "#Cylinder"; scale: Qt.vector3d(0.30, 0.08, 0.30)
                            position: Qt.vector3d(0, 0, 7); eulerRotation.x: 90
                            materials: PrincipledMaterial { baseColor: "#191512"; roughness: 0.2; clearcoatAmount: 0.8 } }
                }
                Node {
                    id: eyeR; position: Qt.vector3d(36, 0, 82)
                    Model { source: "#Cylinder"; scale: Qt.vector3d(0.56, 0.11, 0.56); eulerRotation.x: 90
                            materials: PrincipledMaterial { baseColor: "#f5f2ea"; roughness: 0.25; clearcoatAmount: 0.6 } }
                    Model { id: pupilR; source: "#Cylinder"; scale: Qt.vector3d(0.30, 0.08, 0.30)
                            position: Qt.vector3d(0, 0, 7); eulerRotation.x: 90
                            materials: PrincipledMaterial { baseColor: "#191512"; roughness: 0.2; clearcoatAmount: 0.8 } }
                }
            }
            Model {
                id: siphon               // el sifón asoma por el costado: respira; escupe tinta al huir
                source: "#Cylinder"
                position: Qt.vector3d(-98, 72, 24)
                eulerRotation.z: 64
                scale: Qt.vector3d(0.17, 0.34, 0.17)
                materials: PrincipledMaterial { id: siphonMat; baseColor: "#c9a37e"; roughness: 0.35; clearcoatAmount: 0.5 }
            }
        }

        // Tinta = piezas LEGO negras (etología #5). ModelParticle3D con esferas 1x1.
        ParticleSystem3D {
            id: inkSys
            ModelParticle3D {
                id: inkParticle
                delegate: Component {
                    Model { source: "#Sphere"; scale: Qt.vector3d(0.19, 0.19, 0.19)
                            materials: PrincipledMaterial { baseColor: "#161018"; roughness: 0.5 } }
                }
                maxAmount: 60
                fadeInEffect: ModelParticle3D.FadeScale
                fadeOutEffect: ModelParticle3D.FadeScale
                fadeInDuration: 60
                fadeOutDuration: 900
            }
            ParticleEmitter3D {
                id: inkEmitter
                particle: inkParticle
                position: Qt.vector3d(-100, 115, 30)
                enabled: false
                lifeSpan: 1500
                lifeSpanVariation: 400
                velocity: VectorDirection3D {
                    direction: Qt.vector3d(-85, 75, 45)
                    directionVariation: Qt.vector3d(55, 55, 45)
                }
            }
            Gravity3D { magnitude: 60; direction: Qt.vector3d(0, -1, 0) }
        }
    }

    // ============================ CONSTRUCCIÓN LEGO ============================
    Component {
        id: brickComp
        Model {
            source: "#Cube"
            property alias mat: m
            materials: PrincipledMaterial { id: m; baseColor: "#e3cfa8"; roughness: 0.28; clearcoatAmount: 0.55 }
        }
    }
    Component {
        id: studComp
        Model {
            source: "#Cylinder"
            property alias mat: m
            materials: PrincipledMaterial { id: m; baseColor: "#e3cfa8"; roughness: 0.28; clearcoatAmount: 0.55 }
        }
    }

    property var _layers: []      // placas del manto (para color)
    property var _studs: []
    property var _arms: []        // [{root, segs:[Model...], az, ph}]
    property bool _built: false

    // perfil del manto: media anchura por capa (silueta de domo brick-built)
    readonly property var _profile: [0.60, 0.78, 0.90, 0.97, 1.00, 1.00, 0.97, 0.91, 0.82, 0.70, 0.54, 0.34]
    readonly property real _R: 88
    readonly property int _segsPerArm: 9

    function _build() {
        var j, k, i;
        // manto: placas apiladas con leve variación (mampostería LEGO)
        for (j = 0; j < _profile.length; j++) {
            var w = 2 * _R * _profile[j];
            var b = brickComp.createObject(mantle, {
                position: Qt.vector3d(0, 26 + j * 15.5, 0),
                scale: Qt.vector3d(w / 100, 0.15, (w * 0.94) / 100)
            });
            _layers.push(b);
        }
        // studs 2x2 en la coronilla
        var topY = 26 + _profile.length * 15.5 - 4;
        var offs = [[-19, -19], [19, -19], [-19, 19], [19, 19]];
        for (k = 0; k < 4; k++) {
            var s = studComp.createObject(mantle, {
                position: Qt.vector3d(offs[k][0], topY + 7, offs[k][1]),
                scale: Qt.vector3d(0.30, 0.12, 0.30)
            });
            _studs.push(s);
        }
        // 8 brazos alrededor de la base
        for (k = 0; k < 8; k++) {
            var az = 22.5 + 45 * k;
            var root = Qt.createQmlObject('import QtQuick3D; Node {}', armsRoot);
            root.position = Qt.vector3d(0, 34, 0);
            root.eulerRotation = Qt.vector3d(0, az, 0);
            var segs = [];
            for (i = 0; i < _segsPerArm; i++) {
                var L = 29 - i * 1.6;
                var wS = 25 - i * 2.1;
                var seg = brickComp.createObject(root, {
                    scale: Qt.vector3d(L / 100, wS / 100, wS / 100)
                });
                segs.push(seg);
            }
            _arms.push({ root: root, segs: segs, az: az, ph: k * 0.83 });
        }
        _built = true;
    }
    Component.onCompleted: _build()

    // ============================ COMPOSICIÓN POR TICK ============================
    FrameAnimation {
        running: backend.visible && backend._built
        onTriggered: backend._compose(frameTime)
    }
    property int _frame: 0

    function _compose(dt) {
        if (dt > 0.1) dt = 0.1;
        _t += dt;
        _frame++;

        // ---- humor: decaimiento exponencial hacia la línea base ----
        arousal += ((sleeping ? 0.08 : 0.25) - arousal) * (dt / (escaping ? 3 : 8));
        pleasure += (0.45 - pleasure) * (dt / 22);
        _roughMeter = Math.max(0, _roughMeter - dt * 0.5);
        if (_deimatic > 0) _deimatic = Math.max(0, _deimatic - dt * 2.2);

        // ---- caricias (etología #3): suave = gusto; brusco = susto ----
        if (petActive && !held && !escaping) {
            if (petSpeed < 1.5) {
                var gentle = 1 - petSpeed / 1.6;
                pleasure = Math.min(1, pleasure + dt * 0.28 * Math.max(0.2, gentle));
                arousal = Math.max(0.12, arousal - dt * 0.10);
                _reach = Math.min(1, _reach + dt * 1.6);
                if (pleasure > 0.78) _sfxCooldown("happy", 0.9, 25000);
            } else {
                arousal = Math.min(1, arousal + dt * 0.55);
                _roughMeter += dt * (petSpeed - 1.5) * 0.75;
                if (_roughMeter > 1.0) _startle();
            }
            _idleFor = 0;
        } else {
            _reach = Math.max(0, _reach - dt * 1.2);
        }
        if (held) { arousal = Math.min(1, arousal + dt * 0.25); _idleFor = 0; }   // etología #8
        if (cursorNear) _idleFor = 0; else if (!petActive) _idleFor += dt;

        // ---- camuflaje (etología #7): quieto mucho rato -> se funde con el escritorio ----
        if (_idleFor > camoDelay && camoAmount === 0 && !sleeping && !camoProc.running) _sampleCamo();
        if (camoAmount > 0 && (petActive || cursorNear || arousal > 0.5 || _speaking)) camoAmount = 0;

        // ---- fases derivadas del humor ----
        var breathRate = sleeping ? 0.16 : (0.28 + arousal * 0.95);        // etología #4
        _breathPhase += dt * breathRate * Math.PI * 2;
        _wavePhase += dt * (dancing ? 3.4 : (1.1 + arousal * 1.6 + pleasure * 0.5));
        _colorPhase += dt * (sleeping ? 0.55 : 1.5);

        // ---- cuerpo: flota, respira, mira ----
        var breath = Math.sin(_breathPhase);
        var bob = sleeping ? 0 : Math.sin(_t * 1.05) * (denMode ? 2 : 5);
        octo.position = Qt.vector3d(0, (sleeping ? 26 : 44) + bob, 0);
        octo.eulerRotation = Qt.vector3d(
            headPitch * 6 + (escaping ? -14 : 0),
            headYaw * 15,
            Math.sin(_t * 0.5) * (sleeping ? 0 : 1.6));
        var puls = _speaking ? voiceAmplitude * 0.05 : 0;
        mantle.scale = Qt.vector3d(1 - breath * 0.020 + puls, 1 + breath * 0.038 + puls, 1 - breath * 0.020 + puls);
        siphon.scale = Qt.vector3d(0.16 + Math.max(0, -breath) * 0.05, 0.30, 0.16 + Math.max(0, -breath) * 0.05);

        // ---- ojos: mirada + parpadeo + entrecerrar de gusto ----
        var squint = sleeping ? 0.94 : Math.max(_blink, pleasure > 0.7 ? (pleasure - 0.7) * 1.6 : 0);
        var eyeS = 1 - Math.min(0.94, squint);
        eyeL.scale = Qt.vector3d(1, eyeS, 1);
        eyeR.scale = Qt.vector3d(1, eyeS, 1);
        var px = Math.max(-9, Math.min(9, headYaw * 10));
        var py = Math.max(-6, Math.min(6, -headPitch * 7));
        pupilL.position = Qt.vector3d(px, py, 6);
        pupilR.position = Qt.vector3d(px, py, 6);

        // ---- brazos (etología #2/#3): onda metacrónica + rizo + explorador ----
        var targetAz = (petX - 0.5) * 170;   // azimut hacia el cursor (frente = 0)
        if (_reach > 0.05) {
            var best = 0, bd = 1e9;
            for (var k0 = 0; k0 < 8; k0++) {
                var d0 = Math.abs(_azDelta(_arms[k0].az, targetAz));
                if (d0 < bd) { bd = d0; best = k0; }
            }
            _reachArm = best;
        }
        var curlBase = sleeping ? 1.25 : held ? 1.5 : denMode ? 0.95 : escaping ? -0.3 : 0.62;
        var waveAmp = sleeping ? 0.02 : held ? 0.03 : escaping ? 0.05
                      : dancing ? 0.30 : (0.10 + pleasure * 0.08 + arousal * 0.05);
        for (var k = 0; k < 8; k++) {
            var A = _arms[k];
            var isReach = (k === _reachArm) && _reach > 0.05 && !sleeping && !held && !escaping;
            var wander = (k === _wanderArm) ? Math.sin(Math.min(1, _wanderT / 0.8) * Math.PI) : 0;
            var curl = curlBase * (1 - (isReach ? _reach * 0.9 : 0)) - wander * 0.35;
            var amp = waveAmp * (1 + wander * 1.6) * (isReach ? 0.4 : 1);
            // el brazo explorador gira hacia el cursor
            var az = A.az;
            if (isReach) az = A.az + _azDelta(A.az, targetAz) * _reach * 0.8;
            A.root.eulerRotation = Qt.vector3d(0, az, 0);
            _poseArm(A, curl, amp, isReach ? _reach : 0, escaping);
        }
        if (_wanderArm >= 0) { _wanderT += dt; if (_wanderT > 3.5) _wanderArm = -1; }

        // ---- cromatóforos (etología #1/#6): cada 2 frames ----
        if (_frame % 2 === 0) _composeColors();
    }

    function _azDelta(a, b) { var d = (b - a) % 360; if (d > 180) d -= 360; if (d < -180) d += 360; return d; }

    // Coloca los segmentos de un brazo sobre una curva paramétrica (plano local del brazo:
    // x = hacia afuera, y = arriba). El pulpo real reposa con los brazos desplegados y las
    // PUNTAS enroscadas en espiral hacia arriba — curvatura positiva creciente hacia la punta.
    function _poseArm(A, curl, amp, reach, streamline) {
        var x = 54, y = 0;                                   // arranque: borde del cuerpo
        var a = streamline ? 1.25 : (-0.74 + reach * 0.62);  // sale hacia afuera-abajo; huida: arriba
        var floorY = -74;
        var curlEff = curl * (1 - reach * 0.85);             // extendido hacia el cursor = casi recto
        for (var i = 0; i < _segsPerArm; i++) {
            var t = i / (_segsPerArm - 1);
            var L = 29 - i * 1.6;
            var kappa = streamline ? 0.02
                      : 0.085 + curlEff * 0.30 * Math.pow(t, 1.4)          // espiral concentrada en la punta
                      + Math.sin(_wavePhase - i * 0.8 + A.ph) * amp * 0.5
                      + reach * t * 0.10;                                   // la punta busca la "mano"
            a += kappa;
            var nx = x + L * Math.cos(a);
            var ny = y + L * Math.sin(a);
            if (ny < floorY) {                               // el suelo lo endereza (reposa en el piso)
                a = Math.abs(a) < 0.5 ? a * 0.4 : a * 0.55;
                nx = x + L * Math.cos(a);
                ny = Math.max(floorY, y + L * Math.sin(a));
            }
            var seg = A.segs[i];
            seg.position = Qt.vector3d((x + nx) / 2, (y + ny) / 2, 0);
            seg.eulerRotation = Qt.vector3d(0, 0, a * 180 / Math.PI);
            x = nx; y = ny;
        }
    }

    function _composeColors() {
        // color base derivado del humor
        var c = _mix(cPale, cCoral, pleasure * 0.85 + (dancing ? 0.2 : 0));
        c = _mix(c, cDark, Math.max(0, arousal - 0.38) * 1.5);
        if (_deimatic > 0) c = _mix(c, cFlash, Math.min(1, _deimatic * 1.6));
        c = _mix(c, camoColor, camoAmount * 0.85);
        if (sleeping) {                                       // sueña en colores (etología #6)
            var dp = _colorPhase * 0.35;
            var di = Math.floor(dp) % 3;
            var dmix = _mix(cDream[di], cDream[(di + 1) % 3], dp - Math.floor(dp));
            c = _mix(_dim(c, 0.25), dmix, 0.4 + 0.25 * Math.sin(_colorPhase * 0.7));
        }
        var glow = _speaking ? voiceAmplitude * 0.20 : 0;
        // profundidad de la onda "passing cloud": jugando/cazando/bailando se marca más
        var depth = sleeping ? 0.16 : (0.10 + arousal * 0.16 + (dancing ? 0.14 : 0));
        var j, w;
        for (j = 0; j < _layers.length; j++) {
            w = 0.5 + 0.5 * Math.sin(_colorPhase - j * 0.5);
            var lc = _dim(c, depth * w - glow);
            lc = _mix(lc, Qt.rgba(1, 1, 1, 1), 0.05 * (j / _layers.length));   // coronilla más clara
            _layers[j].mat.baseColor = lc;
        }
        for (j = 0; j < _studs.length; j++) _studs[j].mat.baseColor = _mix(c, Qt.rgba(1, 1, 1, 1), 0.12);
        for (var k = 0; k < 8; k++) {
            var A = _arms[k];
            for (var i = 0; i < _segsPerArm; i++) {
                w = 0.5 + 0.5 * Math.sin(_colorPhase - (i + 3) * 0.55 + A.ph);
                A.segs[i].mat.baseColor = _dim(c, depth * w - glow);
            }
        }
        siphonMat.baseColor = _dim(c, 0.18);
    }

    // ---- susto -> deimático + tinta + huida a chorro (etología #5) ----
    function _startle() {
        if (escaping) return;
        _roughMeter = 0;
        arousal = 1;
        pleasure = Math.max(0, pleasure - 0.35);
        _deimatic = 1;
        camoAmount = 0;
        _sfx("startle", 0.9);
        inkEmitter.burst(42);
        inkDelay.restart();
        escaping = true;
        escapeEnd.restart();
        console.log("miiamia[otto]: ¡susto! tinta y huida a chorro");
    }
    Timer { id: inkDelay; interval: 260; onTriggered: { backend._sfx("ink", 0.8); jetDelay.restart(); } }
    Timer { id: jetDelay; interval: 180; onTriggered: { backend._sfx("jet", 0.9); backend.jetEscape(); } }
    Timer { id: escapeEnd; interval: 1500; onTriggered: backend.escaping = false }

    // ---- parpadeo irregular ----
    Timer {
        running: backend.visible && !backend.sleeping
        interval: 2600; repeat: true
        onTriggered: { blinkAnim.restart(); interval = 2200 + Math.round(Math.random() * 4200); }
    }
    SequentialAnimation {
        id: blinkAnim
        NumberAnimation { target: backend; property: "_blink"; to: 1; duration: 70 }
        PauseAnimation { duration: 60 }
        NumberAnimation { target: backend; property: "_blink"; to: 0; duration: 110 }
    }

    // ---- brazo errante: de vez en cuando un brazo explora solo (etología #2) ----
    Timer {
        running: backend.visible && !backend.sleeping && !backend.held
        interval: 9000; repeat: true
        onTriggered: {
            interval = 7000 + Math.round(Math.random() * 9000);
            backend._wanderArm = Math.floor(Math.random() * 8);
            backend._wanderT = 0;
        }
    }

    // ---- sonidos de su mundo (etología #10) ----
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

    onPetActiveChanged: if (petActive && !escaping) _sfxCooldown("pop", 0.7, 8000)
    onSleepingChanged: _sfxCooldown(sleeping ? "sleep" : "pop", 0.6, 4000)
    onCursorNearChanged: if (cursorNear && !petActive) _sfxCooldown("hello", 0.6, 45000)

    // ---- camuflaje: muestrea el color medio del escritorio ----
    function _sampleCamo() {
        var mon = monitorName !== "" ? ("-o '" + monitorName + "' ") : "";
        camoProc.command = ["bash", "-lc",
            "grim " + mon + "-t png - | magick - -resize 1x1 -depth 8 txt:- | tail -1"];
        camoProc.running = true;
    }
    Process {
        id: camoProc
        stdout: StdioCollector {
            id: camoOut
            onStreamFinished: {
                var m = camoOut.text.match(/#([0-9A-Fa-f]{6})/);
                if (!m) return;
                backend.camoColor = "#" + m[1];
                backend.camoAmount = 0.8;
                console.log("miiamia[otto]: camuflaje -> #" + m[1]);
            }
        }
    }
    Behavior on camoAmount { NumberAnimation { duration: 4000; easing.type: Easing.InOutSine } }
}
