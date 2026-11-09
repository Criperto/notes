import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Notas

Item {
    id: root

    property Window targetWindow: Window.window
    readonly property string mode: (typeof ConfigBackend !== "undefined" && ConfigBackend.windowControlsMode) ? ConfigBackend.windowControlsMode : "auto"
    readonly property bool isWmFloating: (typeof Sys !== "undefined") ? Sys.wmNeedsWindowControls : false
    readonly property bool shouldShow: mode === "always" || (mode === "auto" && isWmFloating)
    readonly property bool onLeft: (typeof Sys !== "undefined" && typeof Sys.windowControlsOnLeft !== "undefined") ? Sys.windowControlsOnLeft : false

    visible: shouldShow
    implicitWidth: shouldShow ? 104 : 0
    implicitHeight: 32

    Component {
        id: minBtnComp
        Rectangle {
            id: minBtn
            width: 32
            height: 32
            radius: 8
            color: minMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12) : "transparent"

            Behavior on color {
                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                ColorAnimation { duration: 120 }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 10
                height: 1.5
                radius: 0.5
                color: minMa.containsMouse ? Theme.text : Theme.muted
            }

            MouseArea {
                id: minMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.targetWindow) {
                        root.targetWindow.showMinimized();
                    }
                }
            }
        }
    }

    Component {
        id: maxBtnComp
        Rectangle {
            id: maxBtn
            width: 32
            height: 32
            radius: 8
            color: maxMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12) : "transparent"

            Behavior on color {
                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                ColorAnimation { duration: 120 }
            }

            readonly property bool isMax: root.targetWindow ? (root.targetWindow.visibility === Window.Maximized) : false

            Item {
                anchors.centerIn: parent
                width: 10
                height: 10

                // Icono maximizar (cuadrado simple)
                Rectangle {
                    visible: !maxBtn.isMax
                    anchors.fill: parent
                    color: "transparent"
                    border.width: 1.2
                    border.color: maxMa.containsMouse ? Theme.text : Theme.muted
                    radius: 1
                }

                // Icono restaurar (dos cuadrados superpuestos)
                Item {
                    visible: maxBtn.isMax
                    anchors.fill: parent

                    Rectangle {
                        x: 2; y: 0
                        width: 7; height: 7
                        color: "transparent"
                        border.width: 1
                        border.color: maxMa.containsMouse ? Theme.text : Theme.muted
                        radius: 0.5
                    }
                    Rectangle {
                        x: 0; y: 2
                        width: 7; height: 7
                        color: maxMa.containsMouse ? Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.95) : Theme.surface
                        border.width: 1
                        border.color: maxMa.containsMouse ? Theme.text : Theme.muted
                        radius: 0.5
                    }
                }
            }

            MouseArea {
                id: maxMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!root.targetWindow) return;
                    if (root.targetWindow.visibility === Window.Maximized) {
                        root.targetWindow.showNormal();
                    } else {
                        root.targetWindow.showMaximized();
                    }
                }
            }
        }
    }

    Component {
        id: closeBtnComp
        Rectangle {
            id: closeBtn
            width: 32
            height: 32
            radius: 8
            color: closeMa.containsMouse ? Theme.danger : "transparent"

            Behavior on color {
                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                ColorAnimation { duration: 120 }
            }

            Item {
                anchors.centerIn: parent
                width: 10
                height: 10

                Rectangle {
                    anchors.centerIn: parent
                    width: 11
                    height: 1.3
                    radius: 0.6
                    rotation: 45
                    color: closeMa.containsMouse ? "#ffffff" : Theme.muted
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 11
                    height: 1.3
                    radius: 0.6
                    rotation: -45
                    color: closeMa.containsMouse ? "#ffffff" : Theme.muted
                }
            }

            MouseArea {
                id: closeMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.targetWindow) {
                        root.targetWindow.close();
                    }
                }
            }
        }
    }

    Row {
        id: buttonsRow
        anchors.left: root.onLeft ? parent.left : undefined
        anchors.right: root.onLeft ? undefined : parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Repeater {
            model: root.onLeft ? ["close", "min", "max"] : ["min", "max", "close"]
            Loader {
                sourceComponent: modelData === "close" ? closeBtnComp : (modelData === "min" ? minBtnComp : maxBtnComp)
            }
        }
    }
}
