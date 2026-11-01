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
    color: Theme.surface

    NotesContent {
        id: content
        anchors.fill: parent
        onCloseRequested: root.close()
        onOpenSettingsRequested: settingsModal.open()
    }

    NotesSettingsModal {
        id: settingsModal
        anchors.fill: parent
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
}
