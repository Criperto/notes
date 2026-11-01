// EditorTooltipLayer.qml — Capa única flotante de tooltips para el editor en la raíz del contenedor
import QtQuick
import QtQuick.Effects
import Notas

Item {
    id: root
    anchors.fill: parent
    z: 9999
    enabled: false // Permite que los clics atraviesen la capa hacia los controles inferiores

    property var targetItem: null
    property string label: ""
    property string shortcut: ""
    property bool active: false

    Timer {
        id: showDelayTimer
        interval: 450
        repeat: false
        onTriggered: {
            if (root.targetItem) {
                root.active = true;
            }
        }
    }

    function showTooltip(target, lbl, sc) {
        if (!target) return;
        if (root.targetItem === target && root.active) {
            root.label = lbl || "";
            root.shortcut = sc || "";
            return;
        }
        root.targetItem = target;
        root.label = lbl || "";
        root.shortcut = sc || "";
        root.active = false;
        showDelayTimer.restart();
    }

    function hideTooltip() {
        showDelayTimer.stop();
        root.active = false;
        root.targetItem = null;
        root.label = "";
        root.shortcut = "";
    }

    readonly property var targetPos: {
        if (!root.targetItem || !root.targetItem.visible) return null;
        try {
            return root.targetItem.mapToItem(root, 0, 0);
        } catch(e) {
            return null;
        }
    }

    Rectangle {
        id: tipBg
        visible: root.active && (root.label !== "" || root.shortcut !== "") && root.targetPos !== null
        opacity: visible ? 1.0 : 0.0

        Behavior on opacity {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            NumberAnimation { duration: 120 }
        }

        width: tipCol.implicitWidth + 20
        height: tipCol.implicitHeight + 12
        radius: 8
        color: Theme.color0
        border.width: 0

        layer.enabled: !GamemodeService.gamemodeActive
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.5)
            shadowBlur: 0.6
            shadowVerticalOffset: 3
        }

        x: {
            if (!root.targetPos || !root.targetItem) return 0;
            var targetCenterX = root.targetPos.x + (root.targetItem.width / 2);
            var idealX = targetCenterX - (width / 2);
            return Math.max(8, Math.min(root.width - width - 8, idealX));
        }

        y: {
            if (!root.targetPos || !root.targetItem) return 0;
            var idealY = root.targetPos.y - height - 6;
            if (idealY < 4) {
                return root.targetPos.y + root.targetItem.height + 6;
            }
            return idealY;
        }

        Column {
            id: tipCol
            anchors.centerIn: parent
            spacing: 2

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
                    font.pixelSize: Theme.fontSizeCaption
                    font.bold: true
                    visible: root.label !== ""
                }
            }

            Text {
                text: root.shortcut
                color: Theme.color1
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeCaption - 1
                font.bold: true
                visible: root.shortcut !== ""
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
