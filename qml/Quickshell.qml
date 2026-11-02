pragma Singleton
import QtQuick
import Notas

Item {
    id: root
    visible: false

    property string clipboardText: Sys.clipboardText
    onClipboardTextChanged: {
        if (Sys.clipboardText !== clipboardText) {
            Sys.clipboardText = clipboardText;
        }
    }

    Connections {
        target: Sys
        function onClipboardTextChanged() {
            if (root.clipboardText !== Sys.clipboardText) {
                root.clipboardText = Sys.clipboardText;
            }
        }
    }

    function env(name, fallback) {
        return Sys.env(name, fallback || "");
    }

    function execDetached(args) {
        return Sys.execDetached(args);
    }

    readonly property string shellDir: Sys.dataShareDir
}
