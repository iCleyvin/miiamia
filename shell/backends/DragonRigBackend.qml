// DragonRigBackend.qml — rig 2.5D especifico para Averno.
//
// No pretende ser un Live2D real: parte de capas extraidas de una sola imagen y les da vida con
// transformaciones, glow y fuego procedural. Es el puente pragmatico entre "sprite bonito" y pet viva.
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
    readonly property int _flapDur: currentState === "music" ? 640
        : currentState === "gaming" ? 900
        : currentState === "sleeping" ? 3200
        : 1450
    readonly property real _flapAmp: currentState === "music" ? 1.0
        : currentState === "gaming" ? 0.82
        : currentState === "sleeping" ? 0.18
        : 0.62

    implicitWidth: 512 * scale
    implicitHeight: 512 * scale

    property real _breath: 0
    property real _flap: 0
    property real _tail: 0
    property real _firePulse: 0
    property real _chargePulse: 0
    property real _emberPulse: 0
    property real _lookX: 0
    property real _lookY: 0
    property real _wingStretch: 0
    property real _bodyCrouch: 0
    property real _snarl: 0

    SequentialAnimation on _breath {
        running: backend._ok
        loops: Animation.Infinite
        NumberAnimation { from: -1; to: 1; duration: 1700; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: -1; duration: 1700; easing.type: Easing.InOutSine }
    }

    SequentialAnimation on _flap {
        running: backend._ok
        loops: Animation.Infinite
        NumberAnimation { from: -1; to: 1; duration: backend._flapDur; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: -1; duration: backend._flapDur; easing.type: Easing.InOutSine }
    }

    SequentialAnimation on _tail {
        running: backend._ok
        loops: Animation.Infinite
        NumberAnimation { from: -1; to: 1; duration: 2400; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: -1; duration: 2600; easing.type: Easing.InOutSine }
    }

    SequentialAnimation on _emberPulse {
        running: backend._ok
        loops: Animation.Infinite
        NumberAnimation { from: 0.55; to: 1.0; duration: 920; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1.0; to: 0.55; duration: 1280; easing.type: Easing.InOutSine }
    }

    Item {
        id: creature
        anchors.fill: parent
        transformOrigin: Item.Bottom
        scale: 1.0 + backend._breath * 0.010 + (backend.talking ? backend._voice * 0.014 : 0)
        y: backend._bodyCrouch * parent.height * 0.018
        transform: [
            Rotation {
                origin.x: creature.width * 0.38
                origin.y: creature.height * 0.78
                angle: (backend.headYaw + backend._lookX) * 1.8
                Behavior on angle { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            },
            Scale {
                origin.x: creature.width * 0.38
                origin.y: creature.height * 0.78
                xScale: 1.0 + backend._bodyCrouch * 0.030
                yScale: 1.0 - backend._bodyCrouch * 0.026
            }
        ]

        // Tail behind the body, slow and heavy.
        Image {
            anchors.fill: parent
            visible: backend._ok
            source: backend._ok ? backend.characterDir + backend.rig.tail : ""
            fillMode: Image.PreserveAspectFit
            smooth: true
            transform: Rotation {
                origin.x: width * 0.68
                origin.y: height * 0.75
                angle: backend._tail * 4.2 - backend._chargePulse * 4
            }
        }

        Image {
            anchors.fill: parent
            visible: backend._ok
            source: backend._ok ? backend.characterDir + backend.rig.wing_l : ""
            fillMode: Image.PreserveAspectFit
            smooth: true
            transform: [
                Rotation {
                    origin.x: width * 0.30
                    origin.y: height * 0.38
                    angle: -2 + backend._flap * backend._flapAmp * 6 - backend._wingStretch * 8 + backend._chargePulse * 3
                },
                Scale {
                    origin.x: width * 0.30
                    origin.y: height * 0.38
                    xScale: 1.0 - Math.abs(backend._flap) * 0.025 + backend._wingStretch * 0.055
                    yScale: 1.0 + Math.abs(backend._flap) * 0.050 + backend._wingStretch * 0.045
                }
            ]
        }

        Image {
            id: body
            anchors.fill: parent
            visible: backend._ok
            source: backend._ok ? backend.characterDir + backend.rig.body : ""
            fillMode: Image.PreserveAspectFit
            smooth: true
            transform: Scale {
                origin.x: width * 0.38
                origin.y: height * 0.76
                xScale: 1.0 + backend._breath * 0.012
                yScale: 1.0 - backend._breath * 0.008
            }
        }

        Image {
            anchors.fill: parent
            visible: backend._ok
            source: backend._ok ? backend.characterDir + backend.rig.wing_r : ""
            fillMode: Image.PreserveAspectFit
            smooth: true
            transform: [
                Rotation {
                    origin.x: width * 0.58
                    origin.y: height * 0.32
                    angle: 5 - backend._flap * backend._flapAmp * 10 + backend._wingStretch * 12 - backend._chargePulse * 3
                },
                Scale {
                    origin.x: width * 0.58
                    origin.y: height * 0.32
                    xScale: 1.0 + Math.abs(backend._flap) * 0.045 + backend._wingStretch * 0.080
                    yScale: 1.0 - Math.abs(backend._flap) * 0.035 + backend._wingStretch * 0.035
                }
            ]
        }

        Image {
            id: head
            anchors.fill: parent
            visible: backend._ok
            source: backend._ok ? backend.characterDir + backend.rig.head : ""
            fillMode: Image.PreserveAspectFit
            smooth: true
            transform: [
                Rotation {
                    origin.x: width * 0.35
                    origin.y: height * 0.33
                    // Keep head motion tiny: this layer was cut from one PNG, so large rotations
                    // break the horn silhouette. Cursor attention lives on the whole creature.
                    angle: backend._lookX * 1.4 + backend._tail * 0.35 - backend._chargePulse * 2.0
                    Behavior on angle { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                },
                Translate {
                    x: backend._lookX * 1.2 - backend._chargePulse * parent.width * 0.010
                    y: backend._lookY * 1.2 + backend._breath * 1.2 + backend._chargePulse * parent.height * 0.010
                    Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                }
            ]
        }

        Image {
            anchors.fill: parent
            visible: backend._ok
            source: backend._ok ? backend.characterDir + backend.rig.glow : ""
            fillMode: Image.PreserveAspectFit
            smooth: true
            opacity: 0.30 + backend._emberPulse * 0.22 + backend._chargePulse * 0.42 + (backend.talking ? backend._voice * 0.28 : 0)
            scale: 1.0 + backend._emberPulse * 0.018 + backend._firePulse * 0.045 + backend._chargePulse * 0.035
        }

        Rectangle {
            id: mouthCharge
            visible: backend._ok
            width: parent.width * 0.060
            height: width * 0.55
            radius: height / 2
            x: parent.width * 0.145
            y: parent.height * 0.405
            color: "#ff5a12"
            opacity: backend._firePulse * 0.88 + backend._chargePulse * 0.76 + (backend.talking ? backend._voice * 0.42 : 0)
            scale: 0.7 + backend._firePulse * 1.4 + backend._chargePulse * 0.9
            transform: Rotation { origin.x: mouthCharge.width / 2; origin.y: mouthCharge.height / 2; angle: 10 }
            Behavior on opacity { NumberAnimation { duration: 70 } }
        }

        Rectangle {
            id: snarlGlow
            visible: backend._ok
            width: parent.width * 0.048
            height: width * 0.36
            radius: height / 2
            x: parent.width * 0.132
            y: parent.height * 0.425
            color: "#fff0b0"
            opacity: backend._snarl * 0.82
            scale: 0.6 + backend._snarl * 1.1
            transform: Rotation { origin.x: snarlGlow.width / 2; origin.y: snarlGlow.height / 2; angle: 9 }
        }

        Item {
            id: flame
            visible: backend._firePulse > 0.02
            opacity: backend._firePulse
            x: parent.width * -0.105
            y: parent.height * 0.390
            width: parent.width * 0.27
            height: parent.height * 0.14
            transform: Rotation { origin.x: flame.width * 0.95; origin.y: flame.height * 0.34; angle: 8 }

            Repeater {
                model: 11
                Rectangle {
                    readonly property real phase: (index % 4) / 4
                    width: flame.width * (0.16 - index * 0.006)
                    height: flame.height * (0.34 + (index % 3) * 0.12)
                    radius: width / 2
                    x: flame.width * (0.86 - index * 0.075) + Math.sin(backend._emberPulse * 6.28 + index) * flame.width * 0.018
                    y: flame.height * (0.28 + Math.sin(index * 1.7 + backend._emberPulse * 5) * 0.18)
                    color: index < 3 ? "#fff2a8" : index < 7 ? "#ff7a18" : "#cf180b"
                    opacity: Math.max(0, 0.85 - index * 0.055) * backend._firePulse
                    scale: 0.6 + backend._firePulse * (1.0 + index * 0.045)
                    transform: Rotation { origin.x: width / 2; origin.y: height / 2; angle: -68 + index * 4 }
                }
            }

            Repeater {
                model: 14
                Rectangle {
                    width: Math.max(2, flame.width * 0.018)
                    height: width
                    radius: width / 2
                    x: flame.width * (0.18 + ((index * 37) % 80) / 100)
                    y: flame.height * (((index * 19) % 100) / 100)
                    color: index % 2 ? "#ffd36b" : "#ff4a12"
                    opacity: backend._firePulse * (0.18 + (index % 5) * 0.08)
                    scale: 0.5 + Math.abs(Math.sin(backend._emberPulse * 6.28 + index)) * 1.3
                }
            }
        }

        Item {
            id: bodyEmbers
            anchors.fill: parent
            visible: backend._ok && backend.currentState !== "sleeping"
            opacity: 0.55 + backend._chargePulse * 0.45
            Repeater {
                model: 18
                Rectangle {
                    readonly property real drift: Math.sin(backend._emberPulse * 6.28 + index * 0.73)
                    width: Math.max(1.5, parent.width * (0.006 + (index % 3) * 0.002))
                    height: width
                    radius: width / 2
                    x: parent.width * (0.16 + ((index * 29) % 54) / 100) + drift * parent.width * 0.012
                    y: parent.height * (0.34 + ((index * 17) % 46) / 100) - Math.abs(drift) * parent.height * 0.035
                    color: index % 4 === 0 ? "#ffd36b" : "#ff4a12"
                    opacity: (0.08 + (index % 5) * 0.025) * (1 + backend._chargePulse * 2.8)
                    scale: 0.7 + Math.abs(drift) * 0.9
                }
            }
        }
    }

    Timer {
        id: idleBehavior
        running: backend._ok && backend.currentState === "idle" && !backend.talking
        repeat: true
        interval: 5200
        onTriggered: {
            var r = Math.random();
            if (r < 0.38) {
                backend._lookX = Math.random() * 1.4 - 0.7;
                backend._lookY = Math.random() * 0.7 - 0.35;
                interval = 3600 + Math.round(Math.random() * 2800);
                lookReset.restart();
            } else if (r < 0.72) {
                wingStretchAnim.restart();
                interval = 6800 + Math.round(Math.random() * 4200);
            } else {
                infernoAnim.restart();
                interval = 12500 + Math.round(Math.random() * 9000);
            }
        }
    }

    SequentialAnimation {
        id: lookReset
        PauseAnimation { duration: 1700 }
        NumberAnimation { target: backend; property: "_lookX"; to: 0; duration: 900; easing.type: Easing.InOutCubic }
        NumberAnimation { target: backend; property: "_lookY"; to: 0; duration: 600; easing.type: Easing.InOutCubic }
    }

    SequentialAnimation {
        id: wingStretchAnim
        NumberAnimation { target: backend; property: "_wingStretch"; from: 0; to: 1; duration: 620; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 780 }
        NumberAnimation { target: backend; property: "_wingStretch"; from: 1; to: 0; duration: 900; easing.type: Easing.InOutCubic }
    }

    SequentialAnimation {
        id: infernoAnim
        ParallelAnimation {
            NumberAnimation { target: backend; property: "_chargePulse"; from: 0; to: 1; duration: 1050; easing.type: Easing.InCubic }
            NumberAnimation { target: backend; property: "_bodyCrouch"; from: 0; to: 1; duration: 1050; easing.type: Easing.InOutCubic }
            NumberAnimation { target: backend; property: "_wingStretch"; from: 0; to: 0.65; duration: 1050; easing.type: Easing.OutCubic }
            NumberAnimation { target: backend; property: "_snarl"; from: 0; to: 0.75; duration: 760; easing.type: Easing.OutCubic }
        }
        ParallelAnimation {
            NumberAnimation { target: backend; property: "_firePulse"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
            NumberAnimation { target: backend; property: "_snarl"; from: 0.75; to: 1; duration: 260; easing.type: Easing.OutCubic }
        }
        PauseAnimation { duration: 1120 }
        ParallelAnimation {
            NumberAnimation { target: backend; property: "_firePulse"; from: 1; to: 0; duration: 620; easing.type: Easing.InQuad }
            NumberAnimation { target: backend; property: "_chargePulse"; from: 1; to: 0; duration: 760; easing.type: Easing.OutCubic }
            NumberAnimation { target: backend; property: "_bodyCrouch"; from: 1; to: 0; duration: 720; easing.type: Easing.OutBack }
            NumberAnimation { target: backend; property: "_wingStretch"; from: 0.65; to: 0; duration: 820; easing.type: Easing.InOutCubic }
            NumberAnimation { target: backend; property: "_snarl"; from: 1; to: 0; duration: 520; easing.type: Easing.InQuad }
        }
    }

    // Small entrance blast so the new pet visibly demonstrates the rig after selection/restart.
    Timer {
        running: backend._ok
        interval: 1200
        repeat: false
        onTriggered: infernoAnim.restart()
    }
}
