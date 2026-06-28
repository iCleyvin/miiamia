// SettingsWindow.qml — menú de configuración de miiamia (M5).
//
// Ventana separada (foco de teclado) con todo lo configurable: aspecto, cerebro (IA), voz e idioma.
// Lee los valores actuales (propiedades puestas por shell.qml desde settings.json) y, al cambiar algo,
// emite señales que shell.qml aplica EN VIVO y persiste. Las descargas (voces / modelos STT) se hacen
// con los helpers de tools/ vía Process.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: win

    // --- Valores actuales (los pone shell.qml) ---
    property real scaleValue: 2.0
    property string voice: "es_ES-sharvard-medium"
    property string stt: "ggml-base"
    property string language: "es"
    property string monitor: ""
    property string persona: ""
    property string customModel: ""
    property string recModelLabel: "Qwen3-4B (alineado) ✓"
    property string aiInfo: "—"
    property bool open: false

    // --- Señales que aplica shell.qml ---
    signal setScale(real v)
    signal setVoice(string v)
    signal setStt(string v)
    signal setLanguage(string v)
    signal setMonitor(string v)
    signal setPersona(string v)
    signal setCustomModel(string v)
    signal redetect()

    readonly property string _tools: Quickshell.shellDir + "/../tools"
    property string status: ""

    visible: open
    onOpenChanged: if (open) win.status = ""

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "miiamia-settings"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    anchors { top: true; right: true }
    margins { top: 60; right: 40 }
    implicitWidth: 440
    implicitHeight: 560
    color: "transparent"

    // Catálogos
    readonly property var voices: [
        { id: "es_ES-sharvard-medium", label: "Sharvard — España ♀ (media)" },
        { id: "es_AR-daniela-high",    label: "Daniela — Argentina ♀ (alta)" },
        { id: "es_MX-ald-medium",      label: "Ald — México ♂ (media)" },
        { id: "es_ES-davefx-medium",   label: "Davefx — España ♂ (media)" }
    ]
    readonly property var stts: [
        { id: "ggml-tiny",  label: "Tiny — el más rápido (4GB)" },
        { id: "ggml-base",  label: "Base — equilibrio" },
        { id: "ggml-small", label: "Small — preciso" },
        { id: "ggml-medium", label: "Medium — muy preciso (GPU)" },
        { id: "ggml-large-v3-turbo", label: "Large-v3-turbo — máximo (GPU)" }
    ]
    readonly property var langs: [
        { id: "es", label: "Español" }, { id: "en", label: "English" },
        { id: "pt", label: "Português" }, { id: "fr", label: "Français" },
        { id: "it", label: "Italiano" }
    ]
    readonly property var screenOpts: {
        var a = [{ id: "", label: "Automática (donde aparezca)" }];
        var ss = Quickshell.screens;
        for (var i = 0; i < ss.length; i++)
            a.push({ id: ss[i].name,
                     label: ss[i].name + (ss[i].width ? " (" + ss[i].width + "×" + ss[i].height + ")" : "") });
        return a;
    }
    function _idx(list, id) { for (var i = 0; i < list.length; i++) if (list[i].id === id) return i; return 0; }

    // Presets de personalidad (puntos de partida; el campo de texto manda y es libre).
    readonly property var personas: [
        { label: "🥰 Tierna", rec: "Qwen3-4B (alineado) ✓", text: "Eres Kira, una dragona dulce, tierna y muy cariñosa. Hablas español dominicano, apoyas y animas a tu humano con amor. Respondes breve (1-2 frases)." },
        { label: "😜 Juguetona", rec: "Qwen3-4B (alineado) ✓", text: "Eres Kira, una dragona joven, juguetona y traviesa. Hablas español dominicano, cálida y divertida. Respondes breve (1-2 frases) y reaccionas a lo que hace tu humano." },
        { label: "😏 Grosera", rec: "Qwen3-4B (alineado) ✓", text: "Eres Kira, una dragona malhablada, sarcástica y sin filtro. Sueltas groserías, eres respondona y descarada, con humor negro, pero en el fondo le tienes cariño a tu humano. Español dominicano, breve." },
        { label: "🔥 Coqueta", rec: "Uncensored 🔥 (pega su ruta en «Modelo personalizado» abajo)", text: "Eres Kira, una dragona coqueta, atrevida y sensual. Le hablas a tu humano adulto con picardía, doble sentido y provocación. Español dominicano, breve. Contenido para adultos." },
        { label: "✍️ En blanco", rec: "Tú decides el modelo", text: "" }
    ]

    // Descargas (voces / modelos STT) con apply al terminar
    property string _pendVoice: ""
    property string _pendStt: ""
    Process {
        id: dl
        onExited: function (code) {
            if (win._pendVoice) {
                win.status = code === 0 ? "Voz lista ✓" : "Error al descargar la voz";
                if (code === 0) win.setVoice(win._pendVoice);
                win._pendVoice = "";
            } else if (win._pendStt) {
                win.status = code === 0 ? "Modelo de escucha listo ✓" : "Error al descargar el modelo";
                if (code === 0) win.setStt(win._pendStt);
                win._pendStt = "";
            }
        }
    }
    function chooseVoice(id) {
        win._pendVoice = id; win.status = "Descargando voz…";
        dl.command = ["bash", win._tools + "/get_voice.sh", id]; dl.running = true;
    }
    function chooseStt(id) {
        win._pendStt = id; win.status = "Descargando modelo de escucha…";
        dl.command = ["bash", win._tools + "/get_stt.sh", id]; dl.running = true;
    }

    // --- UI ---
    Rectangle {
        anchors.fill: parent
        radius: 18
        color: "#f21d1b2e"
        border.color: "#66a78cff"; border.width: 1

        Flickable {
            anchors.fill: parent
            anchors.margins: 16
            contentHeight: col.implicitHeight
            clip: true

            Column {
                id: col
                width: parent.width
                spacing: 14

                Row {
                    width: parent.width
                    Text { text: "⚙  Configuración"; color: "#efe9ff"; font.pixelSize: 18; font.bold: true }
                    Item { width: parent.width - 170; height: 1 }
                    Text {
                        text: "✕"; color: "#9a8fc0"; font.pixelSize: 16
                        MouseArea { anchors.fill: parent; onClicked: win.open = false }
                    }
                }

                // ---- Aspecto ----
                Text { text: "ASPECTO"; color: "#a78cff"; font.pixelSize: 12; font.bold: true }
                Column {
                    width: parent.width; spacing: 4
                    Text { text: "Tamaño de la mascota: " + win.scaleValue.toFixed(1) + "×"; color: "#cfc7e8"; font.pixelSize: 13 }
                    Slider {
                        width: parent.width
                        from: 1.0; to: 4.0; stepSize: 0.25; value: win.scaleValue
                        onMoved: win.setScale(value)
                    }
                }
                Column {
                    width: parent.width; spacing: 6
                    Text { text: "Pantalla (monitor)"; color: "#cfc7e8"; font.pixelSize: 13 }
                    ComboBox {
                        width: parent.width
                        model: win.screenOpts; textRole: "label"
                        currentIndex: win._idx(win.screenOpts, win.monitor)
                        onActivated: win.setMonitor(win.screenOpts[currentIndex].id)
                    }
                }

                // ---- Voz ----
                Text { text: "VOZ"; color: "#a78cff"; font.pixelSize: 12; font.bold: true }
                Column {
                    width: parent.width; spacing: 8
                    Text { text: "Voz de Kira (cómo habla)"; color: "#cfc7e8"; font.pixelSize: 13 }
                    ComboBox {
                        width: parent.width
                        model: win.voices; textRole: "label"
                        currentIndex: win._idx(win.voices, win.voice)
                        onActivated: win.chooseVoice(win.voices[currentIndex].id)
                    }
                    Text { text: "Modelo de escucha (cómo te entiende)"; color: "#cfc7e8"; font.pixelSize: 13 }
                    ComboBox {
                        width: parent.width
                        model: win.stts; textRole: "label"
                        currentIndex: win._idx(win.stts, win.stt)
                        onActivated: win.chooseStt(win.stts[currentIndex].id)
                    }
                    Text { text: "Idioma"; color: "#cfc7e8"; font.pixelSize: 13 }
                    ComboBox {
                        width: parent.width
                        model: win.langs; textRole: "label"
                        currentIndex: win._idx(win.langs, win.language)
                        onActivated: win.setLanguage(win.langs[currentIndex].id)
                    }
                }

                // ---- Personalidad ----
                Text { text: "PERSONALIDAD"; color: "#a78cff"; font.pixelSize: 12; font.bold: true }
                Column {
                    width: parent.width; spacing: 8
                    Text {
                        text: "Elige un estilo o escribe el tuyo. El texto manda y es libre — tú decides cómo habla."
                        color: "#cfc7e8"; font.pixelSize: 13; wrapMode: Text.Wrap; width: parent.width
                    }
                    Flow {
                        width: parent.width; spacing: 6
                        Repeater {
                            model: win.personas
                            delegate: Button {
                                text: modelData.label
                                onClicked: { personaArea.text = modelData.text; win.recModelLabel = modelData.rec; }
                            }
                        }
                    }
                    Rectangle {
                        width: parent.width; height: 120; radius: 10; color: "#2c2a44"
                        ScrollView {
                            anchors.fill: parent; anchors.margins: 8; clip: true
                            TextArea {
                                id: personaArea
                                text: win.persona
                                color: "#f2eeff"; font.pixelSize: 13
                                wrapMode: TextArea.Wrap
                                placeholderText: "Describe cómo quieres que sea y hable Kira… (sin filtros)"
                                background: Item {}
                            }
                        }
                    }
                    Button {
                        text: "Aplicar personalidad"
                        onClicked: { win.setPersona(personaArea.text); win.status = "Personalidad aplicada ✓"; }
                    }
                }

                // ---- Cerebro (IA) ----
                Text { text: "CEREBRO (IA)"; color: "#a78cff"; font.pixelSize: 12; font.bold: true }
                Column {
                    width: parent.width; spacing: 8
                    Text { text: win.aiInfo; color: "#cfc7e8"; font.pixelSize: 13; wrapMode: Text.Wrap; width: parent.width }
                    Text {
                        text: "Recomendado para esta personalidad:  " + win.recModelLabel
                        color: "#ffd27a"; font.pixelSize: 12; wrapMode: Text.Wrap; width: parent.width
                    }
                    Button {
                        text: "Re-detectar hardware y descargar modelo (auto)"
                        onClicked: { win.status = "Detectando hardware y descargando modelo…"; win.redetect(); }
                    }
                    Text {
                        text: "Modelo personalizado (ruta a un .gguf, p.ej. uno uncensored):"
                        color: "#cfc7e8"; font.pixelSize: 12; wrapMode: Text.Wrap; width: parent.width
                    }
                    Rectangle {
                        width: parent.width; height: 36; radius: 8; color: "#2c2a44"
                        TextField {
                            id: customModelField
                            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                            text: win.customModel
                            placeholderText: "/ruta/al/modelo.gguf   (vacío = automático)"
                            color: "#f2eeff"; font.pixelSize: 12; background: Item {}
                        }
                    }
                    Button {
                        text: "Usar este modelo"
                        onClicked: {
                            win.setCustomModel(customModelField.text.trim());
                            win.status = customModelField.text.trim() === ""
                                ? "Volviendo al modelo automático…" : "Modelo personalizado aplicado ✓";
                        }
                    }
                }

                // ---- estado ----
                Text {
                    text: win.status; color: "#ffd27a"; font.pixelSize: 12
                    visible: win.status !== ""; wrapMode: Text.Wrap; width: parent.width
                }
            }
        }
    }
}
