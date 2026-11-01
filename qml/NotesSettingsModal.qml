import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Notas

Item {
    id: root
    visible: opacity > 0
    opacity: 0

    anchors.fill: parent

    signal closed()

    property bool isOpen: false
    property rect originRect: Qt.rect(width / 2, height / 2, 0, 0)
    property int tabIndex: 0
    property string catalogFilter: ""
    property string activeDownloadingLang: ""
    property real downloadProgress: 0.0

    readonly property var tabs: [
        { id: "editor", title: I18n.t("config.tabs.editor", "Editor"), icon: "edit.svg" },
        { id: "appearance", title: I18n.t("config.tabs.appearance", "Apariencia"), icon: "settings.svg" },
        { id: "language", title: I18n.t("config.tabs.language", "Idioma y Corrección"), icon: "spellcheck.svg" },
        { id: "about", title: I18n.t("config.tabs.about", "Acerca de"), icon: "info.svg" }
    ]

    function open(rect) {
        if (rect && typeof rect.x === "number") {
            originRect = rect;
        } else {
            originRect = Qt.rect(width / 2, height / 2, 40, 40);
        }
        isOpen = true;
        opacity = 1.0;
    }

    function close() {
        isOpen = false;
        opacity = 0.0;
        closed();
    }

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.animationsEnabled ? 150 : 0
            easing.type: Easing.OutQuad
        }
    }

    // ── Proceso auxiliar para abrir selector de carpetas vía CLI ─────────
    Process {
        id: dirPickerProc
        command: ["notas", "file-picker", "--directory", "--title", I18n.t("config.notes.select_dir", "Seleccionar carpeta de notas")]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (data) => {
                var p = data.trim();
                if (p !== "") {
                    ConfigBackend.notasDir = p;
                    NotesService.refresh();
                }
            }
        }
    }

    // ── Proceso auxiliar para descargar / instalar diccionarios Hunspell ─
    Process {
        id: spellInstallProc
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (data) => {
                var line = data.trim();
                if (line.startsWith("{") && line.endsWith("}")) {
                    try {
                        var obj = JSON.parse(line);
                        if (typeof obj.percent === "number") {
                            root.downloadProgress = obj.percent / 100.0;
                        }
                        if (obj.status === "done") {
                            root.activeDownloadingLang = "";
                            root.downloadProgress = 0.0;
                            SpellService.refreshDictionaries();
                        }
                    } catch (e) {}
                }
            }
        }
    }

    // ── Lector del catálogo de diccionarios ──────────────────────────────
    property var catalogList: [
        { code: "es_AR", name: "Español (Argentina)" },
        { code: "es_ES", name: "Español (España)" },
        { code: "es_MX", name: "Español (México)" },
        { code: "es_CL", name: "Español (Chile)" },
        { code: "es_CO", name: "Español (Colombia)" },
        { code: "en_US", name: "English (United States)" },
        { code: "en_GB", name: "English (United Kingdom)" },
        { code: "en_CA", name: "English (Canada)" },
        { code: "en_AU", name: "English (Australia)" },
        { code: "pt_BR", name: "Português (Brasil)" },
        { code: "pt_PT", name: "Português (Portugal)" },
        { code: "fr_FR", name: "Français (France)" },
        { code: "de_DE", name: "Deutsch (Deutschland)" },
        { code: "it_IT", name: "Italiano (Italia)" },
        { code: "ca_ES", name: "Català" },
        { code: "gl_ES", name: "Galego" },
        { code: "eu_ES", name: "Euskara" },
        { code: "nl_NL", name: "Nederlands" },
        { code: "pl_PL", name: "Polski" },
        { code: "ru_RU", name: "Русский" },
        { code: "uk_UA", name: "Українська" },
        { code: "sv_SE", name: "Svenska" },
        { code: "da_DK", name: "Dansk" },
        { code: "nb_NO", name: "Norsk Bokmål" },
        { code: "cs_CZ", name: "Čeština" },
        { code: "ro_RO", name: "Română" },
        { code: "tr_TR", name: "Türkçe" },
        { code: "el_GR", name: "Ελληνικά" },
        { code: "eo",    name: "Esperanto" },
        { code: "la",    name: "Latina" }
    ]

    FileView {
        id: catalogFile
        path: (typeof Sys !== "undefined" && Sys.homePath ? Sys.homePath : "") + "/.local/share/notas/catalog.json"
        printErrors: false
        onLoadedChanged: {
            if (loaded && text) {
                try {
                    var parsed = JSON.parse(text);
                    if (parsed && Array.isArray(parsed.languages)) {
                        root.catalogList = parsed.languages;
                    }
                } catch (e) {}
            }
        }
    }

    // ── Fondo atenuado (Backdrop) ─────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    // ── Componentes auxiliares Bento ──────────────────────────────────────
    component BentoCard : Rectangle {
        Layout.fillWidth: true
        radius: 12
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.7)
        border.color: Theme.border
        border.width: 1
    }

    component SettingsCheckbox : Rectangle {
        id: chk
        property bool checked: false
        signal toggled(bool newState)

        width: 20
        height: 20
        radius: 5
        color: checked ? Theme.primary : "transparent"
        border.color: checked ? Theme.primary : Theme.border
        border.width: 1.5

        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }

        Image {
            anchors.centerIn: parent
            width: 14
            height: 14
            source: Theme.iconsPath + "check.svg"
            sourceSize: Qt.size(14, 14)
            visible: chk.checked
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                chk.checked = !chk.checked;
                chk.toggled(chk.checked);
            }
        }
    }

    component SettingsSlider : Item {
        id: sld
        property real from: 0
        property real to: 100
        property real stepSize: 1
        property real value: 50
        signal moved(real val)

        implicitWidth: 160
        implicitHeight: 24

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 6
            radius: 3
            color: Theme.border

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: handle.x + handle.width / 2
                radius: 3
                color: Theme.primary
            }
        }

        Rectangle {
            id: handle
            x: Math.max(0, Math.min(sld.width - width, (sld.to > sld.from) ? ((sld.value - sld.from) / (sld.to - sld.from) * (sld.width - width)) : 0))
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            radius: 8
            color: Theme.primary
            border.color: Theme.surface
            border.width: 2

            MouseArea {
                id: sldMa
                anchors.fill: parent
                anchors.margins: -6
                drag.target: parent
                drag.axis: Drag.XAxis
                drag.minimumX: 0
                drag.maximumX: Math.max(0, sld.width - handle.width)
                cursorShape: Qt.PointingHandCursor

                onPositionChanged: {
                    if (drag.active && sld.width > handle.width) {
                        var frac = handle.x / (sld.width - handle.width);
                        var rawVal = sld.from + frac * (sld.to - sld.from);
                        var stepped = Math.round(rawVal / sld.stepSize) * sld.stepSize;
                        if (stepped !== sld.value) {
                            sld.value = stepped;
                            sld.moved(stepped);
                        }
                    }
                }
            }
        }
    }

    // ── Tarjeta Bento Principal con Morph Animation ──────────────────────
    readonly property real targetWidth: Math.min(root.width - 48, 820)
    readonly property real targetHeight: Math.min(root.height - 48, 620)

    Rectangle {
        id: card
        x: root.isOpen ? Math.round((root.width - targetWidth) / 2) : root.originRect.x
        y: root.isOpen ? Math.round((root.height - targetHeight) / 2) : root.originRect.y
        width: root.isOpen ? targetWidth : root.originRect.width
        height: root.isOpen ? targetHeight : root.originRect.height
        radius: root.isOpen ? 16 : 8

        color: Theme.surface
        border.color: Theme.border
        border.width: 1
        clip: true

        Behavior on x { SpringAnimation { spring: 8.2; damping: 0.88; mass: 0.45 } }
        Behavior on y { SpringAnimation { spring: 8.2; damping: 0.88; mass: 0.45 } }
        Behavior on width { SpringAnimation { spring: 8.2; damping: 0.88; mass: 0.45 } }
        Behavior on height { SpringAnimation { spring: 8.2; damping: 0.88; mass: 0.45 } }
        Behavior on radius { SpringAnimation { spring: 8.2; damping: 0.88; mass: 0.45 } }

        MouseArea {
            anchors.fill: parent
            // Consumir eventos para no cerrar al interactuar dentro del modal
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

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

            // ── Barra de Pestañas con Indicador de Cápsula Deslizante ─────
            Rectangle {
                id: tabsContainer
                Layout.fillWidth: true
                height: 42
                radius: 10
                color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.5)
                border.color: Theme.border
                border.width: 1

                RowLayout {
                    id: tabsRow
                    anchors.fill: parent
                    anchors.margins: 3
                    spacing: 4

                    Repeater {
                        id: tabsRepeater
                        model: root.tabs
                        delegate: Item {
                            id: tabItem
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 8

                                Image {
                                    width: 16
                                    height: 16
                                    source: Theme.iconsPath + modelData.icon
                                    sourceSize: Qt.size(16, 16)
                                }

                                Text {
                                    text: modelData.title
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeBody
                                    font.bold: root.tabIndex === index
                                    color: root.tabIndex === index ? Theme.primary : Theme.text
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.tabIndex = index
                            }
                        }
                    }
                }

                // Cápsula activa deslizante detrás del texto
                Rectangle {
                    id: activeTabPill
                    y: 3
                    height: tabsContainer.height - 6
                    radius: 8
                    color: Theme.surfaceActive
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3)
                    border.width: 1
                    z: -1

                    width: (tabsRepeater.itemAt(root.tabIndex) ? tabsRepeater.itemAt(root.tabIndex).width : 100)
                    x: (tabsRepeater.itemAt(root.tabIndex) ? (tabsRepeater.itemAt(root.tabIndex).x + 3) : 3)

                    Behavior on x { SpringAnimation { spring: 8.5; damping: 0.88; mass: 0.45 } }
                    Behavior on width { SpringAnimation { spring: 8.5; damping: 0.88; mass: 0.45 } }
                }
            }

            // ── Cuerpo de Pestañas con CustomScrollBar ───────────────────
            Flickable {
                id: modalFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width - 12
                contentHeight: stackContent.implicitHeight + 20

                ScrollBar.vertical: CustomScrollBar { id: vbar }

                Item {
                    id: stackContent
                    width: modalFlickable.contentWidth
                    implicitHeight: activeTabCol.implicitHeight

                    // ── PESTAÑA 0: EDITOR ────────────────────────────────
                    ColumnLayout {
                        id: tabEditor
                        visible: root.tabIndex === 0
                        width: parent.width
                        spacing: 12

                        BentoCard {
                            implicitHeight: colDir.implicitHeight + 24
                            ColumnLayout {
                                id: colDir
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 10

                                Text {
                                    text: I18n.t("config.notes.dir", "Carpeta de notas")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                    color: Theme.text
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    SettingsTextField {
                                        id: notesDirInput
                                        Layout.fillWidth: true
                                        text: ConfigBackend.notasDir
                                        placeholder: "/ruta/a/tus/notas"
                                        onAccepted: (newVal) => {
                                            ConfigBackend.notasDir = newVal;
                                            NotesService.refresh();
                                        }
                                    }

                                    Rectangle {
                                        Layout.preferredHeight: 38
                                        Layout.preferredWidth: 110
                                        radius: 8
                                        color: btnBrowseMa.containsMouse ? Theme.surfaceHover : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3)
                                        border.width: 1

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Image {
                                                width: 16; height: 16
                                                source: Theme.iconsPath + "folder.svg"
                                                sourceSize: Qt.size(16, 16)
                                            }
                                            Text {
                                                text: "Examinar..."
                                                color: Theme.primary
                                                font.bold: true
                                                font.pixelSize: Theme.fontSizeSmall
                                            }
                                        }

                                        MouseArea {
                                            id: btnBrowseMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: dirPickerProc.running = true
                                        }
                                    }
                                }
                            }
                        }

                        BentoCard {
                            implicitHeight: colPreview.implicitHeight + 24
                            ColumnLayout {
                                id: colPreview
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 12

                                Text {
                                    text: "Tarjetas y Vista Previa"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                    color: Theme.text
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: I18n.t("config.notes.show_image_previews", "Previsualizar imágenes en tarjetas")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.text
                                    }
                                    SettingsCheckbox {
                                        checked: ConfigBackend.showImagePreviews
                                        onToggled: (st) => ConfigBackend.showImagePreviews = st
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: I18n.t("config.notes.cycle_preview_images", "Alternar imágenes de vista previa")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.text
                                    }
                                    SettingsCheckbox {
                                        checked: ConfigBackend.cyclePreviewImages
                                        onToggled: (st) => ConfigBackend.cyclePreviewImages = st
                                    }
                                }
                            }
                        }

                        BentoCard {
                            implicitHeight: colMetrics.implicitHeight + 24
                            ColumnLayout {
                                id: colMetrics
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 14

                                Text {
                                    text: "Visualización y Editor"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                    color: Theme.text
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: I18n.t("config.notes.editor_zoom", "Zoom del editor") + ": " + ConfigBackend.editorZoom + "%"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.text
                                    }
                                    SettingsSlider {
                                        from: 50
                                        to: 200
                                        stepSize: 10
                                        value: ConfigBackend.editorZoom
                                        onMoved: (v) => ConfigBackend.editorZoom = Math.round(v)
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Tarjetas por fila en cuadrícula: " + ConfigBackend.cardsPerRow
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.text
                                    }
                                    SettingsSlider {
                                        from: 2
                                        to: 5
                                        stepSize: 1
                                        value: ConfigBackend.cardsPerRow
                                        onMoved: (v) => ConfigBackend.cardsPerRow = Math.round(v)
                                    }
                                }
                            }
                        }
                    }

                    // ── PESTAÑA 1: APARIENCIA ────────────────────────────
                    ColumnLayout {
                        id: tabAppearance
                        visible: root.tabIndex === 1
                        width: parent.width
                        spacing: 12

                        BentoCard {
                            implicitHeight: colThemes.implicitHeight + 24
                            ColumnLayout {
                                id: colThemes
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 12

                                Text {
                                    text: I18n.t("config.appearance.theme", "Modo de tema y color")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                    color: Theme.text
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Repeater {
                                        model: [
                                            { id: "system", label: "Sistema", desc: "Paleta Qt del sistema" },
                                            { id: "dark", label: "Oscuro", desc: "Catppuccin Mocha" },
                                            { id: "light", label: "Claro", desc: "Catppuccin Latte" },
                                            { id: "pywal", label: "Pywal", desc: "Colores dinámicos" }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            height: 54
                                            radius: 10
                                            color: ConfigBackend.themeMode === modelData.id ? Theme.surfaceActive : Theme.surfaceHover
                                            border.color: ConfigBackend.themeMode === modelData.id ? Theme.primary : Theme.border
                                            border.width: 1.5

                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: 2
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: modelData.label
                                                    color: ConfigBackend.themeMode === modelData.id ? Theme.primary : Theme.text
                                                    font.bold: true
                                                    font.pixelSize: Theme.fontSizeBody
                                                }
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: modelData.desc
                                                    color: Theme.muted
                                                    font.pixelSize: Theme.fontSizeCaption
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: ConfigBackend.themeMode = modelData.id
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        BentoCard {
                            implicitHeight: colEffects.implicitHeight + 24
                            ColumnLayout {
                                id: colEffects
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 12

                                Text {
                                    text: "Efectos Visuales e Interfaz"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                    color: Theme.text
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Opacidad de la ventana: " + Math.round(ConfigBackend.panelOpacity * 100) + "%"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.text
                                    }
                                    SettingsSlider {
                                        from: 40
                                        to: 100
                                        stepSize: 5
                                        value: Math.round(ConfigBackend.panelOpacity * 100)
                                        onMoved: (v) => ConfigBackend.panelOpacity = v / 100.0
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: I18n.t("config.appearance.blur", "Efecto de desenfoque (Blur)")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.text
                                    }
                                    SettingsCheckbox {
                                        checked: ConfigBackend.blurEnabled
                                        onToggled: (st) => ConfigBackend.blurEnabled = st
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Animaciones fluidas"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.text
                                    }
                                    SettingsCheckbox {
                                        checked: ConfigBackend.animationsEnabled
                                        onToggled: (st) => ConfigBackend.animationsEnabled = st
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: I18n.t("config.appearance.hide_scrollbars", "Ocultar barras de desplazamiento")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.text
                                    }
                                    SettingsCheckbox {
                                        checked: ConfigBackend.hideScrollbars
                                        onToggled: (st) => ConfigBackend.hideScrollbars = st
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Escala global de tipografía: " + Math.round(ConfigBackend.fontSizeScale * 100) + "%"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.text
                                    }
                                    SettingsSlider {
                                        from: 80
                                        to: 140
                                        stepSize: 5
                                        value: Math.round(ConfigBackend.fontSizeScale * 100)
                                        onMoved: (v) => ConfigBackend.fontSizeScale = v / 100.0
                                    }
                                }
                            }
                        }
                    }

                    // ── PESTAÑA 2: IDIOMA Y CORRECCIÓN ───────────────────
                    ColumnLayout {
                        id: tabLanguage
                        visible: root.tabIndex === 2
                        width: parent.width
                        spacing: 12

                        BentoCard {
                            implicitHeight: colLangUi.implicitHeight + 24
                            ColumnLayout {
                                id: colLangUi
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 10

                                Text {
                                    text: I18n.t("config.language.interface", "Idioma de la interfaz")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                    color: Theme.text
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Repeater {
                                        model: [
                                            { code: "es_ar", name: "Español (AR)" },
                                            { code: "es_es", name: "Español (ES)" },
                                            { code: "en", name: "English" },
                                            { code: "de", name: "Deutsch" },
                                            { code: "fr", name: "Français" },
                                            { code: "ja", name: "日本語" }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: 110
                                            height: 34
                                            radius: 8
                                            color: I18n.currentLanguage === modelData.code ? Theme.surfaceActive : Theme.surfaceHover
                                            border.color: I18n.currentLanguage === modelData.code ? Theme.primary : Theme.border
                                            border.width: 1

                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.name
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.bold: I18n.currentLanguage === modelData.code
                                                color: I18n.currentLanguage === modelData.code ? Theme.primary : Theme.text
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    I18n.setLanguage(modelData.code);
                                                    ConfigBackend.language = modelData.code;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        BentoCard {
                            implicitHeight: colSpellCfg.implicitHeight + 24
                            ColumnLayout {
                                id: colSpellCfg
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 12

                                Text {
                                    text: "Corrector Ortográfico Hunspell"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                    color: Theme.text
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Modo de revisión"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.text
                                    }

                                    RowLayout {
                                        spacing: 6
                                        Repeater {
                                            model: [
                                                { id: "auto", label: "Automático" },
                                                { id: "manual", label: "Manual" },
                                                { id: "off", label: "Desactivado" }
                                            ]
                                            delegate: Rectangle {
                                                required property var modelData
                                                width: 86
                                                height: 30
                                                radius: 6
                                                color: ConfigBackend.spellcheckMode === modelData.id ? Theme.surfaceActive : Theme.surfaceHover
                                                border.color: ConfigBackend.spellcheckMode === modelData.id ? Theme.primary : Theme.border
                                                border.width: 1

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData.label
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    font.bold: ConfigBackend.spellcheckMode === modelData.id
                                                    color: ConfigBackend.spellcheckMode === modelData.id ? Theme.primary : Theme.text
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: ConfigBackend.spellcheckMode = modelData.id
                                                }
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Ignorar palabras en MAYÚSCULAS"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.text
                                    }
                                    SettingsCheckbox {
                                        checked: ConfigBackend.ignoreUppercase
                                        onToggled: (st) => ConfigBackend.ignoreUppercase = st
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Ignorar palabras que contienen números"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.text
                                    }
                                    SettingsCheckbox {
                                        checked: ConfigBackend.ignoreWithDigits
                                        onToggled: (st) => ConfigBackend.ignoreWithDigits = st
                                    }
                                }
                            }
                        }

                        // Catálogo de diccionarios Hunspell
                        BentoCard {
                            implicitHeight: colCatalog.implicitHeight + 24
                            ColumnLayout {
                                id: colCatalog
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Diccionarios instalados y catálogo descargable"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: true
                                        color: Theme.text
                                    }

                                    Rectangle {
                                        width: 28; height: 28
                                        radius: 6
                                        color: refreshMa.containsMouse ? Theme.surfaceHover : "transparent"
                                        Image {
                                            anchors.centerIn: parent
                                            width: 16; height: 16
                                            source: Theme.iconsPath + "refresh.svg"
                                            sourceSize: Qt.size(16, 16)
                                        }
                                        MouseArea {
                                            id: refreshMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: SpellService.refreshDictionaries()
                                        }
                                    }
                                }

                                SettingsTextField {
                                    Layout.fillWidth: true
                                    placeholder: "Buscar idioma o código (ej: Español, en_US)..."
                                    onTextChanged: root.catalogFilter = text.toLowerCase().trim()
                                }

                                // Barra de progreso de descarga si está activo
                                Rectangle {
                                    visible: root.activeDownloadingLang !== ""
                                    Layout.fillWidth: true
                                    height: 24
                                    radius: 6
                                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                                    clip: true

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: parent.width * Math.max(0.05, root.downloadProgress)
                                        color: Theme.accent
                                        radius: 6
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Descargando " + root.activeDownloadingLang + "... " + Math.round(root.downloadProgress * 100) + "%"
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeCaption
                                        font.bold: true
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Repeater {
                                        model: {
                                            var list = root.catalogList || [];
                                            var filt = root.catalogFilter;
                                            if (!filt) return list.slice(0, 8); // Top 8 si no hay filtro
                                            return list.filter(function(item) {
                                                return item.name.toLowerCase().indexOf(filt) !== -1 ||
                                                       item.code.toLowerCase().indexOf(filt) !== -1;
                                            });
                                        }
                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            height: 38
                                            radius: 8
                                            color: Theme.surfaceHover

                                            readonly property bool isInstalled: {
                                                var avail = SpellBackend.availableDictionaries || [];
                                                return avail.indexOf(modelData.code) !== -1;
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: 10

                                                Text {
                                                    text: modelData.name
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    font.bold: true
                                                    color: Theme.text
                                                }

                                                Rectangle {
                                                    Layout.preferredHeight: 18
                                                    Layout.preferredWidth: langPillText.implicitWidth + 8
                                                    radius: 4
                                                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                                                    Text {
                                                        id: langPillText
                                                        anchors.centerIn: parent
                                                        text: modelData.code
                                                        color: Theme.primary
                                                        font.family: Theme.fontFamilyMonospace
                                                        font.pixelSize: 10
                                                        font.bold: true
                                                    }
                                                }

                                                Item { Layout.fillWidth: true }

                                                Text {
                                                    text: parent.parent.isInstalled ? "✓ Instalado" : "Disponible"
                                                    color: parent.parent.isInstalled ? Theme.success : Theme.muted
                                                    font.pixelSize: Theme.fontSizeCaption
                                                }

                                                Rectangle {
                                                    Layout.preferredHeight: 26
                                                    Layout.preferredWidth: 72
                                                    radius: 6
                                                    color: parent.parent.isInstalled ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.15) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: parent.parent.parent.isInstalled ? "Eliminar" : "Instalar"
                                                        color: parent.parent.parent.isInstalled ? Theme.danger : Theme.primary
                                                        font.bold: true
                                                        font.pixelSize: Theme.fontSizeCaption
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (parent.parent.isInstalled) {
                                                                spellInstallProc.command = ["notas", "spell", "remove", modelData.code];
                                                                spellInstallProc.running = true;
                                                            } else {
                                                                root.activeDownloadingLang = modelData.code;
                                                                root.downloadProgress = 0.1;
                                                                spellInstallProc.command = ["notas", "spell", "install", modelData.code];
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

                        // Diccionario Personal
                        BentoCard {
                            implicitHeight: colPersonal.implicitHeight + 24
                            ColumnLayout {
                                id: colPersonal
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Diccionario Personal (" + (SpellBackend.personalWords ? SpellBackend.personalWords.length : 0) + " palabras)"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: true
                                        color: Theme.text
                                    }

                                    Rectangle {
                                        visible: SpellBackend.personalWords && SpellBackend.personalWords.length > 0
                                        Layout.preferredHeight: 24
                                        Layout.preferredWidth: 76
                                        radius: 6
                                        color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.15)
                                        Text {
                                            anchors.centerIn: parent
                                            text: "Borrar todo"
                                            color: Theme.danger
                                            font.pixelSize: Theme.fontSizeCaption
                                            font.bold: true
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
                                    spacing: 6
                                    Repeater {
                                        model: SpellBackend.personalWords || []
                                        delegate: Rectangle {
                                            required property string modelData
                                            height: 24
                                            width: wordRow.implicitWidth + 12
                                            radius: 6
                                            color: Theme.surfaceHover
                                            border.color: Theme.border
                                            border.width: 1

                                            RowLayout {
                                                id: wordRow
                                                anchors.centerIn: parent
                                                spacing: 6

                                                Text {
                                                    text: modelData
                                                    color: Theme.text
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fontSizeCaption
                                                }

                                                Text {
                                                    text: "✕"
                                                    color: Theme.muted
                                                    font.pixelSize: 10
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

                    // ── PESTAÑA 3: ACERCA DE ──────────────────────────────
                    ColumnLayout {
                        id: tabAbout
                        visible: root.tabIndex === 3
                        width: parent.width
                        spacing: 12

                        BentoCard {
                            implicitHeight: colAppInfo.implicitHeight + 24
                            ColumnLayout {
                                id: colAppInfo
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 14

                                RowLayout {
                                    spacing: 16
                                    Rectangle {
                                        width: 60; height: 60
                                        radius: 14
                                        color: Theme.surfaceHover
                                        border.color: Theme.border
                                        border.width: 1

                                        Image {
                                            anchors.centerIn: parent
                                            width: 44; height: 44
                                            source: "qrc:/qt/qml/Notas/assets/icons/dev.criperto.Notas.svg"
                                            sourceSize: Qt.size(44, 44)
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: 3
                                        Text {
                                            text: "Notas"
                                            font.family: Theme.fontFamilyDisplay
                                            font.pixelSize: Theme.fontSizeTitleLarge
                                            font.bold: true
                                            color: Theme.text
                                        }
                                        Text {
                                            text: "dev.criperto.Notas • Versión 0.1.0"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.muted
                                        }
                                        Text {
                                            text: "Licencia: GNU General Public License v3.0 or later (GPL-3.0-or-later)"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.bold: true
                                            color: Theme.primary
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "Aplicación nativa de notas en Markdown con editor tipográfico de bloques, previsualización en vivo Typora-style, diagrama Mermaid interactivo, soporte ortográfico multilingüe Hunspell y persistencia segura en disco."
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeBody
                                    color: Theme.text
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        BentoCard {
                            implicitHeight: colPaths.implicitHeight + 24
                            ColumnLayout {
                                id: colPaths
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 8

                                Text {
                                    text: "Rutas y Archivos del Sistema"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                    color: Theme.text
                                }

                                Text {
                                    text: "• Configuración: ~/.config/notas/config.toml\n• Diccionarios: ~/.local/share/notas/dictionaries/\n• Scripts auxiliares: ~/.local/share/notas/scripts/\n• Socket IPC: $XDG_RUNTIME_DIR/notas.sock"
                                    font.family: Theme.fontFamilyMonospace
                                    font.pixelSize: Theme.fontSizeCaption
                                    color: Theme.muted
                                }
                            }
                        }

                        BentoCard {
                            implicitHeight: colShortcuts.implicitHeight + 24
                            ColumnLayout {
                                id: colShortcuts
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 8

                                Text {
                                    text: "Atajos de Teclado Principales"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                    color: Theme.text
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Ctrl+N : Nueva nota\nCtrl+F : Buscar notas / Buscar en texto\nCtrl+, : Configuración\nCtrl+Q : Salir"
                                        font.family: Theme.fontFamilyMonospace
                                        font.pixelSize: Theme.fontSizeCaption
                                        color: Theme.text
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Ctrl+B : Negrita\nCtrl+I : Cursiva\nCtrl+K : Insertar enlace\nEsc : Cerrar nota / editor"
                                        font.family: Theme.fontFamilyMonospace
                                        font.pixelSize: Theme.fontSizeCaption
                                        color: Theme.text
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        id: activeTabCol
                        implicitHeight: {
                            if (root.tabIndex === 0) return tabEditor.implicitHeight;
                            if (root.tabIndex === 1) return tabAppearance.implicitHeight;
                            if (root.tabIndex === 2) return tabLanguage.implicitHeight;
                            return tabAbout.implicitHeight;
                        }
                    }
                }
            }
        }
    }
}
