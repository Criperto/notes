import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Diff.js" as Diff

Item {
    id: root

    property string oldText: ""
    property string newText: ""
    property bool onlyHunks: false
    property int contextLines: 3

    property var _rawDiff: []
    property var _hunkList: []
    property int additionsCount: 0
    property int deletionsCount: 0

    function refresh() {
        if (!oldText && !newText) {
            _rawDiff = [];
            _hunkList = [];
            additionsCount = 0;
            deletionsCount = 0;
            diffListView.model = [];
            return;
        }

        var lines = Diff.diffLines(oldText, newText);
        _rawDiff = lines;

        var st = Diff.stats(lines);
        additionsCount = st.additions;
        deletionsCount = st.deletions;

        if (onlyHunks) {
            _hunkList = _flattenHunks(Diff.hunks(lines, contextLines));
            diffListView.model = _hunkList;
        } else {
            // Asignar números de línea 1-based para vista completa
            var modelData = [];
            var oldN = 1;
            var newN = 1;
            for (var i = 0; i < lines.length; i++) {
                var it = lines[i];
                var itemObj = {
                    type: it.type,
                    val: it.val,
                    oldLine: (it.type === "eq" || it.type === "del") ? oldN : "",
                    newLine: (it.type === "eq" || it.type === "add") ? newN : "",
                    isHunkHeader: false
                };
                if (it.type === "eq" || it.type === "del") oldN++;
                if (it.type === "eq" || it.type === "add") newN++;
                modelData.push(itemObj);
            }
            diffListView.model = modelData;
        }
    }

    function _flattenHunks(hunks) {
        var flat = [];
        for (var h = 0; h < hunks.length; h++) {
            var hunk = hunks[h];
            flat.push({
                type: "hunk_header",
                val: hunk.header,
                oldLine: "@@",
                newLine: "@@",
                isHunkHeader: true
            });
            var oldN = hunk.oldStart;
            var newN = hunk.newStart;
            for (var i = 0; i < hunk.lines.length; i++) {
                var it = hunk.lines[i];
                flat.push({
                    type: it.type,
                    val: it.val,
                    oldLine: (it.type === "eq" || it.type === "del") ? oldN : "",
                    newLine: (it.type === "eq" || it.type === "add") ? newN : "",
                    isHunkHeader: false
                });
                if (it.type === "eq" || it.type === "del") oldN++;
                if (it.type === "eq" || it.type === "add") newN++;
            }
        }
        return flat;
    }

    onOldTextChanged: refresh()
    onNewTextChanged: refresh()
    onOnlyHunksChanged: refresh()

    Component.onCompleted: refresh()

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // Header de estadísticas y alternancia
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            spacing: 10

            // Píldora de adiciones
            Rectangle {
                Layout.preferredHeight: 24
                Layout.preferredWidth: addLabel.implicitWidth + 14
                radius: 12
                color: Qt.rgba(Theme.success.r, Theme.success.g, Theme.success.b, 0.15)
                border.width: 1
                border.color: Qt.rgba(Theme.success.r, Theme.success.g, Theme.success.b, 0.3)

                Text {
                    id: addLabel
                    anchors.centerIn: parent
                    text: "+" + root.additionsCount
                    font.family: Theme.fontFamilyMonospace
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: Theme.success
                }
            }

            // Píldora de eliminaciones
            Rectangle {
                Layout.preferredHeight: 24
                Layout.preferredWidth: delLabel.implicitWidth + 14
                radius: 12
                color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.15)
                border.width: 1
                border.color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.3)

                Text {
                    id: delLabel
                    anchors.centerIn: parent
                    text: "-" + root.deletionsCount
                    font.family: Theme.fontFamilyMonospace
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: Theme.danger
                }
            }

            Item { Layout.fillWidth: true }

            // Botón de alternar: Todo el archivo vs Solo cambios
            Rectangle {
                Layout.preferredHeight: 24
                Layout.preferredWidth: modeText.implicitWidth + 16
                radius: 6
                color: modeHover.hovered ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18) : Qt.rgba(Theme.cardBackground.r, Theme.cardBackground.g, Theme.cardBackground.b, 0.4)
                border.width: 1
                border.color: root.onlyHunks ? Theme.accent : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.15)

                Text {
                    id: modeText
                    anchors.centerIn: parent
                    text: root.onlyHunks ? "Solo cambios" : "Todo el texto"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: root.onlyHunks ? Theme.accent : Theme.text
                }

                HoverHandler { id: modeHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: root.onlyHunks = !root.onlyHunks
                }
            }
        }

        // Vista de lista de diferencias
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 8
            color: Qt.rgba(0, 0, 0, 0.25)
            border.width: 1
            border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1)
            clip: true

            ListView {
                id: diffListView
                anchors.fill: parent
                anchors.margins: 4
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                ScrollBar.vertical: CustomScrollBar {}

                delegate: Rectangle {
                    id: rowDelegate
                    width: diffListView.width
                    height: Math.max(22, lineContent.implicitHeight + 4)
                    color: {
                        if (modelData.isHunkHeader) {
                            return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12);
                        }
                        if (modelData.type === "add") {
                            return Qt.rgba(Theme.success.r, Theme.success.g, Theme.success.b, 0.14);
                        }
                        if (modelData.type === "del") {
                            return Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.14);
                        }
                        return "transparent";
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        anchors.rightMargin: 8
                        spacing: 6

                        // Número línea antigua
                        Text {
                            Layout.preferredWidth: 32
                            horizontalAlignment: Text.AlignRight
                            text: modelData.oldLine !== undefined ? ("" + modelData.oldLine) : ""
                            font.family: Theme.fontFamilyMonospace
                            font.pixelSize: 10
                            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.35)
                        }

                        // Número línea nueva
                        Text {
                            Layout.preferredWidth: 32
                            horizontalAlignment: Text.AlignRight
                            text: modelData.newLine !== undefined ? ("" + modelData.newLine) : ""
                            font.family: Theme.fontFamilyMonospace
                            font.pixelSize: 10
                            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.35)
                        }

                        // Signo (+ / - / espacio / @@)
                        Text {
                            Layout.preferredWidth: 14
                            horizontalAlignment: Text.AlignHCenter
                            text: {
                                if (modelData.isHunkHeader) return "@@";
                                if (modelData.type === "add") return "+";
                                if (modelData.type === "del") return "-";
                                return " ";
                            }
                            font.family: Theme.fontFamilyMonospace
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: {
                                if (modelData.isHunkHeader) return Theme.accent;
                                if (modelData.type === "add") return Theme.success;
                                if (modelData.type === "del") return Theme.danger;
                                return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.2);
                            }
                        }

                        // Contenido de la línea
                        Text {
                            id: lineContent
                            Layout.fillWidth: true
                            text: modelData.val || ""
                            font.family: Theme.fontFamilyMonospace
                            font.pixelSize: 11
                            wrapMode: Text.WrapAnywhere
                            color: {
                                if (modelData.isHunkHeader) return Theme.accent;
                                if (modelData.type === "add") return Theme.success;
                                if (modelData.type === "del") return Theme.danger;
                                return Theme.text;
                            }
                        }
                    }
                }

                // Placeholder si no hay diferencias
                Item {
                    anchors.centerIn: parent
                    visible: diffListView.count === 0
                    width: 200
                    height: 80

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Sin diferencias"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: Theme.textSecondary
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "El contenido es idéntico a esta versión."
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.4)
                        }
                    }
                }
            }
        }
    }
}
