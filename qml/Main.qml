import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Notas

ApplicationWindow {
    id: root
    visible: true
    title: "Notas"
    width: 1080
    height: 760
    minimumWidth: 680
    minimumHeight: 500
    color: "transparent"

    NotesContent {
        id: content
        anchors.fill: parent
        onCloseRequested: root.close()
        onOpenSettingsRequested: (originRect) => settingsModal.open(originRect)
    }

    NotesSettingsModal {
        id: settingsModal
        anchors.fill: parent
        z: 9999
    }

    Shortcut {
        sequence: "Ctrl+,"
        onActivated: settingsModal.open()
    }

    Shortcut {
        sequence: "Ctrl+Q"
        onActivated: {
            NotesService.prepareToQuit();
            root.close();
        }
    }

    Connections {
        target: (typeof Sys !== "undefined") ? Sys : null
        function onIpcCommandReceived(action, target) {
            root.show();
            root.raise();
            root.requestActivate();
            if (action === "close") {
                NotesService.prepareToQuit();
                root.close();
            } else if (action === "toggle") {
                if (root.active) {
                    root.hide();
                } else {
                    root.show();
                    root.raise();
                    root.requestActivate();
                }
            } else if (action === "open" || action === "preview") {
                content.handleIpcAction(action, target);
            } else if (action === "new") {
                content.handleIpcAction("new", target);
            }
        }
    }

    Component.onCompleted: {
        if (typeof Sys !== "undefined" && Sys.initialAction !== "") {
            Qt.callLater(() => {
                content.handleIpcAction(Sys.initialAction, Sys.initialTarget);
            });
        }
    }
}
