import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Diff.js" as Diff

Rectangle {
    id: root

    property bool isOpen: false
    property string notePath: ""
    property string currentText: ""

    signal restoreVersionRequested(string restoredContent)
    signal snapshotCreated()

    width: Math.min(420, parent ? parent.width : 420)
    height: parent ? parent.height : 600
    z: 90

    color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.96)
    border.width: 1
    border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12)
    radius: 12

    // Slide horizontal
    x: isOpen ? (parent.width - width) : parent.width
    Behavior on x {
        NumberAnimation {
            duration: (Theme.animationsEnabled && !GamemodeService.gamemodeActive) ? 220 : 0
            easing.type: Easing.OutCubic
        }
    }

    visible: x < (parent ? parent.width : 9999)

    // Estado interno
    property var versionsList: []
    property int selectedIndex: -1
    property string selectedSnapshotText: ""
    property bool isViewingDiff: false
    property bool isCreatingManual: false
    property bool isLoading: false
    property string statusMessage: ""

    function open() {
        isOpen = true;
        isViewingDiff = false;
        selectedIndex = -1;
        selectedSnapshotText = "";
        refresh();
    }

    function close() {
        isOpen = false;
        isViewingDiff = false;
        isCreatingManual = false;
    }

    function toggle() {
        if (isOpen) close();
        else open();
    }

    function refresh() {
        if (!notePath || notePath.trim() === "") {
            versionsList = [];
            statusMessage = "Guarda la nota primero para ver su historial.";
            return;
        }

        isLoading = true;
        statusMessage = "Cargando versiones...";
        listProc.command = [
            (typeof Sys !== "undefined" && Sys.appExecutable) ? Sys.appExecutable : "notas",
            "history",
            "list",
            notePath,
            "--json"
        ];
        listProc.running = true;
    }

    function createManualSnapshot(label) {
        if (!notePath) return;
        var lbl = (label && label.trim().length > 0) ? label.trim() : "manual";
        isLoading = true;
        snapProc.command = [
            (typeof Sys !== "undefined" && Sys.appExecutable) ? Sys.appExecutable : "notas",
            "history",
            "snapshot",
            notePath,
            "--manual",
            "--label",
            lbl
        ];
        snapProc.running = true;
    }

    function loadVersionContent(versionId) {
        if (!notePath || !versionId) return;
        isLoading = true;
        showProc.versionId = versionId;
        showProc.command = [
            (typeof Sys !== "undefined" && Sys.appExecutable) ? Sys.appExecutable : "notas",
            "history",
            "show",
            notePath,
            versionId
        ];
        showProc.running = true;
    }

    function formatTime(isoStr) {
        if (!isoStr) return "";
        try {
            var d = new Date(isoStr);
            var now = new Date();
            var diffSec = Math.floor((now.getTime() - d.getTime()) / 1000);

            if (diffSec < 60) return "hace un momento";
            if (diffSec < 3600) return "hace " + Math.floor(diffSec / 60) + " min";
            if (diffSec < 86400) return "hace " + Math.floor(diffSec / 3600) + " h";

            var day = d.getDate();
            var month = d.toLocaleDateString(undefined, { month: "short" });
            var hours = ("0" + d.getHours()).slice(-2);
            var mins = ("0" + d.getMinutes()).slice(-2);
            return day + " " + month + " " + hours + ":" + mins;
        } catch (e) {
            return isoStr;
        }
    }

    // Proceso: Listar snapshots
    Process {
        id: listProc
        property string outJson: ""
        running: false
        stdout: SplitParser {
            splitMarker: ""
            onRead: chunk => { listProc.outJson += chunk; }
        }
        onExited: exitCode => {
            root.isLoading = false;
            var raw = listProc.outJson;
            listProc.outJson = "";
            if (exitCode === 0 && raw.trim().length > 0) {
                try {
                    var parsed = JSON.parse(raw);
                    if (Array.isArray(parsed)) {
                        // Invertir para mostrar el más reciente arriba
                        root.versionsList = parsed.slice().reverse();
                        root.statusMessage = root.versionsList.length === 0 ? "Sin versiones guardadas todavía." : "";
                        return;
                    }
                } catch (e) {
                    console.warn("[HistoryPanel] Error parseando JSON de list:", e);
                }
            }
            root.versionsList = [];
            root.statusMessage = "Sin versiones disponibles.";
        }
    }

    // Proceso: Crear snapshot manual
    Process {
        id: snapProc
        running: false
        onExited: exitCode => {
            root.isLoading = false;
            root.isCreatingManual = false;
            manualInput.text = "";
            if (exitCode === 0) {
                root.snapshotCreated();
                root.refresh();
            }
        }
    }

    // Proceso: Mostrar contenido de un snapshot
    Process {
        id: showProc
        property string versionId: ""
        property string outText: ""
        running: false
        stdout: SplitParser {
            splitMarker: ""
            onRead: chunk => { showProc.outText += chunk; }
        }
        onExited: exitCode => {
            root.isLoading = false;
            var text = showProc.outText;
            showProc.outText = "";
            if (exitCode === 0) {
                root.selectedSnapshotText = text;
                root.isViewingDiff = true;
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        // Header del panel
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            spacing: 8

            Image {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                source: Theme.iconsPath + "recent.svg"
                sourceSize: Qt.size(36, 36)
            }

            Text {
                text: root.isViewingDiff ? "Comparando versión" : "Historial de versiones"
                font.family: Theme.fontFamilyDisplay
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Theme.text
                Layout.fillWidth: true
            }

            // Botón cerrar panel
            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 13
                color: closeHover.hovered ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12) : "transparent"

                Image {
                    anchors.centerIn: parent
                    source: Theme.iconsPath + "close.svg"
                    sourceSize: Qt.size(28, 28)
                    width: 14
                    height: 14
                }

                HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.close() }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
        }

        // Barra de acciones superiores (cuando no se está viendo un diff completo)
        ColumnLayout {
            Layout.fillWidth: true
            visible: !root.isViewingDiff
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // Botón Guardar versión actual (manual)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    radius: 8
                    color: saveHover.hovered ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                    border.width: 1
                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        Image {
                            Layout.preferredWidth: 14
                            Layout.preferredHeight: 14
                            source: Theme.iconsPath + "add.svg"
                            sourceSize: Qt.size(28, 28)
                        }

                        Text {
                            text: "Guardar punto de control"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            color: Theme.accent
                        }
                    }

                    HoverHandler { id: saveHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: root.isCreatingManual = !root.isCreatingManual
                    }
                }

                // Botón refrescar
                Rectangle {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    radius: 8
                    color: refreshHover.hovered ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1) : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05)

                    Image {
                        anchors.centerIn: parent
                        source: Theme.iconsPath + "refresh.svg"
                        sourceSize: Qt.size(28, 28)
                        width: 14
                        height: 14
                    }

                    HoverHandler { id: refreshHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.refresh() }
                }
            }

            // Input inline para crear versión manual con etiqueta
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                visible: root.isCreatingManual
                radius: 8
                color: Qt.rgba(0, 0, 0, 0.3)
                border.width: 1
                border.color: Theme.accent

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 4
                    spacing: 4

                    TextInput {
                        id: manualInput
                        Layout.fillWidth: true
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.text
                        clip: true
                        focus: root.isCreatingManual
                        onAccepted: root.createManualSnapshot(manualInput.text)

                        Text {
                            anchors.fill: parent
                            visible: !manualInput.text && !manualInput.activeFocus
                            text: "Etiqueta (ej. Antes de refactor)..."
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.35)
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 54
                        Layout.preferredHeight: 28
                        radius: 6
                        color: Theme.accent

                        Text {
                            anchors.centerIn: parent
                            text: "Guardar"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: Theme.accentText
                        }

                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: root.createManualSnapshot(manualInput.text)
                        }
                    }
                }
            }
        }

        // ── VISTA 1: Lista de versiones ───────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.isViewingDiff

            ListView {
                id: versionsListView
                anchors.fill: parent
                model: root.versionsList
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: CustomScrollBar {}

                delegate: Rectangle {
                    id: versionCard
                    width: versionsListView.width
                    height: 64
                    radius: 8
                    color: {
                        if (root.selectedIndex === index) {
                            return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18);
                        }
                        if (vCardHover.hovered) {
                            return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08);
                        }
                        return Qt.rgba(Theme.cardBackground.r, Theme.cardBackground.g, Theme.cardBackground.b, 0.3);
                    }
                    border.width: 1
                    border.color: root.selectedIndex === index ? Theme.accent : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)

                    HoverHandler { id: vCardHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            root.selectedIndex = index;
                            root.loadVersionContent(modelData.id);
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            // Badge Manual vs Auto
                            Rectangle {
                                Layout.preferredHeight: 18
                                Layout.preferredWidth: badgeLabel.implicitWidth + 10
                                radius: 9
                                color: modelData.is_manual ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25) : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1)

                                Text {
                                    id: badgeLabel
                                    anchors.centerIn: parent
                                    text: modelData.is_manual ? "Manual" : "Auto"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: modelData.is_manual ? Theme.accent : Theme.textSecondary
                                }
                            }

                            // Etiqueta del snapshot
                            Text {
                                Layout.fillWidth: true
                                text: modelData.label || "Sin etiqueta"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                color: Theme.text
                            }

                            // Tiempo relativo
                            Text {
                                text: root.formatTime(modelData.timestamp)
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.4)
                            }
                        }

                        // Métricas (+ líneas, - líneas, tamaño)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "+" + (modelData.added || 0)
                                font.family: Theme.fontFamilyMonospace
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                color: Theme.success
                                visible: (modelData.added || 0) > 0
                            }

                            Text {
                                text: "-" + (modelData.removed || 0)
                                font.family: Theme.fontFamilyMonospace
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                color: Theme.danger
                                visible: (modelData.removed || 0) > 0
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: (modelData.size || 0) > 1024 ? (Math.round((modelData.size || 0) / 102.4) / 10 + " KB") : ((modelData.size || 0) + " B")
                                font.family: Theme.fontFamilyMonospace
                                font.pixelSize: 10
                                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.35)
                            }
                        }
                    }
                }
            }

            // Mensaje vacío / cargando
            Text {
                anchors.centerIn: parent
                visible: root.versionsList.length === 0
                text: root.statusMessage
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.4)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                width: parent.width - 40
            }
        }

        // ── VISTA 2: Diff y Restauración ───────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.isViewingDiff
            spacing: 8

            // Botón volver a la lista
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    Layout.preferredHeight: 24
                    Layout.preferredWidth: backText.implicitWidth + 14
                    radius: 6
                    color: backHover.hovered ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12) : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        Image {
                            Layout.preferredWidth: 10
                            Layout.preferredHeight: 10
                            source: Theme.iconsPath + "chevron-left.svg"
                            sourceSize: Qt.size(20, 20)
                        }

                        Text {
                            id: backText
                            text: "Lista de versiones"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.text
                        }
                    }

                    HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.isViewingDiff = false }
                }

                Item { Layout.fillWidth: true }

                // Copiar versión antigua
                Rectangle {
                    Layout.preferredHeight: 24
                    Layout.preferredWidth: copyText.implicitWidth + 14
                    radius: 6
                    color: copyHover.hovered ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12) : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)

                    Text {
                        id: copyText
                        anchors.centerIn: parent
                        text: "Copiar versión"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.textSecondary
                    }

                    HoverHandler { id: copyHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            if (typeof Quickshell !== "undefined") {
                                Quickshell.clipboardText = root.selectedSnapshotText;
                            }
                        }
                    }
                }
            }

            // Visualizador DiffView comparando el snapshot antiguo con el texto actual
            DiffView {
                id: diffViewer
                Layout.fillWidth: true
                Layout.fillHeight: true
                oldText: root.selectedSnapshotText
                newText: root.currentText
            }

            // Barra inferior de acción: Restaurar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: 8
                color: restoreHover.hovered ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.9) : Theme.accent

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    Image {
                        Layout.preferredWidth: 14
                        Layout.preferredHeight: 14
                        source: Theme.iconsPath + "undo.svg"
                        sourceSize: Qt.size(28, 28)
                    }

                    Text {
                        text: "Restaurar esta versión"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Theme.accentText
                    }
                }

                HoverHandler { id: restoreHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        root.restoreVersionRequested(root.selectedSnapshotText);
                        root.close();
                    }
                }
            }
        }
    }
}
