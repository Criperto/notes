// TrashModal.qml — Papelera estándar FreeDesktop ($XDG_DATA_HOME/Trash) filtrada por notasDir
// Comportamiento y animaciones SpringAnimation idénticas a NotesSettingsModal.qml
pragma ComponentBehavior: Bound
import "."
import Notas
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects

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
    property rect originRect: Qt.rect(Math.round((width - 38) / 2), Math.round((height - 38) / 2), 38, 38)

    readonly property real targetWidth: Math.min(root.width - 48, 580)
    readonly property real targetHeight: Math.min(root.height - 64, 500)

    WheelHandler {
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: root.isOpen || root.isClosing
        onWheel: (event) => {
            event.accepted = true;
        }
    }

    function open(rect) {
        if (isOpen && !isClosing) return;
        NotesService.refreshTrash();
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
        if (!isOpen && !isClosing) return;
        openCardAnim.stop();
        fadeOpenAnim.stop();

        if (isFromButton && backgroundSourceItem && typeof backgroundSourceItem.getTrashButtonRect === "function") {
            var curRect = backgroundSourceItem.getTrashButtonRect();
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

    function formatSize(bytes) {
        var b = Number(bytes) || 0;
        if (b < 1024) return b + " B";
        if (b < 1024 * 1024) return Math.max(1, Math.round(b / 1024)) + " KB";
        return (b / (1024 * 1024)).toFixed(1) + " MB";
    }

    function formatIsoDate(isoStr) {
        if (!isoStr) return "";
        return String(isoStr).replace("T", " ").substring(0, 16);
    }

    ParallelAnimation {
        id: openCardAnim

        SpringAnimation { target: card; property: "x"; to: Math.round((root.width - root.targetWidth) / 2); spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25 }
        SpringAnimation { target: card; property: "y"; to: Math.round((root.height - root.targetHeight) / 2); spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25 }
        SpringAnimation { target: card; property: "width"; to: root.targetWidth; spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25 }
        SpringAnimation { target: card; property: "height"; to: root.targetHeight; spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25 }
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

        SpringAnimation { target: card; property: "x"; to: root.originRect.x; spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25 }
        SpringAnimation { target: card; property: "y"; to: root.originRect.y; spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25 }
        SpringAnimation { target: card; property: "width"; to: (root.originRect.width > 0 ? root.originRect.width : 38); spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25 }
        SpringAnimation { target: card; property: "height"; to: (root.originRect.height > 0 ? root.originRect.height : 38); spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25 }
        NumberAnimation { target: card; property: "radius"; to: 10; duration: 180; easing.type: Easing.OutCubic }

        SequentialAnimation {
            PauseAnimation { duration: 60 }
            NumberAnimation { target: cardBtnContent; property: "opacity"; to: 1.0; duration: 130; easing.type: Easing.OutCubic }
        }

        onFinished: {
            card.x = root.originRect.x;
            card.y = root.originRect.y;
            card.width = (root.originRect.width > 0 ? root.originRect.width : 38);
            card.height = (root.originRect.height > 0 ? root.originRect.height : 38);
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
        sequence: "Escape"
        enabled: root.isOpen
        onActivated: root.close()
    }

    // ── Fondo transparente sin oscurecimiento, igual a NotesSettingsModal ───
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

    // ── Tarjeta Principal con Morph Animation (idéntica a NotesSettingsModal) ──
    Rectangle {
        id: card
        x: Math.round((root.width - root.targetWidth) / 2)
        y: Math.round((root.height - root.targetHeight) / 2)
        width: root.targetWidth
        height: root.targetHeight
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

        // Fondo del botón origen durante el morph
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

        // Frosted glass y superficie tintada
        Item {
            id: modalBgGroup
            anchors.fill: parent
            opacity: 0.0

            Item {
                id: blurMaskItem
                anchors.fill: parent
                layer.enabled: card.radius > 0 && cardBlurContainer.visible
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

                layer.enabled: card.radius > 0 && visible
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

        // Contenido del botón durante morphing
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
                width: 15
                height: 15
                source: Theme.iconsPath + "delete.svg"
                sourceSize: Qt.size(15, 15)
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
            anchors.margins: 20
            spacing: 12
            opacity: 0.0
            visible: opacity > 0

            // Cabecera
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Image {
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                    source: Theme.iconsPath + "delete.svg"
                    sourceSize: Qt.size(18, 18)
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: Theme.accent
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: I18n.t("trash.modal.title", "Papelera de notas") + " (" + NotesService.trashEntries.length + ")"
                    color: Theme.text
                    font.family: Theme.fontFamilyDisplay
                    font.pixelSize: Theme.fontSizeTitle
                    font.bold: true
                    elide: Text.ElideRight
                }

                // Vaciar papelera — mismo estilo pill que Restaurar
                Rectangle {
                    id: emptyAllBtn
                    visible: NotesService.trashEntries.length > 0
                    Layout.preferredHeight: 30
                    Layout.preferredWidth: emptyTxt.implicitWidth + 18
                    radius: 8
                    color: emptyMa.containsMouse
                        ? Theme.accent
                        : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)

                    Text {
                        id: emptyTxt
                        anchors.centerIn: parent
                        text: I18n.t("trash.modal.empty", "Vaciar todo")
                        color: emptyMa.containsMouse ? Theme.textOn(Theme.accent) : Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: emptyMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: NotesService.emptyNotesTrash()
                    }
                }

                // Cerrar
                Rectangle {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    radius: 8
                    color: closeMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12) : "transparent"

                    Image {
                        anchors.centerIn: parent
                        width: 14; height: 14
                        source: Theme.iconsPath + "x.svg"
                        sourceSize: Qt.size(14, 14)
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: closeMa.containsMouse ? Theme.text : Theme.muted
                        }
                    }

                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
                    }
                }
            }

            // Subtítulo informativo
            Text {
                Layout.fillWidth: true
                text: I18n.t("trash.modal.subtitle", "Notas eliminadas en la papelera estándar del sistema")
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeCaption
                elide: Text.ElideRight
            }

            // Lista o estado vacío
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: NotesService.trashEntries.length === 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: I18n.t("trash.modal.noItems", "La papelera de notas está vacía")
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                    }
                }

                ListView {
                    id: trashList
                    anchors.fill: parent
                    visible: NotesService.trashEntries.length > 0
                    clip: true
                    spacing: 8
                    model: NotesService.trashEntries
                    ScrollBar.vertical: CustomScrollBar {}

                    delegate: Rectangle {
                        id: entryRow
                        required property var modelData
                        width: trashList.width
                        height: 58
                        radius: 10
                        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04)
                        border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 10
                            spacing: 10

                            Image {
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                source: Theme.iconsPath + (entryRow.modelData.isDir ? "folder.svg" : "sticky-note-2.svg")
                                sourceSize: Qt.size(16, 16)
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: Theme.muted
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: entryRow.modelData.relativePath || entryRow.modelData.name || ""
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeBody
                                    font.weight: Font.Medium
                                    elide: Text.ElideMiddle
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.formatIsoDate(entryRow.modelData.deletionDate) + "  ·  " + root.formatSize(entryRow.modelData.sizeBytes)
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeCaption
                                    elide: Text.ElideRight
                                }
                            }

                            // Botón Restaurar
                            Rectangle {
                                Layout.preferredHeight: 30
                                Layout.preferredWidth: restTxt.implicitWidth + 18
                                radius: 8
                                color: restMa.containsMouse
                                    ? Theme.accent
                                    : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)

                                Text {
                                    id: restTxt
                                    anchors.centerIn: parent
                                    text: I18n.t("trash.modal.restore", "Restaurar")
                                    color: restMa.containsMouse ? Theme.textOn(Theme.accent) : Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                }

                                MouseArea {
                                    id: restMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: NotesService.restoreFromTrash(entryRow.modelData.id)
                                }
                            }

                            // Botón Eliminar permanentemente
                            Rectangle {
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 30
                                radius: 8
                                color: purgeMa.containsMouse
                                    ? Qt.rgba(Theme.color1.r, Theme.color1.g, Theme.color1.b, 0.22)
                                    : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05)

                                Image {
                                    anchors.centerIn: parent
                                    width: 14; height: 14
                                    source: Theme.iconsPath + "delete-red.svg"
                                    sourceSize: Qt.size(14, 14)
                                }

                                MouseArea {
                                    id: purgeMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: NotesService.purgeFromTrash(entryRow.modelData.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
