// ContextEngine.qml — detecta que esta haciendo el usuario y expone `state`.
//
// Usa la integracion nativa de Quickshell con Hyprland (socket2) — sin daemon Python ni D-Bus.
//  - Hyprland.rawEvent  -> evento 'activewindow>>class,title' en cada cambio de foco.
//  - hyprctl activewindow -j (Process) -> estado inicial al arrancar.
//  - Timer de inactividad -> 'sleeping' (placeholder; idle real con ext-idle-notify en M4).
//
// El avatar consume `state`. Estados: gaming / typing / browsing / idle / sleeping.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: engine

    // Prioridad: jugar > media (video/música) > dormir (inactivo) > actividad de ventana.
    readonly property string state:
        (_classify(activeClass) === "gaming") ? "gaming"
        : (mediaState !== "") ? mediaState
        : _idle ? "sleeping"
        : _classify(activeClass)
    property string activeClass: ""
    property string mediaState: ""     // "watching" | "music" | "" (de media_state.sh por MPRIS)
    property bool _idle: false
    property int idleTimeoutMs: 30000

    // Clase de ventana -> estado de animacion (heuristica por app activa).
    function _classify(cls) {
        var c = (cls || "").toLowerCase();
        if (/gamescope|steam_app_|lutris|heroic|wine|proton|ryujinx|cemu|dolphin-emu|retroarch/.test(c)) return "gaming";
        if (/alacritty|kitty|foot|wezterm|ghostty|konsole|terminal|code|codium|jetbrains|nvim|neovide|emacs|sublime|zed/.test(c)) return "typing";
        if (/firefox|zen|chromium|chrome|brave|vivaldi|librewolf|epiphany|qutebrowser|mullvad/.test(c)) return "browsing";
        return "idle";
    }

    function _setActive(cls) {
        engine.activeClass = cls;
        engine._idle = false;
        idleTimer.restart();
    }

    // Estado inicial.
    Process {
        running: true
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            id: initOut
            onStreamFinished: {
                try {
                    var o = JSON.parse(initOut.text);
                    if (o && o.class) engine._setActive(o.class);
                } catch (e) { /* no hay ventana activa */ }
            }
        }
    }

    // Cambios de foco / actividad en vivo.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // Solo los eventos de ACTIVIDAD real reinician el idle (no configreloaded, monitoradded…),
            // si no la mascota nunca llegaría a "sleeping".
            var ACT = ["activewindow", "openwindow", "closewindow", "windowtitle", "urgent", "fullscreen"];
            if (ACT.indexOf(event.name) >= 0) { engine._idle = false; idleTimer.restart(); }
            if (event.name === "activewindow") {
                // data = "class,title"  (la clase llega hasta la primera coma; el titulo puede tener comas)
                var d = event.data;
                var comma = d.indexOf(",");
                engine._setActive(comma >= 0 ? d.substring(0, comma) : d);
            }
        }
    }

    Timer {
        id: idleTimer
        interval: engine.idleTimeoutMs
        running: true
        onTriggered: engine._idle = true
    }

    // --- Deteccion de media (MPRIS): viendo video (watching) o escuchando musica (music) ---
    Timer { interval: 3000; running: true; repeat: true; onTriggered: mediaProc.running = true }
    Process {
        id: mediaProc
        command: ["bash", Quickshell.shellDir + "/../tools/media_state.sh"]
        stdout: StdioCollector {
            id: mediaOut
            onStreamFinished: {
                var s = mediaOut.text.trim();
                engine.mediaState = (s === "watching" || s === "music") ? s : "";
            }
        }
    }

    onStateChanged: console.log("miiamia[context]: estado =", state, "| class:", activeClass, "| media:", mediaState)
}
