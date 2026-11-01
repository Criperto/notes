// shell.qml — ShellRoot de la aplicación independiente de Notas (qs-notes)
// Lanzar:  qs --no-duplicate -p ~/.config/quickshell/notes/shell.qml

import "."
import Notas
import QtQuick

ShellRoot {
    id: shellRoot
    settings.watchFiles: false

    readonly property string lockFile: {
        var runtimeDir = Quickshell.env("XDG_RUNTIME_DIR");
        if (runtimeDir) return runtimeDir + "/qs-notes.lock";
        var user = Quickshell.env("USER") || "user";
        return "/dev/shm/qs-notes-" + user + ".lock";
    }
    readonly property string winTitle: "qs-notes"
    readonly property string initialAction: Quickshell.env("QS_NOTES_INITIAL_ACTION") || ""
    readonly property string initialTarget: Quickshell.env("QS_NOTES_INITIAL_TARGET") || ""

    // Monitor activo y dimensiones lógicas escaladas
    readonly property var  activeMonitor:    Hyprland.focusedMonitor ?? null
    readonly property real monScale:         (activeMonitor && activeMonitor.scale > 0) ? activeMonitor.scale : 1.0
    readonly property real monLogicalWidth:  activeMonitor ? (activeMonitor.width / monScale) : 1920
    readonly property real monLogicalHeight: activeMonitor ? (activeMonitor.height / monScale) : 1080

    readonly property int  cardW:            Math.min(1080, Math.round(monLogicalWidth * 0.86))
    readonly property int  cardH:            Math.min(760, Math.round(monLogicalHeight * 0.84))

    property string _pendingIpcAction: ""
    property string _pendingIpcTarget: ""

    function _dispatchIpc(act, tgt) {
        if (winLoader.item && winLoader.item.contentItem) {
            winLoader.item.contentItem.handleIpcAction(act, tgt);
        } else {
            shellRoot._pendingIpcAction = act;
            shellRoot._pendingIpcTarget = tgt;
        }
    }

    // ── IPC interno para llamadas sobre instancia viva ──────────────────
    IpcHandler {
        target: "notes"

        function toggle() {
            // Manejado por lock / compositor
        }

        function open() {
            // Enfocar ventana
        }

        function close() {
            NotesService.prepareToQuit();
            lockRemove.running = true;
        }

        function openNote(slugOrKey: string) {
            shellRoot._dispatchIpc("openNote", slugOrKey || "");
        }

        function openPath(filePath: string) {
            shellRoot._dispatchIpc("openPath", filePath || "");
        }

        function previewFile(filePath: string) {
            shellRoot._dispatchIpc("previewFile", filePath || "");
        }

        function createNote(title: string) {
            shellRoot._dispatchIpc("createNote", title || "");
        }
    }

    // ── Lock + toggle (PID-aware) ─────────────────────────────────────────
    Process {
        id: lockCheck
        running: true
        command: ["/bin/sh", "-c",
            "L='" + shellRoot.lockFile + "'; " +
            "ACT='" + shellRoot.initialAction + "'; " +
            "TGT='" + shellRoot.initialTarget + "'; " +
            "CONF='" + Quickshell.shellDir.toString().replace("file://", "") + "/notes/shell.qml'; " +
            "if [ -f \"$L\" ] && PID=$(cat \"$L\" 2>/dev/null) && [ -n \"$PID\" ] " +
            "&& kill -0 \"$PID\" 2>/dev/null && grep -q 'notes/shell.qml' \"/proc/$PID/cmdline\" 2>/dev/null; then " +
            "  WIN=$(hyprctl clients -j 2>/dev/null | jq -r --arg P \"$PID\" " +
            "    '.[] | select(.pid == ($P|tonumber)) | \"\\(.address) \\(.workspace.id)\"' | head -1); " +
            "  if [ -z \"$WIN\" ]; then " +
            "    AGE=$(( $(date +%s) - $(date -r \"$L\" +%s 2>/dev/null || echo 0) )); " +
            "    if [ \"$AGE\" -lt 3 ]; then echo exists; " +
            "    else kill -TERM \"$PID\" 2>/dev/null; echo \"$PPID\" > \"$L\"; echo new; fi; " +
            "  else " +
            "    WA=$(echo \"$WIN\" | awk '{print $1}'); " +
            "    WW=$(echo \"$WIN\" | awk '{print $2}'); " +
            "    AW=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id'); " +
            "    if [ -n \"$ACT\" ]; then " +
            "      if [ \"$WW\" != \"$AW\" ]; then hyprctl dispatch \"hl.dsp.window.move({workspace=$AW,window=\\\"address:$WA\\\"})\" >/dev/null; fi; " +
            "      hyprctl dispatch \"hl.dsp.focus({window=\\\"address:$WA\\\"})\" >/dev/null; " +
            "      if [ -n \"$TGT\" ]; then qs -p \"$CONF\" ipc call notes \"$ACT\" \"$TGT\" >/dev/null 2>&1; " +
            "      else qs -p \"$CONF\" ipc call notes \"$ACT\" >/dev/null 2>&1; fi; " +
            "    elif [ \"$WW\" = \"$AW\" ]; then rm -f \"$L\"; " +
            "    else hyprctl dispatch \"hl.dsp.window.move({workspace=$AW,window=\\\"address:$WA\\\"})\" >/dev/null; " +
            "      hyprctl dispatch \"hl.dsp.focus({window=\\\"address:$WA\\\"})\" >/dev/null; fi; " +
            "    echo exists; " +
            "  fi; " +
            "else echo \"$PPID\" > \"$L\"; echo new; fi"]

        stdout: SplitParser {
            onRead: line => {
                const t = line.trim()
                if (t === "exists") Qt.quit()
                else if (t === "new") showDelayTimer.start()
            }
        }
        Component.onDestruction: { running = false; }
    }

    Timer {
        id: showDelayTimer
        interval: 10
        repeat: false
        property bool _fired: false
        onTriggered: {
            _fired = true;
            if (shellRoot._pendingIpcAction !== "") {
                Qt.callLater(function() {
                    if (winLoader.item && winLoader.item.contentItem) {
                        winLoader.item.contentItem.handleIpcAction(shellRoot._pendingIpcAction, shellRoot._pendingIpcTarget);
                        shellRoot._pendingIpcAction = "";
                        shellRoot._pendingIpcTarget = "";
                    }
                });
            }
        }
    }

    Process {
        id: lockRemove
        command: ["/bin/sh", "-c", "rm -f '" + shellRoot.lockFile + "'"]
        running: false
        onRunningChanged: if (!running) Qt.quit()
        Component.onDestruction: { running = false; }
    }

    // ── Ventana XDG Toplevel ──────────────────────────────────────────────
    Loader {
        id: winLoader
        active: showDelayTimer._fired
        sourceComponent: floatWinComp
    }

    Component {
        id: floatWinComp

        FloatingWindow {
            id: floatWin
            title:          shellRoot.winTitle
            implicitWidth:  shellRoot.cardW
            implicitHeight: shellRoot.cardH
            minimumSize:    Qt.size(680, 500)
            color:          "transparent"
            visible:        (shellRoot.initialAction === "") ? true : (notesContent && notesContent.isReadyToShow)

            property bool _wasShown: false
            property alias contentItem: notesContent

            onVisibleChanged: {
                if (visible) {
                    _wasShown = true;
                    NotesService.refresh();
                    if (typeof SpellService !== "undefined") {
                        SpellService.refreshDicts();
                    }
                } else if (_wasShown) {
                    NotesService.prepareToQuit();
                    lockRemove.running = true;
                }
            }

            Component.onDestruction: {
                if (_wasShown) {
                    NotesService.prepareToQuit();
                    lockRemove.running = true
                }
            }

            NotesContent {
                id: notesContent
                anchors.fill: parent
                initialAction: shellRoot.initialAction
                initialTarget: shellRoot.initialTarget
                onCloseRequested: {
                    floatWin.visible = false;
                    winLoader.active = false;
                    NotesService.prepareToQuit();
                    lockRemove.running = true;
                }
            }
        }
    }
}
