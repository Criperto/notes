// EditorToolTip.qml — Tooltip flotante para botones de la barra de herramientas
import QtQuick
import quickshell 1.0
import "."

Item {
    id: root
    property string label: ""
    property string shortcut: ""
    property bool show: false

    visible: show && (label !== "" || shortcut !== "")
    z: 1000

    readonly property real windowW: {
        var p = root.parent;
        while (p && p.parent) p = p.parent;
        return p ? p.width : 1000;
    }

    readonly property real globalX: {
        if (!root.parent || !root.visible) return 0;
        try {
            var p = root.parent;
            var topItem = p;
            while (topItem && topItem.parent) topItem = topItem.parent;
            if (topItem && typeof p.mapToItem === "function") {
                return p.mapToItem(topItem, 0, 0).x;
            }
        } catch(e) {
            console.debug("[EditorToolTip] Excepción al mapear coordenadas:", e);
        }
        return 0;
    }

    Rectangle {
        id: tipBg
        anchors.bottom: parent ? parent.top : undefined
        anchors.bottomMargin: 6

        x: {
            if (!root.parent) return 0;
            var pw = root.parent.width;
            var idealX = (pw - width) / 2;
            var gx = root.globalX;
            var winW = root.windowW;
            var curRight = gx + idealX + width;
            if (curRight > winW - 16) {
                var shift = curRight - (winW - 16);
                return idealX - shift;
            }
            var curLeft = gx + idealX;
            if (curLeft < 16) {
                return idealX + (16 - curLeft);
            }
            return idealX;
        }
        width: tipCol.implicitWidth + 22
        height: tipCol.implicitHeight + 14
        radius: 8
        color: Theme.color0
        border.width: 0

        Column {
            id: tipCol
            anchors.centerIn: parent
            spacing: 3

            Row {
                spacing: 6
                anchors.horizontalCenter: parent.horizontalCenter

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: Theme.color1
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: root.label
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeCaption + 1
                    font.bold: true
                    visible: root.label !== ""
                }
            }

            Text {
                text: root.shortcut
                color: Theme.color1
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeCaption
                font.bold: true
                visible: root.shortcut !== ""
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    width: tipBg.width
    height: tipBg.height
}
