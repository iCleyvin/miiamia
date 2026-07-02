// Model3DBackend.qml — waifu ANIME 3D (modelo VRM/glTF) via Qt Quick 3D, backend in-process.
//
// Es un backend mas, analogo a SpriteBackend/DragonRigV3Backend: expone la MISMA API que consume
// Pet.qml (characterDir, scale, currentState, talking, voiceAmplitude, headYaw, headPitch) + los
// mapas de indices del manifest. Da VIDA moviendo morph targets (cara) y rotando joints (huesos).
//
// VERIFICADO en este equipo (Qt 6.11.1 + Quickshell 0.3.0 + assimp 6.0.5) con Vivi.vrm (CC0):
//  - RuntimeLoader carga el VRM/GLB (source file:// ABSOLUTO; Qt.resolvedUrl da qrc:/ y falla).
//  - La cara = el Model con mas morphTargets. Vivi: Face tiene 10 primitives x 41 targets = 410
//    morphTargets -> un morph logico t (0..40) se aplica en las 10 copias: t, t+41, ... t+41*9.
//  - Model.skin.joints[i].eulerRotation es escribible y deforma el mesh skinneado (skin.joints=152).
//  - objectName sale VACIO en todo el arbol (bug Qt Forum 156984) -> TODO se direcciona POR INDICE.
//  - VRM 0.x mira -Z -> modelYaw=180 voltea la cara hacia la camara (+Z).
import QtQuick
import QtQuick3D
import QtQuick3D.AssetUtils

Item {
    id: backend

    // --- API que consume Pet.qml (identica a los otros backends) ---
    required property url characterDir
    property real scale: 2.0
    property string currentState: "idle"
    property bool talking: false
    property string voiceState: "idle"         // idle | listening | thinking | speaking
    property string lifeMode: ""               // "", phone, sit, dance
    property real voiceAmplitude: 0.0        // 0..1 lip-sync
    property real headYaw: 0                  // -1 (izq) .. 1 (der)
    property real headPitch: 0                // -1 (arriba) .. 1 (abajo)
    property real cursorProximity: 0.0         // 0..1, continuo; 1 = cursor sobre/cerca del cuerpo

    // --- config del modelo: TODO el objeto manifest.model3d en UNA propiedad. Los campos se
    //     derivan por dentro con defaults (Vivi VRM 0.x). Pasar el objeto entero evita el fallo
    //     de bindear cada sub-objeto var por separado desde el padre (daban undefined). ---
    property var config: null
    readonly property string modelPath:  (config && config.model    !== undefined) ? config.model    : ""
    readonly property int    ftPerPrim:  (config && config.ftPerPrim !== undefined) ? config.ftPerPrim : 41
    readonly property real   modelYaw:   (config && config.modelYaw  !== undefined) ? config.modelYaw  : 180
    readonly property int    yawSign:    (config && config.yawSign   !== undefined) ? config.yawSign   : 1
    readonly property var    morphIdx:   (config && config.morphIdx) ? config.morphIdx
        : ({ blink:12, blink_l:14, blink_r:13, a:29, i:30, u:31, e:32, o:33, angry:0, fun:1, joy:2, sorrow:3, surprised:4 })
    readonly property var    jointIdx:   (config && config.jointIdx) ? config.jointIdx
        : ({ head:18, neck:17, chest:11, upperChest:12, spine:10, hips:1, eyeL:20, eyeR:22,
             leftShoulder:80, leftUpperArm:81, leftLowerArm:82, leftHand:87,
             rightShoulder:108, rightUpperArm:109, rightLowerArm:110, rightHand:115,
             leftUpperLeg:136, leftLowerLeg:145, leftFoot:146,
             rightUpperLeg:149, rightLowerLeg:158, rightFoot:159 })
    readonly property var    hairChains: (config && config.hairChains) ? config.hairChains
        : [[23,24,25],[26,27,28],[29,30,31],[32,33,34],[35,36,37],[38,39,40],[41,42,43],[44,45,46]]
    readonly property var    bustChains: (config && config.bustChains) ? config.bustChains : [[13,14],[15,16]]
    // pose de reposo (una vez al cargar): baja los brazos del T-pose a los costados. [x,y,z] grados.
    readonly property var    armPose:    (config && config.armPose) ? config.armPose
        : ({ leftUpperArm:[0,0,58], leftLowerArm:[6,0,12], rightUpperArm:[0,0,-58], rightLowerArm:[6,0,-12] })
    // realce de curvas (mujer voluptuosa): factor de escala de huesos de busto y de caderas.
    readonly property var    curves:     (config && config.curves) ? config.curves : ({ bust: 1.0, hip: 1.0 })
    // Movimiento procedural del cuerpo completo. El modelo ya trae esqueleto; estos valores reparten
    // cada gesto por la cadena hips -> spine -> chest -> neck -> head para que no parezcan piezas sueltas.
    readonly property var    motion:     (config && config.motion) ? config.motion : ({
        lookYaw: 24, lookPitch: 16, bodyFollow: 0.34, bodyLag: 0.11,
        idleSway: 1.0, breathTorso: 1.15, armLife: 1.0, rootBob: 0.006
    })

    // --- encuadre camara (del manifest.model3d.cam; calibrable por modelo) ---
    readonly property real camY:     (config && config.cam && config.cam.y     !== undefined) ? config.cam.y     : 1.30
    readonly property real camZ:     (config && config.cam && config.cam.z     !== undefined) ? config.cam.z     : 1.45
    readonly property real camFov:   (config && config.cam && config.cam.fov   !== undefined) ? config.cam.fov   : 30
    readonly property real camPitch: (config && config.cam && config.cam.pitch !== undefined) ? config.cam.pitch : -6

    implicitWidth: 128 * scale
    implicitHeight: 128 * scale

    readonly property url modelUrl: modelPath !== "" ? Qt.url(("" + characterDir) + modelPath) : Qt.url("")

    // refs cacheadas tras cargar
    property var  _faceModel: null
    property var  _skin: null
    property bool _ready: false

    // --- estado de vida ---
    property real _lookYaw: 0
    property real _lookPitch: 0
    Behavior on _lookYaw   { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    Behavior on _lookPitch { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    onHeadYawChanged: {
        var sy = backend.yawSign * headYaw;
        backend._lookYaw = sy;
    }
    onHeadPitchChanged: backend._lookPitch = headPitch

    property real _breath: 0                  // -1..1
    property real _sway: 0                     // fase 0..2pi
    property real _blink: 0                    // 0..1 peso parpadeo
    property real _ampSmooth: 0                // amplitud suavizada (lip-sync)
    property real _yawVel: 0                   // velocidad de giro de cabeza (coleo de pelo)
    property real _prevYaw: 0
    property real _posePrevYaw: 0
    property real _bodyYaw: 0
    property real _bodyPitch: 0
    property real _bodyRoll: 0
    property real _rootBob: 0
    property real _lifeOffsetY: 0
    // expresiones lerpeadas (peso actual)
    property real _exJoy: 0
    property real _exFun: 0
    property real _exSorrow: 0
    // --- interaccion (el cursor cerca la calcula Pet.qml) ---
    property bool cursorNear: false
    property bool _greeting: false
    property bool _greetCd: false             // cooldown del saludo visual (no reaccionar sin parar)
    property real _attention: 0                // cercania/interes suavizado
    property real _tilt: 0                     // ladeo de cabeza (gesto tierno)
    property real _idleJoy: 0                   // sonrisa extra en gestos idle
    property real _greetNod: 0                 // asentimiento corto al saludar
    property real _eyeDartYaw: 0               // micro-saccades anime
    property real _eyeDartPitch: 0
    property real _winkL: 0
    property real _winkR: 0
    property real _speechPulse: 0
    Behavior on _eyeDartYaw   { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
    Behavior on _eyeDartPitch { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
    onCursorNearChanged: if (cursorNear && backend._ready) backend._startGreet()

    readonly property int _breathDur: currentState === "sleeping" ? 3300
        : (currentState === "gaming" || currentState === "music") ? 1500 : 2050
    // "despierta" efectiva: si el cursor esta cerca se activa del todo (parpadeo/sway/gestos)
    // aunque el ContextEngine diga sleeping -> reacciona cuando le pones el mouse cerca.
    readonly property bool awake: currentState !== "sleeping" || cursorNear

    // ---------- helpers ----------
    function _tn(o){ if(!o) return "null"; var s=""+o; var m=s.match(/([A-Za-z0-9_]+)\(0x/); return m?m[1]:s; }
    function _scan(node){
        if (!node) return;
        var t = backend._tn(node);
        if (t.indexOf("Model") >= 0) {
            var mc = node.morphTargets ? node.morphTargets.length : 0;
            var cur = backend._faceModel ? backend._faceModel.morphTargets.length : -1;
            if (mc > cur) backend._faceModel = node;              // el mesh con mas morphs = la cara
            if (!backend._skin && node.skin) backend._skin = node.skin;
        }
        var ch = node.children;
        if (ch) for (var i=0;i<ch.length;i++) backend._scan(ch[i]);
    }
    function setMorph(name, w){
        if (!backend._faceModel || !backend.morphIdx) return;
        var base = backend.morphIdx[name]; if (base === undefined || base < 0) return;
        var mts = backend._faceModel.morphTargets; if (!mts) return;
        var reps = Math.floor(mts.length / backend.ftPerPrim);    // = 10 en Vivi
        if (reps < 1) reps = 1;
        var ww = Math.max(0, Math.min(1, w));
        for (var p=0; p<reps; p++){ var idx = base + p*backend.ftPerPrim; if (idx < mts.length) mts[idx].weight = ww; }
    }
    function _joint(idx){
        if (!backend._skin || idx === undefined || idx < 0) return null;
        var js = backend._skin.joints; return (js && idx < js.length) ? js[idx] : null;
    }
    function rotJoint(name, x, y, z){ if (!backend.jointIdx) return; var j = backend._joint(backend.jointIdx[name]); if (j) j.eulerRotation = Qt.vector3d(x,y,z); }
    function _rotIdx(idx, x, y, z){ var j = backend._joint(idx); if (j) j.eulerRotation = Qt.vector3d(x,y,z); }
    function _lerp(a,b,t){ return a + (b-a)*t; }
    function _mv(k, def){ return (backend.motion && backend.motion[k] !== undefined) ? backend.motion[k] : def; }
    function _armBase(name, axis, def){
        if (!backend.armPose || !backend.armPose[name]) return def;
        return backend.armPose[name][axis] !== undefined ? backend.armPose[name][axis] : def;
    }

    // pose de reposo estatica (brazos abajo): se aplica una vez tras cargar
    function _applyArmPose(){
        if (!backend.armPose) return;
        for (var k in backend.armPose){ var r = backend.armPose[k]; backend.rotJoint(k, r[0], r[1], r[2]); }
    }

    // realce de curvas: escala los huesos de busto (raiz de cada bustChain) y ensancha caderas. Una vez al cargar.
    function _applyCurves(){
        if (!backend.curves) return;
        var bs = backend.curves.bust !== undefined ? backend.curves.bust : 1.0;
        var hp = backend.curves.hip  !== undefined ? backend.curves.hip  : 1.0;
        var bc = backend.bustChains || [];
        for (var i=0;i<bc.length;i++){ var j = backend._joint(bc[i][0]); if (j) j.scale = Qt.vector3d(bs,bs,bs); }
        if (hp !== 1.0 && backend.jointIdx){ var hip = backend._joint(backend.jointIdx.hips); if (hip) hip.scale = Qt.vector3d(hp,1.0,hp); }
    }

    // Saludo visual seguro para VRM: mirada/sonrisa/ladeo. No levantar brazos sin calibrar ejes del rig.
    function _startGreet(){
        if (backend._greetCd || !backend._ready) return;
        backend._greetCd = true; greetCd.restart();
        backend._greeting = true; greetAnim.restart();
        greetNodAnim.restart();
        tiltAnim.restart();
        idleJoyAnim.restart();
        if (Math.random() < 0.40) winkRAnim.restart();
    }

    // ---------- COMPOSE POSE: un punto de escritura por joint por tick ----------
    function _composePose(){
        if (!backend._ready) return;
        // acercar el cursor la DESPIERTA (aunque el contexto diga sleeping): abre ojos y te mira
        var sleeping = currentState === "sleeping" && !backend.cursorNear;
        var listening = backend.voiceState === "listening";
        var thinking = backend.voiceState === "thinking";
        var speaking = talking || backend.voiceState === "speaking";
        var phoneMode = backend.lifeMode === "phone";
        var sitMode = backend.lifeMode === "sit";
        var danceMode = backend.lifeMode === "dance";

        var attTarget = sleeping ? (backend.cursorNear ? 0.85 : 0.0) : backend.cursorProximity;
        if (phoneMode) attTarget = Math.max(attTarget, 0.28);
        if (listening) attTarget = Math.max(attTarget, 0.72);
        if (thinking) attTarget = Math.max(attTarget, 0.42);
        if (speaking) attTarget = Math.max(attTarget, 0.48);
        backend._attention = backend._lerp(backend._attention, Math.max(0, Math.min(1, attTarget)), 0.075);

        // --- expresiones objetivo por estado (lerp suave) ---
        var tJoy = speaking ? 0.24 : (danceMode ? 0.42 : (currentState==="music" ? 0.30 : 0.0));
        if (backend._greeting) tJoy = Math.max(tJoy, 0.55);         // saludo = alegre
        else if (backend.cursorNear && !sleeping) tJoy = Math.max(tJoy, 0.30 + backend._attention * 0.16);  // te acercas = sonrie
        else if (backend._attention > 0.15 && !sleeping) tJoy = Math.max(tJoy, backend._attention * 0.14);
        if (listening) tJoy = Math.max(tJoy, 0.16);
        tJoy = Math.max(tJoy, backend._idleJoy);                    // gesto idle
        var tFun = currentState==="gaming" ? 0.42 : (danceMode ? 0.34 : (thinking ? 0.20 : 0.0));
        var tSor = 0.0;
        backend._exJoy = backend._lerp(backend._exJoy, tJoy, 0.08);
        backend._exFun = backend._lerp(backend._exFun, tFun, 0.08);
        backend._exSorrow = backend._lerp(backend._exSorrow, tSor, 0.08);

        // --- controlador de pose global ---
        var yawMax = backend._mv("lookYaw", 24), pitMax = backend._mv("lookPitch", 16);
        var stateHeadPitch = (currentState==="typing"||currentState==="browsing") ? 7
                           : (currentState==="watching") ? -6
                           : listening ? -3
                           : thinking ? 3
                           : phoneMode ? -8
                           : (sleeping ? 12 : 0);
        var ly = sleeping ? 0 : backend._lookYaw;
        var lp = sleeping ? 0 : backend._lookPitch;
        if (phoneMode && !backend.cursorNear) {
            ly *= 0.35;
            lp = Math.min(lp * 0.35, -0.42);
        }
        var lookYawDeg = ly * yawMax;
        var lookPitchDeg = lp * pitMax;
        var yawDelta = ly - backend._posePrevYaw;
        backend._posePrevYaw = ly;
        backend._yawVel = backend._lerp(backend._yawVel, yawDelta * 10.0, 0.25);

        var idleSway = sleeping ? 0 : Math.sin(backend._sway * 0.72) * backend._mv("idleSway", 1.0);
        var dancePhase = backend._sway * 2.15;
        var musicBounce = danceMode ? Math.sin(dancePhase) * 2.6
                         : currentState === "music" ? Math.sin(backend._sway * 1.8) * 1.4 : 0;
        var listenPulse = listening ? Math.sin(backend._sway * 1.05) * 0.65 : 0;
        var talkPulse = speaking ? backend._ampSmooth * 1.2 : 0;
        var follow = sleeping ? 0 : backend._mv("bodyFollow", 0.34);
        var lag = backend._mv("bodyLag", 0.11);
        backend._bodyYaw = backend._lerp(backend._bodyYaw, lookYawDeg * follow + idleSway * 0.45, lag);
        backend._bodyPitch = backend._lerp(backend._bodyPitch,
            lookPitchDeg * follow * 0.45 + (sleeping ? 7 : 0) + (phoneMode ? -2.0 : 0) + (sitMode ? 3.5 : 0)
            + musicBounce * 0.35 - backend._attention * 1.0 + listenPulse, lag);
        backend._bodyRoll = backend._lerp(backend._bodyRoll,
            backend._tilt * 0.26 - backend._bodyYaw * 0.10 + idleSway + musicBounce * 0.55 + (thinking ? 0.8 : 0), lag);
        backend._lifeOffsetY = backend._lerp(backend._lifeOffsetY, sitMode ? -0.20 : 0, 0.08);
        backend._rootBob = backend._lifeOffsetY + (sleeping ? backend._breath * 0.002
            : Math.sin(backend._sway) * backend._mv("rootBob", 0.006) + backend._breath * 0.0025 + talkPulse * 0.002
              + (danceMode ? Math.abs(Math.sin(dancePhase)) * 0.014 : 0));

        // --- esqueleto axial: cadera y columna guian el cuerpo antes de cuello/cabeza ---
        var breath = backend._breath * backend._mv("breathTorso", 1.15);
        backend.rotJoint("hips", sleeping ? 3 : -breath * 0.10, -backend._bodyYaw * 0.10, -backend._bodyRoll * 0.16);
        backend.rotJoint("spine", backend._bodyPitch * 0.20 + breath * 0.25, backend._bodyYaw * 0.22, backend._bodyRoll * 0.26);
        backend.rotJoint("chest", backend._bodyPitch * 0.34 + breath * 0.55 + talkPulse, backend._bodyYaw * 0.32, backend._bodyRoll * 0.34);
        backend.rotJoint("upperChest", backend._bodyPitch * 0.28 + breath * 0.32, backend._bodyYaw * 0.28, backend._bodyRoll * 0.24);

        // --- mirada: el cuello/cabeza completan lo que ya empezo el torso; ojos solo corrigen fino ---
        backend.rotJoint("neck",
            lookPitchDeg * 0.20 + stateHeadPitch * 0.22 + backend._bodyPitch * 0.12 + backend._greetNod * 1.7,
            lookYawDeg * 0.22 + backend._bodyYaw * 0.12,
            backend._tilt * 0.22 + backend._bodyRoll * 0.10);
        backend.rotJoint("head",
            lookPitchDeg * 0.52 + stateHeadPitch * 0.78 + backend._breath * 0.45 + backend._greetNod * 4.2
                + (phoneMode ? -8.5 : 0) + (danceMode ? Math.sin(dancePhase + 0.6) * 1.1 : 0),
            lookYawDeg * 0.50 + backend._bodyYaw * 0.08 + (danceMode ? Math.sin(dancePhase * 0.5) * 2.0 : 0),
            backend._tilt * 0.78 + backend._bodyRoll * 0.08 + (danceMode ? Math.sin(dancePhase) * 1.6 : 0));
        backend._rotIdx(backend.jointIdx.eyeL,
            lp*6 + backend._eyeDartPitch*7,
            ly*10 + backend._eyeDartYaw*11,
            -backend._bodyRoll*0.12);
        backend._rotIdx(backend.jointIdx.eyeR,
            lp*6 + backend._eyeDartPitch*7,
            ly*10 + backend._eyeDartYaw*11,
            -backend._bodyRoll*0.12);

        // --- brazos: reposo vivo que hereda el pulso del torso ---
        var armLife = sleeping ? 0.28 : backend._mv("armLife", 1.0) + backend._attention * 0.18;
        var armSwing = Math.sin(backend._sway * 0.85) * armLife;
        var danceArm = danceMode ? Math.sin(dancePhase) * 7.0 : 0;
        var phoneArm = 0;
        backend.rotJoint("leftShoulder", 0, 0, 0);
        backend.rotJoint("rightShoulder", 0, 0, 0);
        backend.rotJoint("leftUpperArm",
            backend._armBase("leftUpperArm", 0, 0) + breath * 0.18 + phoneArm * 10 + (danceMode ? Math.sin(dancePhase + 0.3) * 3 : 0),
            backend._armBase("leftUpperArm", 1, 0) - backend._bodyYaw * 0.10 + phoneArm * 5,
            backend._armBase("leftUpperArm", 2, 58) + armSwing * 0.9 + backend._bodyRoll * 0.16 - phoneArm * 32 + danceArm);
        backend.rotJoint("leftLowerArm",
            backend._armBase("leftLowerArm", 0, 6) + armSwing * 0.7 + phoneArm * 32,
            backend._armBase("leftLowerArm", 1, 0) + phoneArm * -12,
            backend._armBase("leftLowerArm", 2, 12) + armSwing * 0.45 + phoneArm * 12);
        backend.rotJoint("rightUpperArm",
            backend._armBase("rightUpperArm", 0, 0) + breath * 0.18 + phoneArm * 10 + (danceMode ? Math.sin(dancePhase + 2.2) * 3 : 0),
            backend._armBase("rightUpperArm", 1, 0) - backend._bodyYaw * 0.10 + phoneArm * -5,
            backend._armBase("rightUpperArm", 2, -58) - armSwing * 0.9 + backend._bodyRoll * 0.16 + phoneArm * 32 - danceArm);
        backend.rotJoint("rightLowerArm",
            backend._armBase("rightLowerArm", 0, 6) - armSwing * 0.7 + phoneArm * 32,
            backend._armBase("rightLowerArm", 1, 0) + phoneArm * 12,
            backend._armBase("rightLowerArm", 2, -12) - armSwing * 0.45 - phoneArm * 12);

        // --- piernas: modo sentado discreto; se mantiene suave para evitar poses imposibles si el eje varia ---
        backend.rotJoint("leftUpperLeg", sitMode ? -28 : 0, 0, sitMode ? 5 : 0);
        backend.rotJoint("rightUpperLeg", sitMode ? -28 : 0, 0, sitMode ? -5 : 0);
        backend.rotJoint("leftLowerLeg", sitMode ? 38 : 0, 0, 0);
        backend.rotJoint("rightLowerLeg", sitMode ? 38 : 0, 0, 0);
        backend.rotJoint("leftFoot", sitMode ? -12 : 0, 0, 0);
        backend.rotJoint("rightFoot", sitMode ? -12 : 0, 0, 0);

        // --- pelo + busto (spring-bone aproximado: seno con desfase + reaccion al giro) ---
        var drive = sleeping ? 0 : backend._yawVel * 7.0;
        var js = backend._skin ? backend._skin.joints : null;
        var hairC = backend.hairChains || [], bustC = backend.bustChains || [];
        if (js){
            var swayAmp = sleeping ? 0.3 : 1.0;
            for (var c=0;c<hairC.length;c++){
                var chain = hairC[c];
                for (var k=0;k<chain.length;k++){
                    var j = js[chain[k]]; if (!j) continue;
                    var ph = backend._sway + k*0.6 + c*1.1, amp = (1.4 + k*1.0) * swayAmp;
                    j.eulerRotation = Qt.vector3d(Math.sin(ph)*amp*0.5,
                                                  Math.sin(ph*0.8)*amp + drive*(k+1)*0.18,
                                                  Math.cos(ph)*amp);
                }
            }
            // busto: rebote sutil (seno lento + reaccion), SFW discreto
            for (var b=0;b<bustC.length;b++){
                var bc = bustC[b];
                for (var m=0;m<bc.length;m++){
                    var jb = js[bc[m]]; if (!jb) continue;
                    var bph = backend._sway*0.5 + m*0.5 + b*0.4;
                    var bamp = (0.8 + m*0.6) * swayAmp;
                    jb.eulerRotation = Qt.vector3d(Math.sin(bph)*bamp + drive*0.15, 0, Math.cos(bph)*bamp*0.4);
                }
            }
        }

        // --- cara: parpadeo + lip-sync + expresiones ---
        backend.setMorph("blink", sleeping ? 1.0 : backend._blink);
        // lip-sync: energia -> boca 'a' (con pseudo-vocal por bandas para mas vida)
        if (speaking || backend.voiceAmplitude > 0.02){
            backend._ampSmooth = backend._lerp(backend._ampSmooth, Math.max(0,Math.min(1,backend.voiceAmplitude)), 0.35);
            var e = Math.max(backend._ampSmooth, speaking ? backend._speechPulse * 0.28 : 0);
            backend.setMorph("a", e*0.85);
            backend.setMorph("i", e < 0.35 ? e*0.4 : 0);
            backend.setMorph("o", e > 0.6 ? (e-0.6)*0.7 : 0);
        } else {
            backend._ampSmooth = backend._lerp(backend._ampSmooth, 0, 0.4);
            backend.setMorph("a", 0); backend.setMorph("i", 0); backend.setMorph("o", 0);
        }
        backend.setMorph("blink_l", sleeping ? 0 : backend._winkL);
        backend.setMorph("blink_r", sleeping ? 0 : backend._winkR);
        backend.setMorph("joy", backend._exJoy);
        backend.setMorph("fun", backend._exFun);
        backend.setMorph("sorrow", backend._exSorrow);
    }

    onModelUrlChanged: { backend._ready = false; backend._faceModel = null; backend._skin = null; }

    // ---------- View3D (overlay transparente VERIFICADO) ----------
    View3D {
        id: view3d
        anchors.fill: parent
        renderMode: View3D.Offscreen
        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Transparent
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: currentState === "gaming" ? SceneEnvironment.Medium : SceneEnvironment.High
        }
        PerspectiveCamera {
            id: cam
            position: Qt.vector3d(0, backend.camY, backend.camZ)
            eulerRotation.x: backend.camPitch
            fieldOfView: backend.camFov
            clipNear: 0.05; clipFar: 50
        }
        DirectionalLight { eulerRotation.x: -25; eulerRotation.y: -20; brightness: 1.2 }
        DirectionalLight { eulerRotation.x: -8;  eulerRotation.y: 160; brightness: 0.55 }

        RuntimeLoader {
            id: loader
            source: backend.modelUrl
            position: Qt.vector3d(0, backend._rootBob, 0)
            eulerRotation.y: backend.modelYaw
            onStatusChanged: {
                if (status === RuntimeLoader.Success) {
                    backend._faceModel = null; backend._skin = null;
                    backend._scan(loader);
                    backend._ready = (backend._skin !== null || backend._faceModel !== null);
                    console.log("miiamia[model3d]:", backend.modelPath, "listo — morphs=" +
                        (backend._faceModel ? backend._faceModel.morphTargets.length : -1) +
                        " joints=" + (backend._skin ? backend._skin.joints.length : -1));
                    if (backend._ready) { backend._applyArmPose(); backend._applyCurves(); Qt.callLater(backend._composePose); }
                } else if (status === RuntimeLoader.Error) {
                    console.warn("Model3DBackend: error al cargar", backend.modelUrl, "-", errorString);
                    backend._ready = false;
                }
            }
        }

        // Props 3D integrados en la misma escena/camara. No son overlays 2D: comparten luz,
        // perspectiva y bob con el cuerpo. Se mantienen discretos hasta tener sockets por hueso.
        Node {
            id: phone3d
            visible: backend.lifeMode === "phone"
            position: Qt.vector3d(0.04, 0.96 + backend._rootBob, 0.34)
            eulerRotation.x: -10
            eulerRotation.y: -8
            eulerRotation.z: -6
            Model {
                source: "#Cube"
                scale: Qt.vector3d(0.00135, 0.00225, 0.00012)
                materials: PrincipledMaterial {
                    baseColor: "#101018"
                    roughness: 0.42
                    metalness: 0.08
                }
            }
            Model {
                source: "#Cube"
                position: Qt.vector3d(0, 0, 0.012)
                scale: Qt.vector3d(0.00110, 0.00188, 0.00003)
                materials: PrincipledMaterial {
                    baseColor: "#1c2438"
                    roughness: 0.6
                }
            }
            Model {
                source: "#Cube"
                position: Qt.vector3d(0, 0.032, 0.016)
                scale: Qt.vector3d(0.00055, 0.000035, 0.000025)
                materials: PrincipledMaterial { baseColor: "#c79cff"; roughness: 0.35 }
            }
            Model {
                source: "#Cube"
                position: Qt.vector3d(0.003, -0.018, 0.016)
                scale: Qt.vector3d(0.00042, 0.000035, 0.000025)
                materials: PrincipledMaterial { baseColor: "#93d8ff"; roughness: 0.35 }
            }
        }

        Node {
            id: headphones3d
            visible: backend.lifeMode === "dance"
            position: Qt.vector3d(0, 1.50 + backend._rootBob, 0.04)
            eulerRotation.z: Math.sin(backend._sway * 2.15) * 2.0
            Model {
                source: "#Sphere"
                position: Qt.vector3d(-0.15, -0.01, 0.04)
                scale: Qt.vector3d(0.00062, 0.00078, 0.00036)
                materials: PrincipledMaterial { baseColor: "#f4b4cf"; roughness: 0.35 }
            }
            Model {
                source: "#Sphere"
                position: Qt.vector3d(0.15, -0.01, 0.04)
                scale: Qt.vector3d(0.00062, 0.00078, 0.00036)
                materials: PrincipledMaterial { baseColor: "#f4b4cf"; roughness: 0.35 }
            }
            Model {
                source: "#Sphere"
                position: Qt.vector3d(-0.15, -0.01, 0.065)
                scale: Qt.vector3d(0.00035, 0.00045, 0.00016)
                materials: PrincipledMaterial { baseColor: "#384053"; roughness: 0.65 }
            }
            Model {
                source: "#Sphere"
                position: Qt.vector3d(0.15, -0.01, 0.065)
                scale: Qt.vector3d(0.00035, 0.00045, 0.00016)
                materials: PrincipledMaterial { baseColor: "#384053"; roughness: 0.65 }
            }
        }

        Node {
            id: cushion3d
            visible: backend.lifeMode === "sit"
            position: Qt.vector3d(0, 0.36 + backend._rootBob, 0.02)
            Model {
                source: "#Cube"
                scale: Qt.vector3d(0.0032, 0.00042, 0.00155)
                materials: PrincipledMaterial {
                    baseColor: "#7d5aa8"
                    roughness: 0.78
                }
            }
            Model {
                source: "#Cube"
                position: Qt.vector3d(0, 0.034, 0.02)
                scale: Qt.vector3d(0.0023, 0.00008, 0.00105)
                materials: PrincipledMaterial {
                    baseColor: "#b896df"
                    roughness: 0.7
                }
            }
        }
    }

    // ---------- motores de vida (gateados por estado) ----------
    Timer {   // tick de composicion ~30fps (66ms dormida)
        running: backend._ready
        interval: currentState === "sleeping" ? 66 : 33
        repeat: true
        onTriggered: backend._composePose()
    }
    SequentialAnimation on _breath {
        running: backend._ready
        loops: Animation.Infinite
        NumberAnimation { from:-1; to:1; duration: backend._breathDur; easing.type: Easing.InOutSine }
        NumberAnimation { from:1; to:-1; duration: backend._breathDur; easing.type: Easing.InOutSine }
    }
    SequentialAnimation on _speechPulse {
        running: backend._ready && (backend.talking || backend.voiceState === "speaking")
        loops: Animation.Infinite
        NumberAnimation { from:0.15; to:1; duration: 95; easing.type: Easing.OutQuad }
        NumberAnimation { from:1; to:0.1; duration: 120; easing.type: Easing.InQuad }
    }
    // Fase CONTINUA (sin wrap): antes era NumberAnimation 0->2π en loop, y como los consumidores
    // usan múltiplos no enteros de la fase (sin(_sway*0.72), pelo *0.8, dance *2.15...), el salto
    // 2π->0 daba un tirón visible del pelo/audífonos cada 2.6 s. Acumular no envuelve nunca.
    FrameAnimation {
        running: backend._ready && backend.awake
        onTriggered: backend._sway += frameTime * 2.4166   // 2π/2.6s = misma velocidad que antes
    }
    Timer { running: backend._ready; interval: 120; repeat: true; onTriggered: backend._yawVel *= 0.8 }
    // parpadeo esporadico (dormida = blink fijo 1 via _composePose)
    Timer {
        id: blinkTimer
        running: backend._ready && backend.awake
        interval: 2800; repeat: true
        onTriggered: { blinkAnim.restart(); interval = 2000 + Math.round(Math.random()*3600); }
    }
    SequentialAnimation {
        id: blinkAnim
        NumberAnimation { target: backend; property:"_blink"; to:1; duration:70;  easing.type:Easing.InQuad }
        PauseAnimation  { duration: 55 }
        NumberAnimation { target: backend; property:"_blink"; to:0; duration:110; easing.type:Easing.OutQuad }
    }

    // --- saludo visual: expresion/torso, sin brazo alto hasta calibrar ejes por modelo ---
    PauseAnimation {
        id: greetAnim
        duration: 1800
        onFinished: backend._greeting = false
    }
    SequentialAnimation {
        id: greetNodAnim
        NumberAnimation { target: backend; property:"_greetNod"; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: backend; property:"_greetNod"; to: -0.25; duration: 180; easing.type: Easing.InOutSine }
        NumberAnimation { target: backend; property:"_greetNod"; to: 0; duration: 260; easing.type: Easing.OutCubic }
    }
    Timer { id: greetCd; interval: 9000; onTriggered: backend._greetCd = false }

    // --- micro-saccades: ojos vivos, mas activos cuando esta atenta o escuchando ---
    Timer {
        id: eyeDartTimer
        running: backend._ready && backend.awake
        interval: 900
        repeat: true
        onTriggered: {
            interval = 700 + Math.round(Math.random() * (backend._attention > 0.4 ? 900 : 1800));
            var amp = backend._attention > 0.25 ? 0.09 : 0.045;
            backend._eyeDartYaw = (Math.random() * 2 - 1) * amp;
            backend._eyeDartPitch = (Math.random() * 2 - 1) * amp * 0.65;
        }
    }

    // --- ladeo tierno de cabeza (gesto) ---
    SequentialAnimation {
        id: tiltAnim
        NumberAnimation { target: backend; property:"_tilt"; to: 9;  duration: 520; easing.type: Easing.OutCubic }
        PauseAnimation  { duration: 750 }
        NumberAnimation { target: backend; property:"_tilt"; to: 0;  duration: 620; easing.type: Easing.InOutSine }
    }
    // --- sonrisa espontanea (gesto idle) ---
    SequentialAnimation {
        id: idleJoyAnim
        NumberAnimation { target: backend; property:"_idleJoy"; to: 0.4; duration: 500 }
        PauseAnimation  { duration: 1500 }
        NumberAnimation { target: backend; property:"_idleJoy"; to: 0;   duration: 800 }
    }
    SequentialAnimation {
        id: winkLAnim
        NumberAnimation { target: backend; property:"_winkL"; to: 1; duration: 80; easing.type: Easing.InQuad }
        PauseAnimation  { duration: 70 }
        NumberAnimation { target: backend; property:"_winkL"; to: 0; duration: 130; easing.type: Easing.OutQuad }
    }
    SequentialAnimation {
        id: winkRAnim
        NumberAnimation { target: backend; property:"_winkR"; to: 1; duration: 80; easing.type: Easing.InQuad }
        PauseAnimation  { duration: 70 }
        NumberAnimation { target: backend; property:"_winkR"; to: 0; duration: 130; easing.type: Easing.OutQuad }
    }
    Timer {
        id: winkTimer
        running: backend._ready && backend.awake && !talking && backend.voiceState === "idle"
        interval: 11000
        repeat: true
        onTriggered: {
            interval = 10000 + Math.round(Math.random() * 14000);
            if (backend.cursorProximity > 0.35 && Math.random() < 0.45)
                (Math.random() < 0.5 ? winkLAnim : winkRAnim).restart();
        }
    }
    // "hace cosas sola": cada ~14-26s (despierta, sin saludar) hace un gesto aleatorio
    Timer {
        id: idleGestures
        running: backend._ready && backend.awake && currentState !== "gaming"
        interval: 6000; repeat: true
        onTriggered: {
            interval = 14000 + Math.round(Math.random()*12000);
            var r = Math.random();
            if (r < 0.42) tiltAnim.restart();         // ladea la cabeza
            else if (r < 0.82) idleJoyAnim.restart(); // sonrie
            else (Math.random() < 0.5 ? winkLAnim : winkRAnim).restart();
        }
    }
}
