import QtQuick
import QtQuick.Effects

Item {
    id: root

    property alias color: bgRect.color
    property alias radius: maskRect.radius
    property alias border: bgRect.border
    default property alias contentData: contentItem.data

    Rectangle {
        id: bgRect
        anchors.fill: parent
        radius: maskRect.radius
        color: "transparent"
        z: -1
    }

    Item {
        id: maskSourceItem
        anchors.fill: parent
        layer.enabled: root.radius > 0
        visible: false

        Rectangle {
            id: maskRect
            anchors.fill: parent
            radius: 0
            color: "black"
        }
    }

    Item {
        id: contentItem
        anchors.fill: parent
        layer.enabled: root.radius > 0
        layer.effect: MultiEffect {
            maskEnabled: root.radius > 0
            maskSource: maskSourceItem
        }
    }
}
