// MorphingFab.qml — Botón "+" expandible con opciones "Importar notas" y "Nueva nota"
import "."
import Notas
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

ClippingRectangle {
    id: root

    signal newNoteRequested()
    signal clipNoteRequested()
    signal webClipRequested()
    signal importNotesRequested()

    property bool expanded: false
    property int keyboardOptionIndex: 3

    activeFocusOnTab: true
    Accessible.role: Accessible.ButtonMenu
    Accessible.name: I18n.t("notes.fab.create_new", "Nueva nota")

    function _triggerOption(idx) {
        root.expanded = false;
        if (idx === 0) root.importNotesRequested();
        else if (idx === 1) root.clipNoteRequested();
        else if (idx === 2) root.webClipRequested();
        else root.newNoteRequested();
    }

    Keys.onReturnPressed: (event) => {
        if (!root.expanded) {
            root.expanded = true;
        } else {
            root._triggerOption(root.keyboardOptionIndex);
        }
        event.accepted = true;
    }
    Keys.onEnterPressed: (event) => Keys.onReturnPressed(event)
    Keys.onSpacePressed: (event) => Keys.onReturnPressed(event)

    Keys.onDownPressed: (event) => {
        if (root.expanded) {
            root.keyboardOptionIndex = (root.keyboardOptionIndex + 1) % 4;
            event.accepted = true;
        }
    }
    Keys.onUpPressed: (event) => {
        if (root.expanded) {
            root.keyboardOptionIndex = (root.keyboardOptionIndex - 1 + 4) % 4;
            event.accepted = true;
        }
    }
    Keys.onEscapePressed: (event) => {
        if (root.expanded) {
            root.expanded = false;
            event.accepted = true;
        }
    }

    FocusRing {
        cornerRadius: root.radius
    }

    // Ancho dinámico basado en las opciones de texto (+ márgenes e íconos)
    readonly property real dynamicExpandedWidth: {
        var maxTextWidth = Math.max(importText.implicitTextWidth, Math.max(clipText.implicitTextWidth, Math.max(webClipText.implicitTextWidth, newNoteText.implicitTextWidth)));
        return Math.max(220, Math.min(290, Math.ceil(maxTextWidth + 88)));
    }

    component FabOptionText: Item {
        id: optContainer
        property alias text: optLabel.text
        property bool isHovered: false
        readonly property real implicitTextWidth: optLabel.implicitWidth
        Layout.fillWidth: true
        Layout.preferredHeight: optLabel.implicitHeight
        clip: true

        readonly property real overflow: Math.max(0, optLabel.implicitWidth - width)
        readonly property bool shouldMarquee: isHovered && overflow > 2

        Text {
            id: optLabel
            x: 0
            color: root.contentColor
            font.family: Theme.fontFamilyDisplay
            font.pixelSize: Theme.fontSizeTitle - 1
            font.bold: true
            elide: optContainer.shouldMarquee ? Text.ElideNone : Text.ElideRight

            SequentialAnimation on x {
                running: optContainer.shouldMarquee && Theme.animationsEnabled && !GamemodeService.gamemodeActive
                loops: Animation.Infinite

                PauseAnimation { duration: 600 }
                NumberAnimation {
                    to: -optContainer.overflow
                    duration: Math.max(1000, optContainer.overflow * 28)
                    easing.type: Easing.InOutQuad
                }
                PauseAnimation { duration: 800 }
                NumberAnimation {
                    to: 0
                    duration: Math.max(1000, optContainer.overflow * 28)
                    easing.type: Easing.InOutQuad
                }
                PauseAnimation { duration: 600 }
            }
        }
    }

    width: expanded ? dynamicExpandedWidth : 56
    height: expanded ? 232 : 56
    radius: expanded ? 18 : 16

    color: Theme.primary
    readonly property color contentColor: Theme.textOn(Theme.primary)

    clip: true

    Behavior on width {
        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
        SpringAnimation {
            spring: 3.2
            damping: 0.42
            mass: 1.0
            epsilon: 0.25
        }
    }

    Behavior on height {
        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
        SpringAnimation {
            spring: 3.2
            damping: 0.42
            mass: 1.0
            epsilon: 0.25
        }
    }

    Behavior on radius {
        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    // ── Opciones al expandirse: Importar notas y Nueva nota ────────────────
    ColumnLayout {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 12
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 4

        opacity: root.expanded ? 1.0 : 0.0
        visible: opacity > 0.0

        Behavior on opacity {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            NumberAnimation {
                duration: 140
            }
        }

        // Opción 1: Importar notas (.md, .txt, .docx)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            radius: 10
            color: (importMa.containsMouse || (root.expanded && root.activeFocus && root.keyboardOptionIndex === 0)) ? Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.18) : "transparent"

            Behavior on color {
                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                ColorAnimation { duration: 120 }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10

                Image {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    source: Theme.iconsPath + "upload-file.svg"
                    sourceSize: Qt.size(22, 22)
                    smooth: true
                    mipmap: true
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: root.contentColor
                    }
                }

                FabOptionText {
                    id: importText
                    text: I18n.t("notes.fab.import_notes", "Importar notas")
                    isHovered: importMa.containsMouse || (root.expanded && root.activeFocus && root.keyboardOptionIndex === 0)
                }
            }

            MouseArea {
                id: importMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (NotesService.debug) console.log("[MorphingFab] Solicitando importación de notas");
                    root.expanded = false;
                    root.importNotesRequested();
                }
            }
        }

        // Opción 2: Desde portapapeles (crear nota con contenido copiado)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            radius: 10
            color: (clipMa.containsMouse || (root.expanded && root.activeFocus && root.keyboardOptionIndex === 1)) ? Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.18) : "transparent"

            Behavior on color {
                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                ColorAnimation { duration: 120 }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10

                Image {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    source: Theme.iconsPath + "content-paste.svg"
                    sourceSize: Qt.size(22, 22)
                    smooth: true
                    mipmap: true
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: root.contentColor
                    }
                }

                FabOptionText {
                    id: clipText
                    text: I18n.t("notes.fab.from_clipboard", "Desde portapapeles")
                    isHovered: clipMa.containsMouse || (root.expanded && root.activeFocus && root.keyboardOptionIndex === 1)
                }
            }

            MouseArea {
                id: clipMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (NotesService.debug) console.log("[MorphingFab] Creando nota desde portapapeles");
                    root.expanded = false;
                    root.clipNoteRequested();
                }
            }
        }

        // Opción 3: Clipper web (recortar página o artículo desde URL)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            radius: 10
            color: (webClipMa.containsMouse || (root.expanded && root.activeFocus && root.keyboardOptionIndex === 2)) ? Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.18) : "transparent"

            Behavior on color {
                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                ColorAnimation { duration: 120 }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10

                Image {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    source: Theme.iconsPath + "web-clip.svg"
                    sourceSize: Qt.size(22, 22)
                    smooth: true
                    mipmap: true
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: root.contentColor
                    }
                }

                FabOptionText {
                    id: webClipText
                    text: I18n.t("notes.fab.web_clip", "Clipper web")
                    isHovered: webClipMa.containsMouse || (root.expanded && root.activeFocus && root.keyboardOptionIndex === 2)
                }
            }

            MouseArea {
                id: webClipMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (NotesService.debug) console.log("[MorphingFab] Solicitando clipper web");
                    root.expanded = false;
                    root.webClipRequested();
                }
            }
        }

        // Opción 4: Nueva nota (texto/markdown)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            radius: 10
            color: (newNoteMa.containsMouse || (root.expanded && root.activeFocus && root.keyboardOptionIndex === 3)) ? Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.18) : "transparent"

            Behavior on color {
                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                ColorAnimation { duration: 120 }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10

                Image {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    source: Theme.iconsPath + "edit-note.svg"
                    sourceSize: Qt.size(22, 22)
                    smooth: true
                    mipmap: true
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: root.contentColor
                    }
                }

                FabOptionText {
                    id: newNoteText
                    text: I18n.t("notes.fab.new_note", "Nueva nota")
                    isHovered: newNoteMa.containsMouse || (root.expanded && root.activeFocus && root.keyboardOptionIndex === 3)
                }
            }

            MouseArea {
                id: newNoteMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (NotesService.debug) console.log("[MorphingFab] Creando nueva nota estándar");
                    root.expanded = false;
                    root.newNoteRequested();
                }
            }
        }
    }

    // ── Botón con ícono '+' en reposo / rotado a '✕' al expandirse ────────
    // En reposo ocupa todo el botón (56x56); al expandirse se ubica en la esquina inferior derecha
    Item {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: 56
        height: 56

        Image {
            anchors.centerIn: parent
            width: 24
            height: 24
            source: Theme.iconsPath + "add.svg"
            sourceSize: Qt.size(24, 24)
            smooth: true
            mipmap: true

            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: root.contentColor
            }

            // Gira a 45 grados ÚNICAMENTE cuando está expandido
            rotation: root.expanded ? 45 : 0

            Behavior on rotation {
                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            id: fabBtnMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.expanded = !root.expanded;
                if (NotesService.debug) console.log("[MorphingFab] Estado expandido del FAB:", root.expanded);
            }
        }
    }
}
