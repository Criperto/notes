// SlidingLabel.qml — texto que desliza verticalmente al cambiar (F17).
// Dos etiquetas apiladas: la saliente sube y se desvanece, la entrante sube
// desde abajo. El ancho propio se anima para que la píldora lo siga sin saltos.
// Sin animaciones (o gamemode), el texto cambia directo. Clics rápidos: la
// animación en curso se termina al instante y arranca la nueva.
import QtQuick
import Notas

Item {
    id: root

    property string text: ""
    property string fontFamily: Theme.fontFamily
    property int fontSize: Theme.fontSizeSmall
    property bool fontBold: false
    property color color: Theme.text
    property int animMs: 200

    property bool _ready: false
    property string _shown: ""

    clip: true
    implicitWidth: currentLabel.implicitWidth
    implicitHeight: currentLabel.implicitHeight

    Behavior on implicitWidth {
        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    function _finishInstant() {
        slideAnim.stop();
        currentLabel.text = root.text;
        currentLabel.y = 0;
        currentLabel.opacity = 1;
        outgoingLabel.opacity = 0;
        root._shown = root.text;
    }

    onTextChanged: {
        if (!root._ready || !(Theme.animationsEnabled && !GamemodeService.gamemodeActive)) {
            root._finishInstant();
            return;
        }
        slideAnim.stop();
        outgoingLabel.text = root._shown;
        outgoingLabel.y = 0;
        outgoingLabel.opacity = 1;
        root._shown = root.text;
        currentLabel.text = root.text;
        currentLabel.y = currentLabel.height;
        currentLabel.opacity = 0;
        slideAnim.restart();
    }

    Component.onCompleted: {
        root._ready = true;
        root._finishInstant();
    }

    ParallelAnimation {
        id: slideAnim
        NumberAnimation { target: outgoingLabel; property: "y"; from: 0; to: -outgoingLabel.height; duration: root.animMs; easing.type: Easing.OutCubic }
        NumberAnimation { target: outgoingLabel; property: "opacity"; from: 1; to: 0; duration: root.animMs; easing.type: Easing.OutCubic }
        NumberAnimation { target: currentLabel; property: "y"; from: currentLabel.height; to: 0; duration: root.animMs; easing.type: Easing.OutCubic }
        NumberAnimation { target: currentLabel; property: "opacity"; from: 0; to: 1; duration: root.animMs; easing.type: Easing.OutCubic }
    }

    Text {
        id: outgoingLabel
        width: parent.width
        opacity: 0
        color: root.color
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        font.bold: root.fontBold
    }

    Text {
        id: currentLabel
        width: parent.width
        color: root.color
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        font.bold: root.fontBold
    }
}
