// ShortcutsSheet.qml — Modal accesible con el mapa completo de atajos de teclado
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

    readonly property real targetWidth: Math.min(root.width - Theme.s(48), Theme.s(740))
    readonly property real targetHeight: Math.min(root.height - Theme.s(48), Theme.s(600))

    WheelHandler {
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: root.isOpen || root.isClosing
        onWheel: (event) => {
            event.accepted = true;
        }
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
            closeBtn.forceActiveFocus();
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
        closeBtn.forceActiveFocus();
    }

    function close() {
        if (!isOpen && !isClosing) return;
        openCardAnim.stop();
        fadeOpenAnim.stop();

        if (isFromButton && backgroundSourceItem && typeof backgroundSourceItem.getShortcutsButtonRect === "function") {
            var curRect = backgroundSourceItem.getShortcutsButtonRect();
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

    // Atajos de cierre
    Shortcut {
        enabled: root.isOpen && !root.isClosing
        sequence: "Esc"
        onActivated: root.close()
    }

    Shortcut {
        enabled: root.isOpen && !root.isClosing
        sequence: "Escape"
        onActivated: root.close()
    }

    Shortcut {
        enabled: root.isOpen && !root.isClosing
        sequence: "Ctrl+/"
        onActivated: root.close()
    }

    Shortcut {
        enabled: root.isOpen && !root.isClosing
        sequence: "F1"
        onActivated: root.close()
    }

    // Backdrop
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45 * (modalBgGroup.opacity > 0 ? modalBgGroup.opacity : (root.isOpen ? 1.0 : 0.0)))
        visible: root.isOpen || root.isClosing

        MouseArea {
            anchors.fill: parent
            enabled: root.isOpen
            onClicked: root.close()
            onWheel: (wheel) => { wheel.accepted = true; }
        }
    }

    // Tarjeta Bento Principal con Morph Animation
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

        // Apariencia del botón cuando está colapsado
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

        // Apariencia del modal (Frosted Glass y superficie) con fade
        Item {
            id: modalBgGroup
            anchors.fill: parent
            opacity: 0.0

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

        // Contenido del botón durante el morph
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
                source: Theme.iconsPath + "keyboard.svg"
                sourceSize: Qt.size(16, 16)
                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: Theme.muted
                }
            }
        }

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
            anchors.margins: Theme.s(22)
            spacing: Theme.s(16)
            opacity: 0.0

            // Cabecera
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.s(12)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.s(4)

                    Text {
                        text: I18n.t("shortcuts.title", "Atajos de Teclado")
                        color: Theme.text
                        font {
                            family: Theme.fontFamilyDisplay
                            pixelSize: Theme.fontSizeTitleLarge
                            bold: true
                        }
                    }

                    Text {
                        text: I18n.t("shortcuts.subtitle", "Navegación y productividad con teclado")
                        color: Theme.muted
                        font {
                            family: Theme.fontFamily
                            pixelSize: Theme.fontSizeSmall
                        }
                    }
                }

                // Botón Cerrar (idéntico al de NotesSettingsModal)
                Rectangle {
                    id: closeBtn
                    width: Theme.s(32)
                    height: Theme.s(32)
                    radius: Theme.s(8)
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

                    FocusRing {
                        target: closeBtn
                    }

                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
                    }

                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: I18n.t("shortcuts.close", "Cerrar atajos")

                    Keys.onReturnPressed: root.close()
                    Keys.onEnterPressed: root.close()
                    Keys.onSpacePressed: root.close()
                }
            }

            // Separador
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.outlineVariant ? Theme.outlineVariant : Qt.rgba(1, 1, 1, 0.08)
            }

            // Vista scrolleable con categorías y CustomScrollBar
            Flickable {
                id: scrollContent
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: Math.max(100, width - vbar.reservedSpace)
                contentHeight: categoriesCol.implicitHeight + Theme.s(16)

                ScrollBar.vertical: CustomScrollBar { id: vbar }

                ColumnLayout {
                    id: categoriesCol
                    width: scrollContent.contentWidth
                    spacing: Theme.s(20)

                    // Categoría 1: Navegación General
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.s(8)

                        Text {
                            text: I18n.t("shortcuts.cat_nav", "Navegación General").toUpperCase()
                            color: Theme.accent
                            font {
                                family: Theme.fontFamily
                                pixelSize: Theme.fontSizeSmall
                                bold: true
                                letterSpacing: 1.1
                            }
                        }

                        Repeater {
                            model: [
                                { keys: "Tab / Shift+Tab", desc: I18n.t("shortcuts.nav_tab", "Mover foco entre buscador, etiquetas y tarjetas") },
                                { keys: "Enter", desc: I18n.t("shortcuts.nav_enter", "Abrir la nota seleccionada") },
                                { keys: "Delete / Supr", desc: I18n.t("shortcuts.nav_delete", "Enviar nota a papelera (con deshacer)") },
                                { keys: "Ctrl+N", desc: I18n.t("shortcuts.nav_new", "Crear una nueva nota de inmediato") },
                                { keys: "Ctrl+F / /", desc: I18n.t("shortcuts.nav_search", "Enfocar barra de búsqueda") },
                                { keys: "Ctrl+,", desc: I18n.t("shortcuts.nav_settings", "Abrir ajustes y configuración") },
                                { keys: "Ctrl+/ / F1", desc: I18n.t("shortcuts.nav_help", "Ver esta hoja de atajos de teclado") },
                                { keys: "Esc", desc: I18n.t("shortcuts.nav_esc", "Cerrar modal o volver a la vista principal") }
                            ]

                            delegate: RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.s(12)

                                Rectangle {
                                    id: keyBadge
                                    implicitWidth: keyTxt.implicitWidth + Theme.s(16)
                                    implicitHeight: Theme.s(26)
                                    radius: Theme.s(6)
                                    color: Qt.rgba(0, 0, 0, 0.3)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.12)

                                    Text {
                                        id: keyTxt
                                        anchors.centerIn: parent
                                        text: modelData.keys
                                        color: Theme.textSecondary ? Theme.textSecondary : Theme.text
                                        font {
                                            family: Theme.fontFamilyMonospace
                                            pixelSize: Theme.fontSizeSmall
                                            bold: true
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.desc
                                    color: Theme.text
                                    wrapMode: Text.WordWrap
                                    font {
                                        family: Theme.fontFamily
                                        pixelSize: Theme.fontSizeBody
                                    }
                                }
                            }
                        }
                    }

                    // Categoría 2: Edición y Markdown
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.s(8)

                        Text {
                            text: I18n.t("shortcuts.cat_editor", "Edición y Markdown").toUpperCase()
                            color: Theme.accent
                            font {
                                family: Theme.fontFamily
                                pixelSize: Theme.fontSizeSmall
                                bold: true
                                letterSpacing: 1.1
                            }
                        }

                        Repeater {
                            model: [
                                { keys: "Ctrl+B", desc: I18n.t("shortcuts.edit_bold", "Texto en negrita") },
                                { keys: "Ctrl+I", desc: I18n.t("shortcuts.edit_italic", "Texto en cursiva") },
                                { keys: "Ctrl+K", desc: I18n.t("shortcuts.edit_link", "Insertar enlace Markdown") },
                                { keys: "/", desc: I18n.t("shortcuts.edit_slash", "Menú de comandos rápidos (Slash Menu)") },
                                { keys: "Ctrl+Z / Ctrl+Y", desc: I18n.t("shortcuts.edit_undo", "Deshacer y rehacer persistente") },
                                { keys: "Ctrl+S", desc: I18n.t("shortcuts.edit_save", "Guardar nota de inmediato") }
                            ]

                            delegate: RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.s(12)

                                Rectangle {
                                    implicitWidth: keyTxt2.implicitWidth + Theme.s(16)
                                    implicitHeight: Theme.s(26)
                                    radius: Theme.s(6)
                                    color: Qt.rgba(0, 0, 0, 0.3)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.12)

                                    Text {
                                        id: keyTxt2
                                        anchors.centerIn: parent
                                        text: modelData.keys
                                        color: Theme.textSecondary ? Theme.textSecondary : Theme.text
                                        font {
                                            family: Theme.fontFamilyMonospace
                                            pixelSize: Theme.fontSizeSmall
                                            bold: true
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.desc
                                    color: Theme.text
                                    wrapMode: Text.WordWrap
                                    font {
                                        family: Theme.fontFamily
                                        pixelSize: Theme.fontSizeBody
                                    }
                                }
                            }
                        }
                    }

                    // Categoría 3: Herramientas Avanzadas
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.s(8)

                        Text {
                            text: I18n.t("shortcuts.cat_tools", "Herramientas Avanzadas").toUpperCase()
                            color: Theme.accent
                            font {
                                family: Theme.fontFamily
                                pixelSize: Theme.fontSizeSmall
                                bold: true
                                letterSpacing: 1.1
                            }
                        }

                        Repeater {
                            model: [
                                { keys: "F7", desc: I18n.t("shortcuts.tool_spell", "Ejecutar revisión ortográfica manual") },
                                { keys: "F10", desc: I18n.t("shortcuts.tool_toolbar", "Alternar foco a barra de herramientas del editor") },
                                { keys: "Ctrl+Alt+W", desc: I18n.t("shortcuts.tool_clip", "Clipper web (recortar URL a Markdown)") },
                                { keys: "Ctrl+Alt+V", desc: I18n.t("shortcuts.tool_paste", "Capturar nueva nota desde portapapeles") }
                            ]

                            delegate: RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.s(12)

                                Rectangle {
                                    implicitWidth: keyTxt3.implicitWidth + Theme.s(16)
                                    implicitHeight: Theme.s(26)
                                    radius: Theme.s(6)
                                    color: Qt.rgba(0, 0, 0, 0.3)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.12)

                                    Text {
                                        id: keyTxt3
                                        anchors.centerIn: parent
                                        text: modelData.keys
                                        color: Theme.textSecondary ? Theme.textSecondary : Theme.text
                                        font {
                                            family: Theme.fontFamilyMonospace
                                            pixelSize: Theme.fontSizeSmall
                                            bold: true
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.desc
                                    color: Theme.text
                                    wrapMode: Text.WordWrap
                                    font {
                                        family: Theme.fontFamily
                                        pixelSize: Theme.fontSizeBody
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
