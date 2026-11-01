import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Notas

Rectangle {
    id: root

    property string text: ""
    property string textBuffer: text
    property string placeholder: ""
    property string iconSource: ""
    property string actionButtonText: ""
    property string actionButtonIcon: ""
    signal actionTriggered()
    signal accepted(string value)
    signal acceptedText(string value)

    onTextChanged: {
        if (!textInput.activeFocus && textBuffer !== text) {
            textBuffer = text;
        }
    }

    implicitHeight: 38
    radius: 10
    color: Qt.hsva(Theme.surface.hsvHue,
                   Math.min(1, Theme.surface.hsvSaturation),
                   Math.min(1, Theme.surface.hsvValue + 0.04), 1)
    border.color: textInput.activeFocus
        ? Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.65)
        : Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.12)
    border.width: 1

    Behavior on border.color {
        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
        ColorAnimation { duration: 150 }
    }

    function commit() {
        if (root.text !== root.textBuffer) {
            root.text = root.textBuffer;
            root.accepted(root.textBuffer);
            root.acceptedText(root.textBuffer);
        }
    }

    RowLayout {
        anchors {
            fill: parent
            leftMargin: 10
            rightMargin: 8
        }
        spacing: 8

        // Icono izquierdo opcional
        Image {
            visible: root.iconSource !== ""
            Layout.preferredWidth: 15
            Layout.preferredHeight: 15
            source: root.iconSource
            sourceSize: Qt.size(15, 15)
            smooth: true
            mipmap: true
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: textInput.activeFocus ? Theme.accent : Theme.muted
                Behavior on colorizationColor {
                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                    ColorAnimation { duration: 150 }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                text: root.placeholder
                color: Theme.muted
                font {
                    pixelSize: Theme.fontSizeBody
                    family: Theme.fontFamily
                }
                visible: root.textBuffer === "" && !textInput.activeFocus
                elide: Text.ElideRight
            }

            TextInput {
                id: textInput
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                text: root.textBuffer
                color: Theme.text
                clip: true
                font {
                    pixelSize: Theme.fontSizeBody
                    family: Theme.fontFamily
                }
                selectByMouse: true
                CustomTextCursor {}

                onTextEdited: {
                    root.textBuffer = text;
                }

                onActiveFocusChanged: {
                    if (!activeFocus) {
                        root.commit();
                    }
                }

                Keys.onReturnPressed: (event) => {
                    root.commit();
                    event.accepted = true;
                }
                Keys.onEnterPressed: (event) => Keys.onReturnPressed(event)

                Keys.onEscapePressed: {
                    root.textBuffer = root.text;
                    text = root.text;
                    focus = false;
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) {
                            textInput.forceActiveFocus();
                            sharedInputContextMenu.open(textInput);
                        }
                    }
                }
            }
        }

        // Botón limpiar texto (✕)
        Rectangle {
            visible: root.textBuffer !== ""
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            radius: 10
            color: clearHov.hovered
                ? Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.14)
                : "transparent"

            HoverHandler { id: clearHov }

            Text {
                anchors.centerIn: parent
                text: "✕"
                color: Theme.muted
                font.pixelSize: 10
                font.family: Theme.fontFamily
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.textBuffer = "";
                    root.commit();
                    textInput.forceActiveFocus();
                }
            }
        }

        // Botón de acción opcional (ej: Explorar)
        Rectangle {
            id: actionBtn
            visible: root.actionButtonText !== "" || root.actionButtonIcon !== ""
            Layout.preferredHeight: 28
            Layout.preferredWidth: Math.max(28, actionRow.implicitWidth + 16)
            radius: 7
            color: actionMa.pressed
                ? Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Math.min(1, Theme.accent.hsvValue + 0.18), 0.50)
                : actionHov.hovered
                    ? Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.30)
                    : Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.18)

            scale: actionMa.pressed ? 0.94 : 1.0
            Behavior on scale {
                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
            }

            HoverHandler { id: actionHov }

            RowLayout {
                id: actionRow
                anchors.centerIn: parent
                spacing: 5

                Image {
                    visible: root.actionButtonIcon !== ""
                    Layout.preferredWidth: 13
                    Layout.preferredHeight: 13
                    source: root.actionButtonIcon
                    sourceSize: Qt.size(13, 13)
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: Theme.accent
                    }
                }

                Text {
                    visible: root.actionButtonText !== ""
                    text: root.actionButtonText
                    color: Theme.accent
                    font {
                        pixelSize: 11
                        bold: true
                        family: Theme.fontFamily
                    }
                }
            }

            MouseArea {
                id: actionMa
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.commit();
                    root.actionTriggered();
                }
            }
        }
    }

    ContextMenu {
        id: sharedInputContextMenu
    }
}
