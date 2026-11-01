// ToolbarButton.qml — Botón reusable para la barra de herramientas del editor Markdown
import QtQuick
import QtQuick.Effects
import Notas
import "."
import "EditorActions.js" as EA

Rectangle {
    id: tbRoot

    property string actionId: ""
    property string iconSource: ""
    property string textLabel: ""
    property bool underlineText: false
    property string tooltipLabel: ""
    property string tooltipShortcut: ""
    property bool active: false
    property var tooltipLayer: null
    // Estado deshabilitado
    property bool disabled: false
    property string disabledReason: ""

    signal clicked()

    readonly property string resolvedLabel: {
        if (tbRoot.actionId) return EA.getLabel(tbRoot.actionId, I18n);
        return tbRoot.tooltipLabel;
    }

    readonly property string resolvedShortcut: {
        if (tbRoot.actionId) return EA.getShortcut(tbRoot.actionId);
        return tbRoot.tooltipShortcut;
    }

    width: 30
    height: 30
    radius: 8

    color: tbRoot.disabled
        ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04)
        : (active
            ? Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.28)
            : (mouseArea.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12) : "transparent"))

    Behavior on color {
        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
        ColorAnimation { duration: 120 }
    }

    Image {
        id: iconImg
        visible: tbRoot.iconSource !== ""
        anchors.centerIn: parent
        width: 16
        height: 16
        source: tbRoot.iconSource
        sourceSize: Qt.size(16, 16)
        layer.enabled: !GamemodeService.gamemodeActive
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: tbRoot.disabled ? Theme.muted : (tbRoot.active ? Theme.accent : (mouseArea.containsMouse ? Theme.accent : Theme.text))
        }
    }

    Text {
        id: lblText
        visible: tbRoot.iconSource === "" && tbRoot.textLabel !== ""
        anchors.centerIn: parent
        text: tbRoot.textLabel
        font.bold: true
        font.underline: tbRoot.underlineText
        font.pixelSize: Theme.fontSizeCaption + 1
        font.family: Theme.fontFamily
        color: tbRoot.disabled ? Theme.muted : (tbRoot.active ? Theme.accent : (mouseArea.containsMouse ? Theme.accent : Theme.text))
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: tbRoot.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
        onEntered: {
            if (tbRoot.tooltipLayer) {
                if (tbRoot.disabled) {
                    tbRoot.tooltipLayer.showTooltip(tbRoot,
                        tbRoot.disabledReason || I18n.t("notes.editor.txt_no_format", "No disponible en .txt — convertí a .md para usar formato"), "");
                } else {
                    tbRoot.tooltipLayer.showTooltip(tbRoot, tbRoot.resolvedLabel, tbRoot.resolvedShortcut);
                }
            }
        }
        onExited: {
            if (tbRoot.tooltipLayer) {
                tbRoot.tooltipLayer.hideTooltip();
            }
        }
        onClicked: {
            if (tbRoot.disabled) return;
            if (tbRoot.tooltipLayer) {
                tbRoot.tooltipLayer.hideTooltip();
            }
            tbRoot.clicked();
        }
    }
}
