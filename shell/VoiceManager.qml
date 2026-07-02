// VoiceManager.qml — puente QML <-> daemon de voz (M4).
//
// Lanza voice/voice_daemon.py y habla con él por stdio (JSON-lines). Expone el estado de voz
// (idle/listening/thinking/speaking) y la amplitud (lip-sync) para que Pet.qml anime a la mascota.
// El push-to-talk lo dispara Pet.qml (click derecho mantenido) -> pttStart()/pttStop().
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: vm

    // --- Config (la pone shell.qml) ---
    property string aiUrl: "http://127.0.0.1:8080"
    property string model: "kira"
    property string persona: ""
    property string ttsVoice: "es_ES-sharvard-medium"
    property string voiceFx: ""        // efecto de voz por pet (p.ej. "infernal"); "" = sin efecto
    property real   lengthScale: 1.0   // velocidad de habla (>1.0 = más lento y pausado)
    property string sttModel: "ggml-base"
    property string language: "es"
    property int    speaker: 1

    // Rutas estándar (las prepara install/setup_voice.sh)
    readonly property string _home: Quickshell.env("HOME")
    readonly property string _voiceDir: _home + "/.local/share/miiamia/voice"
    readonly property string piperBin: _voiceDir + "/piper/piper"
    readonly property string piperVoice: _voiceDir + "/voices/" + ttsVoice + ".onnx"
    readonly property string whisperBin: "whisper-server"
    readonly property string whisperModel: _home + "/.cache/miiamia/models/" + sttModel + ".bin"

    // --- Estado expuesto al avatar ---
    property string voiceState: "idle"     // idle | listening | thinking | speaking
    property real   amplitude: 0.0
    property string lastTranscript: ""
    property string lastReply: ""
    property bool   daemonReady: false

    signal recordingStarted()   // shell.qml -> ai.ensureRunning() (calentar el motor mientras hablas)

    // --- API para Pet.qml / shell.qml ---
    function pttStart() { console.log("miiamia[voice]: PTT start"); recordingStarted(); _send({ "cmd": "ptt_start" }); }
    function pttStop()  { console.log("miiamia[voice]: PTT stop"); _send({ "cmd": "ptt_stop" }); }
    function cancel()   { _send({ "cmd": "cancel" }); }
    function say(text)  { _send({ "cmd": "say", "text": text }); }   // hablar un texto suelto (comentario espontáneo)
    function setGaming(on) { _send({ "cmd": "gaming", "on": on }); }

    function _send(obj) {
        if (daemon.running) daemon.write(JSON.stringify(obj) + "\n");
    }
    function _sendConfig() {
        _send({ "cmd": "config", "ai_url": aiUrl, "model": model, "persona": persona,
                "piper_bin": piperBin, "piper_voice": piperVoice, "speaker": speaker,
                "voice_fx": voiceFx, "length_scale": lengthScale,
                "whisper_bin": whisperBin, "whisper_model": whisperModel, "language": language });
    }

    Process {
        id: daemon
        command: ["python3", "-u", Quickshell.shellDir + "/../voice/voice_daemon.py"]
        running: true
        stdinEnabled: true   // OBLIGATORIO para poder write() al daemon
        // Si el daemon muere, resetear el estado (si no, la pet queda con el anillo de "escuchando"
        // congelado y AutoVision vetada) y relanzarlo con backoff.
        onExited: {
            vm.daemonReady = false;
            vm.voiceState = "idle";
            vm.amplitude = 0;
            console.error("miiamia[voice]: el daemon de voz murió; reintento en 3s");
            respawn.restart();
        }
        stdout: SplitParser {
            onRead: function (line) {
                var ev;
                try { ev = JSON.parse(line); } catch (e) { return; }
                if (ev.event === "ready") { vm.daemonReady = true; vm._sendConfig(); console.log("miiamia[voice]: daemon listo"); }
                else if (ev.event === "state") {
                    vm.voiceState = ev.value;
                    if (ev.value !== "speaking" && ev.value !== "listening") vm.amplitude = 0;
                    console.log("miiamia[voice]: estado=" + ev.value);
                } else if (ev.event === "amplitude") vm.amplitude = ev.value;
                else if (ev.event === "transcript") { vm.lastTranscript = ev.text; console.log("miiamia[voice]: oíste: " + ev.text); }
                else if (ev.event === "reply") { vm.lastReply = ev.text; console.log("miiamia[voice]: respondió: " + ev.text); }
                else if (ev.event === "error") console.error("miiamia[voice]:", ev.msg);
            }
        }
    }

    Timer {
        id: respawn
        interval: 3000
        onTriggered: if (!daemon.running) daemon.running = true
    }

    onAiUrlChanged: if (daemonReady) _sendConfig()
    onPersonaChanged: if (daemonReady) _sendConfig()
    onTtsVoiceChanged: if (daemonReady) _sendConfig()
    onVoiceFxChanged: if (daemonReady) _sendConfig()
    onLengthScaleChanged: if (daemonReady) _sendConfig()
    onSttModelChanged: if (daemonReady) _sendConfig()
    onLanguageChanged: if (daemonReady) _sendConfig()
}
