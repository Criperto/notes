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
    signal importNotesRequested()

    property bool expanded: false

    // Ancho dinámico basado en las opciones de texto (+ márgenes e íconos)
    readonly property real dynamicExpandedWidth: {
        var maxTextWidth = Math.max(importText.implicitWidth, Math.max(clipText.implicitWidth, newNoteText.implicitWidth));
        return Math.max(185, Math.ceil(maxTextWidth + 64));
    }

    width: expanded ? dynamicExpandedWidth : 56
    height: expanded ? 190 : 56
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
            color: importMa.containsMouse ? Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.14) : "transparent"

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

                Text {
                    id: importText
                    Layout.fillWidth: true
                    text: I18n.t("notes.fab.import_notes", "Importar notas")
                    color: root.contentColor
                    font.family: Theme.fontFamilyDisplay
                    font.pixelSize: Theme.fontSizeTitle - 1
                    font.bold: true
                    elide: Text.ElideRight
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
            color: clipMa.containsMouse ? Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.14) : "transparent"

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

                Text {
                    id: clipText
                    Layout.fillWidth: true
                    text: I18n.t("notes.fab.from_clipboard", "Desde portapapeles")
                    color: root.contentColor
                    font.family: Theme.fontFamilyDisplay
                    font.pixelSize: Theme.fontSizeTitle - 1
                    font.bold: true
                    elide: Text.ElideRight
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

        // Opción 3: Nueva nota (texto/markdown)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            radius: 10
            color: newNoteMa.containsMouse ? Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.14) : "transparent"

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

                Text {
                    id: newNoteText
                    Layout.fillWidth: true
                    text: I18n.t("notes.fab.new_note", "Nueva nota")
                    color: root.contentColor
                    font.family: Theme.fontFamilyDisplay
                    font.pixelSize: Theme.fontSizeTitle - 1
                    font.bold: true
                    elide: Text.ElideRight
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
