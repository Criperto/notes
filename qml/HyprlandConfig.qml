pragma Singleton
import QtQuick

QtObject {
    id: root
    readonly property bool blurEnabled: true
    readonly property int quickshellBlurMax: 32
}
