// Reactions.qml — reacción por EVENTO al contexto (el "salto" de vida propia).
//
// Cuando cambias de actividad (abrir un juego, poner música, darle play a un video, ponerte a
// escribir…), la pet lo nota AL MOMENTO y suelta un comentario en personaje (globo + voz).
// Complementa la vista automática (que es por tiempo y necesita cerebro con visión): esto es
// instantáneo, 100% local y funciona sin IA — frases del manifest (`reactions.<estado>`) o
// defaults neutros. Anti-spam: debounce (el estado debe asentarse), cooldown por estado y
// separación mínima entre reacciones.
import QtQuick
import Quickshell

Scope {
    id: rx

    // --- Config (la pone shell.qml) ---
    property bool   enabled: true
    property var    manifest: ({})        // manifest del personaje activo (lee .reactions)
    property string contextState: "idle"

    // --- Gating (lo pone shell.qml) ---
    property bool   chatOpen: false
    property bool   talking: false
    property string voiceState: "idle"

    // texto listo -> shell.qml lo manda al globo (+ voz salvo sleeping)
    signal react(string state, string text)

    // Frases por defecto (si el manifest no trae `reactions` para ese estado).
    readonly property var defaults: ({
        "gaming":   ["¡A jugar! Yo te acompaño 🎮", "Modo gamer activado. ¡Tú puedes!", "Uy, partida nueva… ¡dale sin miedo!"],
        "music":    ["Ohh, musiquita 🎵 me encanta", "¡Esa canción suena bien!", "Modo fiesta: me pongo a bailar"],
        "watching": ["Peli y palomitas… me apunto 🍿", "¿Qué vemos? Me acomodo aquí", "Shhh, que ya empieza"],
        "typing":   ["Te veo concentrado… yo vigilo ⌨️", "Modo trabajo: no molesto", "Escribe, escribe, que yo te cuido"],
        "browsing": ["¿Qué andas curioseando? 🌐", "Navegando se te va el tiempo, ¿eh?"],
        "sleeping": ["*bostezo*… me echo una siesta 😴", "Zzz…"]
    })

    property string _pending: ""
    property var    _lastByState: ({})
    property double _lastAnyAt: 0
    property bool   _booted: false        // no reaccionar al estado con el que ARRANCA la sesión

    property int settleMs: 3500          // el estado debe asentarse (alt-tab no cuenta)
    property int perStateCooldownMs: 15 * 60000   // misma actividad: 1 vez cada 15 min
    property int globalGapMs: 90 * 1000            // entre reacciones cualesquiera: 90 s
    property int bootMs: 4000                      // gracia al arrancar (el estado inicial no es un evento)

    onContextStateChanged: {
        if (!_booted) return;             // el primer estado es el arranque, no un evento
        _pending = contextState;
        settle.restart();
    }
    Timer { id: settle; interval: rx.settleMs; onTriggered: rx._maybeReact(rx._pending) }
    Timer { interval: rx.bootMs; running: true; onTriggered: rx._booted = true }

    function _maybeReact(st) {
        if (!enabled) return;
        if (st !== contextState) return;                       // volvió a cambiar durante el settle
        if (st === "idle" || st === "") return;                // volver a idle no se comenta
        if (chatOpen || talking || voiceState !== "idle") return;   // no interrumpir
        var now = Date.now();
        if (now - _lastAnyAt < globalGapMs) return;
        if (now - (_lastByState[st] || 0) < perStateCooldownMs) return;
        var phrases = (manifest && manifest.reactions && manifest.reactions[st])
                      ? manifest.reactions[st] : defaults[st];
        if (!phrases || phrases.length === 0) return;
        _lastByState[st] = now;
        _lastAnyAt = now;
        var t = phrases[Math.floor(Math.random() * phrases.length)];
        console.log("miiamia[reactions]: " + st + " -> " + t);
        rx.react(st, t);
    }
}
