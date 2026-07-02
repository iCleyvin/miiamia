// AIBackend.qml — gestiona el motor de IA local para el chat (M3.5, "para todo el mundo").
//
// Lee ~/.config/miiamia/ai.toml (lo escribe tools/provision.sh) y, si backend=="embedded",
// arranca llama-server BAJO DEMANDA al abrir el chat, sondea /health, y lo apaga al jugar o
// tras inactividad — para no pesar siempre. Si backend=="ollama"/"external", solo apunta la URL.
//
// ChatBubble.qml no cambia: ya habla OpenAI /v1; aqui solo se decide a QUE servidor y CUANDO.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: be

    // --- Config (parseada de ai.toml) ---
    property string backend: "embedded"                       // "embedded" | "agent" | "ollama" | "external"
    property string baseEndpoint: "http://127.0.0.1:8080"     // llama-server local (de ai.toml)
    property string agentProvider: "local"                    // provider EFECTIVO (lo resuelve y pasa shell.qml)
    property string agentEndpoint: "http://127.0.0.1:9090"    // agent_daemon (cerebro)
    // El daemon (cerebro) hace falta si ai.toml lo pide O si el provider efectivo no es local:
    // nada en el repo escribe backend="agent" en ai.toml, así que un usuario que elige claude-cli/
    // cloud en el menú se quedaba sin cerebro (health-poll a :8080 muerto). Derivarlo del provider
    // lo arregla sin tocar ai.toml.
    readonly property bool _useDaemon:
        (backend === "agent" || agentProvider !== "local") && backend !== "ollama" && backend !== "external"
    // ¿hace falta el motor local? solo si el provider efectivo es local (en modo daemon lo proxea).
    readonly property bool _useLocalEngine:
        (backend === "embedded" || backend === "agent") && agentProvider === "local"
    // Lo que ven ChatBubble/voice: el daemon (9090) en modo agent; llama-server directo en embedded.
    readonly property string endpoint: _useDaemon ? agentEndpoint : baseEndpoint
    property string modelPath: ""
    property string modelOverride: ""   // ruta a un GGUF custom (del menú); gana sobre modelPath
    readonly property string effectiveModelPath: modelOverride !== "" ? modelOverride : modelPath
    property int    ctxSize: 4096
    property int    nPredict: 512
    property int    idleUnloadSecs: 180   // 3 min: libera RAM/VRAM pronto (objetivo 4GB). provision.sh lo confirma.
    property bool   gamingUnload: true
    property bool   downloaded: false

    // --- Runtime ---
    // idle | starting | ready | nomodel | error
    property string status: "idle"
    readonly property bool ready: status === "ready"
    readonly property bool embedded: backend === "embedded"
    property string contextState: "idle"   // lo setea shell.qml desde ContextEngine (para gaming-unload)
    property bool _serverFailed: false      // el último arranque falló (puerto ocupado, binario, OOM)
    property int  _healthRetries: 0         // tope de sondeos de /health
    property var  _hxhr: null               // XHR de /health en vuelo (evita acumularlos)

    // puerto del llama-server LOCAL (el daemon lo proxea en modo agent) — siempre del baseEndpoint
    function _port() { var m = baseEndpoint.match(/:(\d+)/); return m ? m[1] : "8080"; }

    // --- Cargar ai.toml (parser TOML-plano minimo) ---
    FileView {
        id: cfg
        path: Quickshell.env("HOME") + "/.config/miiamia/ai.toml"
        blockLoading: true
    }
    Component.onCompleted: _loadConfig()
    function _loadConfig() {
        var t = "";
        try { t = cfg.text(); } catch (e) {}
        if (!t) { be.status = "nomodel"; return; }   // sin config -> 1er arranque (FirstRunSetup)
        var lines = t.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var ln = lines[i].replace(/#.*$/, "").trim();
            var eq = ln.indexOf("=");
            if (eq < 0) continue;
            var k = ln.substring(0, eq).trim();
            var v = ln.substring(eq + 1).trim().replace(/^"|"$/g, "");
            if (k === "backend") be.backend = v;
            else if (k === "endpoint") be.baseEndpoint = v;
            else if (k === "model_path") be.modelPath = v;
            else if (k === "ctx_size") be.ctxSize = parseInt(v) || 4096;
            else if (k === "n_predict") be.nPredict = parseInt(v) || 512;
            else if (k === "idle_unload_secs") be.idleUnloadSecs = parseInt(v) || 0;
            else if (k === "gaming_unload") be.gamingUnload = (v === "true");
            else if (k === "downloaded") be.downloaded = (v === "true");
        }
        if (be.backend === "ollama" || be.backend === "external") be.status = "ready";   // ya corriendo
        else if (be._useLocalEngine && be.modelOverride === "" && (!be.downloaded || be.modelPath === ""))
            be.status = "nomodel";   // necesita motor local pero no hay modelo
        // agent-cloud: no necesita modelo local; queda "idle" y se "enciende" sondeando el daemon.
        console.log("miiamia[ai]: backend=" + be.backend + " endpoint=" + be.endpoint
                    + " provider=" + be.agentProvider + " status=" + be.status);
    }

    // --- Proceso llama-server (solo embedded) ---
    Process {
        id: server
        running: false
        command: ["llama-server", "--model", be.effectiveModelPath,
                  "--ctx-size", String(be.ctxSize), "--n-predict", String(be.nPredict),
                  "--n-gpu-layers", "99", "--host", "127.0.0.1", "--port", be._port(),
                  "--jinja", "--no-warmup"]
        onRunningChanged: if (!running) {
            healthTimer.stop();
            if (be.status === "starting") {   // murió mientras arrancaba = fallo (puerto/OOM/binario)
                be.status = "error"; be._serverFailed = true;
                console.error("miiamia[ai]: llama-server falló al arrancar");
            } else be.status = "idle";
        }
    }

    // --- Proceso agent_daemon (cerebro: routing de provider + tools). Solo backend=="agent". ---
    // Liviano (stdlib, ~15-20 MB). Vive con la pet. Reenruta a local o cloud según settings.
    Process {
        id: agentd
        running: be._useDaemon
        command: ["python3", "-u", Quickshell.shellDir + "/../agent/agent_daemon.py"]
        onRunningChanged: if (!running && be._useDaemon) {
            console.error("miiamia[ai]: el agent_daemon se cerró inesperadamente; reintento en 5s");
            if (be.status === "ready" && be._useDaemon) be.status = "idle";   // que nadie hable a un puerto muerto
            agentdRespawn.restart();
        }
    }
    Timer {   // respawn con backoff: un daemon caído no puede dejar a la pet sin cerebro para siempre
        id: agentdRespawn
        interval: 5000
        onTriggered: if (be._useDaemon && !agentd.running) agentd.running = true
    }

    // Arranque perezoso: llamar al abrir el chat / enviar un mensaje.
    function ensureRunning() {
        if (be.backend === "ollama" || be.backend === "external") { be.status = "ready"; return; }
        if (be.status === "nomodel" || be._serverFailed) return;
        idleTimer.restart();
        if (be.status === "ready" || be.status === "starting") return;
        be.status = "starting";
        be._healthRetries = 0;
        if (be._useLocalEngine) server.running = true;   // llama-server (el daemon lo proxea en modo agent)
        healthTimer.start();                              // sondea endpoint/health (daemon o llama-server)
        console.log("miiamia[ai]: encendiendo " + (be._useDaemon ? "cerebro/" + be.agentProvider : "motor local"));
    }
    function shutdown() {
        if (be.status === "idle") return;
        healthTimer.stop();
        idleTimer.stop();
        server.running = false;
        be.status = "idle";
        console.log("miiamia[ai]: llama-server apagado");
    }
    // Recarga la config (tras provision.sh) y obliga a respawn del motor con el modelo nuevo.
    function reload() { be._serverFailed = false; shutdown(); _loadConfig(); console.log("miiamia[ai]: config recargada"); }

    // Sondeo de /health hasta que el servidor responde.
    Timer {
        id: healthTimer
        interval: 500; repeat: true
        onTriggered: {
            if (++be._healthRetries > 120) {   // ~60 s sin responder -> error (no sondear infinito)
                healthTimer.stop(); be.shutdown();
                be.status = "error"; be._serverFailed = true;
                console.error("miiamia[ai]: el motor no respondió a tiempo");
                return;
            }
            if (be._hxhr && be._hxhr.readyState !== XMLHttpRequest.DONE) return;   // no acumules XHR
            var xhr = new XMLHttpRequest();
            be._hxhr = xhr;
            xhr.open("GET", be.endpoint + "/health");
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                if (be._useLocalEngine && !server.running) return;   // ignora respuestas tras shutdown() (motor local)
                if (xhr.status === 200 && xhr.responseText.indexOf('"ok"') >= 0) {
                    be.status = "ready";
                    healthTimer.stop();
                    console.log("miiamia[ai]: motor listo");
                }
            };
            xhr.send();
        }
    }

    // Apagar por inactividad. Aplica siempre que haya motor local (embedded O agent+local:
    // antes solo embedded, y en modo agente llama-server quedaba cargado para siempre).
    property bool chatOpen: false   // lo pone shell.qml; con el chat visible NO se apaga (input congelado si no)
    Timer {
        id: idleTimer
        interval: Math.max(1, be.idleUnloadSecs) * 1000
        running: false
        onTriggered: {
            if (be.idleUnloadSecs <= 0 || !be._useLocalEngine) return;
            if (be.chatOpen) { idleTimer.restart(); return; }   // re-chequear luego, no congelar el chat
            be.shutdown();
        }
    }

    // Apagar al entrar en juego (liberar VRAM/RAM para el juego). Solo si hay motor local.
    onContextStateChanged:
        if (_useLocalEngine && gamingUnload && contextState === "gaming" && status !== "idle")
            shutdown()

    // Al cambiar el modelo personalizado: respawnea el motor con el modelo nuevo.
    onModelOverrideChanged: {
        be._serverFailed = false;   // el modelo nuevo merece su propio intento (evita lockout)
        if (be.status === "ready" || be.status === "starting") shutdown();
        if (be._useLocalEngine) {
            if (be.modelOverride !== "" && be.status === "nomodel") be.status = "idle";
            // al VACIAR el custom sin modelo provisionado, volver a nomodel (no lanzar --model "")
            else if (be.modelOverride === "" && (!be.downloaded || be.modelPath === "")) be.status = "nomodel";
        }
    }

    // Si el provider EFECTIVO cambia a nube, el motor local ya no se usa -> apágalo (ahorra RAM/VRAM).
    onAgentProviderChanged: if (!_useLocalEngine && status !== "idle") shutdown();

    // Al cerrar la app: no dejar procesos huérfanos (llama-server gasta VRAM; el daemon, RAM).
    Component.onDestruction: {
        if (be._hxhr) be._hxhr.abort();
        if (server.running) server.running = false;
        if (agentd.running) agentd.running = false;
    }
}
