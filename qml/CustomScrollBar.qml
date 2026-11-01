import QtQuick
import QtQuick.Controls
import quickshell 1.0

ScrollBar {
    id: root

    // ── Dimensiones y personalización de estilo ──────────────────────────────
    property real thickness: 4
    property real gap: 2
    property real thumbRadius: thickness / 2
    property color baseColor: Theme.accent
    property real thumbOpacity: 0.45
    property color thumbColor: Qt.hsva(baseColor.hsvHue, baseColor.hsvSaturation, baseColor.hsvValue, thumbOpacity)
    property bool alwaysOn: false
    property bool suppressed: false

    // Soporte opcional para vinculación standalone (ej. sidebars o vistas separadas)
    property Flickable flickable: null

    // ── Estado reactivo y cálculo de espacio reservado ───────────────────────
    readonly property bool isNeeded: size > 0 && size < 1.0
    readonly property bool isShowing: !Theme.hideScrollbars && !suppressed && isNeeded && policy !== ScrollBar.AlwaysOff
    readonly property real reservedSpace: isShowing ? (thickness + gap) : 0

    policy: (Theme.hideScrollbars || suppressed)
        ? ScrollBar.AlwaysOff
        : (alwaysOn ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded)
    visible: isShowing

    // Bindings automáticos cuando se usa en modo standalone con `flickable` asignado
    Binding on active {
        when: root.flickable !== null
        value: root.flickable ? (root.flickable.moving || root.flickable.flicking) : false
    }
    Binding on size {
        when: root.flickable !== null
        value: root.flickable
            ? (root.orientation === Qt.Horizontal
                ? root.flickable.visibleArea.widthRatio
                : root.flickable.visibleArea.heightRatio)
            : 1.0
    }
    Binding on position {
        when: root.flickable !== null && !root.pressed
        value: root.flickable
            ? (root.orientation === Qt.Horizontal
                ? root.flickable.visibleArea.xPosition
                : root.flickable.visibleArea.yPosition)
            : 0.0
    }

    onPositionChanged: {
        if (pressed && flickable) {
            if (orientation === Qt.Horizontal) {
                flickable.contentX = position * flickable.contentWidth
            } else {
                flickable.contentY = position * flickable.contentHeight
            }
        }
    }

    contentItem: Rectangle {
        implicitWidth: root.thickness
        implicitHeight: root.thickness
        radius: root.thumbRadius
        color: root.thumbColor
    }
}
