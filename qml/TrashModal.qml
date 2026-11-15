// TrashModal.qml — Papelera estándar FreeDesktop ($XDG_DATA_HOME/Trash) filtrada por notasDir
import "."
import Notas
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects

Item {
    id: root
    anchors.fill: parent
    z: 960
    property bool isOpen: false
    opacity: 0.0
    visible: opacity > 0.01

    function open() {
        NotesService.refreshTrash();
        isOpen = true;
        openAnim.restart();
    }

    function close() {
        if (!isOpen) return;
        isOpen = false;
        closeAnim.restart();
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

    Shortcut {
        sequence: "Escape"
        enabled: root.isOpen
        onActivated: root.close()
    }

    ParallelAnimation {
        id: openAnim
        NumberAnimation { target: root; property: "opacity"; to: 1.0; duration: 160; easing.type: Easing.OutCubic }
        SpringAnimation { target: dialogCard; property: "scale"; from: 0.94; to: 1.0; spring: 3.5; damping: 0.38; mass: 0.85 }
    }

    ParallelAnimation {
        id: closeAnim
        NumberAnimation { target: root; property: "opacity"; to: 0.0; duration: 130; easing.type: Easing.InCubic }
        NumberAnimation { target: dialogCard; property: "scale"; to: 0.95; duration: 130; easing.type: Easing.InCubic }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    Rectangle {
        id: dialogCard
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 560)
        height: Math.min(parent.height - 64, 480)
        radius: 16
        color: Theme.surface
        border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.14)
        border.width: 1

        MouseArea {
            anchors.fill: parent
            onClicked: {} // Bloquea propagación al backdrop
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

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

                // Vaciar papelera
                Rectangle {
                    visible: NotesService.trashEntries.length > 0
                    Layout.preferredHeight: 30
                    Layout.preferredWidth: emptyTxt.implicitWidth + 20
                    radius: 8
                    color: emptyMa.containsMouse
                        ? Qt.rgba(Theme.color1.r, Theme.color1.g, Theme.color1.b, 0.22)
                        : Qt.rgba(Theme.color1.r, Theme.color1.g, Theme.color1.b, 0.12)
                    border.color: Qt.rgba(Theme.color1.r, Theme.color1.g, Theme.color1.b, 0.35)
                    border.width: 1

                    Text {
                        id: emptyTxt
                        anchors.centerIn: parent
                        text: I18n.t("trash.modal.empty", "Vaciar todo")
                        color: Theme.color1
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
