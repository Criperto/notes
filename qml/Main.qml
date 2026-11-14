import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Effects
import Notas

ApplicationWindow {
    id: root
    visible: content.isReadyToShow
    title: {
        if (typeof NotesService !== "undefined" && NotesService.isEditing && NotesService.activeNote) {
            var t = (NotesService.activeNote.title && NotesService.activeNote.title.trim() !== "")
                ? NotesService.activeNote.title.trim()
                : (NotesService.activeNote.fileName || "Sin título");
            return "Notas - " + t;
        }
        return "Notas";
    }
    width: 1080
    height: 760
    minimumWidth: 680
    minimumHeight: 500
    color: "transparent"
    flags: Qt.Window | (winControls.visible ? Qt.FramelessWindowHint : 0)

    NotesContent {
        id: content
        anchors.fill: parent
        windowControlsWidth: winControls.visible ? winControls.implicitWidth : 0
        windowControlsOnLeft: winControls.visible ? winControls.onLeft : false
        initialAction: (typeof Sys !== "undefined") ? Sys.initialAction : ""
        initialTarget: (typeof Sys !== "undefined") ? Sys.initialTarget : ""
        isSettingsOpen: settingsModal.isOpen || settingsModal.isClosing
        onCloseRequested: root.close()
        onOpenSettingsRequested: (originRect, initialTab) => settingsModal.open(originRect, initialTab)
    }

    WindowControls {
        id: winControls
        y: (typeof NotesService !== "undefined" && NotesService.isEditing) ? 20 : 15
        anchors.left: onLeft ? parent.left : undefined
        anchors.right: onLeft ? undefined : parent.right
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        targetWindow: root
        z: 500

        Behavior on y {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
    }

    Loader {
        id: settingsLoader
        anchors.fill: parent
        z: 9999
        active: false
        sourceComponent: NotesSettingsModal {
            anchors.fill: parent
            backgroundSourceItem: content
        }
    }

    QtObject {
        id: settingsModal
        readonly property bool isOpen: settingsLoader.item ? settingsLoader.item.isOpen : false
        readonly property bool isClosing: settingsLoader.item ? settingsLoader.item.isClosing : false
        readonly property string currentTabValue: settingsLoader.item ? settingsLoader.item.currentTabValue : "editor"

        function open(originRect, initialTab) {
            if (!settingsLoader.active) {
                settingsLoader.active = true;
            }
            if (settingsLoader.item) {
                settingsLoader.item.open(originRect, initialTab);
            }
        }

        function close() {
            if (settingsLoader.item) {
                settingsLoader.item.close();
            }
        }

        function setTab(tabName) {
            if (settingsLoader.item) {
                settingsLoader.item.setTab(tabName);
            }
        }
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
            if (action === "close") {
                NotesService.prepareToQuit();
                root.close();
                return;
            }
            if (action === "sync") {
                if (typeof ConfigBackend !== "undefined") {
                    ConfigBackend.syncWithQuickshell = (target === "true" || target === "1");
                }
                return;
            }
            if (action === "toggle") {
                if (root.visible && root.active) {
                    root.hide();
                } else {
                    root.show();
                    root.raise();
                    root.requestActivate();
                }
                return;
            }

            root.show();
            root.raise();
            root.requestActivate();
            if (action === "open" || action === "preview") {
                content.handleIpcAction(action, target);
            } else if (action === "new") {
                content.handleIpcAction("new", target);
            } else if (action === "find") {
                content.handleIpcAction("find", target);
            } else if (action === "reload") {
                content.handleIpcAction("reload", target);
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
