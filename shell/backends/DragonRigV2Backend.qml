// DragonRigV2Backend.qml — Averno v2, rig overlay conservador.
//
// La clave de esta version es no "cortar" el dragon: el cuerpo completo queda siempre intacto
// y las capas solo agregan parallax, tension de alas, brillo y fuego. Asi la anatomia no se rompe
// cuando la mascota respira, mira o escupe fuego.
import QtQuick

Item {
    id: backend

    required property url characterDir
    property var rig: null
    property real scale: 2.0
    property string currentState: "idle"
    property bool talking: false
    property real voiceAmplitude: 0.0
    property real headYaw: 0
    property real headPitch: 0

    readonly property bool _ok: rig !== null && rig !== undefined
    readonly property real _voice: Math.max(0, Math.min(1, voiceAmplitude))
    readonly property int _wingDur: currentState === "music" ? 780
        : currentState === "gaming" ? 1050
        : currentState === "sleeping" ? 3600
        : currentState === "typing" ? 2400
        : currentState === "browsing" ? 2100
        : currentState === "watching" ? 2600
        : 1700
    readonly property real _wingAmp: currentState === "sleeping" ? 0.18
        : currentState === "gaming" ? 0.64
        : currentState === "music" ? 0.86
        : currentState === "typing" ? 0.30
        : currentState === "browsing" ? 0.34
        : currentState === "watching" ? 0.26
        : 0.48
    readonly property int _breathDur: currentState === "sleeping" ? 2900 : 1900

    // --- Posturas por estado: el dragón adopta una pose distinta según la actividad. Son SESGOS que
    //     se suman a la animación viva (no cortan el cuerpo) y se interpolan suave al cambiar de estado. ---
    property real _poseCrouch:                       // se asienta/acurruca (0 erguido .. 1 agachado)
          currentState === "sleeping" ? 1.0
        : currentState === "watching" ? 0.32
        : currentState === "gaming"   ? 0.22
        : currentState === "browsing" ? 0.14
        : currentState === "typing"   ? 0.12 : 0.0
    property real _poseHead:                          // inclinación de cabeza (-1 arriba .. 1 abajo)
          currentState === "sleeping" ? 0.78
        : currentState === "typing"   ? 0.70
        : currentState === "browsing" ? 0.40
        : currentState === "watching" ? -0.42
        : currentState === "gaming"   ? -0.18
        : currentState === "music"    ? -0.05 : 0.0
    property real _poseWing:                          // apertura de alas (-1 plegadas .. 1 abiertas)
          currentState === "gaming"   ? 0.65
        : currentState === "music"    ? 0.50
        : currentState === "browsing" ? -0.15
        : currentState === "watching" ? -0.28
        : currentState === "typing"   ? -0.42
        : currentState === "sleeping" ? -0.78 : 0.0
    property real _poseGlow:                          // brillo interno (-1 apagado .. 1 intenso)
          currentState === "gaming"   ? 0.55
        : currentState === "music"    ? 0.45
        : currentState === "watching" ? 0.12
        : currentState === "typing"   ? 0.05
        : currentState === "sleeping" ? -0.55 : 0.0
    Behavior on _poseCrouch { NumberAnimation { duration: 750; easing.type: Easing.InOutCubic } }
    Behavior on _poseHead   { NumberAnimation { duration: 750; easing.type: Easing.InOutCubic } }
    Behavior on _poseWing   { NumberAnimation { duration: 750; easing.type: Easing.InOutCubic } }
    Behavior on _poseGlow   { NumberAnimation { duration: 750; easing.type: Easing.InOutCubic } }

    implicitWidth: 512 * scale
    implicitHeight: 512 * scale

    property real _breath: 0
    property real _wing: 0
    property real _tail: 0
    property real _ember: 0
    property real _lookX: 0
    property real _lookY: 0
    property real _stretch: 0
    property real _crouch: 0
    property real _fire: 0
    property real _snarl: 0

    SequentialAnimation on _breath {
        running: backend._ok
        loops: Animation.Infinite
        NumberAnimation { from: -1; to: 1; duration: backend._breathDur; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: -1; duration: backend._breathDur; easing.type: Easing.InOutSine }
    }

    SequentialAnimation on _wing {
        running: backend._ok
        loops: Animation.Infinite
        NumberAnimation { from: -1; to: 1; duration: backend._wingDur; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: -1; duration: backend._wingDur; easing.type: Easing.InOutSine }
    }

    SequentialAnimation on _tail {
        running: backend._ok
        loops: Animation.Infinite
        NumberAnimation { from: -1; to: 1; duration: 2800; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: -1; duration: 3000; easing.type: Easing.InOutSine }
    }

    SequentialAnimation on _ember {
        running: backend._ok
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: 960; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0; duration: 1220; easing.type: Easing.InOutSine }
    }

    Item {
        id: creature
        anchors.fill: parent
        transformOrigin: Item.Bottom
        y: backend._crouch * parent.height * 0.014 + backend._poseCrouch * parent.height * 0.042
        scale: 1.0 + backend._breath * 0.007 + (backend.talking ? backend._voice * 0.010 : 0)
        transform: Rotation {
            origin.x: creature.width * 0.40
            origin.y: creature.height * 0.82
            angle: (backend.headYaw + backend._lookX) * 1.2
            Behavior on angle { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        }

        Image {
            id: body
            anchors.fill: parent
            visible: backend._ok
            source: backend._ok ? backend.characterDir + backend.rig.body : ""
            fillMode: Image.PreserveAspectFit
            smooth: true
            transform: Scale {
                origin.x: body.width * 0.38
                origin.y: body.height * 0.78
                xScale: 1.0 + backend._breath * 0.010 + backend._crouch * 0.020 + backend._poseCrouch * 0.038
                yScale: 1.0 - backend._breath * 0.006 - backend._crouch * 0.018 - backend._poseCrouch * 0.048
            }
        }

        Image {
            anchors.fill: parent
            visible: backend._ok
            source: backend._ok ? backend.characterDir + backend.rig.tail : ""
            fillMode: Image.PreserveAspectFit
            smooth: true
            opacity: 0.42 + backend._stretch * 0.18
            transform: [
                Rotation {
                    origin.x: width * 0.67
                    origin.y: height * 0.77
                    angle: backend._tail * 2.8 - backend._crouch * 2.5
                },
                Translate {
                    x: backend._tail * parent.width * 0.006
                    y: Math.abs(backend._tail) * parent.height * 0.002
                }
            ]
        }

        Image {
            anchors.fill: parent
            visible: backend._ok
            source: backend._ok ? backend.characterDir + backend.rig.wing_l : ""
            fillMode: Image.PreserveAspectFit
            smooth: true
            opacity: 0.34 + backend._stretch * 0.20
            transform: [
                Rotation {
                    origin.x: width * 0.29
                    origin.y: height * 0.33
                    angle: backend._wing * backend._wingAmp * 4.8 - backend._stretch * 5.0 + backend._crouch * 1.4 - backend._poseWing * 6.5
                },
                Scale {
                    origin.x: width * 0.29
                    origin.y: height * 0.33
                    xScale: 1.0 + backend._stretch * 0.024
                    yScale: 1.0 + Math.abs(backend._wing) * 0.018 + backend._stretch * 0.035
                }
            ]
        }

        Image {
            anchors.fill: parent
            visible: backend._ok
            source: backend._ok ? backend.characterDir + backend.rig.wing_r : ""
            fillMode: Image.PreserveAspectFit
            smooth: true
            opacity: 0.48 + backend._stretch * 0.24
            transform: [
                Rotation {
                    origin.x: width * 0.60
                    origin.y: height * 0.31
                    angle: -backend._wing * backend._wingAmp * 7.2 + backend._stretch * 7.0 - backend._crouch * 1.8 + backend._poseWing * 9.0
                },
                Scale {
                    origin.x: width * 0.60
                    origin.y: height * 0.31
                    xScale: 1.0 + Math.abs(backend._wing) * 0.026 + backend._stretch * 0.044
                    yScale: 1.0 - Math.abs(backend._wing) * 0.014 + backend._stretch * 0.020
                }
            ]
        }

        Image {
            anchors.fill: parent
            visible: backend._ok
            source: backend._ok ? backend.characterDir + backend.rig.head : ""
            fillMode: Image.PreserveAspectFit
            smooth: true
            opacity: 0.18 + backend._snarl * 0.14
            transform: Translate {
                x: backend._lookX * parent.width * 0.003 - backend._crouch * parent.width * 0.004
                y: backend._lookY * parent.height * 0.003 + backend._breath * parent.height * 0.002 + backend._poseHead * parent.height * 0.012
                Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            }
        }

        Image {
            anchors.fill: parent
            visible: backend._ok
            source: backend._ok ? backend.characterDir + backend.rig.glow : ""
            fillMode: Image.PreserveAspectFit
            smooth: true
            opacity: Math.max(0, 0.28 + backend._ember * 0.18 + backend._fire * 0.30 + backend._snarl * 0.22 + backend._poseGlow * 0.22)
            scale: 1.0 + backend._ember * 0.016 + backend._fire * 0.030 + Math.max(0, backend._poseGlow) * 0.020
        }

        Image {
            anchors.fill: parent
            visible: backend._ok
            source: backend._ok ? backend.characterDir + backend.rig.mouth_glow : ""
            fillMode: Image.PreserveAspectFit
            smooth: true
            opacity: 0.18 + backend._snarl * 0.54 + backend._fire * 0.78 + (backend.talking ? backend._voice * 0.22 : 0)
            scale: 1.0 + backend._snarl * 0.035 + backend._fire * 0.060
        }

        Rectangle {
            id: mouthCharge
            visible: backend._ok
            width: parent.width * 0.050
            height: width * 0.48
            radius: height / 2
            x: parent.width * 0.108
            y: parent.height * 0.345
            color: "#fff0a8"
            opacity: backend._fire * 0.78 + backend._snarl * 0.42 + (backend.talking ? backend._voice * 0.22 : 0)
            scale: 0.6 + backend._fire * 1.25 + backend._snarl * 0.55
            transform: Rotation { origin.x: mouthCharge.width / 2; origin.y: mouthCharge.height / 2; angle: -10 }
            Behavior on opacity { NumberAnimation { duration: 70 } }
        }

        Item {
            id: flame
            visible: backend._fire > 0.02
            opacity: backend._fire
            x: parent.width * -0.425
            y: parent.height * 0.287
            width: parent.width * 0.545
            height: parent.height * 0.215
            transform: Rotation { origin.x: flame.width * 0.94; origin.y: flame.height * 0.52; angle: -7 }

            Image {
                anchors.fill: parent
                source: backend._ok && backend.rig.fire_breath !== undefined ? backend.characterDir + backend.rig.fire_breath : ""
                fillMode: Image.PreserveAspectFit
                smooth: true
                opacity: 0.96 + Math.sin(backend._ember * 6.28) * 0.04
                transform: [
                    Scale {
                        origin.x: flame.width * 0.92
                        origin.y: flame.height * 0.50
                        xScale: 0.92 + backend._fire * 0.16 + Math.sin(backend._ember * 6.28) * 0.025
                        yScale: 0.86 + backend._fire * 0.14 + Math.cos(backend._ember * 6.28) * 0.035
                    },
                    Translate {
                        x: Math.sin(backend._ember * 12.56) * flame.width * 0.012
                        y: Math.cos(backend._ember * 6.28) * flame.height * 0.020
                    }
                ]
            }

            Repeater {
                model: 16
                Rectangle {
                    width: Math.max(2, flame.width * 0.017)
                    height: width
                    radius: width / 2
                    x: flame.width * (0.18 + ((index * 37) % 80) / 100)
                    y: flame.height * (((index * 23) % 100) / 100)
                    color: index % 2 ? "#ffd36b" : "#ff4a12"
                    opacity: backend._fire * (0.16 + (index % 5) * 0.07)
                    scale: 0.5 + Math.abs(Math.sin(backend._ember * 6.28 + index)) * 1.25
                }
            }
        }

        Item {
            anchors.fill: parent
            visible: backend._ok && backend.currentState !== "sleeping"
            opacity: 0.46 + backend._fire * 0.30
            Repeater {
                model: 20
                Rectangle {
                    readonly property real drift: Math.sin(backend._ember * 6.28 + index * 0.61)
                    width: Math.max(1.5, parent.width * (0.005 + (index % 3) * 0.002))
                    height: width
                    radius: width / 2
                    x: parent.width * (0.18 + ((index * 29) % 58) / 100) + drift * parent.width * 0.010
                    y: parent.height * (0.34 + ((index * 17) % 44) / 100) - Math.abs(drift) * parent.height * 0.030
                    color: index % 4 === 0 ? "#ffe08a" : "#ff4a12"
                    opacity: (0.07 + (index % 5) * 0.023) * (1 + backend._fire * 2.2)
                    scale: 0.7 + Math.abs(drift) * 0.85
                }
            }
        }

    }

    Timer {
        id: idleBehavior
        running: backend._ok && backend.currentState === "idle" && !backend.talking
        repeat: true
        interval: 4200
        onTriggered: {
            var r = Math.random();
            if (r < 0.34) {
                backend._lookX = Math.random() * 1.0 - 0.5;
                backend._lookY = Math.random() * 0.6 - 0.3;
                interval = 3000 + Math.round(Math.random() * 2400);
                lookReset.restart();
            } else if (r < 0.70) {
                wingStretchAnim.restart();
                interval = 5600 + Math.round(Math.random() * 3400);
            } else {
                infernoAnim.restart();
                interval = 9800 + Math.round(Math.random() * 7000);
            }
        }
    }

    SequentialAnimation {
        id: lookReset
        PauseAnimation { duration: 1400 }
        ParallelAnimation {
            NumberAnimation { target: backend; property: "_lookX"; to: 0; duration: 760; easing.type: Easing.InOutCubic }
            NumberAnimation { target: backend; property: "_lookY"; to: 0; duration: 620; easing.type: Easing.InOutCubic }
        }
    }

    SequentialAnimation {
        id: wingStretchAnim
        NumberAnimation { target: backend; property: "_stretch"; from: 0; to: 1; duration: 660; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 760 }
        NumberAnimation { target: backend; property: "_stretch"; from: 1; to: 0; duration: 920; easing.type: Easing.InOutCubic }
    }

    SequentialAnimation {
        id: infernoAnim
        ParallelAnimation {
            NumberAnimation { target: backend; property: "_crouch"; from: 0; to: 1; duration: 900; easing.type: Easing.InOutCubic }
            NumberAnimation { target: backend; property: "_stretch"; from: 0; to: 0.75; duration: 900; easing.type: Easing.OutCubic }
            NumberAnimation { target: backend; property: "_snarl"; from: 0; to: 0.85; duration: 780; easing.type: Easing.OutCubic }
        }
        ParallelAnimation {
            NumberAnimation { target: backend; property: "_fire"; from: 0; to: 1; duration: 240; easing.type: Easing.OutCubic }
            NumberAnimation { target: backend; property: "_snarl"; from: 0.85; to: 1; duration: 240; easing.type: Easing.OutCubic }
        }
        PauseAnimation { duration: 1380 }
        ParallelAnimation {
            NumberAnimation { target: backend; property: "_fire"; from: 1; to: 0; duration: 620; easing.type: Easing.InQuad }
            NumberAnimation { target: backend; property: "_crouch"; from: 1; to: 0; duration: 720; easing.type: Easing.OutBack }
            NumberAnimation { target: backend; property: "_stretch"; from: 0.75; to: 0; duration: 840; easing.type: Easing.InOutCubic }
            NumberAnimation { target: backend; property: "_snarl"; from: 1; to: 0; duration: 520; easing.type: Easing.InQuad }
        }
    }

    Timer {
        id: entranceKick
        interval: 900
        repeat: false
        onTriggered: if (backend._ok) infernoAnim.restart()
    }

    onRigChanged: entranceKick.restart()
    Component.onCompleted: entranceKick.restart()
}
