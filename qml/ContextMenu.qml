import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Notas

Popup {
    id: root

    property var target: null
    property var extraItems: []
    signal extraItemTriggered(var item)

    padding: 6
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent | Popup.CloseOnPressOutside
    dim: false

    background: Rectangle {
        radius: 10
        color: Theme.surface
        border.color: Theme.border
        border.width: 1
    }

    function openAt(targetInput, xPos, yPos, customItems) {
        target = targetInput;
        extraItems = (customItems && Array.isArray(customItems)) ? customItems : [];
        if (target && target.Window && target.Window.contentItem) {
            parent = target.Window.contentItem;
            var pt = target.mapToItem(parent, xPos || 0, yPos || 0);
            x = Math.max(8, Math.min(pt.x, parent.width - width - 8));
            y = Math.max(8, Math.min(pt.y, parent.height - height - 8));
        }
        open();
    }

    function open(targetInput, customItems) {
        if (!targetInput) return;
        openAt(targetInput, 10, 20, customItems);
    }

    function openAtTextCursor(targetInput, customItems) {
        if (!targetInput) return;
        var r = targetInput.cursorRectangle || { x: 10, y: 20, height: 20 };
        openAt(targetInput, r.x, r.y + r.height + 4, customItems);
    }

    function toggleAtTextCursor(targetInput, customItems) {
        if (root.visible) {
            root.close();
        } else {
            openAtTextCursor(targetInput, customItems);
        }
    }

    contentItem: ColumnLayout {
        spacing: 2
        width: 180

        // Extra items (ej. sugerencias ortográficas o acciones de bloque)
        Repeater {
            model: root.extraItems
            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                radius: 6
                color: itemMa.containsMouse ? Theme.surfaceHover : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: modelData.label || modelData.text || ""
                        color: Theme.primary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: itemMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.close();
                        if (typeof modelData.triggered === "function") {
                            modelData.triggered();
                        } else if (typeof modelData.onTriggered === "function") {
                            modelData.onTriggered();
                        }
                        root.extraItemTriggered(modelData);
                    }
                }
            }
        }

        Rectangle {
            visible: root.extraItems.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.border
        }

        // Cortar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: 6
            color: cutMa.containsMouse ? Theme.surfaceHover : "transparent"
            enabled: root.target && typeof root.target.cut === "function" && (root.target.selectedText !== "")

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: I18n.t("common.actions.cut", "Cortar")
                    color: parent.parent.enabled ? Theme.text : Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
                Text {
                    text: "Ctrl+X"
                    color: Theme.muted
                    font.family: Theme.fontFamilyMonospace
                    font.pixelSize: Theme.fontSizeCaption
                }
            }

            MouseArea {
                id: cutMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (root.target && typeof root.target.cut === "function") {
                        root.target.cut();
                    }
                    root.close();
                }
            }
        }

        // Copiar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: 6
            color: copyMa.containsMouse ? Theme.surfaceHover : "transparent"
            enabled: root.target && typeof root.target.copy === "function" && (root.target.selectedText !== "")

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: I18n.t("common.actions.copy", "Copiar")
                    color: parent.parent.enabled ? Theme.text : Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
                Text {
                    text: "Ctrl+C"
                    color: Theme.muted
                    font.family: Theme.fontFamilyMonospace
                    font.pixelSize: Theme.fontSizeCaption
                }
            }

            MouseArea {
                id: copyMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (root.target && typeof root.target.copy === "function") {
                        root.target.copy();
                    }
                    root.close();
                }
            }
        }

        // Pegar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: 6
            color: pasteMa.containsMouse ? Theme.surfaceHover : "transparent"
            enabled: root.target && typeof root.target.paste === "function"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: I18n.t("common.actions.paste", "Pegar")
                    color: parent.parent.enabled ? Theme.text : Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
                Text {
                    text: "Ctrl+V"
                    color: Theme.muted
                    font.family: Theme.fontFamilyMonospace
                    font.pixelSize: Theme.fontSizeCaption
                }
            }

            MouseArea {
                id: pasteMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (root.target && typeof root.target.paste === "function") {
                        root.target.paste();
                    }
                    root.close();
                }
            }
        }

        // Seleccionar todo
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: 6
            color: selMa.containsMouse ? Theme.surfaceHover : "transparent"
            enabled: root.target && typeof root.target.selectAll === "function"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: I18n.t("common.actions.select_all", "Seleccionar todo")
                    color: parent.parent.enabled ? Theme.text : Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
                Text {
                    text: "Ctrl+A"
                    color: Theme.muted
                    font.family: Theme.fontFamilyMonospace
                    font.pixelSize: Theme.fontSizeCaption
                }
            }

            MouseArea {
                id: selMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (root.target && typeof root.target.selectAll === "function") {
                        root.target.selectAll();
                    }
                    root.close();
                }
            }
        }
    }
}
