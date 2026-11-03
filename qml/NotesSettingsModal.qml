import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Effects
import Notas

Item {
    id: root
    visible: isOpen || isClosing || opacity > 0
    opacity: (isOpen || isClosing) ? 1.0 : 0.0

    anchors.fill: parent
    z: 9999

    signal closed()

    property bool isOpen: false
    property bool isClosing: false
    property bool isFromButton: false
    property Item backgroundSourceItem: null
    property rect originRect: Qt.rect(Math.round((width - 40) / 2), Math.round((height - 40) / 2), 40, 40)
    property int tabIndex: 0

    WheelHandler {
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: root.isOpen || root.isClosing
        onWheel: (event) => {
            event.accepted = true;
        }
    }

    readonly property string notasBin: (typeof Sys !== "undefined" && Sys.appExecutable) ? Sys.appExecutable : "notas"

    // Estado del gestor de diccionarios (portado de LanguageManager.qml)
    property string spellInstallingCode: ""
    property int spellInstallProgress: 0
    property string spellInstallStage: ""
    property string spellDictSearchText: ""
    property string statusMessage: ""
    property bool statusIsError: false

    readonly property bool showAppearanceTab: (typeof Sys === "undefined" || !Sys.hasQuickshellConfig)
    readonly property var allTabs: [
        { value: "editor",     label: I18n.t("config.tabs.editor", "Editor"),                         icon: "edit.svg" },
        { value: "appearance", label: I18n.t("config.tabs.appearance", "Apariencia"),                 icon: "settings.svg" },
        { value: "language",   label: I18n.t("config.tabs.language", "Idioma y Corrección"),          icon: "spellcheck.svg" },
        { value: "about",      label: I18n.t("config.tabs.about", "Acerca de"),                       icon: "info.svg" }
    ]
    readonly property var tabs: showAppearanceTab ? allTabs : allTabs.filter(function(t) { return t.value !== "appearance"; })

    onTabsChanged: {
        var found = false;
        for (var i = 0; i < tabs.length; i++) {
            if (tabs[i].value === currentTabValue) {
                found = true;
                if (root.tabIndex !== i) root.tabIndex = i;
                break;
            }
        }
        if (!found) {
            root.tabIndex = 0;
        }
    }

    readonly property string currentTabValue: (tabIndex >= 0 && tabIndex < tabs.length) ? tabs[tabIndex].value : "editor"

    function _safeHue(c) {
        return (c && c.hsvHue >= 0) ? c.hsvHue : 0.0;
    }

    function _hsva(c, vAdd, alpha) {
        if (!c) return Qt.rgba(0, 0, 0, alpha);
        var h = (c.hsvHue >= 0) ? c.hsvHue : 0.0;
        var s = Math.max(0.0, Math.min(1.0, c.hsvSaturation));
        var v = Math.max(0.0, Math.min(1.0, c.hsvValue + (vAdd || 0.0)));
        return Qt.hsva(h, s, v, alpha);
    }

    function toggle(rect) {
        if (isOpen && !isClosing) {
            close();
        } else {
            open(rect);
        }
    }

    function open(rect) {
        if (isOpen && !isClosing) return;
        closeCardAnim.stop();
        fadeCloseAnim.stop();
        var noteIsActive = (typeof NotesService !== "undefined" && NotesService.isEditing);
        if (!noteIsActive && rect && typeof rect.x === "number") {
            originRect = rect;
            isFromButton = true;
        } else {
            originRect = Qt.rect(Math.round((root.width - targetWidth) / 2), Math.round((root.height - targetHeight) / 2), targetWidth, targetHeight);
            isFromButton = false;
        }
        if (typeof SpellService !== "undefined") {
            SpellService.refreshDicts();
        }
        isOpen = true;
        isClosing = false;

        if (!Theme.animationsEnabled || GamemodeService.gamemodeActive) {
            card.x = Math.round((root.width - targetWidth) / 2);
            card.y = Math.round((root.height - targetHeight) / 2);
            card.width = targetWidth;
            card.height = targetHeight;
            card.radius = 16;
            cardBtnContent.opacity = 0.0;
            modalBgGroup.opacity = 1.0;
            modalContentLayout.opacity = 1.0;
            return;
        }

        if (isFromButton) {
            card.x = originRect.x;
            card.y = originRect.y;
            card.width = originRect.width > 0 ? originRect.width : 38;
            card.height = originRect.height > 0 ? originRect.height : 38;
            card.radius = 10;
            cardBtnContent.opacity = 1.0;
            modalBgGroup.opacity = 0.0;
            modalContentLayout.opacity = 0.0;
            openCardAnim.restart();
        } else {
            card.x = Math.round((root.width - targetWidth) / 2);
            card.y = Math.round((root.height - targetHeight) / 2);
            card.width = targetWidth;
            card.height = targetHeight;
            card.radius = 16;
            cardBtnContent.opacity = 0.0;
            modalBgGroup.opacity = 0.0;
            modalContentLayout.opacity = 0.0;
            fadeOpenAnim.restart();
        }
    }

    function close() {
        if (sharedContextMenu.visible) {
            sharedContextMenu.closeMenu();
        }
        if (!isOpen && !isClosing) return;
        openCardAnim.stop();
        fadeOpenAnim.stop();

        if (isFromButton && backgroundSourceItem && typeof backgroundSourceItem.getSettingsButtonRect === "function") {
            var curRect = backgroundSourceItem.getSettingsButtonRect();
            if (curRect && typeof curRect.x === "number") {
                originRect = curRect;
            }
        }

        if (!Theme.animationsEnabled || GamemodeService.gamemodeActive) {
            isOpen = false;
            isClosing = false;
            closed();
            return;
        }

        if (!isFromButton) {
            isClosing = true;
            fadeCloseAnim.restart();
            return;
        }

        isClosing = true;
        closeCardAnim.restart();
    }

    ParallelAnimation {
        id: openCardAnim

        SpringAnimation { target: card; property: "x"; to: Math.round((root.width - targetWidth) / 2); spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25 }
        SpringAnimation { target: card; property: "y"; to: Math.round((root.height - targetHeight) / 2); spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25 }
        SpringAnimation { target: card; property: "width"; to: targetWidth; spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25 }
        SpringAnimation { target: card; property: "height"; to: targetHeight; spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25 }
        NumberAnimation { target: card; property: "radius"; to: 16; duration: 200; easing.type: Easing.OutCubic }
        NumberAnimation { target: cardBtnContent; property: "opacity"; to: 0.0; duration: 100; easing.type: Easing.OutCubic }
        NumberAnimation { target: modalBgGroup; property: "opacity"; to: 1.0; duration: 200; easing.type: Easing.OutCubic }

        SequentialAnimation {
            PauseAnimation { duration: 60 }
            NumberAnimation { target: modalContentLayout; property: "opacity"; to: 1.0; duration: 160; easing.type: Easing.OutCubic }
        }
    }

    ParallelAnimation {
        id: closeCardAnim

        NumberAnimation { target: modalContentLayout; property: "opacity"; to: 0.0; duration: 80; easing.type: Easing.OutCubic }
        NumberAnimation { target: modalBgGroup; property: "opacity"; to: 0.0; duration: 200; easing.type: Easing.OutCubic }

        SpringAnimation { target: card; property: "x"; to: originRect.x; spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25 }
        SpringAnimation { target: card; property: "y"; to: originRect.y; spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25 }
        SpringAnimation { target: card; property: "width"; to: (originRect.width > 0 ? originRect.width : 38); spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25 }
        SpringAnimation { target: card; property: "height"; to: (originRect.height > 0 ? originRect.height : 38); spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25 }
        NumberAnimation { target: card; property: "radius"; to: 10; duration: 180; easing.type: Easing.OutCubic }

        SequentialAnimation {
            PauseAnimation { duration: 60 }
            NumberAnimation { target: cardBtnContent; property: "opacity"; to: 1.0; duration: 130; easing.type: Easing.OutCubic }
        }

        onFinished: {
            card.x = originRect.x;
            card.y = originRect.y;
            card.width = (originRect.width > 0 ? originRect.width : 38);
            card.height = (originRect.height > 0 ? originRect.height : 38);
            card.radius = 10;
            root.isOpen = false;
            root.isClosing = false;
            root.closed();
        }
    }

    ParallelAnimation {
        id: fadeOpenAnim
        NumberAnimation { target: modalBgGroup; property: "opacity"; to: 1.0; duration: 150; easing.type: Easing.OutCubic }
        NumberAnimation { target: modalContentLayout; property: "opacity"; to: 1.0; duration: 150; easing.type: Easing.OutCubic }
    }

    ParallelAnimation {
        id: fadeCloseAnim
        NumberAnimation { target: modalBgGroup; property: "opacity"; to: 0.0; duration: 120; easing.type: Easing.OutCubic }
        NumberAnimation { target: modalContentLayout; property: "opacity"; to: 0.0; duration: 120; easing.type: Easing.OutCubic }
        onFinished: {
            root.isOpen = false;
            root.isClosing = false;
            root.closed();
        }
    }

    onWidthChanged: {
        if (isOpen && !isClosing && !openCardAnim.running) {
            card.x = Math.round((width - targetWidth) / 2);
            card.width = targetWidth;
        }
    }
    onHeightChanged: {
        if (isOpen && !isClosing && !openCardAnim.running) {
            card.y = Math.round((height - targetHeight) / 2);
            card.height = targetHeight;
        }
    }

    Shortcut {
        enabled: root.isOpen
        sequence: "Escape"
        onActivated: {
            if (sharedContextMenu.visible) {
                sharedContextMenu.closeMenu();
            } else {
                root.close();
            }
        }
    }

    // ── Procesos auxiliares (selector de carpeta + diccionarios Hunspell) ────
    Process {
        id: dirPickerProc
        command: [root.notasBin, "file-picker", "--directory", "--title", I18n.t("config.notes.select_dir", "Seleccionar carpeta de notas")]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (data) => {
                var p = data.trim();
                if (p !== "") {
                    ConfigBackend.notasDir = p;
                    dirInput.text = p;
                    NotesService.refresh();
                }
            }
        }
        Component.onDestruction: { running = false; }
    }

    Process {
        id: spellInstallProc
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                var cleaned = line.trim();
                if (!cleaned) return;
                try {
                    var data = JSON.parse(cleaned);
                    if (data.status === "progress" && data.progress !== undefined) {
                        root.spellInstallProgress = data.progress;
                        root.spellInstallStage = data.stage || "";
                    } else if (data.status === "installed") {
                        root.spellInstallProgress = 100;
                    } else if (data.status === "error") {
                        root.statusMessage = data.message || "Error al instalar diccionario";
                        root.statusIsError = true;
                    }
                } catch (e) {}
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                console.warn("[SpellInstall stderr]", line);
            }
        }
        onExited: (code) => {
            var target = root.spellInstallingCode;
            root.spellInstallingCode = "";
            root.spellInstallProgress = 0;
            root.spellInstallStage = "";
            if (code === 0) {
                if (typeof SpellService !== "undefined") {
                    SpellService.refreshDicts();
                }
                root.statusMessage = I18n.t("config.language.spell_installed", "Diccionario instalado");
                root.statusIsError = false;
            } else if (!root.statusIsError) {
                root.statusMessage = "Fallo al instalar diccionario (" + target + ")";
                root.statusIsError = true;
            }
        }
        Component.onDestruction: { running = false; }
    }

    Process {
        id: spellRemoveProc
        running: false
        stdout: StdioCollector {
            id: removeCollector
            onStreamFinished: {
                try {
                    var data = JSON.parse(removeCollector.text);
                    if (data.reason === "system_dict") {
                        root.statusMessage = data.message || "Diccionario del sistema (no removible)";
                        root.statusIsError = true;
                    } else if (data.status === "error") {
                        root.statusMessage = data.message || "No se pudo quitar el diccionario";
                        root.statusIsError = true;
                    }
                } catch (e) {}
            }
        }
        onExited: (code) => {
            if (code === 0 && !root.statusIsError) {
                if (typeof SpellService !== "undefined") {
                    SpellService.refreshDicts();
                }
                root.statusMessage = I18n.t("config.language.spell_removed", "Diccionario quitado");
                root.statusIsError = false;
            }
        }
        Component.onDestruction: { running = false; }
    }

    Process {
        id: spellImportProc
        running: false
        stdout: StdioCollector {
            id: importCollector
            onStreamFinished: {
                try {
                    var data = JSON.parse(importCollector.text);
                    if (data.status === "imported") {
                        if (typeof SpellService !== "undefined") {
                            SpellService.refreshDicts();
                        }
                        root.statusMessage = "Diccionario importado: " + (data.codes ? data.codes.join(", ") : "");
                        root.statusIsError = false;
                    } else if (data.status === "error") {
                        root.statusMessage = data.message || "Error al importar diccionario";
                        root.statusIsError = true;
                    }
                } catch (e) {
                    console.warn("[SpellImport] Parse error:", e);
                }
            }
        }
        onExited: (code) => {
            if (code !== 0 && !root.statusIsError) {
                root.statusMessage = "Error al procesar archivo de diccionario";
                root.statusIsError = true;
            }
        }
        Component.onDestruction: { running = false; }
    }

    Process {
        id: dictPickerProc
        command: [
            root.notasBin, "file-picker",
            "--title", "Importar diccionario (.dic, .aff, .oxt, .zip)",
            "--filter", "Diccionarios Hunspell (*.dic, *.aff, *.oxt, *.zip):*.dic:*.aff:*.oxt:*.zip"
        ]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                var p = line.trim();
                if (p) {
                    root.statusIsError = false;
                    spellImportProc.command = [root.notasBin, "spell", "import", p];
                    spellImportProc.running = true;
                }
            }
        }
        Component.onDestruction: { running = false; }
    }

    onStatusMessageChanged: {
        if (statusMessage !== "") {
            statusTimer.restart();
        } else {
            statusTimer.stop();
        }
    }

    Timer {
        id: statusTimer
        interval: 3200
        repeat: false
        onTriggered: {
            root.statusMessage = "";
            root.statusIsError = false;
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // COMPONENTES REUTILIZABLES (PORTADOS 1:1 DE SchemaForm.qml / ThemeManager.qml)
    // ══════════════════════════════════════════════════════════════════════════

    component SectionHeader: RowLayout {
        property string title: ""
        property string iconName: ""
        Layout.fillWidth: true
        spacing: 8

        Image {
            visible: parent.iconName !== ""
            width: 14
            height: 14
            source: parent.iconName !== "" ? (Theme.iconsPath + parent.iconName) : ""
            sourceSize: Qt.size(14, 14)
            layer.enabled: visible && !GamemodeService.gamemodeActive
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: Theme.muted
            }
        }

        Text {
            text: parent.title.toUpperCase()
            color: Theme.muted
            font {
                pixelSize: Theme.fontSizeSmall
                bold: true
                letterSpacing: 1.2
                family: Theme.fontFamily
            }
        }
    }

    component BentoCard: Rectangle {
        Layout.fillWidth: true
        color: "transparent"
        border.width: 0
    }

    // ── SegmentedPicker (copiado de ThemeManager.qml / SchemaForm.qml) ────────
    component SegmentedPicker: Rectangle {
        id: picker

        property var options: []
        property string currentValue: ""
        property bool active: true
        property var supportedList: []
        property var segmentRefs: []
        property real barHeight: 32

        readonly property int activeIndex: {
            for (var i = 0; i < options.length; i++) {
                if (options[i].value === currentValue)
                    return i;
            }
            return -1;
        }
        property bool isLoaded: false
        readonly property bool animReady: picker.isLoaded && root.isOpen && Math.abs(card.width - root.targetWidth) < 4

        signal selected(string value, int idx)

        Layout.fillWidth: true
        implicitHeight: barHeight
        radius: 10
        color: root._hsva(Theme.surface, 0.04, 0.35)
        border.color: root._hsva(Theme.text, 0, 0.08)
        border.width: 1
        clip: true

        Component.onCompleted: {
            Qt.callLater(function() {
                picker.isLoaded = true;
            });
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: {}
        }

        // Cápsula activa flotante con SpringAnimation elástica y squash en bordes
        Rectangle {
            id: activeIndicator

            readonly property var activeRef: (picker.activeIndex >= 0 && picker.activeIndex < picker.segmentRefs.length)
                ? picker.segmentRefs[picker.activeIndex]
                : null
            property real idealX: activeRef ? (activeRef.x + enumRow.x) : 2
            property real idealWidth: activeRef ? activeRef.width : 0
            readonly property real leftBound: 2
            readonly property real rightBound: Math.max(leftBound, parent ? parent.width - 2 : 2)
            readonly property real visualLeft: Math.max(leftBound, idealX)
            readonly property real visualRight: Math.min(rightBound, idealX + idealWidth)

            z: 1
            visible: picker.activeIndex >= 0 && width > 0
            height: parent.height - 4
            radius: 8
            anchors.verticalCenter: parent.verticalCenter
            color: picker.active
                ? root._hsva(Theme.accent, 0, 0.14)
                : root._hsva(Theme.muted, 0, 0.08)
            border.color: picker.active
                ? root._hsva(Theme.accent, 0, 0.25)
                : root._hsva(Theme.text, 0, 0.10)
            border.width: 1
            x: visualLeft
            width: Math.max(0, visualRight - visualLeft)

            Behavior on idealX {
                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive && picker.animReady
                SpringAnimation {
                    spring: 4.5
                    damping: 0.35
                    mass: 0.65
                    epsilon: 0.25
                }
            }

            Behavior on idealWidth {
                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive && picker.animReady
                SpringAnimation {
                    spring: 4.5
                    damping: 0.35
                    mass: 0.65
                    epsilon: 0.25
                }
            }
        }

        RowLayout {
            id: enumRow
            z: 2
            anchors.fill: parent
            anchors.margins: 2
            spacing: 4

            Repeater {
                model: picker.options

                delegate: Rectangle {
                    id: segmentBtn

                    required property var modelData
                    required property int index
                    readonly property bool isSelected: modelData.value === picker.currentValue
                    readonly property bool isSupported: picker.supportedList.length === 0 || picker.supportedList.indexOf(modelData.value) !== -1
                    readonly property bool hasIcon: Boolean(modelData.icon && modelData.icon !== "")

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "transparent"
                    border.color: !isSupported ? root._hsva(Theme.danger, 0, 0.25) : "transparent"
                    border.width: !isSupported ? 1 : 0
                    radius: 6
                    opacity: !isSupported ? 0.35 : 1.0

                    Component.onCompleted: {
                        var refs = picker.segmentRefs.slice();
                        refs[index] = segmentBtn;
                        picker.segmentRefs = refs;
                    }
                    Component.onDestruction: {
                        var refs = picker.segmentRefs.slice();
                        if (refs[index] === segmentBtn)
                            refs[index] = null;
                        picker.segmentRefs = refs;
                    }

                    // Variante con icono + etiqueta (barra superior de pestañas)
                    RowLayout {
                        visible: segmentBtn.hasIcon
                        anchors.centerIn: parent
                        spacing: 7

                        Image {
                            width: 15
                            height: 15
                            source: segmentBtn.hasIcon ? (Theme.iconsPath + segmentBtn.modelData.icon) : ""
                            sourceSize: Qt.size(15, 15)
                            layer.enabled: parent.visible && !GamemodeService.gamemodeActive
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: segmentBtn.isSelected ? Theme.accent : Theme.muted
                                Behavior on colorizationColor {
                                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                    ColorAnimation { duration: 120 }
                                }
                            }
                        }

                        Text {
                            text: segmentBtn.modelData.label || ""
                            color: segmentBtn.isSelected ? Theme.accent : Theme.muted
                            font {
                                pixelSize: Theme.fontSizeBody
                                bold: segmentBtn.isSelected
                                family: Theme.fontFamily
                            }
                            Behavior on color {
                                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                ColorAnimation { duration: 120 }
                            }
                        }
                    }

                    // Variante solo texto con marquee (idéntica a SchemaForm.qml / ThemeManager.qml)
                    Item {
                        id: segmentTextClip
                        visible: !segmentBtn.hasIcon

                        readonly property bool overflows: segmentLbl.implicitWidth > width && width > 0
                        readonly property real gap: 24
                        readonly property real stride: segmentLbl.implicitWidth + gap
                        property real offset: 0

                        height: parent.height
                        clip: true

                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 6
                            rightMargin: 6
                        }

                        Text {
                            id: segmentLbl
                            x: segmentTextClip.overflows ? segmentTextClip.offset : (parent.width - implicitWidth) / 2
                            anchors.verticalCenter: parent.verticalCenter
                            text: segmentBtn.modelData.label || ""
                            color: segmentBtn.isSelected ? Theme.accent : Theme.muted
                            onTextChanged: segmentTextClip.offset = 0

                            font {
                                pixelSize: Theme.fontSizeBodySecondary
                                bold: segmentBtn.isSelected
                                family: Theme.fontFamily
                            }

                            Behavior on color {
                                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                ColorAnimation { duration: 120 }
                            }
                        }

                        Text {
                            x: segmentTextClip.offset + segmentTextClip.stride
                            anchors.verticalCenter: parent.verticalCenter
                            visible: segmentTextClip.overflows
                            text: segmentLbl.text
                            color: segmentLbl.color
                            font: segmentLbl.font
                        }

                        SequentialAnimation on offset {
                            running: segmentTextClip.visible && segmentTextClip.overflows && Theme.animationsEnabled && !GamemodeService.gamemodeActive
                            loops: GamemodeService.gamemodeActive ? 0 : Animation.Infinite

                            PauseAnimation { duration: 1500 }

                            NumberAnimation {
                                from: 0
                                to: -segmentTextClip.stride
                                duration: Math.max(200, segmentTextClip.stride * 16)
                                easing.type: Easing.Linear
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: (picker.active && segmentBtn.isSupported) ? Qt.PointingHandCursor : Qt.ArrowCursor
                        enabled: picker.active && segmentBtn.isSupported
                        onClicked: {
                            picker.selected(segmentBtn.modelData.value, segmentBtn.index);
                        }
                    }
                }
            }
        }
    }

    // ── Switch líquido y elástico (copiado de boolField en SchemaForm.qml) ───
    component SchemaSwitchRow: Rectangle {
        id: bf

        property string label: ""
        property string comment: ""
        property bool checked: false
        property bool isDisabled: false
        signal toggled(bool newValue)

        opacity: isDisabled ? 0.45 : 1.0
        Behavior on opacity {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            NumberAnimation { duration: 150 }
        }

        Layout.fillWidth: true
        implicitHeight: 46
        radius: 8
        color: rowMouse.containsMouse ? root._hsva(Theme.text, 0, 0.04) : "transparent"
        border.width: 0

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: bf.isDisabled ? Qt.ArrowCursor : Qt.PointingHandCursor
            onClicked: {
                if (!bf.isDisabled) {
                    bf.toggled(!bf.checked);
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: bf.label
                    color: Theme.text
                    font {
                        pixelSize: Theme.fontSizeSubheading
                        family: Theme.fontFamily
                    }
                }

                Text {
                    visible: text !== ""
                    text: bf.comment
                    color: Theme.muted
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    font {
                        pixelSize: Theme.fontSizeBodySecondary
                        family: Theme.fontFamily
                    }
                }
            }

            Rectangle {
                id: swRect

                width: 40
                height: 22
                radius: 11
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                color: bf.checked
                    ? root._hsva(Theme.success, 0, 0.70)
                    : root._hsva(Theme.muted, 0, 0.35)

                Rectangle {
                    id: swThumb

                    width: (rowMouse.pressed || swMouse.pressed) ? 19 : 14
                    height: 14
                    radius: 7
                    color: Theme.text
                    anchors.verticalCenter: parent.verticalCenter
                    x: bf.checked ? parent.width - width - 4 : 4

                    Behavior on x {
                        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                        NumberAnimation {
                            duration: 250
                            easing.type: Easing.OutBack
                        }
                    }

                    Behavior on width {
                        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                        NumberAnimation {
                            duration: 150
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                MouseArea {
                    id: swMouse
                    anchors.fill: parent
                    cursorShape: bf.isDisabled ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: {
                        if (!bf.isDisabled) {
                            bf.toggled(!bf.checked);
                        }
                    }
                }

                Behavior on color {
                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                    ColorAnimation { duration: 220 }
                }
            }
        }
    }

    // ── Deslizador numérico (copiado de numField en SchemaForm.qml) ──────────
    component SchemaSliderRow: ColumnLayout {
        id: nf

        property string label: ""
        property string comment: ""
        property real val: 0
        property real minV: 0
        property real maxV: 100
        property real stepSize: 1
        property bool isInt: true
        property string suffix: ""
        signal moved(real newVal)

        function _snap(raw) {
            var clamped = Math.max(nf.minV, Math.min(nf.maxV, raw));
            if (nf.stepSize > 0) {
                clamped = Math.round(clamped / nf.stepSize) * nf.stepSize;
            }
            if (nf.isInt) {
                clamped = Math.round(clamped);
            }
            return Math.max(nf.minV, Math.min(nf.maxV, clamped));
        }

        Layout.fillWidth: true
        spacing: 6

        RowLayout {
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                text: nf.label
                color: Theme.text
                font {
                    pixelSize: Theme.fontSizeSubheading
                    family: Theme.fontFamily
                }
            }

            Text {
                text: (nf.isInt ? Math.round(nf.val).toString() : nf.val.toFixed(2)) + nf.suffix
                color: Theme.accent
                font {
                    pixelSize: Theme.fontSizeBody
                    bold: true
                    family: Theme.fontFamily
                }
            }
        }

        Item {
            id: track

            readonly property real frac: Math.max(0.0, Math.min(1.0, (nf.val - nf.minV) / Math.max(0.0001, (nf.maxV - nf.minV))))

            Layout.fillWidth: true
            Layout.preferredHeight: 6
            Layout.topMargin: 4
            Layout.leftMargin: 3
            Layout.rightMargin: 3

            Rectangle {
                anchors.fill: parent
                radius: 3
                color: root._hsva(Theme.muted, 0, 0.16)
            }

            Rectangle {
                width: Math.max(height, track.frac * track.width)
                height: parent.height
                radius: 3
                color: Theme.accent
            }

            Rectangle {
                id: knob

                z: 1
                width: 8
                height: 18
                radius: 4
                anchors.verticalCenter: parent.verticalCenter
                x: track.frac * track.width - 4
                color: Theme.color2
                scale: kDrag.active ? 1.3 : (hKnob.hovered ? 1.15 : 1.0)

                HoverHandler { id: hKnob }

                DragHandler {
                    id: kDrag
                    target: null
                    xAxis.enabled: true
                    yAxis.enabled: false
                    onCentroidChanged: {
                        if (active && track.width > 0) {
                            var localX = track.mapFromItem(null, centroid.scenePosition.x, centroid.scenePosition.y).x;
                            var f = Math.max(0.0, Math.min(1.0, localX / track.width));
                            var nextV = nf._snap(nf.minV + f * (nf.maxV - nf.minV));
                            if (nextV !== nf.val) {
                                nf.moved(nextV);
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    cursorShape: Qt.SizeHorCursor
                }

                Behavior on scale {
                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.OutBack
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    if (track.width <= 0) return;
                    var f = Math.max(0.0, Math.min(1.0, mouse.x / track.width));
                    var nextV = nf._snap(nf.minV + f * (nf.maxV - nf.minV));
                    if (nextV !== nf.val) {
                        nf.moved(nextV);
                    }
                }
            }
        }

        Text {
            visible: text !== ""
            text: nf.comment
            color: Theme.muted
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font {
                pixelSize: Theme.fontSizeBodySecondary
                family: Theme.fontFamily
            }
        }
    }

    // ── Fondo transparente con captura de clicks para cerrar ────────────────
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: "transparent"
        visible: root.isOpen || root.isClosing

        MouseArea {
            anchors.fill: parent
            enabled: root.isOpen
            onClicked: root.close()
            onWheel: (wheel) => { wheel.accepted = true; }
        }
    }

    // ── Tarjeta Bento Principal con Morph Animation (igual a morphCard) ──────
    readonly property real targetWidth: Math.min(root.width - 48, 840)
    readonly property real targetHeight: Math.min(root.height - 48, 650)

    Rectangle {
        id: card
        x: Math.round((root.width - targetWidth) / 2)
        y: Math.round((root.height - targetHeight) / 2)
        width: targetWidth
        height: targetHeight
        radius: 16
        color: "transparent"
        clip: true

        layer.enabled: (modalBgGroup.opacity > 0.005) && !GamemodeService.gamemodeActive
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.45 * modalBgGroup.opacity)
            shadowBlur: 0.6
            shadowVerticalOffset: 6
            shadowHorizontalOffset: 0
        }

        // ── Apariencia del botón cuando está colapsado (fondo y borde de botón) ──
        Rectangle {
            id: cardBtnBg
            anchors.fill: parent
            radius: card.radius
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05)
            border.color: Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.12)
            border.width: 1
            visible: root.isFromButton && opacity > 0
            opacity: 1.0 - modalBgGroup.opacity
        }

        // ── Apariencia del modal (Frosted Glass y superficie) con fade ────────
        Item {
            id: modalBgGroup
            anchors.fill: parent
            opacity: 0.0

            // Máscara redondeada para recortar perfectamente el contenedor de desenfoque a las esquinas
            Item {
                id: blurMaskItem
                anchors.fill: parent
                layer.enabled: card.radius > 0
                visible: false

                Rectangle {
                    anchors.fill: parent
                    radius: card.radius
                    color: "black"
                }
            }

            // Desenfoque recortado estrictamente a la tarjeta con máscara redondeada y padding perimetral interno
            Item {
                id: cardBlurContainer
                anchors.fill: parent
                clip: true
                visible: (root.isOpen || root.isClosing) && !GamemodeService.gamemodeActive && root.backgroundSourceItem !== null

                layer.enabled: card.radius > 0
                layer.smooth: true
                layer.effect: MultiEffect {
                    autoPaddingEnabled: false
                    maskEnabled: card.radius > 0
                    maskSource: blurMaskItem
                }

                readonly property real blurPadding: 96
                readonly property real bgW: root.backgroundSourceItem ? root.backgroundSourceItem.width : root.width
                readonly property real bgH: root.backgroundSourceItem ? root.backgroundSourceItem.height : root.height

                readonly property real padLeft: Math.min(blurPadding, Math.max(0, card.x))
                readonly property real padTop: Math.min(blurPadding, Math.max(0, card.y))
                readonly property real padRight: Math.min(blurPadding, Math.max(0, bgW - (card.x + card.width)))
                readonly property real padBottom: Math.min(blurPadding, Math.max(0, bgH - (card.y + card.height)))

                readonly property real sampleX: Math.round(Math.max(0, card.x - padLeft))
                readonly property real sampleY: Math.round(Math.max(0, card.y - padTop))
                readonly property real sampleW: Math.round(Math.max(1, Math.min(bgW - sampleX, card.width + padLeft + padRight)))
                readonly property real sampleH: Math.round(Math.max(1, Math.min(bgH - sampleY, card.height + padTop + padBottom)))

                ShaderEffectSource {
                    id: cardBlurSrc
                    x: -Math.round(card.x - cardBlurContainer.sampleX)
                    y: -Math.round(card.y - cardBlurContainer.sampleY)
                    width: cardBlurContainer.sampleW
                    height: cardBlurContainer.sampleH

                    sourceItem: root.backgroundSourceItem
                    sourceRect: Qt.rect(cardBlurContainer.sampleX, cardBlurContainer.sampleY, cardBlurContainer.sampleW, cardBlurContainer.sampleH)
                    live: (root.isOpen || root.isClosing) && Theme.animationsEnabled && !GamemodeService.gamemodeActive
                    hideSource: false
                    layer.enabled: parent.visible
                    layer.smooth: true
                    layer.effect: MultiEffect {
                        autoPaddingEnabled: false
                        blurEnabled: !GamemodeService.gamemodeActive
                        blur: 1.0
                        blurMax: 96
                        saturation: 0.20
                    }
                }
            }

            // Superficie de fondo tintada sobre el blur (transparencia justa para apreciar el blur)
            Rectangle {
                id: cardBgTint
                anchors.fill: parent
                radius: card.radius
                color: Qt.hsva(Theme.surface.hsvHue,
                               Math.min(1, Theme.surface.hsvSaturation),
                               Math.min(1, Theme.surface.hsvValue + 0.02),
                               (!GamemodeService.gamemodeActive && root.backgroundSourceItem !== null)
                                   ? 0.85
                                   : (GamemodeService.gamemodeActive ? 1.0 : Theme.panelOpacity))
                border.color: Theme.border
                border.width: 1
            }
        }

        Item {
            id: cardBtnContent
            anchors.right: parent.right
            anchors.top: parent.top
            transformOrigin: Item.TopRight
            width: Math.min(parent.width, (root.originRect.width > 0) ? root.originRect.width : 38)
            height: Math.min(parent.height, (root.originRect.height > 0) ? root.originRect.height : 38)
            visible: root.isFromButton && opacity > 0
            opacity: 0.0
            z: 10
            clip: true

            Image {
                anchors.centerIn: parent
                width: 16
                height: 16
                source: Theme.iconsPath + "settings.svg"
                sourceSize: Qt.size(16, 16)
                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: Theme.muted
                }
            }
        }

        // ── Consumir clicks dentro de la tarjeta para evitar que se propaguen al backdrop ──
        MouseArea {
            id: cardClickBlocker
            anchors.fill: parent
            enabled: root.isOpen
            acceptedButtons: Qt.AllButtons
            onClicked: {}
        }

        ColumnLayout {
            id: modalContentLayout
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14
            opacity: 0.0
            visible: opacity > 0

            // ── Cabecera ─────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: I18n.t("config.modal.title", "Configuración de Notas")
                    font.family: Theme.fontFamilyDisplay
                    font.pixelSize: Theme.fontSizeTitleLarge
                    font.bold: true
                    color: Theme.text
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 32
                    height: 32
                    radius: 8
                    color: closeArea.containsMouse ? Theme.surfaceHover : "transparent"

                    Image {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        source: Theme.iconsPath + "close.svg"
                        sourceSize: Qt.size(16, 16)
                        layer.enabled: !GamemodeService.gamemodeActive
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: closeArea.containsMouse ? Theme.text : Theme.muted
                        }
                    }

                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
                    }
                }
            }

            // ── Barra Superior Animada (SegmentedPicker de Settings) ─────
            SegmentedPicker {
                id: topTabsPicker
                barHeight: 38
                options: root.tabs
                currentValue: root.currentTabValue
                onSelected: (val, idx) => {
                    if (root.tabIndex !== idx) {
                        root.tabIndex = idx;
                        modalFlickable.contentY = 0;
                    }
                }
            }

            // ── Cuerpo de Pestañas con CustomScrollBar ───────────────────
            Flickable {
                id: modalFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: Math.max(100, width - vbar.reservedSpace)
                contentHeight: activeTabCol.implicitHeight + 20

                ScrollBar.vertical: CustomScrollBar { id: vbar }

                Item {
                    id: stackContent
                    width: modalFlickable.contentWidth
                    implicitHeight: activeTabCol.implicitHeight

                    // ══════════════════════════════════════════════════════
                    // PESTAÑA 0: EDITOR
                    // ══════════════════════════════════════════════════════
                    ColumnLayout {
                        id: tabEditor
                        visible: root.currentTabValue === "editor"
                        width: parent.width
                        spacing: 14

                        SectionHeader {
                            iconName: "folder.svg"
                            title: I18n.t("config.notes.storage_section", "Almacenamiento e Importación")
                        }

                        BentoCard {
                            implicitHeight: colDir.implicitHeight + 8
                            ColumnLayout {
                                id: colDir
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                anchors.topMargin: 2
                                anchors.bottomMargin: 6
                                spacing: 12

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        text: I18n.t("config.notes.dir", "Carpeta de notas")
                                        color: Theme.text
                                        font {
                                            pixelSize: Theme.fontSizeSubheading
                                            family: Theme.fontFamily
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 36
                                            radius: 8
                                            color: root._hsva(Theme.surface, 0.04, 0.35)
                                            border.color: dirInput.activeFocus
                                                ? root._hsva(Theme.accent, 0, 0.65)
                                                : root._hsva(Theme.text, 0, 0.12)
                                            border.width: 1

                                            TextInput {
                                                id: dirInput
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                verticalAlignment: TextInput.AlignVCenter
                                                text: ConfigBackend.notasDir
                                                color: Theme.text
                                                font.family: Theme.fontFamilyMonospace
                                                font.pixelSize: Theme.fontSizeBody
                                                selectByMouse: true
                                                clip: true
                                                CustomTextCursor {}

                                                onEditingFinished: {
                                                    var trimmed = text.trim();
                                                    if (trimmed !== "" && ConfigBackend.notasDir !== trimmed) {
                                                        ConfigBackend.notasDir = trimmed;
                                                        NotesService.refresh();
                                                    }
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    acceptedButtons: Qt.RightButton
                                                    onClicked: (mouse) => {
                                                        if (mouse.button === Qt.RightButton) {
                                                            dirInput.forceActiveFocus();
                                                            sharedContextMenu.open(dirInput);
                                                        }
                                                    }
                                                }
                                            }

                                            Connections {
                                                target: ConfigBackend
                                                function onNotasDirChanged() {
                                                    if (!dirInput.activeFocus && dirInput.text !== ConfigBackend.notasDir) {
                                                        dirInput.text = ConfigBackend.notasDir;
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle {
                                            implicitWidth: btnBrowseRow.implicitWidth + 24
                                            implicitHeight: 36
                                            radius: 8
                                            color: browseMa.pressed
                                                ? root._hsva(Theme.accent, 0.18, 0.65)
                                                : (browseHov.hovered
                                                    ? root._hsva(Theme.accent, 0, 0.42)
                                                    : root._hsva(Theme.accent, 0, 0.28))
                                            scale: browseMa.pressed ? 0.96 : 1.0

                                            Behavior on color {
                                                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                                ColorAnimation { duration: 80 }
                                            }
                                            Behavior on scale {
                                                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                                NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
                                            }

                                            HoverHandler { id: browseHov }

                                            RowLayout {
                                                id: btnBrowseRow
                                                anchors.centerIn: parent
                                                spacing: 6

                                                Image {
                                                    width: 14
                                                    height: 14
                                                    source: Theme.iconsPath + "folder.svg"
                                                    sourceSize: Qt.size(14, 14)
                                                    layer.enabled: !GamemodeService.gamemodeActive
                                                    layer.effect: MultiEffect {
                                                        colorization: 1.0
                                                        colorizationColor: Theme.accent
                                                    }
                                                }

                                                Text {
                                                    text: I18n.t("config.notes.browse", "Examinar")
                                                    color: Theme.accent
                                                    font {
                                                        pixelSize: Theme.fontSizeBody
                                                        bold: true
                                                        family: Theme.fontFamily
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                id: browseMa
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (!dirPickerProc.running) {
                                                        dirPickerProc.running = true;
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        text: I18n.t("config.notes.dir_comment", "Directorio donde se almacenarán las notas en formato Markdown (.md). Soporta $XDG_DOCUMENTS_DIR y $HOME.")
                                        color: Theme.muted
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        font {
                                            pixelSize: Theme.fontSizeBodySecondary
                                            family: Theme.fontFamily
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        text: I18n.t("config.notes.import_mode", "Al arrastrar un archivo")
                                        color: Theme.text
                                        font {
                                            pixelSize: Theme.fontSizeSubheading
                                            family: Theme.fontFamily
                                        }
                                    }

                                    SegmentedPicker {
                                        options: [
                                            { value: "copy", label: I18n.t("config.notes.import_mode_copy", "Copiar a carpeta de notas") },
                                            { value: "move", label: I18n.t("config.notes.import_mode_move", "Mover archivo original") }
                                        ]
                                        currentValue: ConfigBackend.importMode
                                        onSelected: (val) => {
                                            if (ConfigBackend.importMode !== val) ConfigBackend.importMode = val;
                                        }
                                    }
                                }
                            }
                        }

                        SectionHeader {
                            iconName: "grid.svg"
                            title: I18n.t("config.notes.view_section", "Vista y Editor")
                        }

                        BentoCard {
                            implicitHeight: colEditorOpts.implicitHeight + 8
                            ColumnLayout {
                                id: colEditorOpts
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                anchors.topMargin: 2
                                anchors.bottomMargin: 6
                                spacing: 12

                                SchemaSwitchRow {
                                    visible: (typeof Sys === "undefined" || !Sys.hasQuickshellConfig)
                                    label: I18n.t("config.notes.show_image_previews", "Previsualizar imágenes en tarjetas")
                                    comment: I18n.t("config.notes.show_image_previews_comment", "Muestra miniaturas de imágenes en las tarjetas de notas.")
                                    checked: ConfigBackend.showImagePreviews
                                    onToggled: (v) => { ConfigBackend.showImagePreviews = v; }
                                }

                                SchemaSwitchRow {
                                    visible: (typeof Sys === "undefined" || !Sys.hasQuickshellConfig)
                                    label: I18n.t("config.notes.cycle_preview_images", "Alternar imágenes de vista previa")
                                    comment: I18n.t("config.notes.cycle_preview_images_comment", "Cambia suavemente cada 3 segundos entre las imágenes de la nota.")
                                    checked: ConfigBackend.cyclePreviewImages
                                    isDisabled: !ConfigBackend.showImagePreviews
                                    onToggled: (v) => { ConfigBackend.cyclePreviewImages = v; }
                                }

                                SchemaSliderRow {
                                    label: I18n.t("config.notes.cards_per_row", "Tarjetas por fila")
                                    comment: I18n.t("config.notes.cards_per_row_comment", "Número preferido de columnas en la cuadrícula de notas.")
                                    val: ConfigBackend.cardsPerRow
                                    minV: 2
                                    maxV: 5
                                    stepSize: 1
                                    isInt: true
                                    onMoved: (v) => { ConfigBackend.cardsPerRow = Math.round(v); }
                                }

                                SchemaSliderRow {
                                    label: I18n.t("config.notes.editor_zoom", "Zoom del editor")
                                    comment: I18n.t("config.notes.editor_zoom_comment", "Nivel de zoom predeterminado para el editor de notas.")
                                    val: ConfigBackend.editorZoom
                                    minV: 50
                                    maxV: 300
                                    stepSize: 5
                                    isInt: true
                                    suffix: " %"
                                    onMoved: (v) => { ConfigBackend.editorZoom = Math.round(v); }
                                }
                            }
                        }
                    }

                    // ══════════════════════════════════════════════════════
                    // PESTAÑA 1: APARIENCIA (PORTADO DE ThemeManager.qml)
                    // ══════════════════════════════════════════════════════
                    ColumnLayout {
                        id: tabAppearance
                        visible: root.currentTabValue === "appearance"
                        width: parent.width
                        spacing: 14

                        SectionHeader {
                            iconName: "settings.svg"
                            title: I18n.t("config.theme.source_section", "Origen de Colores y Tema")
                        }

                        BentoCard {
                            visible: (typeof Sys !== "undefined" && Sys.hasQuickshellConfig)
                            implicitHeight: syncRow.implicitHeight + 8
                            RowLayout {
                                id: syncRow
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                anchors.topMargin: 2
                                anchors.bottomMargin: 6
                                spacing: 12
                                Image {
                                    width: 22
                                    height: 22
                                    source: Theme.iconsPath + "settings.svg"
                                    sourceSize: Qt.size(22, 22)
                                    layer.enabled: true
                                    layer.effect: MultiEffect { colorization: 1.0; colorizationColor: Theme.accent }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    Text {
                                        text: I18n.t("config.theme.qs_synced_title", "Esquema y Colores sincronizados")
                                        color: Theme.text
                                        font { pixelSize: Theme.fontSizeSubheading; bold: true; family: Theme.fontFamily }
                                    }
                                    Text {
                                        text: I18n.t("config.theme.qs_synced_desc", "El tema de color, la opacidad y las preferencias se sincronizan automáticamente con tu configuración de Quickshell.")
                                        color: Theme.muted
                                        font { pixelSize: Theme.fontSizeBodySecondary; family: Theme.fontFamily }
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }

                        BentoCard {
                            visible: (typeof Sys === "undefined" || !Sys.hasQuickshellConfig)
                            implicitHeight: colThemeSource.implicitHeight + 8
                            ColumnLayout {
                                id: colThemeSource
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                anchors.topMargin: 2
                                anchors.bottomMargin: 6
                                spacing: 14

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        text: I18n.t("config.theme.color_source", "Esquema de color activo")
                                        color: Theme.text
                                        font {
                                            pixelSize: Theme.fontSizeSubheading
                                            family: Theme.fontFamily
                                        }
                                    }

                                    SegmentedPicker {
                                        options: [
                                            { value: "pywal",  label: I18n.t("config.theme.pywal", "Pywal (Fondo)") },
                                            { value: "qt",     label: I18n.t("config.theme.qt", "Qt (Sistema)") },
                                            { value: "custom", label: I18n.t("config.theme.custom", "Personalizado") }
                                        ]
                                        currentValue: (ConfigBackend.themeMode === "system") ? "qt" : ConfigBackend.themeMode
                                        onSelected: (val) => {
                                            if (ConfigBackend.themeMode !== val) {
                                                ConfigBackend.themeMode = val;
                                            }
                                            if (val === "qt" && typeof Sys !== "undefined") {
                                                Sys.refreshQtColors();
                                            }
                                        }
                                    }

                                    Text {
                                        text: {
                                            if (ConfigBackend.themeMode === "pywal") {
                                                return Theme.pywalAvailable
                                                    ? I18n.t("config.theme.pywal_active_hint", "Sincronizando paleta dinámicamente desde ~/.cache/wal/colors.json")
                                                    : I18n.t("config.theme.pywal_missing_hint", "No se detectó ~/.cache/wal/colors.json; usando colores de respaldo de Qt.");
                                            }
                                            if (ConfigBackend.themeMode === "qt" || ConfigBackend.themeMode === "system") {
                                                return I18n.t("config.theme.qt_active_hint", "Extrayendo paleta activa de Kvantum / qt6ct / Qt SystemPalette.");
                                            }
                                            return I18n.t("config.theme.custom_active_hint", "Usando paleta predefinida personalizada de Quickshell.");
                                        }
                                        color: Theme.muted
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        font {
                                            pixelSize: Theme.fontSizeBodySecondary
                                            family: Theme.fontFamily
                                        }
                                    }
                                }

                                SchemaSwitchRow {
                                    label: I18n.t("config.theme.light_mode", "Modo claro")
                                    comment: I18n.t("config.theme.light_mode_comment", "Alterna entre variante oscura y clara para los temas predefinidos.")
                                    checked: ConfigBackend.lightMode
                                    isDisabled: ConfigBackend.themeMode !== "custom"
                                    onToggled: (v) => {
                                        if (ConfigBackend.themeMode !== "custom") ConfigBackend.themeMode = "custom";
                                        ConfigBackend.lightMode = v;
                                    }
                                }

                                // Cuadrícula de los 14 temas predefinidos de ThemeManager.qml
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Text {
                                        text: I18n.t("config.theme.predefined_title", "Temas predefinidos")
                                        color: Theme.text
                                        font {
                                            pixelSize: Theme.fontSizeSubheading
                                            family: Theme.fontFamily
                                        }
                                    }

                                    Flow {
                                        id: themesFlow
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 4
                                        Layout.rightMargin: 4
                                        spacing: 12

                                        Repeater {
                                            model: Theme.predefinedThemes

                                            delegate: Rectangle {
                                                id: themeCircle
                                                required property var modelData
                                                readonly property bool isCustomActive: ConfigBackend.themeMode === "custom"
                                                readonly property bool isSelected: isCustomActive && ConfigBackend.customThemeName === modelData.id

                                                width: 44
                                                height: 44
                                                radius: 8
                                                color: isSelected
                                                    ? Theme.accent
                                                    : (hovCard.hovered ? root._hsva(Theme.text, 0, 0.20) : root._hsva(Theme.text, 0, 0.08))
                                                border.color: isSelected
                                                    ? Theme.accent
                                                    : (hovCard.hovered ? root._hsva(Theme.text, 0, 0.40) : root._hsva(Theme.text, 0, 0.15))
                                                border.width: isSelected ? 3 : 1
                                                scale: isSelected ? 1.08 : (maCard.pressed ? 0.92 : 1.0)
                                                opacity: isCustomActive ? 1.0 : 0.65

                                                HoverHandler { id: hovCard }

                                                Rectangle {
                                                    anchors.fill: parent
                                                    anchors.margins: themeCircle.isSelected ? 4 : 2
                                                    radius: themeCircle.isSelected ? 5 : 6
                                                    color: {
                                                        var data = Theme.getPredefinedThemeColors(themeCircle.modelData.id, ConfigBackend.lightMode);
                                                        return data.colors.color1;
                                                    }
                                                }

                                                MouseArea {
                                                    id: maCard
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (ConfigBackend.themeMode !== "custom") {
                                                            ConfigBackend.themeMode = "custom";
                                                        }
                                                        if (ConfigBackend.customThemeName !== themeCircle.modelData.id) {
                                                            ConfigBackend.customThemeName = themeCircle.modelData.id;
                                                        }
                                                    }
                                                }

                                                Behavior on color {
                                                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                                    ColorAnimation { duration: 120 }
                                                }
                                                Behavior on border.color {
                                                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                                    ColorAnimation { duration: 120 }
                                                }
                                                Behavior on scale {
                                                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                                    NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                                                }
                                                Behavior on opacity {
                                                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                                    NumberAnimation { duration: 150 }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        SectionHeader {
                            iconName: "activity.svg"
                            title: I18n.t("config.theme.interface_section", "Interfaz, Escala y Efectos")
                        }

                        BentoCard {
                            implicitHeight: colAppearanceOpts.implicitHeight + 8
                            ColumnLayout {
                                id: colAppearanceOpts
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                anchors.topMargin: 2
                                anchors.bottomMargin: 6
                                spacing: 12

                                SchemaSliderRow {
                                    visible: (typeof Sys === "undefined" || !Sys.hasQuickshellConfig)
                                    label: I18n.t("config.general.panel_opacity", "Opacidad del fondo")
                                    comment: I18n.t("config.general.panel_opacity_comment", "Nivel de opacidad de la ventana principal de Notas.")
                                    val: ConfigBackend.panelOpacity
                                    minV: 20
                                    maxV: 100
                                    stepSize: 1
                                    isInt: true
                                    suffix: " %"
                                    onMoved: (v) => { ConfigBackend.panelOpacity = Math.round(v); }
                                }

                                SchemaSliderRow {
                                    label: I18n.t("config.font.scale", "Escala tipográfica de interfaz")
                                    comment: I18n.t("config.font.scale_comment", "Ajusta el tamaño global de textos y controles.")
                                    val: Math.round(ConfigBackend.fontSizeScale * 100)
                                    minV: 85
                                    maxV: 135
                                    stepSize: 5
                                    isInt: true
                                    suffix: " %"
                                    onMoved: (v) => { ConfigBackend.fontSizeScale = Math.round(v) / 100.0; }
                                }

                                SchemaSwitchRow {
                                    label: I18n.t("config.hyprland.animations", "Animaciones fluidas")
                                    comment: I18n.t("config.hyprland.animations_comment", "Habilita transiciones elásticas y animaciones de interfaz.")
                                    checked: ConfigBackend.animationsEnabled
                                    onToggled: (v) => { ConfigBackend.animationsEnabled = v; }
                                }

                                SchemaSwitchRow {
                                    label: I18n.t("config.hyprland.blur", "Efectos de desenfoque")
                                    comment: I18n.t("config.hyprland.blur_comment", "Habilita desenfoque y sombras suaves cuando el sistema lo soporta.")
                                    checked: ConfigBackend.blurEnabled
                                    onToggled: (v) => { ConfigBackend.blurEnabled = v; }
                                }

                                SchemaSwitchRow {
                                    label: I18n.t("config.general.hide_scrollbars", "Ocultar barras de desplazamiento")
                                    comment: I18n.t("config.general.hide_scrollbars_comment", "Mantiene el desplazamiento con rueda o gestos ocultando las barras visuales.")
                                    checked: ConfigBackend.hideScrollbars
                                    onToggled: (v) => { ConfigBackend.hideScrollbars = v; }
                                }
                            }
                        }
                    }

                    // ══════════════════════════════════════════════════════
                    // PESTAÑA 2: IDIOMA Y CORRECCIÓN (PORTADO DE LanguageManager.qml)
                    // ══════════════════════════════════════════════════════
                    ColumnLayout {
                        id: tabLanguage
                        visible: root.currentTabValue === "language"
                        width: parent.width
                        spacing: 14

                        SectionHeader {
                            iconName: "language.svg"
                            title: I18n.t("config.language.ui_title", "Idioma de la Interfaz")
                        }

                        BentoCard {
                            implicitHeight: colUiLang.implicitHeight + 8
                            ColumnLayout {
                                id: colUiLang
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                anchors.topMargin: 2
                                anchors.bottomMargin: 6
                                spacing: 10

                                Text {
                                    text: I18n.t("config.language.ui_subtitle", "Selecciona el idioma de menús, etiquetas y controles de Notas.")
                                    color: Theme.muted
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    font {
                                        pixelSize: Theme.fontSizeBodySecondary
                                        family: Theme.fontFamily
                                    }
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    // Opción Automático
                                    Rectangle {
                                        readonly property bool isSel: !ConfigBackend.language || ConfigBackend.language === "auto"
                                        implicitWidth: autoLangLbl.implicitWidth + 24
                                        implicitHeight: 32
                                        radius: 8
                                        color: isSel
                                            ? root._hsva(Theme.accent, 0, 0.22)
                                            : (autoLangHov.hovered ? root._hsva(Theme.text, 0, 0.10) : root._hsva(Theme.text, 0, 0.04))
                                        border.color: isSel
                                            ? root._hsva(Theme.accent, 0, 0.45)
                                            : root._hsva(Theme.text, 0, 0.10)
                                        border.width: 1

                                        HoverHandler { id: autoLangHov }

                                        Text {
                                            id: autoLangLbl
                                            anchors.centerIn: parent
                                            text: I18n.t("config.language.auto_system", "Automático (Sistema)")
                                            color: parent.isSel ? Theme.accent : Theme.text
                                            font {
                                                pixelSize: Theme.fontSizeBody
                                                bold: parent.isSel
                                                family: Theme.fontFamily
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: I18n.setLanguage("auto")
                                        }
                                    }

                                    Repeater {
                                        model: I18n.availableLanguages
                                        delegate: Rectangle {
                                            required property var modelData
                                            readonly property bool isSel: ConfigBackend.language === modelData.code
                                            implicitWidth: uiLangPillTxt.implicitWidth + 24
                                            implicitHeight: 32
                                            radius: 8
                                            color: isSel
                                                ? root._hsva(Theme.accent, 0, 0.22)
                                                : (uiLangPillHov.hovered ? root._hsva(Theme.text, 0, 0.10) : root._hsva(Theme.text, 0, 0.04))
                                            border.color: isSel
                                                ? root._hsva(Theme.accent, 0, 0.45)
                                                : root._hsva(Theme.text, 0, 0.10)
                                            border.width: 1

                                            HoverHandler { id: uiLangPillHov }

                                            Text {
                                                id: uiLangPillTxt
                                                anchors.centerIn: parent
                                                text: modelData.name || modelData.code
                                                color: parent.isSel ? Theme.accent : Theme.text
                                                font {
                                                    pixelSize: Theme.fontSizeBody
                                                    bold: parent.isSel
                                                    family: Theme.fontFamily
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: I18n.setLanguage(modelData.code)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        SectionHeader {
                            iconName: "spellcheck.svg"
                            title: I18n.t("config.language.spell_title", "Corrector Ortográfico")
                        }

                        BentoCard {
                            implicitHeight: colSpell.implicitHeight + 8
                            ColumnLayout {
                                id: colSpell
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                anchors.topMargin: 2
                                anchors.bottomMargin: 6
                                spacing: 12

                                SchemaSwitchRow {
                                    label: I18n.t("config.language.spell_enabled", "Activar corrector ortográfico")
                                    comment: I18n.t("config.language.spell_enabled_desc", "Habilita la revisión ortográfica con subrayado ondulado y sugerencias al hacer clic derecho.")
                                    checked: SpellConfig.enabled
                                    onToggled: (v) => { SpellConfig.enabled = v; }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    opacity: SpellConfig.enabled ? 1.0 : 0.45

                                    Text {
                                        text: I18n.t("config.notes.spellcheck_mode", "Modo de verificación en el editor")
                                        color: Theme.text
                                        font {
                                            pixelSize: Theme.fontSizeSubheading
                                            family: Theme.fontFamily
                                        }
                                    }

                                    SegmentedPicker {
                                        active: SpellConfig.enabled
                                        options: [
                                            { value: "off",    label: I18n.t("config.notes.spellcheck_off", "Desactivado") },
                                            { value: "manual", label: I18n.t("config.notes.spellcheck_manual", "Manual (F7 / Botón)") },
                                            { value: "auto",   label: I18n.t("config.notes.spellcheck_auto", "Automático en tiempo real") }
                                        ]
                                        currentValue: NotesConfig.spellcheckMode
                                        onSelected: (val) => { NotesConfig.spellcheckMode = val; }
                                    }
                                }

                                SchemaSwitchRow {
                                    label: I18n.t("config.spellcheck.ignore_uppercase", "Ignorar MAYÚSCULAS")
                                    comment: I18n.t("config.spellcheck.ignore_uppercase_comment", "No marcar siglas o palabras escritas completamente en mayúsculas.")
                                    checked: SpellConfig.ignoreUppercase
                                    isDisabled: !SpellConfig.enabled
                                    onToggled: (v) => { SpellConfig.ignoreUppercase = v; }
                                }

                                SchemaSwitchRow {
                                    label: I18n.t("config.spellcheck.ignore_digits", "Ignorar palabras con números")
                                    comment: I18n.t("config.spellcheck.ignore_digits_comment", "No marcar códigos alfanuméricos que contengan dígitos (ej. v2, h1, utf8).")
                                    checked: SpellConfig.ignoreWithDigits
                                    isDisabled: !SpellConfig.enabled
                                    onToggled: (v) => { SpellConfig.ignoreWithDigits = v; }
                                }

                                // Idiomas activos simultáneamente (Multi-idioma automático — copiado de LanguageManager.qml)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        text: I18n.t("config.language.spell_active_title", "Idiomas activos (Detección simultánea)").toUpperCase()
                                        color: Theme.muted
                                        font {
                                            pixelSize: Theme.fontSizeSmall
                                            bold: true
                                            letterSpacing: 1.2
                                            family: Theme.fontFamily
                                        }
                                    }

                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Repeater {
                                            model: (typeof SpellConfig !== "undefined" && SpellConfig.effectiveLanguages) ? SpellConfig.effectiveLanguages : ["es_AR"]
                                            delegate: Rectangle {
                                                required property string modelData
                                                required property int index
                                                implicitWidth: pillActiveTxt.implicitWidth + 20
                                                implicitHeight: 26
                                                radius: 13
                                                color: pillHov.hovered
                                                    ? root._hsva(Theme.accent, 0, 0.28)
                                                    : root._hsva(Theme.accent, 0, 0.18)
                                                border.color: root._hsva(Theme.accent, 0, 0.40)
                                                border.width: 1

                                                HoverHandler { id: pillHov }

                                                Text {
                                                    id: pillActiveTxt
                                                    anchors.centerIn: parent
                                                    text: (index === 0 ? "★ " : "✓ ") + modelData + (index === 0 ? " (" + I18n.t("config.language.spell_primary", "Principal") + ")" : "")
                                                    color: Theme.accent
                                                    font {
                                                        pixelSize: Theme.fontSizeBodySecondary
                                                        bold: true
                                                        family: Theme.fontFamily
                                                    }
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: SpellConfig.setPrimaryLanguage(modelData)
                                                }
                                            }
                                        }
                                    }
                                }

                                // Buscador de diccionarios + botón Importar archivo
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Layout.topMargin: 4

                                    Rectangle {
                                        id: dictSearchBox
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 36
                                        radius: 8
                                        color: root._hsva(Theme.surface, 0.04, 0.35)
                                        border.color: dictSearchInput.activeFocus
                                            ? root._hsva(Theme.accent, 0, 0.65)
                                            : root._hsva(Theme.text, 0, 0.12)
                                        border.width: 1

                                        Behavior on border.color {
                                            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                            ColorAnimation { duration: 150 }
                                        }

                                        Image {
                                            id: dictSearchIcon
                                            width: 14
                                            height: 14
                                            anchors.left: parent.left
                                            anchors.leftMargin: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            source: Theme.iconsPath + "search.svg"
                                            sourceSize: Qt.size(14, 14)
                                            opacity: 0.6
                                            layer.enabled: !GamemodeService.gamemodeActive
                                            layer.effect: MultiEffect {
                                                colorization: 1.0
                                                colorizationColor: Theme.muted
                                            }
                                        }

                                        TextInput {
                                            id: dictSearchInput
                                            anchors {
                                                left: dictSearchIcon.right
                                                leftMargin: 8
                                                right: dictClearBtn.visible ? dictClearBtn.left : parent.right
                                                rightMargin: dictClearBtn.visible ? 6 : 12
                                                top: parent.top
                                                bottom: parent.bottom
                                            }
                                            verticalAlignment: TextInput.AlignVCenter
                                            color: Theme.text
                                            font {
                                                family: Theme.fontFamily
                                                pixelSize: Theme.fontSizeSubheading
                                            }
                                            clip: true
                                            selectByMouse: true
                                            CustomTextCursor {}
                                            onTextChanged: root.spellDictSearchText = text

                                            MouseArea {
                                                anchors.fill: parent
                                                acceptedButtons: Qt.RightButton
                                                onClicked: (mouse) => {
                                                    if (mouse.button === Qt.RightButton) {
                                                        dictSearchInput.forceActiveFocus();
                                                        sharedContextMenu.open(dictSearchInput);
                                                    }
                                                }
                                            }
                                        }

                                        Text {
                                            text: I18n.t("config.language.spell_search_placeholder", "Buscar diccionario o código (ej. es_AR, en_US)...")
                                            color: Theme.muted
                                            font {
                                                family: Theme.fontFamily
                                                pixelSize: Theme.fontSizeSubheading
                                                italic: true
                                            }
                                            anchors.fill: dictSearchInput
                                            verticalAlignment: Text.AlignVCenter
                                            visible: dictSearchInput.text === "" && !dictSearchInput.activeFocus
                                            enabled: false
                                        }

                                        Rectangle {
                                            id: dictClearBtn
                                            width: 20
                                            height: 20
                                            radius: 10
                                            anchors.right: parent.right
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: dictSearchInput.text !== ""
                                            color: dictClearMa.containsMouse
                                                ? root._hsva(Theme.text, 0, 0.18)
                                                : root._hsva(Theme.text, 0, 0.08)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "✕"
                                                color: Theme.muted
                                                font {
                                                    pixelSize: Theme.fontSizeSmall
                                                    bold: true
                                                    family: Theme.fontFamily
                                                }
                                            }

                                            MouseArea {
                                                id: dictClearMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    dictSearchInput.text = "";
                                                    dictSearchInput.forceActiveFocus();
                                                }
                                            }
                                        }
                                    }

                                    // Botón Importar (.dic, .aff, .oxt, .zip)
                                    Rectangle {
                                        id: btnImportDict
                                        implicitWidth: btnImportRow.implicitWidth + 24
                                        implicitHeight: 36
                                        radius: 8
                                        color: maImport.pressed
                                            ? root._hsva(Theme.accent, 0.18, 0.65)
                                            : (hImport.hovered
                                                ? root._hsva(Theme.accent, 0, 0.42)
                                                : root._hsva(Theme.accent, 0, 0.28))
                                        scale: maImport.pressed ? 0.96 : 1.0

                                        Behavior on color {
                                            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                            ColorAnimation { duration: 80 }
                                        }
                                        Behavior on scale {
                                            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                            NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
                                        }

                                        HoverHandler { id: hImport }

                                        RowLayout {
                                            id: btnImportRow
                                            anchors.centerIn: parent
                                            spacing: 6

                                            Image {
                                                width: 14
                                                height: 14
                                                source: Theme.iconsPath + "folder.svg"
                                                sourceSize: Qt.size(14, 14)
                                                layer.enabled: !GamemodeService.gamemodeActive
                                                layer.effect: MultiEffect {
                                                    colorization: 1.0
                                                    colorizationColor: Theme.accent
                                                }
                                            }

                                            Text {
                                                text: I18n.t("config.language.spell_import_btn", "Importar archivo")
                                                color: Theme.accent
                                                font {
                                                    pixelSize: Theme.fontSizeBody
                                                    bold: true
                                                    family: Theme.fontFamily
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: maImport
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (!dictPickerProc.running) {
                                                    dictPickerProc.running = true;
                                                }
                                            }
                                        }
                                    }
                                }

                                // Mensaje de estado (instalado / quitado / error)
                                Rectangle {
                                    visible: root.statusMessage !== ""
                                    Layout.fillWidth: true
                                    implicitHeight: 34
                                    radius: 8
                                    color: root.statusIsError
                                        ? root._hsva(Theme.danger, 0, 0.16)
                                        : root._hsva(Theme.success, 0, 0.16)
                                    border.color: root.statusIsError
                                        ? root._hsva(Theme.danger, 0, 0.40)
                                        : root._hsva(Theme.success, 0, 0.40)
                                    border.width: 1

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 12
                                        anchors.right: parent.right
                                        anchors.rightMargin: 12
                                        text: root.statusMessage
                                        color: root.statusIsError ? Theme.danger : Theme.success
                                        elide: Text.ElideRight
                                        font {
                                            pixelSize: Theme.fontSizeBody
                                            bold: true
                                            family: Theme.fontFamily
                                        }
                                    }
                                }

                                Text {
                                    text: {
                                        var q = root.spellDictSearchText.trim();
                                        if (q !== "") {
                                            return I18n.t("config.language.spell_results", "Resultados de búsqueda:") + " (" + dictColumnContainer.filteredDicts.length + ")";
                                        }
                                        return I18n.t("config.language.spell_recommended_hint", "Idiomas instalados y recomendados (escribe en el buscador para ver más de 30 idiomas)");
                                    }
                                    color: Theme.muted
                                    Layout.fillWidth: true
                                    font {
                                        pixelSize: Theme.fontSizeBodySecondary
                                        family: Theme.fontFamily
                                        italic: (root.spellDictSearchText.trim() === "")
                                    }
                                }

                                // Lista de Diccionarios (copiada de LanguageManager.qml)
                                ColumnLayout {
                                    id: dictColumnContainer
                                    Layout.fillWidth: true
                                    spacing: 6

                                    readonly property var filteredDicts: {
                                        var list = (typeof SpellService !== "undefined" && SpellService.installedDicts) ? SpellService.installedDicts : [];
                                        var q = root.spellDictSearchText.trim().toLowerCase();
                                        if (q !== "") {
                                            return list.filter(function(d) {
                                                var n = (d.name || "").toLowerCase();
                                                var nat = (d.native || "").toLowerCase();
                                                var c = (d.code || "").toLowerCase();
                                                return n.indexOf(q) !== -1 || nat.indexOf(q) !== -1 || c.indexOf(q) !== -1;
                                            });
                                        }

                                        var sysCode = (typeof SpellConfig !== "undefined" && SpellConfig.systemLocale) ? SpellConfig.systemLocale : "es_AR";
                                        var sysBase = sysCode.split("_")[0].toLowerCase();
                                        var baseRec = ["es_AR", "es_ES", "en_US", "en_GB", "pt_BR", "fr_FR", "de_DE", "it_IT"];

                                        var result = [];
                                        var seen = ({});

                                        for (var i = 0; i < list.length; i++) {
                                            if (list[i].installed) {
                                                result.push(list[i]);
                                                seen[list[i].code] = true;
                                            }
                                        }

                                        var added = 0;
                                        for (var j = 0; j < list.length; j++) {
                                            var item = list[j];
                                            if (seen[item.code]) continue;
                                            var code = item.code;
                                            var isRec = baseRec.indexOf(code) !== -1 || code.toLowerCase().startsWith(sysBase);
                                            if (isRec && added < 4) {
                                                result.push(item);
                                                seen[code] = true;
                                                added++;
                                            }
                                        }

                                        return result;
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 96
                                        radius: 10
                                        visible: dictColumnContainer.filteredDicts.length === 0
                                        color: root._hsva(Theme.surface, 0.02, 0.35)
                                        border.color: root._hsva(Theme.text, 0, 0.08)
                                        border.width: 1

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 4

                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: I18n.t("config.language.spell_no_match", "No se encontraron diccionarios")
                                                color: Theme.muted
                                                font {
                                                    pixelSize: Theme.fontSizeBody
                                                    bold: true
                                                    family: Theme.fontFamily
                                                }
                                            }

                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: I18n.t("config.language.spell_no_match_hint", "Puedes importar manualmente archivos .dic / .aff o .oxt")
                                                color: Theme.muted
                                                opacity: 0.75
                                                font {
                                                    pixelSize: Theme.fontSizeSmall
                                                    family: Theme.fontFamily
                                                }
                                            }
                                        }
                                    }

                                    Repeater {
                                        id: dictRepeater
                                        model: dictColumnContainer.filteredDicts
                                        delegate: Rectangle {
                                            id: dictRow
                                            required property var modelData
                                            Layout.fillWidth: true
                                            implicitHeight: 52
                                            radius: 10
                                            color: dictRowHov.hovered
                                                ? root._hsva(Theme.text, 0, 0.05)
                                                : "transparent"
                                            border.color: dictRowHov.hovered
                                                ? root._hsva(Theme.accent, 0, 0.25)
                                                : "transparent"
                                            border.width: 1

                                            Behavior on color {
                                                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                                ColorAnimation { duration: 80 }
                                            }
                                            Behavior on border.color {
                                                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                                ColorAnimation { duration: 80 }
                                            }

                                            HoverHandler { id: dictRowHov }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 16
                                                anchors.rightMargin: 16
                                                spacing: 12

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                                                    spacing: 2

                                                    Text {
                                                        text: dictRow.modelData.name || dictRow.modelData.code
                                                        color: Theme.text
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                        font {
                                                            pixelSize: Theme.fontSizeSubheading
                                                            bold: true
                                                            family: Theme.fontFamily
                                                        }
                                                    }

                                                    Text {
                                                        text: dictRow.modelData.code + (dictRow.modelData.source === "system" ? " · " + I18n.t("config.language.spell_system", "Sistema") : "")
                                                        color: Theme.muted
                                                        font {
                                                            pixelSize: Theme.fontSizeBodySecondary
                                                            family: Theme.fontFamily
                                                        }
                                                    }
                                                }

                                                RowLayout {
                                                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                                    spacing: 8

                                                    // Badge "Instalado" o "Sistema"
                                                    Rectangle {
                                                        visible: Boolean(dictRow.modelData.installed)
                                                        implicitWidth: pillInstTxt.implicitWidth + 20
                                                        implicitHeight: 32
                                                        radius: 8
                                                        color: root._hsva(Theme.success, 0, 0.16)
                                                        border.color: root._hsva(Theme.success, 0, 0.40)
                                                        border.width: 1

                                                        Text {
                                                            id: pillInstTxt
                                                            anchors.centerIn: parent
                                                            text: dictRow.modelData.source === "system"
                                                                ? "✓ " + I18n.t("config.language.spell_system", "Sistema")
                                                                : "✓ " + I18n.t("config.language.spell_installed", "Instalado")
                                                            color: Theme.success
                                                            font {
                                                                pixelSize: Theme.fontSizeBodySecondary
                                                                bold: true
                                                                family: Theme.fontFamily
                                                            }
                                                        }
                                                    }

                                                    // Toggle Activo / Pausado
                                                    Rectangle {
                                                        id: btnToggleActive
                                                        visible: Boolean(dictRow.modelData.installed)
                                                        readonly property bool isLangActive: SpellConfig.isLanguageEnabled(dictRow.modelData.code)
                                                        implicitWidth: lblToggleTxt.implicitWidth + 24
                                                        implicitHeight: 32
                                                        radius: 8
                                                        color: maToggle.pressed
                                                            ? (isLangActive ? root._hsva(Theme.accent, 0.18, 0.65) : root._hsva(Theme.text, 0, 0.16))
                                                            : (hToggle.hovered
                                                                ? (isLangActive ? root._hsva(Theme.accent, 0, 0.42) : root._hsva(Theme.text, 0, 0.10))
                                                                : (isLangActive ? root._hsva(Theme.accent, 0, 0.28) : root._hsva(Theme.text, 0, 0.05)))
                                                        scale: maToggle.pressed ? 0.96 : 1.0

                                                        Behavior on color {
                                                            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                                            ColorAnimation { duration: 80 }
                                                        }
                                                        Behavior on scale {
                                                            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                                            NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
                                                        }

                                                        HoverHandler { id: hToggle }

                                                        Text {
                                                            id: lblToggleTxt
                                                            anchors.centerIn: parent
                                                            text: btnToggleActive.isLangActive
                                                                ? I18n.t("config.language.spell_active", "Activo")
                                                                : I18n.t("config.language.spell_paused", "Pausado")
                                                            color: btnToggleActive.isLangActive ? Theme.accent : Theme.muted
                                                            font {
                                                                pixelSize: Theme.fontSizeBody
                                                                bold: true
                                                                family: Theme.fontFamily
                                                            }
                                                        }

                                                        MouseArea {
                                                            id: maToggle
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: SpellConfig.toggleLanguage(dictRow.modelData.code)
                                                        }
                                                    }

                                                    // Botón Quitar (usa spellRemoveProc separado — nunca descarga!)
                                                    Rectangle {
                                                        id: btnRemove
                                                        visible: Boolean(dictRow.modelData.installed) && dictRow.modelData.source !== "system"
                                                        implicitWidth: lblRemTxt.implicitWidth + 28
                                                        implicitHeight: 32
                                                        radius: 8
                                                        color: maRem.pressed
                                                            ? root._hsva(Theme.color3, 0.18, 0.65)
                                                            : (hRem.hovered
                                                                ? root._hsva(Theme.color3, 0, 0.42)
                                                                : root._hsva(Theme.color3, 0, 0.28))
                                                        scale: maRem.pressed ? 0.96 : 1.0

                                                        Behavior on color {
                                                            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                                            ColorAnimation { duration: 80 }
                                                        }
                                                        Behavior on scale {
                                                            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                                            NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
                                                        }

                                                        HoverHandler { id: hRem }

                                                        Text {
                                                            id: lblRemTxt
                                                            anchors.centerIn: parent
                                                            text: I18n.t("config.language.spell_remove", "Quitar")
                                                            color: Theme.color3
                                                            font {
                                                                pixelSize: Theme.fontSizeBody
                                                                bold: true
                                                                family: Theme.fontFamily
                                                            }
                                                        }

                                                        MouseArea {
                                                            id: maRem
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (!spellRemoveProc.running) {
                                                                    root.statusIsError = false;
                                                                    spellRemoveProc.command = [root.notasBin, "spell", "remove", dictRow.modelData.code];
                                                                    spellRemoveProc.running = true;
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // Barra de progreso animada durante la instalación
                                                    Rectangle {
                                                        id: installProgressBar
                                                        visible: !dictRow.modelData.installed && (root.spellInstallingCode === dictRow.modelData.code)
                                                        width: 132
                                                        height: 32
                                                        radius: 8
                                                        clip: true
                                                        color: root._hsva(Theme.text, 0, 0.08)
                                                        border.color: root._hsva(Theme.accent, 0, 0.40)
                                                        border.width: 1

                                                        Rectangle {
                                                            id: progressFill
                                                            anchors.left: parent.left
                                                            anchors.top: parent.top
                                                            anchors.bottom: parent.bottom
                                                            width: Math.max(8, Math.round(parent.width * (Math.min(100, Math.max(0, root.spellInstallProgress)) / 100.0)))
                                                            radius: 8

                                                            gradient: Gradient {
                                                                orientation: Gradient.Horizontal
                                                                GradientStop { position: 0.0; color: Theme.accent }
                                                                GradientStop { position: 1.0; color: Theme.success }
                                                            }

                                                            Behavior on width {
                                                                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                                                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                                                            }
                                                        }

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: root.spellInstallProgress + "%" + (root.spellInstallStage === "aff" ? " (reglas)" : " (vocabulario)")
                                                            color: Theme.text
                                                            font {
                                                                pixelSize: Theme.fontSizeSmall
                                                                bold: true
                                                                family: Theme.fontFamily
                                                            }
                                                        }
                                                    }

                                                    // Botón Instalar
                                                    Rectangle {
                                                        id: btnInstall
                                                        visible: !dictRow.modelData.installed && (root.spellInstallingCode !== dictRow.modelData.code)
                                                        implicitWidth: lblInstTxt.implicitWidth + 28
                                                        implicitHeight: 32
                                                        radius: 8
                                                        opacity: (root.spellInstallingCode !== "") ? 0.45 : 1.0
                                                        color: maInst.pressed
                                                            ? root._hsva(Theme.accent, 0.18, 0.65)
                                                            : (hInst.hovered
                                                                ? root._hsva(Theme.accent, 0, 0.42)
                                                                : root._hsva(Theme.accent, 0, 0.28))
                                                        scale: maInst.pressed ? 0.96 : 1.0

                                                        Behavior on color {
                                                            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                                            ColorAnimation { duration: 80 }
                                                        }
                                                        Behavior on scale {
                                                            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                                            NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
                                                        }

                                                        HoverHandler { id: hInst }

                                                        Text {
                                                            id: lblInstTxt
                                                            anchors.centerIn: parent
                                                            text: I18n.t("config.language.spell_install", "Instalar")
                                                            color: Theme.accent
                                                            font {
                                                                pixelSize: Theme.fontSizeBody
                                                                bold: true
                                                                family: Theme.fontFamily
                                                            }
                                                        }

                                                        MouseArea {
                                                            id: maInst
                                                            anchors.fill: parent
                                                            enabled: root.spellInstallingCode === "" && !spellInstallProc.running
                                                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                            onClicked: {
                                                                root.statusIsError = false;
                                                                root.spellInstallingCode = dictRow.modelData.code;
                                                                root.spellInstallProgress = 5;
                                                                root.spellInstallStage = "aff";
                                                                spellInstallProc.command = [root.notasBin, "spell", "install", dictRow.modelData.code];
                                                                spellInstallProc.running = true;
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Diccionario personal del usuario
                        BentoCard {
                            visible: SpellService.personalWords && SpellService.personalWords.length > 0
                            implicitHeight: colPersonalWords.implicitHeight + 8
                            ColumnLayout {
                                id: colPersonalWords
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                anchors.topMargin: 2
                                anchors.bottomMargin: 6
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: I18n.t("config.spellcheck.personal_dict", "Diccionario personal") + " (" + SpellService.personalWords.length + ")"
                                        color: Theme.text
                                        font {
                                            pixelSize: Theme.fontSizeSubheading
                                            bold: true
                                            family: Theme.fontFamily
                                        }
                                    }

                                    Rectangle {
                                        implicitWidth: clearPersonalLbl.implicitWidth + 20
                                        implicitHeight: 28
                                        radius: 7
                                        color: clearPersonalHov.hovered
                                            ? root._hsva(Theme.color3, 0, 0.35)
                                            : root._hsva(Theme.color3, 0, 0.20)
                                        HoverHandler { id: clearPersonalHov }
                                        Text {
                                            id: clearPersonalLbl
                                            anchors.centerIn: parent
                                            text: I18n.t("config.spellcheck.clear_personal", "Vaciar")
                                            color: Theme.color3
                                            font {
                                                pixelSize: Theme.fontSizeBodySecondary
                                                bold: true
                                                family: Theme.fontFamily
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: SpellService.clearPersonalWords()
                                        }
                                    }
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Repeater {
                                        model: SpellService.personalWords
                                        delegate: Rectangle {
                                            required property string modelData
                                            implicitWidth: chipRow.implicitWidth + 18
                                            implicitHeight: 26
                                            radius: 13
                                            color: root._hsva(Theme.text, 0, 0.06)
                                            border.color: root._hsva(Theme.text, 0, 0.12)
                                            border.width: 1

                                            RowLayout {
                                                id: chipRow
                                                anchors.centerIn: parent
                                                spacing: 6

                                                Text {
                                                    text: modelData
                                                    color: Theme.text
                                                    font {
                                                        pixelSize: Theme.fontSizeBodySecondary
                                                        family: Theme.fontFamily
                                                    }
                                                }

                                                Text {
                                                    text: "✕"
                                                    color: Theme.muted
                                                    font {
                                                        pixelSize: Theme.fontSizeSmall
                                                        bold: true
                                                        family: Theme.fontFamily
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        anchors.margins: -4
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: SpellService.removePersonalWord(modelData)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ══════════════════════════════════════════════════════
                    // PESTAÑA 3: ACERCA DE
                    // ══════════════════════════════════════════════════════
                    ColumnLayout {
                        id: tabAbout
                        visible: root.currentTabValue === "about"
                        width: parent.width
                        spacing: 14

                        BentoCard {
                            implicitHeight: colAppInfo.implicitHeight + 16
                            ColumnLayout {
                                id: colAppInfo
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                anchors.topMargin: 8
                                anchors.bottomMargin: 8
                                spacing: 12

                                Image {
                                    Layout.alignment: Qt.AlignHCenter
                                    width: 76
                                    height: 76
                                    source: Theme.iconsPath + "dev.criperto.Notas.svg"
                                    sourceSize: Qt.size(76, 76)
                                    fillMode: Image.PreserveAspectFit
                                    mipmap: true
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Notas"
                                    font.family: Theme.fontFamilyDisplay
                                    font.pixelSize: 24
                                    font.bold: true
                                    color: Theme.text
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "dev.criperto.Notas • Versión 0.1.0"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.muted
                                }

                                // Badge pills interactivos de Autor y Repositorio
                                RowLayout {
                                    Layout.alignment: Qt.AlignHCenter
                                    spacing: 10

                                    Rectangle {
                                        id: authorBadge
                                        property bool hovered: authorMouse.containsMouse
                                        implicitWidth: authorRow.implicitWidth + 24
                                        implicitHeight: 28
                                        radius: 14
                                        color: hovered ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                                                       : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                                        border.color: hovered ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)
                                                              : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3)
                                        border.width: 1

                                        Behavior on color {
                                            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                            ColorAnimation { duration: 150 }
                                        }

                                        RowLayout {
                                            id: authorRow
                                            anchors.centerIn: parent
                                            spacing: 6

                                            Image {
                                                width: 13
                                                height: 13
                                                source: Theme.iconsPath + "link.svg"
                                                sourceSize: Qt.size(13, 13)
                                                layer.enabled: !GamemodeService.gamemodeActive
                                                layer.effect: MultiEffect {
                                                    colorization: 1.0
                                                    colorizationColor: Theme.accent
                                                }
                                            }

                                            Text {
                                                text: "github.com/Criperto"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.bold: true
                                                color: Theme.accent
                                            }
                                        }

                                        MouseArea {
                                            id: authorMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Qt.openUrlExternally("https://github.com/Criperto")
                                        }
                                    }

                                    Rectangle {
                                        id: repoBadge
                                        property bool hovered: repoMouse.containsMouse
                                        implicitWidth: repoRow.implicitWidth + 24
                                        implicitHeight: 28
                                        radius: 14
                                        color: hovered ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                                                       : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                                        border.color: hovered ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)
                                                              : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3)
                                        border.width: 1

                                        Behavior on color {
                                            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                            ColorAnimation { duration: 150 }
                                        }

                                        RowLayout {
                                            id: repoRow
                                            anchors.centerIn: parent
                                            spacing: 6

                                            Image {
                                                width: 13
                                                height: 13
                                                source: Theme.iconsPath + "code.svg"
                                                sourceSize: Qt.size(13, 13)
                                                layer.enabled: !GamemodeService.gamemodeActive
                                                layer.effect: MultiEffect {
                                                    colorization: 1.0
                                                    colorizationColor: Theme.accent
                                                }
                                            }

                                            Text {
                                                text: "Criperto/notes"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.bold: true
                                                color: Theme.accent
                                            }
                                        }

                                        MouseArea {
                                            id: repoMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Qt.openUrlExternally("https://github.com/Criperto/notes")
                                        }
                                    }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Licencia: GNU General Public License v3.0 or later (GPL-3.0-or-later)"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                    color: Theme.accent
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: Math.min(parent.width - 32, 600)
                                    text: "Aplicación nativa de notas en Markdown con editor tipográfico de bloques, previsualización interactiva en vivo, diagramas Mermaid interactivos, corrección ortográfica multilingüe Hunspell y persistencia atómica en disco."
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeBody
                                    color: Theme.text
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.2
                                }
                            }
                        }

                        BentoCard {
                            implicitHeight: colPaths.implicitHeight + 8
                            ColumnLayout {
                                id: colPaths
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                anchors.topMargin: 2
                                anchors.bottomMargin: 6
                                spacing: 10

                                RowLayout {
                                    spacing: 8
                                    Image {
                                        width: 15
                                        height: 15
                                        source: Theme.iconsPath + "folder.svg"
                                        sourceSize: Qt.size(15, 15)
                                        layer.enabled: !GamemodeService.gamemodeActive
                                        layer.effect: MultiEffect {
                                            colorization: 1.0
                                            colorizationColor: Theme.muted
                                        }
                                    }
                                    Text {
                                        text: "Rutas y Archivos del Sistema"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSubheading
                                        font.bold: true
                                        color: Theme.text
                                    }
                                }

                                GridLayout {
                                    columns: 2
                                    columnSpacing: 16
                                    rowSpacing: 6
                                    Layout.fillWidth: true

                                    Text { text: "Configuración:"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeBodySecondary }
                                    Text { text: "~/.config/notas/config.json"; color: Theme.text; font.family: Theme.fontFamilyMonospace; font.pixelSize: Theme.fontSizeBodySecondary }

                                    Text { text: "Diccionarios Hunspell:"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeBodySecondary }
                                    Text { text: "~/.local/share/notas/dictionaries/"; color: Theme.text; font.family: Theme.fontFamilyMonospace; font.pixelSize: Theme.fontSizeBodySecondary }

                                    Text { text: "Diccionario personal:"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeBodySecondary }
                                    Text { text: "~/.config/notas/personal.dic"; color: Theme.text; font.family: Theme.fontFamilyMonospace; font.pixelSize: Theme.fontSizeBodySecondary }

                                    Text { text: "Socket IPC:"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeBodySecondary }
                                    Text { text: "$XDG_RUNTIME_DIR/notas.sock"; color: Theme.text; font.family: Theme.fontFamilyMonospace; font.pixelSize: Theme.fontSizeBodySecondary }

                                    Text { text: "Perfil GitHub:"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeBodySecondary }
                                    Text {
                                        text: "https://github.com/Criperto"
                                        color: linkAuthorMouse.containsMouse ? Theme.accent : Theme.text
                                        font.family: Theme.fontFamilyMonospace
                                        font.pixelSize: Theme.fontSizeBodySecondary
                                        font.underline: linkAuthorMouse.containsMouse
                                        MouseArea {
                                            id: linkAuthorMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Qt.openUrlExternally("https://github.com/Criperto")
                                        }
                                    }

                                    Text { text: "Repositorio:"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeBodySecondary }
                                    Text {
                                        text: "https://github.com/Criperto/notes"
                                        color: linkRepoMouse.containsMouse ? Theme.accent : Theme.text
                                        font.family: Theme.fontFamilyMonospace
                                        font.pixelSize: Theme.fontSizeBodySecondary
                                        font.underline: linkRepoMouse.containsMouse
                                        MouseArea {
                                            id: linkRepoMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Qt.openUrlExternally("https://github.com/Criperto/notes")
                                        }
                                    }
                                }
                            }
                        }

                        BentoCard {
                            implicitHeight: colShortcuts.implicitHeight + 8
                            ColumnLayout {
                                id: colShortcuts
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                anchors.topMargin: 2
                                anchors.bottomMargin: 6
                                spacing: 10

                                RowLayout {
                                    spacing: 8
                                    Image {
                                        width: 15
                                        height: 15
                                        source: Theme.iconsPath + "code.svg"
                                        sourceSize: Qt.size(15, 15)
                                        layer.enabled: !GamemodeService.gamemodeActive
                                        layer.effect: MultiEffect {
                                            colorization: 1.0
                                            colorizationColor: Theme.muted
                                        }
                                    }
                                    Text {
                                        text: "Atajos de Teclado Principales"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSubheading
                                        font.bold: true
                                        color: Theme.text
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 24

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 4
                                        Text { text: "Ctrl+N : Nueva nota"; font.family: Theme.fontFamilyMonospace; font.pixelSize: Theme.fontSizeBodySecondary; color: Theme.text }
                                        Text { text: "Ctrl+F : Buscar notas / en nota"; font.family: Theme.fontFamilyMonospace; font.pixelSize: Theme.fontSizeBodySecondary; color: Theme.text }
                                        Text { text: "Ctrl+, : Configuración"; font.family: Theme.fontFamilyMonospace; font.pixelSize: Theme.fontSizeBodySecondary; color: Theme.text }
                                        Text { text: "Ctrl+Q : Salir"; font.family: Theme.fontFamilyMonospace; font.pixelSize: Theme.fontSizeBodySecondary; color: Theme.text }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 4
                                        Text { text: "Ctrl+B / Ctrl+I : Negrita / Cursiva"; font.family: Theme.fontFamilyMonospace; font.pixelSize: Theme.fontSizeBodySecondary; color: Theme.text }
                                        Text { text: "Ctrl+K : Insertar enlace"; font.family: Theme.fontFamilyMonospace; font.pixelSize: Theme.fontSizeBodySecondary; color: Theme.text }
                                        Text { text: "F7 : Alternar corrector"; font.family: Theme.fontFamilyMonospace; font.pixelSize: Theme.fontSizeBodySecondary; color: Theme.text }
                                        Text { text: "Esc : Cerrar nota / diálogo"; font.family: Theme.fontFamilyMonospace; font.pixelSize: Theme.fontSizeBodySecondary; color: Theme.text }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        id: activeTabCol
                        implicitHeight: {
                            if (root.currentTabValue === "editor") return tabEditor.implicitHeight;
                            if (root.currentTabValue === "appearance") return tabAppearance.implicitHeight;
                            if (root.currentTabValue === "language") return tabLanguage.implicitHeight;
                            return tabAbout.implicitHeight;
                        }
                    }
                }
            }
        }
    }

    ContextMenu {
        id: sharedContextMenu
    }
}
