import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Effects
import Notas

ApplicationWindow {
    id: root
    visible: content.isReadyToShow
    title: "Notas"
    width: 1080
    height: 760
    minimumWidth: 680
    minimumHeight: 500
    color: "transparent"

    NotesContent {
        id: content
        anchors.fill: parent
        initialAction: (typeof Sys !== "undefined") ? Sys.initialAction : ""
        initialTarget: (typeof Sys !== "undefined") ? Sys.initialTarget : ""
        isSettingsOpen: settingsModal.isOpen || settingsModal.isClosing
        onCloseRequested: root.close()
        onOpenSettingsRequested: (originRect, initialTab) => settingsModal.open(originRect, initialTab)
    }

    NotesSettingsModal {
        id: settingsModal
        anchors.fill: parent
        z: 9999
        backgroundSourceItem: content
    }

    function toggleSettings(initialTab) {
        if (settingsModal.isOpen && !settingsModal.isClosing) {
            if (initialTab && typeof initialTab === "string" && settingsModal.currentTabValue !== initialTab) {
                settingsModal.setTab(initialTab);
            } else {
                settingsModal.close();
            }
        } else {
            var noteIsActive = (typeof NotesService !== "undefined" && NotesService.isEditing);
            if (!noteIsActive && content && typeof content.getSettingsButtonRect === "function") {
                var btnRect = content.getSettingsButtonRect();
                settingsModal.open(btnRect, initialTab);
            } else {
                settingsModal.open(null, initialTab);
            }
        }
    }

    Shortcut {
        sequence: "Ctrl+,"
        onActivated: root.toggleSettings()
    }

    Shortcut {
        sequence: "Ctrl+/"
        onActivated: root.toggleSettings("shortcuts")
    }

    Shortcut {
        sequence: "F1"
        onActivated: root.toggleSettings("shortcuts")
    }

    Shortcut {
        sequence: "Ctrl+Shift+V"
        onActivated: content.createNoteFromClipboard()
    }

    Shortcut {
        sequence: "Ctrl+Alt+W"
        onActivated: content.openWebClipper()
    }

    Shortcut {
        sequence: "Ctrl+Q"
        onActivated: {
            NotesService.prepareToQuit();
            root.close();
        }
    }

    onActiveChanged: {
        if (root.active && typeof Sys !== "undefined" && typeof Sys.updateInstanceStatus === "function") {
            Sys.updateInstanceStatus((typeof NotesService !== "undefined" && NotesService.activeNote) ? (NotesService.activeNote.filePath || "") : "", (typeof NotesService !== "undefined") && NotesService.isEditing);
        }
    }

    Connections {
        target: (typeof Sys !== "undefined") ? Sys : null
        function onRemoteEditLockClaimed(notePath, newOwnerPid) {
            content.handleRemoteEditLockClaimed(notePath, newOwnerPid);
        }
        function onRemoteNoteSaved(notePath) {
            content.handleRemoteNoteSaved(notePath);
        }
        function onRemoteNoteDeleted(notePath) {
            content.handleRemoteNoteDeleted(notePath);
        }
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
            } else if (action === "find") {
                content.handleIpcAction("find", target);
            } else if (action === "reload") {
                content.handleIpcAction("reload", target);
            } else if (action === "sync") {
                if (typeof ConfigBackend !== "undefined") {
                    ConfigBackend.syncWithQuickshell = (target === "true" || target === "1");
                }
            }
        }
    }

    Component.onCompleted: {
        if (!content.initialAction && typeof Sys !== "undefined" && Sys.initialAction !== "") {
            Qt.callLater(() => {
                content.handleIpcAction(Sys.initialAction, Sys.initialTarget);
            });
        }
    }
}
