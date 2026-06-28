// shell.qml — punto de entrada de miiamia (se ejecuta con `quickshell -p ~/miiamia/shell`).
//
// Carga el personaje activo y monta su ventana overlay (Pet.qml).
// M1: el personaje activo esta fijo en "kira". En M2 se leera de config/miiamia.toml
// (lo expone el daemon Python de contexto, que tambien empuja el estado por D-Bus).
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: app

    property string activeCharacter: "kira"

    // Quickshell.shellDir = ruta REAL del dir que contiene shell.qml (.../miiamia/shell).
    // (Qt.resolvedUrl resuelve contra el FS virtual interno qrc:/, no sirve para archivos.)
    readonly property string projectRoot: Quickshell.shellDir.replace(/\/shell$/, "")
    readonly property string charDirPath: projectRoot + "/characters/" + activeCharacter

    // URL (file://) del directorio del personaje — para que AnimatedSprite resuelva imagenes.
    readonly property url characterDir: "file://" + charDirPath + "/"
    // Ruta de filesystem del manifest — FileView usa path, no url.
    readonly property string manifestPath: charDirPath + "/" + activeCharacter + ".json"

    // IO nativo de Quickshell (XMLHttpRequest sobre archivos locales esta deshabilitado).
    FileView {
        id: manifestFile
        path: app.manifestPath
        blockLoading: true   // lectura sincrona: el manifest esta listo al construir la mascota
    }

    readonly property var manifest: {
        try {
            return JSON.parse(manifestFile.text());
        } catch (e) {
            console.error("miiamia: no pude cargar el manifest", manifestPath, "-", e);
            // Fallback minimo para no romper el arbol; la mascota simplemente no se ve.
            return { animations: {}, scale: 2.0, defaultState: "idle" };
        }
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
        if (s.scale === undefined) s.scale = (manifest.scale !== undefined ? manifest.scale : 2.0);
        if (!s.voice) s.voice = {};
        if (!s.voice.tts_voice) s.voice.tts_voice =
            (manifest.voice && manifest.voice.voice) ? manifest.voice.voice : "es_ES-sharvard-medium";
        if (!s.voice.stt_model) s.voice.stt_model = "ggml-base";
        if (!s.voice.language) s.voice.language = "es";
        if (s.monitor === undefined) s.monitor = "";
        if (s.persona === undefined) s.persona = "";
        if (s.custom_model === undefined) s.custom_model = "";
        return s;
    }
    // Persona activa: la del menú si el usuario la definió; si no, la del personaje.
    readonly property string effectivePersona:
        (settings.persona && settings.persona.length > 0) ? settings.persona
        : (manifest.persona !== undefined ? manifest.persona : "")
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
        saver.command = ["python3", projectRoot + "/tools/save_settings.py", JSON.stringify(s)];
        saver.running = true;
    }
    Process { id: saver }
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
        modelOverride: app.settings.custom_model !== undefined ? app.settings.custom_model : ""
    }

    // Voz (M4): STT (whisper.cpp) + TTS (Piper). Push-to-talk = click derecho sobre la mascota.
    VoiceManager {
        id: voice
        aiUrl: ai.endpoint
        model: "kira"
        persona: app.effectivePersona
        ttsVoice: app.settings.voice.tts_voice
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
        voice: app.settings.voice.tts_voice
        stt: app.settings.voice.stt_model
        language: app.settings.voice.language
        monitor: app.settings.monitor !== undefined ? app.settings.monitor : ""
        persona: app.effectivePersona
        customModel: app.settings.custom_model !== undefined ? app.settings.custom_model : ""
        aiInfo: "Backend: " + ai.backend + "  ·  modelo: "
                + (ai.effectiveModelPath ? ai.effectiveModelPath.split("/").pop() : "—") + "  ·  " + ai.status
        onSetScale: function (v) { app.applySetting("scale", v) }
        onSetVoice: function (v) { app.applySetting("voice.tts_voice", v) }
        onSetStt: function (v) { app.applySetting("voice.stt_model", v) }
        onSetLanguage: function (v) { app.applySetting("voice.language", v) }
        onSetMonitor: function (v) { app.applySetting("monitor", v) }
        onSetPersona: function (v) { app.applySetting("persona", v) }
        onSetCustomModel: function (v) { app.applySetting("custom_model", v) }
        onRedetect: provisioner.running = true
    }

    Pet {
        petData: app.manifest
        characterDir: app.characterDir
        scaleOverride: app.settings.scale
        monitorName: app.settings.monitor !== undefined ? app.settings.monitor : ""
        contextState: context.state
        talking: chatWindow.streaming
        voiceState: voice.voiceState
        voiceAmplitude: voice.amplitude
        onPetClicked: chatWindow.open = !chatWindow.open
        onVoicePttStart: voice.pttStart()
        onVoicePttStop: voice.pttStop()
    }

    Component.onCompleted: console.log("miiamia: personaje activo =", activeCharacter,
        "| manifest:", (manifest.name !== undefined ? manifest.name : "FALLO"))
}
