import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Notas

ApplicationWindow {
    id: root
    visible: true
    title: "Notas"
    width: 1040
    height: 740
    minimumWidth: 680
    minimumHeight: 500
    color: Theme.surface

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 16

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: I18n.t("notes.header.title", "Notas")
            color: Theme.text
            font.pixelSize: Theme.fontSizeDisplay
            font.bold: true
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "v0.1.0 • Motor QML + Rust cxx-qt 0.10"
            color: Theme.muted
            font.pixelSize: Theme.fontSizeBody
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 240
            height: 48
            radius: 12
            color: Theme.primary

            Text {
                anchors.centerIn: parent
                text: "dev.criperto.Notas"
                color: Theme.textOn(Theme.primary)
                font.bold: true
            }
        }
    }
}
