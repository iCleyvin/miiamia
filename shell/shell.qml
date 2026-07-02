// shell.qml — punto de entrada de miiamia (se ejecuta con `quickshell -p ~/miiamia/shell`).
//
// Carga el personaje activo (settings.json) y monta su ventana overlay (Pet.qml) junto con
// el chat, los ajustes, el cerebro (AIBackend), la voz (VoiceManager) y la vista automática.
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: app

    readonly property string activeCharacter:
        (settings.active_character && settings.active_character.length > 0) ? settings.active_character : "kira"

    // Quickshell.shellDir = ruta REAL del dir que contiene shell.qml (.../miiamia/shell).
    // (Qt.resolvedUrl resuelve contra el FS virtual interno qrc:/, no sirve para archivos.)
    readonly property string projectRoot: Quickshell.shellDir.replace(/\/shell$/, "")
    readonly property string charDirPath: projectRoot + "/characters/" + activeCharacter

    // URL (file://) del directorio del personaje — para que AnimatedSprite resuelva imagenes.
    // NO reactiva sobre activeCharacter: la fija loadCharacter() JUNTO al manifest, para que el
    // directorio y el manifest cambien de forma atómica (si no, characterDir cambia antes que el
    // manifest y el backend viejo intenta cargar rutas inexistentes -> "mancha").
    property url characterDir: "file://" + charDirPath + "/"

    // IO nativo de Quickshell (XMLHttpRequest sobre archivos locales esta deshabilitado).
    FileView {
        id: manifestFile
        blockLoading: true   // lectura sincrona de la carga INICIAL
        // Los cambios de path EN VIVO cargan async con solo blockLoading -> text() devolvía el
        // manifest VIEJO al cambiar de skin desde el menú (bug "mancha"). blockAllReads bloquea
        // también las relecturas por cambio de path. Verificado con harness offscreen.
        blockAllReads: true
    }

    // Manifest del personaje activo. Se recarga EN VIVO al cambiar de skin (no es binding).
    property var manifest: ({ animations: {}, scale: 2.0, defaultState: "idle" })
    function loadCharacter() {
        // Derivar las rutas LOCALMENTE de activeCharacter: las properties encadenadas
        // (charDirPath) pueden leerse STALE dentro del handler de cambio — verificado con
        // harness: devolvían la ruta del skin ANTERIOR (mitad del bug "mancha").
        var dir = app.projectRoot + "/characters/" + app.activeCharacter;
        manifestFile.path = dir + "/" + app.activeCharacter + ".json";
        manifestFile.reload();                   // FileView NO releé solo al cambiar path en vivo -> forzar
        try { app.manifest = JSON.parse(manifestFile.text()); }
        catch (e) { console.error("miiamia: manifest inválido", manifestFile.path, "-", e); return; }
        app.characterDir = "file://" + dir + "/";   // dir DESPUÉS del manifest (atómico)
        console.log("miiamia[skin]: char=" + app.activeCharacter + " backend=" + app.manifest.backend + " dir=" + app.characterDir);
    }
    property bool _ready: false
    onActiveCharacterChanged: if (_ready) loadCharacter()   // ignora cambios transitorios de init

    // Índice de skins disponibles (characters/skins.json) para el menú.
    FileView { id: skinsFile; path: projectRoot + "/characters/skins.json"; blockLoading: true }
    readonly property var skinsIndex: {
        try { return JSON.parse(skinsFile.text()); } catch (e) { return [{ id: "kira", label: "Kira" }]; }
    }

    // --- Ajustes del usuario (settings.json), editables desde el menú de configuración (M5) ---
    FileView {
        id: settingsFile
        path: Quickshell.env("HOME") + "/.config/miiamia/settings.json"
        blockLoading: true
    }
    property var settings: _loadSettings()
    function _loadSettings() {
        var s = {};
        try { s = JSON.parse(settingsFile.text()); } catch (e) { s = {}; }
        if (s.scale === undefined) s.scale = 2.0;
        if (!s.voice) s.voice = {};
        if (!s.voice.tts_voice) s.voice.tts_voice = "es_ES-sharvard-medium";
        if (!s.voice.stt_model) s.voice.stt_model = "ggml-base";
        if (!s.voice.language) s.voice.language = "es";
        if (s.monitor === undefined) s.monitor = "";
        if (s.persona === undefined) s.persona = "";
        if (s.custom_model === undefined) s.custom_model = "";
        if (s.active_character === undefined) s.active_character = "kira";
        // Bloque "agent" (cerebro multi-provider + manos). Defaults = comportamiento actual (local, sin tools).
        if (!s.agent) s.agent = {};
        if (s.agent.provider === undefined) s.agent.provider = "local";
        if (s.agent.api_key === undefined) s.agent.api_key = "";
        if (s.agent.base_url === undefined) s.agent.base_url = "";
        if (s.agent.model === undefined) s.agent.model = "";
        if (!s.agent.tools) s.agent.tools = { enabled: false };
        if (s.agent.tools.enabled === undefined) s.agent.tools.enabled = false;
        // Vista automática: la pet mira la pantalla sola y comenta por iniciativa propia.
        if (!s.agent.auto_vision) s.agent.auto_vision = {};
        if (s.agent.auto_vision.enabled === undefined) s.agent.auto_vision.enabled = false;
        if (s.agent.auto_vision.interval_secs === undefined) s.agent.auto_vision.interval_secs = 240;
        if (s.agent.auto_vision.tts === undefined) s.agent.auto_vision.tts = true;
        return s;
    }
    // Provider EFECTIVO (mismo criterio que el daemon): cae a local si está mal configurado.
    // Permite que AIBackend sepa si saltarse el motor local (cloud => 0 RAM/VRAM de modelo).
    readonly property string effectiveProvider: {
        var a = settings.agent || {};
        var p = a.provider || "local";
        if (p === "local") return "local";
        if (p === "claude-cli") return "claude-cli";   // CLI `claude` con login del usuario (sin key)
        if (p === "cloud") return (a.base_url && a.api_key) ? "cloud" : "local";
        return a.api_key ? p : "local";   // claude / opencode
    }
    // Persona activa: la del menú si el usuario la definió; si no, la del personaje.
    readonly property string effectivePersona:
        (settings.persona && settings.persona.length > 0) ? settings.persona
        : (manifest.persona !== undefined ? manifest.persona : "")

    // Voz POR PET: solo si el manifest declara voice.fx (opt-in) se usa su voz/efecto/velocidad
    // propios; si no, se respeta la voz global de ajustes (no toca las demás skins, que traen
    // voice sin fx). Así el dragón suena infernal y lento SOLO para esta pet.
    readonly property var _petVoice:
        (manifest.voice !== undefined && manifest.voice && manifest.voice.fx) ? manifest.voice : null
    readonly property string effectiveTtsVoice:
        (_petVoice && _petVoice.voice) ? _petVoice.voice : settings.voice.tts_voice
    readonly property string effectiveVoiceFx: _petVoice ? _petVoice.fx : ""
    readonly property real effectiveLengthScale:
        (_petVoice && _petVoice.length_scale !== undefined) ? _petVoice.length_scale : 1.0
    function applySetting(path, value) {
        var s = JSON.parse(JSON.stringify(app.settings));   // clon profundo
        var parts = path.split(".");
        var o = s;
        for (var i = 0; i < parts.length - 1; i++) {
            if (o[parts[i]] === undefined) o[parts[i]] = {};
            o = o[parts[i]];
        }
        o[parts[parts.length - 1]] = value;
        app.settings = s;                                   // reasigna -> re-evalúa bindings en vivo
        _saveSettings();
    }
    // Guardado serializado: si el saver sigue corriendo (p.ej. arrastrando el slider de escala),
    // se marca pendiente y se re-guarda al terminar — antes el último cambio podía perderse.
    // El JSON va por STDIN (no argv): puede llevar API keys y argv es visible en /proc.
    property bool _savePending: false
    function _saveSettings() {
        if (saver.running) { _savePending = true; return; }
        saver.running = true;   // onStarted escribe el JSON y cierra stdin
    }
    Process {
        id: saver
        command: ["python3", projectRoot + "/tools/save_settings.py"]
        stdinEnabled: true
        onStarted: {
            saver.write(JSON.stringify(app.settings) + "\n");
            saver.stdinEnabled = false;   // cierra stdin -> el script lee EOF y escribe
        }
        onExited: function (code) {
            saver.stdinEnabled = true;
            if (code !== 0) console.error("miiamia: fallo guardando settings.json (código " + code + ")");
            if (app._savePending) { app._savePending = false; app._saveSettings(); }
        }
    }
    Process {   // re-detecta hardware + descarga el modelo de IA, luego recarga el motor
        id: provisioner
        command: ["bash", projectRoot + "/tools/provision.sh"]
        onExited: function (code) { if (code === 0) ai.reload(); }
    }

    // Motor de contexto: detecta actividad (juego/escritura/navegacion/idle) via Hyprland.
    ContextEngine { id: context }

    // Motor de IA local (M3.5): arranca llama-server bajo demanda segun ai.toml. Sin Ollama.
    AIBackend {
        id: ai
        contextState: context.state
        agentProvider: app.effectiveProvider   // local o cloud; decide si arranca el motor local
        modelOverride: app.settings.custom_model !== undefined ? app.settings.custom_model : ""
        chatOpen: chatWindow.open              // con el chat visible no se apaga por idle
    }

    // Voz (M4): STT (whisper.cpp) + TTS (Piper). Push-to-talk = click derecho sobre la mascota.
    VoiceManager {
        id: voice
        aiUrl: ai.endpoint
        model: "kira"
        persona: app.effectivePersona
        ttsVoice: app.effectiveTtsVoice
        voiceFx: app.effectiveVoiceFx
        lengthScale: app.effectiveLengthScale
        sttModel: app.settings.voice.stt_model
        language: app.settings.voice.language
        onRecordingStarted: ai.ensureRunning()   // calienta el motor mientras hablas
    }
    Connections {
        target: context
        function onStateChanged() { voice.setGaming(context.state === "gaming") }
    }

    // Chat con la mascota. Habla OpenAI /v1 al backend que gestiona AIBackend (embebido u Ollama).
    ChatBubble {
        id: chatWindow
        persona: app.effectivePersona
        charName: app.manifest.name !== undefined ? app.manifest.name : "miiamia"
        aiUrl: ai.endpoint
        backendReady: ai.ready
        model: "kira"
        hasVision: app.effectiveProvider !== "local"   // gate del 👁 (el modelo local no ve)
        monitorName: app.settings.monitor !== undefined ? app.settings.monitor : ""
    }
    Connections {
        target: chatWindow
        function onOpenChanged() { if (chatWindow.open) ai.ensureRunning() }
        function onSent() { ai.ensureRunning() }
        function onOpenSettings() { settingsWindow.open = true }
    }

    // Menú de configuración (M5): aspecto, IA, voz, idioma. Se abre con el ⚙ del chat.
    SettingsWindow {
        id: settingsWindow
        scaleValue: app.settings.scale
        character: app.activeCharacter
        skins: app.skinsIndex
        voice: app.settings.voice.tts_voice
        stt: app.settings.voice.stt_model
        language: app.settings.voice.language
        monitor: app.settings.monitor !== undefined ? app.settings.monitor : ""
        // persona = override GLOBAL del usuario (no la efectiva: precargar la del skin y "Aplicar"
        // la congelaba para todos los personajes). personaHint = la propia del skin, informativa.
        persona: app.settings.persona !== undefined ? app.settings.persona : ""
        personaHint: app.manifest.persona !== undefined ? app.manifest.persona : ""
        customModel: app.settings.custom_model !== undefined ? app.settings.custom_model : ""
        agentProvider: app.settings.agent.provider
        agentHasKey: (app.settings.agent.api_key || "").length > 0
        agentBaseUrl: app.settings.agent.base_url
        agentModel: app.settings.agent.model
        agentToolsEnabled: app.settings.agent.tools.enabled
        aiInfo: "Cerebro: " + (app.effectiveProvider === "local" ? "local (" + ai.backend + ")" : app.effectiveProvider)
                + "  ·  modelo: " + (ai.effectiveModelPath ? ai.effectiveModelPath.split("/").pop() : "—") + "  ·  " + ai.status
        onSetScale: function (v) { app.applySetting("scale", v) }
        onSetCharacter: function (v) { app.applySetting("active_character", v) }
        onSetVoice: function (v) { app.applySetting("voice.tts_voice", v) }
        onSetStt: function (v) { app.applySetting("voice.stt_model", v) }
        onSetLanguage: function (v) { app.applySetting("voice.language", v) }
        onSetMonitor: function (v) { app.applySetting("monitor", v) }
        onSetPersona: function (v) { app.applySetting("persona", v) }
        onSetCustomModel: function (v) { app.applySetting("custom_model", v) }
        onSetProvider: function (v) { app.applySetting("agent.provider", v) }
        onSetApiKey: function (v) { app.applySetting("agent.api_key", v) }
        onSetBaseUrl: function (v) { app.applySetting("agent.base_url", v) }
        onSetModel: function (v) { app.applySetting("agent.model", v) }
        onSetToolsEnabled: function (v) { app.applySetting("agent.tools.enabled", v) }
        onRedetect: provisioner.running = true
    }

    // Vista automática con interacción propia: la pet mira la pantalla cada cierto tiempo (con gating)
    // y suelta un comentario espontáneo -> globo sobre la pet + voz (TTS). Solo con cerebro con visión.
    AutoVision {
        id: autoVision
        aiUrl: ai.endpoint
        persona: app.effectivePersona
        model: "kira"
        enabled: app.settings.agent.auto_vision.enabled === true
        intervalMs: Math.max(60, (app.settings.agent.auto_vision.interval_secs || 240)) * 1000
        providerHasVision: app.effectiveProvider !== "local"
        monitorName: app.settings.monitor !== undefined ? app.settings.monitor : ""
        contextState: context.state
        chatOpen: chatWindow.open
        talking: chatWindow.streaming
        voiceState: voice.voiceState
        backendReady: ai.ready
        onNeedsWarmup: ai.ensureRunning()
        onRemark: function (text) {
            petWindow.bubbleText = text;
            if (app.settings.agent.auto_vision.tts === true) voice.say(text);
        }
    }

    Pet {
        id: petWindow
        petData: app.manifest
        characterDir: app.characterDir
        projectRoot: app.projectRoot
        live2dConf: app.manifest.live2d !== undefined ? app.manifest.live2d : null
        scaleOverride: app.settings.scale
        monitorName: app.settings.monitor !== undefined ? app.settings.monitor : ""
        contextState: context.state
        talking: chatWindow.streaming
        voiceState: voice.voiceState
        voiceAmplitude: voice.amplitude
        onPetClicked: chatWindow.open = !chatWindow.open
        onVoicePttStart: voice.pttStart()
        onVoicePttStop: voice.pttStop()
        // Saludo espontaneo: cuando acercas el cursor a la pet, saluda (globo + voz dulce).
        onPetApproached: {
            var gs = app.manifest.greetings;
            if (gs && gs.length > 0) {
                var t = gs[Math.floor(Math.random() * gs.length)];
                petWindow.bubbleText = t;
                voice.say(t);
            }
        }
    }

    // Calienta el cerebro (solo el /health del daemon) un par de segundos tras arrancar — ya con
    // ai.toml cargado — para que el primer vistazo automático lo encuentre listo. DEFERIDO a propósito:
    // si corriera antes de _loadConfig, AIBackend creería que es "embedded" y arrancaría llama-server
    // (gastando VRAM) sin necesidad, ya que en claude-cli/nube el cerebro no usa motor local.
    Timer {
        id: autoVisionWarmup
        interval: 2500; repeat: false
        running: app.settings.agent.auto_vision.enabled === true && app.effectiveProvider !== "local"
        onTriggered: ai.ensureRunning()
    }

    Component.onCompleted: {
        _ready = true;
        loadCharacter();
        console.log("miiamia: personaje activo =", activeCharacter,
            "| manifest:", (manifest.name !== undefined ? manifest.name : "FALLO"));
    }
}
