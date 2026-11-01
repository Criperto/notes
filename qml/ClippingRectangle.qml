import QtQuick
import QtQuick.Effects

Item {
    id: root

    property alias color: bgRect.color
    property alias radius: bgRect.radius
    property alias border: bgRect.border
    default property alias data: contentItem.data

    Rectangle {
        id: bgRect
        anchors.fill: parent
        color: "transparent"
        visible: false
    }

    Item {
        id: contentItem
        anchors.fill: parent
        layer.enabled: root.radius > 0
        layer.effect: MultiEffect {
            maskEnabled: root.radius > 0
            maskSource: bgRect
        }
    }
}
