pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Notas
import "."

// Barra flotante superior derecha de acciones sobre imagen (Zoom In + Copiar imagen).
// Reutilizada en BlockImage y BlockList tanto en modo normal como en preview.
Item {
    id: root

    property bool available: true
    property bool hoveredOutside: false
    property bool showZoomButton: true
    property string localPath: ""
    property Item targetImageItem: null
    property bool copiedRecently: false
    property bool _isDestroyed: false

    signal zoomRequested()

    readonly property real parentW: parent ? parent.width : 0
    readonly property real parentH: parent ? parent.height : 0
    readonly property bool placeOutside: (parentW > 0 && parentW < (actionRow.implicitWidth + 24)) || (parentH > 0 && parentH < 44)

    readonly property bool isZoomHovered: root.showZoomButton && (zoomMa.containsMouse || zoomHover.hovered)
    readonly property bool isCopyHovered: copyMa.containsMouse || btnHover.hovered
    readonly property bool isButtonHovered: isCopyHovered || isZoomHovered || bridgeHover.hovered || hoverGraceTimer.running
    readonly property bool isShowing: available && (hoveredOutside || isButtonHovered || copiedRecently)

    onHoveredOutsideChanged: {
        if (!hoveredOutside && placeOutside) {
            hoverGraceTimer.restart();
        }
    }

    Timer {
        id: hoverGraceTimer
        interval: 160
        repeat: false
    }

    HoverHandler {
        id: bridgeHover
        enabled: root.available
    }

    anchors.top: parent ? parent.top : undefined
    anchors.right: parent ? (placeOutside ? undefined : parent.right) : undefined
    anchors.left: parent ? (placeOutside ? parent.right : undefined) : undefined
    anchors.margins: 8
    anchors.topMargin: placeOutside ? Math.max(0, Math.min(8, Math.round((parentH - height) / 2))) : 8
    anchors.rightMargin: 8
    anchors.leftMargin: 0

    width: actionRow.implicitWidth + (placeOutside ? 6 : 0)
    height: 22
    visible: available && opacity > 0.0
    opacity: isShowing ? 1.0 : 0.0

    Behavior on opacity {
        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }

    Component.onDestruction: {
        _isDestroyed = true;
    }

    Timer {
        id: copiedTimer
        interval: 1600
        repeat: false
        onTriggered: {
            if (!root._isDestroyed) root.copiedRecently = false;
        }
    }

    function _pointInside(item, fromItem, lx, ly) {
        if (!item || !item.visible || !fromItem) return false;
        var pt = fromItem.mapToItem(item, lx, ly);
        return pt.x >= 0 && pt.x <= item.width && pt.y >= 0 && pt.y <= item.height;
    }

    function actionAtPoint(fromItem, lx, ly) {
        if (!visible || opacity <= 0.0 || !fromItem) return "";
        if (root.showZoomButton && _pointInside(zoomBtn, fromItem, lx, ly)) return "zoom";
        if (_pointInside(copyBtn, fromItem, lx, ly)) return "copy";
        return "";
    }

    function containsPointIn(fromItem, lx, ly) {
        return actionAtPoint(fromItem, lx, ly) !== "";
    }

    function _markCopied() {
        if (root._isDestroyed) return;
        root.copiedRecently = true;
        copiedTimer.restart();
    }

    function triggerZoom() {
        if (root._isDestroyed || !root.showZoomButton) return;
        root.zoomRequested();
    }

    function triggerCopy() {
        if (root._isDestroyed || typeof Sys === "undefined") return;
        var lp = (root.localPath || "").trim();
        if (lp !== "" && typeof Sys.copyImageToClipboard === "function") {
            if (Sys.copyImageToClipboard(lp)) {
                root._markCopied();
                return;
            }
        }
        if (root.targetImageItem && typeof root.targetImageItem.grabToImage === "function"
                && typeof Sys.copyImageDataToClipboard === "function") {
            root.targetImageItem.grabToImage(function(result) {
                if (!root || root._isDestroyed || !result || !result.image) return;
                if (Sys.copyImageDataToClipboard(result.image)) {
                    root._markCopied();
                }
            });
        }
    }

    Row {
        id: actionRow
        x: root.placeOutside ? 6 : 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        // Botón sólo-icono de Zoom In a la izquierda de Copiar
        Rectangle {
            id: zoomBtn
            visible: root.showZoomButton
            width: 24
            height: 22
            radius: 6
            color: Qt.rgba(
                Theme.background.r,
                Theme.background.g,
                Theme.background.b,
                root.isZoomHovered ? 0.90 : 0.74
            )
            border.width: 1
            border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, root.isZoomHovered ? 0.24 : 0.14)

            Image {
                anchors.centerIn: parent
                width: 13
                height: 13
                source: Theme.iconsPath + "zoom-in.svg"
                sourceSize: Qt.size(13, 13)
                layer.enabled: root.visible && zoomBtn.visible
                layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: root.isZoomHovered ? Theme.text : Theme.muted
                }
            }

            HoverHandler {
                id: zoomHover
                enabled: root.available && zoomBtn.visible
            }

            MouseArea {
                id: zoomMa
                anchors.fill: parent
                enabled: root.available && root.visible && zoomBtn.visible
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    mouse.accepted = true;
                    root.triggerZoom();
                }
            }
        }

        // Botón de Copiar imagen directa al portapapeles
        Rectangle {
            id: copyBtn
            width: copyRow.implicitWidth + 12
            height: 22
            radius: 6
            color: Qt.rgba(
                Theme.background.r,
                Theme.background.g,
                Theme.background.b,
                root.isCopyHovered ? 0.90 : 0.74
            )
            border.width: 1
            border.color: root.copiedRecently
                ? Qt.rgba(Theme.success.r, Theme.success.g, Theme.success.b, 0.55)
                : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, root.isCopyHovered ? 0.24 : 0.14)

            RowLayout {
                id: copyRow
                anchors.centerIn: parent
                spacing: 4

                Image {
                    Layout.preferredWidth: 12
                    Layout.preferredHeight: 12
                    source: Theme.iconsPath + (root.copiedRecently ? "check.svg" : "content-copy.svg")
                    sourceSize: Qt.size(12, 12)
                    layer.enabled: root.visible
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: root.copiedRecently
                            ? Theme.success
                            : (root.isCopyHovered ? Theme.text : Theme.muted)
                    }
                }

                Text {
                    text: root.copiedRecently
                        ? I18n.t("notes.editor.copied", "Copiado")
                        : I18n.t("notes.editor.copy", "Copiar")
                    color: root.copiedRecently
                        ? Theme.success
                        : (root.isCopyHovered ? Theme.text : Theme.muted)
                    font.family: Theme.fontFamily
                    font.pixelSize: EditorMetrics.fs(Theme.fontSizeCaption - 1)
                }
            }

            HoverHandler {
                id: btnHover
                enabled: root.available
            }

            MouseArea {
                id: copyMa
                anchors.fill: parent
                enabled: root.available && root.visible
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    mouse.accepted = true;
                    root.triggerCopy();
                }
            }
        }
    }
}
