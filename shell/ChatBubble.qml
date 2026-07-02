// ChatBubble.qml — ventana de chat con la mascota (M3).
//
// Ventana SEPARADA del overlay (bug Hyprland #14136): aqui keyboardFocus=OnDemand para escribir;
// el overlay de la mascota se queda en None.
//
// AGNOSTICO DEL BACKEND: habla el endpoint estandar OpenAI `/v1/chat/completions` (SSE streaming).
// Funciona con el motor EMBEBIDO (llama.cpp, sin depender de nada) o con Ollama si existe.
// La persona se manda como mensaje 'system' -> no depende de Modelfiles ni de un motor concreto.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: chat

    property string aiUrl: "http://127.0.0.1:8080"   // servidor local OpenAI-compat (embebido u Ollama)
    property string model: "miiamia"
    property string persona: ""
    property string charName: "Kira"
    property bool open: false
    property bool streaming: false    // <- el avatar usa esto para animar 'talking'
    property bool backendReady: true  // <- AIBackend pone false mientras enciende el motor
    signal sent()                     // emitido al mandar un mensaje (shell.qml -> ensureRunning)
    signal openSettings()             // el ⚙ abre el menú de configuración
    property string pendingVisionText: ""
    readonly property string eyePath: Quickshell.env("HOME") + "/.cache/miiamia/eyes/last.png"
    property bool hasVision: false    // el provider efectivo tiene visión (gate del 👁; Qwen3 local no ve)
    property string monitorName: ""   // monitor a capturar (el de la pet); "" = todos
    property var _xhr: null           // request en vuelo (para abortar por atasco o al cerrar)

    // Watchdog anti-atasco: si el servidor acepta la conexión pero deja de mandar datos, el
    // streaming quedaba en true para siempre (input y ✕ muertos). Abortar dispara DONE -> limpieza.
    Timer {
        id: stallWatch
        interval: 45000
        onTriggered: if (chat._xhr) { console.warn("miiamia[chat]: stream atascado, abortando"); chat._xhr.abort(); }
    }

    visible: open
    onOpenChanged: if (open) input.forceActiveFocus()

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "miiamia-chat"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    anchors { bottom: true; right: true }
    margins { bottom: 300; right: 40 }
    implicitWidth: 380
    implicitHeight: 440
    color: "transparent"

    ListModel { id: msgs }

    // --- Llamada al modelo con streaming (OpenAI /v1, Server-Sent Events) ---
    function send(text) {
        chat._sendContent(text, text);
    }

    function captureVision(text) {
        if (chat.streaming || !chat.backendReady || !chat.hasVision) return;
        chat.pendingVisionText = text && text.length > 0
            ? text
            : "Mira mi pantalla y dime qué ves. Si hay algo importante, descríbelo y dime qué puedes hacer con eso.";
        // Captura solo el monitor de la pet y reduce a 1280px (menos tokens/latencia); si no hay
        // ImageMagick 7 (`magick`), manda la captura a resolución completa igual.
        var mon = chat.monitorName !== "" ? ("-o '" + chat.monitorName + "' ") : "";
        eyeCapture.command = ["bash", "-lc",
            "mkdir -p ~/.cache/miiamia/eyes && grim " + mon + "-t png ~/.cache/miiamia/eyes/last.png"
            + " && { command -v magick >/dev/null && magick ~/.cache/miiamia/eyes/last.png -resize '1280x>' ~/.cache/miiamia/eyes/last.png || true; }"];
        eyeCapture.running = true;
    }

    function sendVision(path, text) {
        var content = [
            { "type": "text", "text": text },
            { "type": "image_url", "image_url": { "url": "file://" + path } }
        ];
        chat._sendContent("👁 " + text, content);
    }

    function _sendContent(displayText, apiContent) {
        if (!displayText || chat.streaming || !chat.backendReady) return;
        chat.sent();
        msgs.append({ "role": "user", "text": displayText });

        // Construye los mensajes para la API: persona (system) + TODA la conversacion (memoria).
        var apiMsgs = [];
        if (chat.persona) apiMsgs.push({ "role": "system", "content": chat.persona });
        for (var i = 0; i < msgs.count - 1; i++)
            apiMsgs.push({ "role": msgs.get(i).role, "content": msgs.get(i).text });
        apiMsgs.push({ "role": "user", "content": apiContent });
        // (El "thinking" de Qwen3 se suprime con chat_template_kwargs abajo; NO ensuciar el
        //  mensaje del usuario con '/no_think' — es de SmolLM3 y confunde el hilo.)

        msgs.append({ "role": "assistant", "text": "" });   // se rellena al streamear
        var slot = msgs.count - 1;
        chat.streaming = true;
        listView.positionViewAtEnd();

        var xhr = new XMLHttpRequest();
        chat._xhr = xhr;
        stallWatch.restart();
        xhr.open("POST", chat.aiUrl + "/v1/chat/completions");
        xhr.setRequestHeader("Content-Type", "application/json");
        var processed = 0;
        var raw = "";   // texto crudo acumulado; lo mostrado pasa por _stripThink()

        xhr.onreadystatechange = function () {
            stallWatch.restart();   // hay actividad -> el stream no está atascado
            if (xhr.readyState >= XMLHttpRequest.LOADING) {
                var parts = xhr.responseText.split("\n");
                var upTo = (xhr.readyState === XMLHttpRequest.DONE) ? parts.length : parts.length - 1;
                for (; processed < upTo; processed++) {
                    var line = parts[processed];
                    if (line.indexOf("data:") !== 0) continue;
                    var payload = line.substring(5).trim();
                    if (payload === "" || payload === "[DONE]") continue;
                    try {
                        var o = JSON.parse(payload);
                        var d = o.choices && o.choices[0] && o.choices[0].delta
                              ? o.choices[0].delta.content : "";
                        if (d) {
                            raw += d;
                            msgs.setProperty(slot, "text", chat._stripThink(raw));
                            listView.positionViewAtEnd();
                        }
                    } catch (e) { /* linea parcial */ }
                }
            }
            if (xhr.readyState === XMLHttpRequest.DONE) {
                stallWatch.stop();
                chat._xhr = null;
                chat.streaming = false;
                if (msgs.get(slot).text === "")
                    msgs.setProperty(slot, "text", "…(sin respuesta — ¿está corriendo el motor de IA?)");
                console.log("miiamia[chat] <" + chat.model + ">:", msgs.get(slot).text);
            }
        };
        // chat_template_kwargs.enable_thinking=false -> suprime el modo "thinking" (CoT) de Qwen3 en
        // llama-server; si no, Qwen3 manda el razonamiento a delta.reasoning_content (no content) y el
        // streaming se ve en blanco y luego de golpe. Otros backends (Ollama) ignoran el campo.
        xhr.send(JSON.stringify({ "model": chat.model, "messages": apiMsgs, "stream": true,
            "chat_template_kwargs": { "enable_thinking": false } }));
    }

    Process {
        id: eyeCapture
        onExited: function (code) {
            if (code === 0) chat.sendVision(chat.eyePath, chat.pendingVisionText);
            else {
                msgs.append({ "role": "assistant", "text": "No pude capturar la pantalla con grim." });
                console.error("miiamia[eyes]: grim falló con código", code);
            }
        }
    }

    // Qwen3 con thinking suprimido emite un bloque <think>...</think> (a veces vacío) al inicio del
    // contenido. Lo quitamos para no mostrarlo. Mientras el bloque está abierto, no mostramos nada.
    function _stripThink(t) {
        var m = t.match(/^\s*<think>[\s\S]*?<\/think>\s*/);
        if (m) return t.substring(m[0].length);
        if (/^\s*<think>/.test(t) && t.indexOf("</think>") === -1) return "";
        return t;
    }

    // --- UI ---
    Rectangle {
        anchors.fill: parent
        radius: 18
        color: "#ee1d1b2e"
        border.color: "#66a78cff"
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Row {
                width: parent.width
                spacing: 8
                Rectangle { width: 10; height: 10; radius: 5; color: "#a78cff"; anchors.verticalCenter: parent.verticalCenter }
                Text { text: chat.charName; color: "#efe9ff"; font.pixelSize: 15; font.bold: true }
                Item { width: parent.width - 205; height: 1 }
                Text {
                    text: "👁"; color: "#9a8fc0"; font.pixelSize: 15
                    visible: chat.hasVision   // sin cerebro con visión el 👁 no aplica (Qwen3 local no ve)
                    MouseArea {
                        anchors.fill: parent
                        enabled: chat.backendReady && !chat.streaming
                        onClicked: {
                            var t = input.text.trim();
                            if (t.length > 0) input.text = "";
                            chat.captureVision(t);
                        }
                    }
                }
                Text {
                    text: "⚙"; color: "#9a8fc0"; font.pixelSize: 16
                    MouseArea { anchors.fill: parent; onClicked: chat.openSettings() }
                }
                Text {
                    text: chat.streaming ? "✕ detener" : "✕"
                    color: "#9a8fc0"; font.pixelSize: 13
                    // Siempre clickeable: si hay stream en curso lo aborta (antes quedabas atrapado
                    // con el ✕ deshabilitado hasta que el stream terminara... si terminaba).
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (chat._xhr) chat._xhr.abort();
                            else chat.open = false;
                        }
                    }
                }
            }

            ListView {
                id: listView
                width: parent.width
                height: parent.height - 92
                clip: true
                spacing: 8
                model: msgs
                delegate: Column {
                    width: ListView.view.width
                    Rectangle {
                        property bool mine: role === "user"
                        anchors.right: mine ? parent.right : undefined
                        width: Math.min(parent.width * 0.82, label.implicitWidth + 22)
                        height: label.implicitHeight + 16
                        radius: 12
                        color: mine ? "#5b46a0" : "#2c2a44"
                        Text {
                            id: label
                            anchors.fill: parent
                            anchors.margins: 8
                            text: model.text
                            color: "#f2eeff"
                            wrapMode: Text.Wrap
                            font.pixelSize: 14
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 40
                radius: 12
                color: "#2c2a44"
                TextField {
                    id: input
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    placeholderText: !chat.backendReady ? ("Encendiendo a " + chat.charName + "…")
                                   : chat.streaming ? (chat.charName + " está pensando…")
                                   : ("Escríbele a " + chat.charName + "…")
                    placeholderTextColor: "#7d73a8"
                    color: "#f2eeff"
                    font.pixelSize: 14
                    background: Item {}
                    enabled: chat.backendReady && !chat.streaming
                    onAccepted: { if (text.trim()) { chat.send(text.trim()); text = ""; } }
                }
            }
        }
    }

    // Autotest opcional: MIIAMIA_SELFTEST=1 -> envia un saludo al abrir (verifica el pipeline IA).
    Component.onCompleted: {
        if (Quickshell.env("MIIAMIA_SELFTEST") === "1") { chat.open = true; selftest.start(); }
    }
    // Espera a que el motor encienda antes de enviar el saludo de prueba.
    Timer {
        id: selftest
        interval: 500; repeat: true
        onTriggered: if (chat.backendReady) { stop(); chat.send("Hola, preséntate en una sola frase."); }
    }
}
