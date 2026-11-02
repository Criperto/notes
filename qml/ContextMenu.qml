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

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0.0
            to: 1.0
            duration: Theme.animationsEnabled ? 120 : 0
            easing.type: Easing.OutQuad
        }
    }

    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1.0
            to: 0.0
            duration: Theme.animationsEnabled ? 90 : 0
            easing.type: Easing.InQuad
        }
    }

    function openAt(targetInput, xPos, yPos, customItems) {
        target = targetInput;
        extraItems = (customItems && Array.isArray(customItems)) ? customItems : [];

        var win = target ? (target.Window ? target.Window.contentItem : null) : null;
        if (!win && typeof Overlay !== "undefined" && Overlay.overlay) {
            win = Overlay.overlay;
        }

        var posX = 0;
        var posY = 0;

        if (target && win && typeof xPos === "number" && typeof yPos === "number") {
            var pt = target.mapToItem(win, xPos, yPos);
            posX = pt.x;
            posY = pt.y;
        } else if (typeof Sys !== "undefined" && Sys.lastMouseX > 0) {
            posX = Sys.lastMouseX;
            posY = Sys.lastMouseY;
        } else if (target && win) {
            var rx = 0;
            var ry = 0;
            if (target.cursorRectangle) {
                rx = target.cursorRectangle.x;
                ry = target.cursorRectangle.y + (target.cursorRectangle.height || 20);
            } else {
                ry = target.height || 24;
            }
            var ptCursor = target.mapToItem(win, rx, ry);
            posX = ptCursor.x;
            posY = ptCursor.y;
        }

        if (win) {
            parent = win;
            x = Math.max(8, Math.min(posX, win.width - 230));
            y = Math.max(8, Math.min(posY, win.height - 300));
        }

        root.visible = true;
    }

    function open(targetInput, customItems) {
        if (!targetInput && !target) return;
        openAt(targetInput || target, undefined, undefined, customItems);
    }

    function openAtTextCursor(targetInput, customItems) {
        var tgt = targetInput || target;
        if (!tgt) return;
        var r = tgt.cursorRectangle || { x: 10, y: 20, height: 20 };
        openAt(tgt, r.x, r.y + (r.height || 20) + 4, customItems);
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
        width: 220

        // Extra items (sugerencias ortográficas, acciones de bloque, etc.)
        Repeater {
            model: root.extraItems
            delegate: Item {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: {
                    if (modelData.kind === "separator") return 7;
                    if (modelData.kind === "header") return 22;
                    return 30;
                }

                // Separador
                Rectangle {
                    visible: modelData.kind === "separator"
                    anchors.centerIn: parent
                    width: parent.width - 8
                    height: 1
                    color: Theme.border
                }

                // Encabezado de sección
                Text {
                    visible: modelData.kind === "header"
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: (modelData.text || modelData.label || "").toUpperCase()
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeCaption - 1
                    font.bold: true
                    elide: Text.ElideRight
                }

                // Elemento interactivo (sugerencia o acción)
                Rectangle {
                    visible: modelData.kind !== "separator" && modelData.kind !== "header"
                    anchors.fill: parent
                    radius: 6
                    color: itemMa.containsMouse && (modelData.enabled !== false) ? Theme.surfaceHover : "transparent"
                    enabled: modelData.enabled !== false

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: modelData.label || modelData.text || ""
                            color: (modelData.kind === "suggestion" || modelData.isSuggestion) ? Theme.accent : (modelData.enabled !== false ? Theme.text : Theme.muted)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: !!(modelData.kind === "suggestion" || modelData.isSuggestion)
                            elide: Text.ElideRight
                        }

                        // Badge de idioma o atajo para sugerencias o acciones
                        Rectangle {
                            visible: !!(modelData.lang || modelData.shortcut)
                            Layout.preferredHeight: 18
                            Layout.preferredWidth: badgeText.implicitWidth + 8
                            radius: 4
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)

                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: modelData.lang || modelData.shortcut || ""
                                color: Theme.accent
                                font.family: Theme.fontFamilyMonospace
                                font.pixelSize: 10
                                font.bold: true
                            }
                        }
                    }

                    MouseArea {
                        id: itemMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: (modelData.enabled !== false) ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (modelData.enabled === false) return;
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
            enabled: !!(root.target && typeof root.target.cut === "function" && (root.target.selectedText !== ""))

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
            enabled: !!(root.target && typeof root.target.copy === "function" && (root.target.selectedText !== ""))

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
            enabled: !!(root.target && typeof root.target.paste === "function")

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
            enabled: !!(root.target && typeof root.target.selectAll === "function")

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
