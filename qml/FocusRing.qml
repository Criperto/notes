import QtQuick
import Notas

Rectangle {
    id: root

    property Item target: parent
    property bool active: Boolean(target && target.activeFocus)
    property real offset: 2
    property real ringWidth: 2
    property color ringColor: Theme.accent
    property real cornerRadius: (target && target.radius !== undefined) ? (target.radius + offset) : 8

    anchors.fill: target ? target : undefined
    anchors.margins: -offset

    color: "transparent"
    radius: cornerRadius
    border.width: ringWidth
    border.color: ringColor

    visible: opacity > 0.001
    opacity: active && (target ? (target.visible && target.opacity > 0.01) : true) ? 1.0 : 0.0

    Behavior on opacity {
        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
        NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
    }

    Accessible.ignored: true
}
