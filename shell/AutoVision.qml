// AutoVision.qml — "vista automática con interacción propia".
//
// Cada cierto tiempo la pet MIRA la pantalla por iniciativa propia (grim), se la manda al cerebro
// con visión (agent_daemon :9090 -> claude-cli) y suelta UN comentario espontáneo en personaje.
// shell.qml conecta la señal remark() a: globo sobre la pet + voz (TTS).
//
// Gating estricto (en _canGlance): solo si está activo, hay cerebro con visión, no estás jugando ni
// la pet duerme, el chat está cerrado y no hay voz/charla en curso. Se calla si no hay nada que decir.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: av

    // --- Config (la pone shell.qml) ---
    property string aiUrl: "http://127.0.0.1:9090"
    property string persona: ""
    property string model: "kira"
    property bool   enabled: false
    property int    intervalMs: 240000          // ~4 min
    property bool   providerHasVision: false     // false en local (Qwen3 no ve)
    property string monitorName: ""

    // --- Entradas de gating (las pone shell.qml) ---
    property string contextState: "idle"
    property bool   chatOpen: false
    property bool   talking: false
    property string voiceState: "idle"
    property bool   backendReady: false

    signal remark(string text)   // comentario espontáneo listo (shell.qml -> globo + voz)
    signal needsWarmup()          // pide encender el cerebro si aún no está listo

    property bool _busy: false
    property bool _first: true
    property string _lastRemark: ""
    property var _xhr: null
    readonly property string _eyePath: Quickshell.env("HOME") + "/.cache/miiamia/eyes/auto.png"

    // Watchdog: si el request se cuelga, _busy quedaba en true para siempre y la vista automática
    // moría en silencio hasta reiniciar. Abortar dispara DONE -> _busy=false y a la próxima.
    Timer {
        id: stallWatch
        interval: 90000
        onTriggered: if (av._xhr) { console.warn("miiamia[autovision]: request atascado, abortando"); av._xhr.abort(); }
    }

    readonly property bool _canGlance:
        enabled && providerHasVision && backendReady && !_busy
        && !chatOpen && !talking && voiceState === "idle"
        && contextState !== "gaming" && contextState !== "sleeping"

    // Primer vistazo pronto (45 s tras arrancar) para que se note; luego al intervalo elegido.
    Timer {
        id: glanceTimer
        interval: av._first ? 45000 : av.intervalMs
        running: av.enabled
        repeat: true
        triggeredOnStart: false
        onTriggered: { av._first = false; av._tryGlance(); }
    }

    function _tryGlance() {
        if (enabled && providerHasVision && !backendReady) av.needsWarmup();   // calienta para la próxima
        if (!_canGlance) return;
        av._busy = true;
        var mon = monitorName !== "" ? ("-o '" + monitorName + "' ") : "";
        // captura el monitor activo y la reduce a 1280px de ancho (menos tokens/latencia de visión);
        // sin ImageMagick 7 (`magick`) manda la captura completa en vez de fallar siempre
        grim.command = ["bash", "-lc",
            "mkdir -p ~/.cache/miiamia/eyes && grim " + mon + "-t png '" + _eyePath + "'"
            + " && { command -v magick >/dev/null && magick '" + _eyePath + "' -resize '1280x>' '" + _eyePath + "' || true; }"];
        grim.running = true;
    }

    Process {
        id: grim
        onExited: function (code) {
            if (code === 0) av._ask();
            else { av._busy = false; console.error("miiamia[autovision]: grim/magick falló, código", code); }
        }
    }

    function _ask() {
        var prompt = "Estás mirando la pantalla de tu humano por iniciativa propia (no te preguntó nada). "
            + "Mira la captura y suelta UN comentario corto y espontáneo, con tu personalidad, sobre algo "
            + "concreto que veas. Una sola frase, máximo 14 palabras. No saludes ni expliques que estás "
            + "mirando. Si no hay nada que valga la pena comentar, responde EXACTAMENTE: [silencio]";
        // pista de contexto: mejora la relevancia del comentario sin gastar tokens de visión
        var hint = ({ "music": "escuchando música", "watching": "viendo un video",
                      "typing": "escribiendo", "browsing": "navegando" })[contextState];
        if (hint) prompt += " Contexto: tu humano está " + hint + ".";
        if (_lastRemark.length > 0)
            prompt += " Hace poco dijiste: \"" + _lastRemark + "\" — no repitas eso ni algo parecido.";

        var content = [
            { "type": "text", "text": prompt },
            { "type": "image_url", "image_url": { "url": "file://" + _eyePath } }
        ];
        var apiMsgs = [];
        if (persona) apiMsgs.push({ "role": "system", "content": persona });
        apiMsgs.push({ "role": "user", "content": content });

        var xhr = new XMLHttpRequest();
        av._xhr = xhr;
        stallWatch.restart();
        xhr.open("POST", aiUrl + "/v1/chat/completions");
        xhr.setRequestHeader("Content-Type", "application/json");
        var raw = "";
        var processed = 0;
        xhr.onreadystatechange = function () {
            stallWatch.restart();
            if (xhr.readyState >= XMLHttpRequest.LOADING) {
                var parts = xhr.responseText.split("\n");
                var upTo = (xhr.readyState === XMLHttpRequest.DONE) ? parts.length : parts.length - 1;
                for (; processed < upTo; processed++) {
                    var line = parts[processed];
                    if (line.indexOf("data:") !== 0) continue;
                    var p = line.substring(5).trim();
                    if (p === "" || p === "[DONE]") continue;
                    try {
                        var o = JSON.parse(p);
                        var d = o.choices && o.choices[0] && o.choices[0].delta
                              ? o.choices[0].delta.content : "";
                        if (d) raw += d;
                    } catch (e) { /* línea parcial */ }
                }
            }
            if (xhr.readyState === XMLHttpRequest.DONE) {
                stallWatch.stop();
                av._xhr = null;
                av._busy = false;
                var txt = av._clean(raw);
                if (txt.length > 1 && txt.toLowerCase().indexOf("[silencio]") < 0) {
                    av._lastRemark = txt;
                    av.remark(txt);
                } else {
                    console.log("miiamia[autovision]: sin comentario (silencio)");
                }
            }
        };
        xhr.send(JSON.stringify({ "model": model, "messages": apiMsgs, "stream": true,
            "chat_template_kwargs": { "enable_thinking": false } }));
    }

    // Quita el bloque <think> de Qwen3, comillas envolventes y espacios.
    function _clean(t) {
        t = t.replace(/^\s*<think>[\s\S]*?<\/think>\s*/, "");
        t = t.trim().replace(/^["'“”\s]+|["'“”\s]+$/g, "");
        return t;
    }
}
