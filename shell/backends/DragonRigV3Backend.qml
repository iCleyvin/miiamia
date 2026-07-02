// DragonRigV3Backend.qml - Averno v3, rig por partes con pivotes declarados.
//
// A diferencia de DragonRigV2, aqui cada parte anatomica es una capa propia. El manifest define
// los assets y pivotes; el backend solo compone, anima y mezcla estados.
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

    readonly property bool _ok: rig !== null && rig !== undefined && rig.parts !== undefined
    readonly property real _voice: Math.max(0, Math.min(1, voiceAmplitude))
    readonly property int _breathDur: currentState === "sleeping" ? 3100 : 1850
    readonly property int _wingDur: currentState === "music" ? 720
        : currentState === "gaming" ? 980
        : currentState === "sleeping" ? 3800
        : currentState === "typing" ? 2300
        : currentState === "watching" ? 2700
        : 1650
    readonly property real _wingAmp: currentState === "sleeping" ? 0.12
        : currentState === "music" ? 1.0
        : currentState === "gaming" ? 0.74
        : currentState === "typing" ? 0.28
        : currentState === "watching" ? 0.22
        : 0.56
    property real _poseCrouch: currentState === "sleeping" ? 1.0
        : currentState === "watching" ? 0.32
        : currentState === "gaming" ? 0.24
        : currentState === "typing" ? 0.14
        : currentState === "browsing" ? 0.12
        : 0.0
    property real _poseHead: currentState === "sleeping" ? 0.65
        : currentState === "typing" ? 0.52
        : currentState === "browsing" ? 0.30
        : currentState === "watching" ? -0.34
        : currentState === "gaming" ? -0.18
        : 0.0
    property real _poseWing: currentState === "sleeping" ? -0.72
        : currentState === "typing" ? -0.38
        : currentState === "watching" ? -0.24
        : currentState === "gaming" ? 0.68
        : currentState === "music" ? 0.54
        : 0.0
    property real _poseGlow: currentState === "sleeping" ? -0.45
        : currentState === "gaming" ? 0.55
        : currentState === "music" ? 0.42
        : currentState === "watching" ? 0.12
        : 0.0

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
    property int _fireFrame: 0
    property real _snarl: 0

    function part(name) {
        return _ok && rig.parts[name] !== undefined ? characterDir + rig.parts[name] : "";
    }

    function fireFrame(offset) {
        if (!_ok || rig.fire === undefined || rig.fire.frames === undefined || rig.fire.frames.length === 0)
            return part("fire_breath");
        var index = (_fireFrame + offset) % rig.fire.frames.length;
        return characterDir + rig.fire.frames[index];
    }

    function pivot(name, key, fallback) {
        if (!_ok || rig.pivots === undefined || rig.pivots[name] === undefined || rig.pivots[name][key] === undefined)
            return fallback;
        return rig.pivots[name][key];
    }

    Behavior on _poseCrouch { NumberAnimation { duration: 760; easing.type: Easing.InOutCubic } }
    Behavior on _poseHead { NumberAnimation { duration: 760; easing.type: Easing.InOutCubic } }
    Behavior on _poseWing { NumberAnimation { duration: 760; easing.type: Easing.InOutCubic } }
    Behavior on _poseGlow { NumberAnimation { duration: 760; easing.type: Easing.InOutCubic } }

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
        NumberAnimation { from: -1; to: 1; duration: 2600; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: -1; duration: 3100; easing.type: Easing.InOutSine }
    }

    SequentialAnimation on _ember {
        running: backend._ok
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: 940; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0; duration: 1240; easing.type: Easing.InOutSine }
    }

    Item {
        id: creature
        anchors.fill: parent
        y: backend._crouch * height * 0.014 + backend._poseCrouch * height * 0.040
        scale: 1.0 + backend._breath * 0.006 + (backend.talking ? backend._voice * 0.010 : 0)
        transformOrigin: Item.Bottom
        transform: Rotation {
            origin.x: creature.width * 0.40
            origin.y: creature.height * 0.83
            angle: (backend.headYaw + backend._lookX) * 1.0
            Behavior on angle { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        }

        Image {
            id: tail
            anchors.fill: parent
            source: backend.part("tail")
            fillMode: Image.PreserveAspectFit
            smooth: true
            transform: [
                Rotation {
                    origin.x: tail.width * backend.pivot("tail", "x", 0.66)
                    origin.y: tail.height * backend.pivot("tail", "y", 0.73)
                    angle: backend._tail * 4.2 - backend._crouch * 4.0 - backend._poseCrouch * 2.2
                },
                Translate {
                    x: backend._tail * parent.width * 0.010
                    y: Math.abs(backend._tail) * parent.height * 0.003
                }
            ]
        }

        Image {
            id: wingL
            anchors.fill: parent
            source: backend.part("wing_l")
            fillMode: Image.PreserveAspectFit
            smooth: true
            transform: [
                Rotation {
                    origin.x: wingL.width * backend.pivot("wing_l", "x", 0.29)
                    origin.y: wingL.height * backend.pivot("wing_l", "y", 0.35)
                    angle: backend._wing * backend._wingAmp * 7.2 - backend._stretch * 7.0 - backend._poseWing * 9.0
                },
                Scale {
                    origin.x: wingL.width * backend.pivot("wing_l", "x", 0.29)
                    origin.y: wingL.height * backend.pivot("wing_l", "y", 0.35)
                    xScale: 1.0 + backend._stretch * 0.030
                    yScale: 1.0 + Math.abs(backend._wing) * 0.026 + backend._stretch * 0.050
                }
            ]
        }

        Image {
            id: hindLegs
            anchors.fill: parent
            source: backend.part("hind_legs")
            fillMode: Image.PreserveAspectFit
            smooth: true
            transform: [
                Rotation {
                    origin.x: hindLegs.width * backend.pivot("hind_legs", "x", 0.60)
                    origin.y: hindLegs.height * backend.pivot("hind_legs", "y", 0.78)
                    angle: backend.currentState === "gaming" ? backend._tail * 1.2 : backend._breath * 0.35
                },
                Translate { y: backend._poseCrouch * parent.height * 0.008 }
            ]
        }

        Image {
            id: body
            anchors.fill: parent
            source: backend.part("body")
            fillMode: Image.PreserveAspectFit
            smooth: true
            transform: Scale {
                origin.x: body.width * backend.pivot("body", "x", 0.38)
                origin.y: body.height * backend.pivot("body", "y", 0.78)
                xScale: 1.0 + backend._breath * 0.010 + backend._crouch * 0.018 + backend._poseCrouch * 0.035
                yScale: 1.0 - backend._breath * 0.006 - backend._crouch * 0.018 - backend._poseCrouch * 0.046
            }
        }

        Image {
            id: frontLegs
            anchors.fill: parent
            source: backend.part("front_legs")
            fillMode: Image.PreserveAspectFit
            smooth: true
            transform: [
                Rotation {
                    origin.x: frontLegs.width * backend.pivot("front_legs", "x", 0.28)
                    origin.y: frontLegs.height * backend.pivot("front_legs", "y", 0.79)
                    angle: backend.currentState === "typing" ? backend._wing * 1.1 : backend._breath * 0.45
                },
                Translate { y: -backend._poseCrouch * parent.height * 0.006 }
            ]
        }

        Image {
            id: wingR
            anchors.fill: parent
            source: backend.part("wing_r")
            fillMode: Image.PreserveAspectFit
            smooth: true
            transform: [
                Rotation {
                    origin.x: wingR.width * backend.pivot("wing_r", "x", 0.60)
                    origin.y: wingR.height * backend.pivot("wing_r", "y", 0.31)
                    angle: -backend._wing * backend._wingAmp * 5.4 + backend._stretch * 5.2 + backend._poseWing * 6.2
                },
                Scale {
                    origin.x: wingR.width * backend.pivot("wing_r", "x", 0.60)
                    origin.y: wingR.height * backend.pivot("wing_r", "y", 0.31)
                    xScale: 1.0 + Math.abs(backend._wing) * 0.018 + backend._stretch * 0.032
                    yScale: 1.0 - Math.abs(backend._wing) * 0.010 + backend._stretch * 0.018
                }
            ]
        }

        Image {
            id: head
            anchors.fill: parent
            source: backend.part("head")
            fillMode: Image.PreserveAspectFit
            smooth: true
            transform: [
                Rotation {
                    origin.x: head.width * backend.pivot("head", "x", 0.30)
                    origin.y: head.height * backend.pivot("head", "y", 0.42)
                    angle: backend._lookX * 2.4 + backend.headYaw * 2.0 - backend._snarl * 2.8 + backend._poseHead * 1.4
                    Behavior on angle { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                },
                Translate {
                    x: backend._lookX * parent.width * 0.006 - backend._crouch * parent.width * 0.006
                    y: backend._lookY * parent.height * 0.006 + backend._breath * parent.height * 0.003 + backend._poseHead * parent.height * 0.014
                    Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                }
            ]
        }

        Image {
            anchors.fill: parent
            source: backend.part("chest_glow")
            fillMode: Image.PreserveAspectFit
            smooth: true
            opacity: Math.max(0, 0.35 + backend._ember * 0.22 + backend._fire * 0.36 + backend._poseGlow * 0.24)
            scale: 1.0 + backend._ember * 0.018 + backend._fire * 0.036 + Math.max(0, backend._poseGlow) * 0.022
        }

        Image {
            anchors.fill: parent
            source: backend.part("eye_glow")
            fillMode: Image.PreserveAspectFit
            smooth: true
            opacity: backend.currentState === "sleeping" ? 0.10 : 0.55 + backend._snarl * 0.34 + backend._fire * 0.20
        }

        Image {
            anchors.fill: parent
            source: backend.part("mouth_glow")
            fillMode: Image.PreserveAspectFit
            smooth: true
            opacity: 0.12 + backend._snarl * 0.42 + backend._fire * 0.82 + (backend.talking ? backend._voice * 0.24 : 0)
            scale: 1.0 + backend._snarl * 0.045 + backend._fire * 0.070
        }

        Item {
            id: flame
            visible: backend._fire > 0.02
            opacity: backend._fire
            x: parent.width * -0.438
            y: parent.height * 0.306
            width: parent.width * 0.520
            height: parent.height * 0.205
            transform: Rotation {
                origin.x: flame.width * 0.96
                origin.y: flame.height * 0.50
                angle: -8 + Math.sin(backend._ember * 6.28) * 1.4
            }

            Image {
                id: fireUpper
                anchors.fill: parent
                source: backend.fireFrame(0)
                fillMode: Image.PreserveAspectFit
                smooth: true
                opacity: 0.42 + Math.sin(backend._ember * 6.28 + 0.7) * 0.08
                transform: [
                    Scale {
                        origin.x: flame.width * 0.96
                        origin.y: flame.height * 0.48
                        xScale: 0.86 + backend._fire * 0.14 + Math.sin(backend._ember * 6.28 + 0.8) * 0.035
                        yScale: 0.72 + backend._fire * 0.11 + Math.cos(backend._ember * 6.28 + 0.3) * 0.040
                    },
                    Translate {
                        x: flame.width * -0.038 + Math.sin(backend._ember * 12.56) * flame.width * 0.012
                        y: flame.height * -0.085 + Math.cos(backend._ember * 6.28) * flame.height * 0.020
                    },
                    Rotation {
                        origin.x: flame.width * 0.96
                        origin.y: flame.height * 0.48
                        angle: -3 + Math.sin(backend._ember * 6.28 + 1.4) * 1.2
                    }
                ]
            }

            Image {
                id: fireLower
                anchors.fill: parent
                source: backend.fireFrame(3)
                fillMode: Image.PreserveAspectFit
                smooth: true
                opacity: 0.34 + Math.sin(backend._ember * 6.28 + 2.2) * 0.06
                transform: [
                    Scale {
                        origin.x: flame.width * 0.96
                        origin.y: flame.height * 0.54
                        xScale: 0.80 + backend._fire * 0.12 + Math.sin(backend._ember * 6.28 + 2.0) * 0.030
                        yScale: 0.66 + backend._fire * 0.10 + Math.cos(backend._ember * 6.28 + 2.7) * 0.036
                    },
                    Translate {
                        x: flame.width * -0.034 + Math.sin(backend._ember * 12.56 + 0.8) * flame.width * 0.011
                        y: flame.height * 0.090 + Math.cos(backend._ember * 6.28 + 1.6) * flame.height * 0.020
                    },
                    Rotation {
                        origin.x: flame.width * 0.96
                        origin.y: flame.height * 0.54
                        angle: 4 + Math.sin(backend._ember * 6.28 + 2.6) * 1.2
                    }
                ]
            }

            Image {
                id: fireCore
                anchors.fill: parent
                source: backend.fireFrame(6)
                fillMode: Image.PreserveAspectFit
                smooth: true
                opacity: 0.82 + Math.sin(backend._ember * 6.28 + 1.1) * 0.05
                transform: [
                    Scale {
                        origin.x: flame.width * 0.97
                        origin.y: flame.height * 0.51
                        xScale: 0.68 + backend._fire * 0.12 + Math.sin(backend._ember * 6.28) * 0.018
                        yScale: 0.54 + backend._fire * 0.10 + Math.cos(backend._ember * 6.28) * 0.026
                    },
                    Translate {
                        x: flame.width * -0.010 + Math.sin(backend._ember * 12.56 + 2.2) * flame.width * 0.008
                        y: Math.cos(backend._ember * 6.28 + 0.5) * flame.height * 0.012
                    }
                ]
            }
        }

        Item {
            anchors.fill: parent
            visible: backend._ok && backend.currentState !== "sleeping"
            opacity: 0.42 + backend._fire * 0.30
            Repeater {
                model: 22
                Rectangle {
                    readonly property real drift: Math.sin(backend._ember * 6.28 + index * 0.61)
                    width: Math.max(1.5, parent.width * (0.005 + (index % 3) * 0.002))
                    height: width
                    radius: width / 2
                    x: parent.width * (0.16 + ((index * 31) % 62) / 100) + drift * parent.width * 0.010
                    y: parent.height * (0.30 + ((index * 17) % 48) / 100) - Math.abs(drift) * parent.height * 0.030
                    color: index % 4 === 0 ? "#ffe08a" : "#ff4a12"
                    opacity: (0.06 + (index % 5) * 0.022) * (1 + backend._fire * 2.0)
                    scale: 0.7 + Math.abs(drift) * 0.85
                }
            }
        }
    }

    Timer {
        id: fireFrameTimer
        running: backend._ok && backend._fire > 0.02
        repeat: true
        interval: backend._ok && backend.rig.fire !== undefined && backend.rig.fire.fps !== undefined
            ? Math.max(24, Math.round(1000 / backend.rig.fire.fps))
            : 56
        onTriggered: {
            var frameCount = backend.rig.fire !== undefined && backend.rig.fire.frames !== undefined
                ? backend.rig.fire.frames.length
                : 1;
            backend._fireFrame = (backend._fireFrame + 1) % Math.max(1, frameCount);
        }
    }

    Timer {
        id: idleBehavior
        running: backend._ok && backend.currentState === "idle" && !backend.talking
        repeat: true
        interval: 4000
        onTriggered: {
            var r = Math.random();
            if (r < 0.34) {
                backend._lookX = Math.random() * 1.0 - 0.5;
                backend._lookY = Math.random() * 0.6 - 0.3;
                interval = 2900 + Math.round(Math.random() * 2300);
                lookReset.restart();
            } else if (r < 0.70) {
                wingStretchAnim.restart();
                interval = 5400 + Math.round(Math.random() * 3200);
            } else {
                infernoAnim.restart();
                interval = 9000 + Math.round(Math.random() * 6500);
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
        NumberAnimation { target: backend; property: "_stretch"; from: 0; to: 1; duration: 620; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 740 }
        NumberAnimation { target: backend; property: "_stretch"; from: 1; to: 0; duration: 920; easing.type: Easing.InOutCubic }
    }

    SequentialAnimation {
        id: infernoAnim
        ParallelAnimation {
            NumberAnimation { target: backend; property: "_crouch"; from: 0; to: 1; duration: 860; easing.type: Easing.InOutCubic }
            NumberAnimation { target: backend; property: "_stretch"; from: 0; to: 0.82; duration: 860; easing.type: Easing.OutCubic }
            NumberAnimation { target: backend; property: "_snarl"; from: 0; to: 0.88; duration: 720; easing.type: Easing.OutCubic }
        }
        ParallelAnimation {
            NumberAnimation { target: backend; property: "_fire"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { target: backend; property: "_snarl"; from: 0.88; to: 1; duration: 220; easing.type: Easing.OutCubic }
        }
        PauseAnimation { duration: 1380 }
        ParallelAnimation {
            NumberAnimation { target: backend; property: "_fire"; from: 1; to: 0; duration: 620; easing.type: Easing.InQuad }
            NumberAnimation { target: backend; property: "_crouch"; from: 1; to: 0; duration: 720; easing.type: Easing.OutBack }
            NumberAnimation { target: backend; property: "_stretch"; from: 0.82; to: 0; duration: 840; easing.type: Easing.InOutCubic }
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
