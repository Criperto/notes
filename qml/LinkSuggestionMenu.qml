import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Notas
import "."

Item {
    id: root

    property bool isOpen: false
    property string mode: "notes" // "notes" | "anchors"
    property string targetNoteTitle: ""
    property var items: []
    property var triggerInfo: null
    property var targetInput: null
    property int highlightedNavIndex: -1

    readonly property real menuWidth: 360
    readonly property real menuHeight: Math.min(380, Math.max(68, (items.length * 46) + 52))

    signal suggestionSelected(var item, var triggerInfo)

    visible: isOpen || menuBox.opacity > 0.01
    enabled: isOpen
    anchors.fill: parent
    z: 99997

    onHighlightedNavIndexChanged: {
        if (highlightedNavIndex >= 0 && menuFlickable) {
            var itemY = highlightedNavIndex * 46;
            if (itemY < menuFlickable.contentY) {
                menuFlickable.contentY = itemY;
            } else if (itemY + 46 > menuFlickable.contentY + menuFlickable.height) {
                menuFlickable.contentY = (itemY + 46) - menuFlickable.height;
            }
        }
    }

    // Clic fuera del menú cierra la paleta sin absorber el clic para otros componentes
    MouseArea {
        id: outsideDismissArea
        anchors.fill: parent
        enabled: root.isOpen
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: (mouse) => {
            root.close();
            mouse.accepted = false;
        }
    }

    function open(input, trigger, newMode, itemsList, noteTitle) {
        if (!input) return;
        targetInput = input;
        triggerInfo = trigger;
        mode = newMode || "notes";
        targetNoteTitle = noteTitle || "";
        items = itemsList || [];
        highlightedNavIndex = items.length > 0 ? 0 : -1;
        updatePosition(input, trigger);
        isOpen = true;
    }

    function update(trigger, newMode, itemsList, noteTitle) {
        if (!isOpen) return;
        triggerInfo = trigger;
        if (newMode) mode = newMode;
        if (noteTitle !== undefined) targetNoteTitle = noteTitle;
        items = itemsList || [];
        if (highlightedNavIndex >= items.length) {
            highlightedNavIndex = Math.max(0, items.length - 1);
        } else if (highlightedNavIndex < 0 && items.length > 0) {
            highlightedNavIndex = 0;
        }
        if (targetInput) {
            updatePosition(targetInput, trigger);
        }
    }

    function close() {
        if (!isOpen) return;
        isOpen = false;
        highlightedNavIndex = -1;
        items = [];
        targetInput = null;
        triggerInfo = null;
        targetNoteTitle = "";
    }

    function selectNextItem() {
        if (!items || items.length === 0) return;
        highlightedNavIndex = (highlightedNavIndex + 1) % items.length;
    }

    function selectPreviousItem() {
        if (!items || items.length === 0) return;
        highlightedNavIndex = (highlightedNavIndex - 1 + items.length) % items.length;
    }

    function triggerSelectedItem() {
        if (highlightedNavIndex >= 0 && highlightedNavIndex < items.length) {
            triggerItem(highlightedNavIndex);
            return true;
        }
        return false;
    }

    function triggerItem(index) {
        if (index >= 0 && index < items.length) {
            var item = items[index];
            var trig = triggerInfo;
            close();
            root.suggestionSelected(item, trig);
        }
    }

    function updatePosition(input, trigger) {
        if (!input) return;
        var curPos = (trigger && typeof trigger.openIndex === "number")
            ? trigger.openIndex
            : (input.cursorPosition || 0);

        var maxPos = (typeof input.length === "number")
            ? input.length
            : (input.text ? input.text.length : 0);
        curPos = Math.max(0, Math.min(curPos, maxPos));

        var rect = (typeof input.positionToRectangle === "function")
            ? input.positionToRectangle(curPos)
            : Qt.rect(0, 0, 0, 24);

        var ptTop = input.mapToItem(root, rect.x, rect.y);
        var ptBottom = input.mapToItem(root, rect.x, rect.y + rect.height);

        var menuW = root.menuWidth;
        var menuH = root.menuHeight;

        var gap = 8;
        var spaceBelow = root.height - (ptBottom.y + gap);
        var spaceAbove = ptTop.y - gap;

        if (spaceBelow >= menuH || spaceBelow >= spaceAbove) {
            menuBox.y = Math.round(ptBottom.y + gap);
            menuBox.transformOrigin = Item.TopLeft;
        } else {
            menuBox.y = Math.round(Math.max(16, ptTop.y - menuH - gap));
            menuBox.transformOrigin = Item.BottomLeft;
        }

        var targetX = ptTop.x - 8;
        menuBox.x = Math.round(Math.max(16, Math.min(root.width - menuW - 16, targetX)));
    }

    Rectangle {
        id: menuBox
        visible: root.isOpen || opacity > 0.01
        enabled: root.isOpen
        width: root.menuWidth
        height: root.menuHeight
        radius: 12
        color: Theme.color0
        border.width: 1
        border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12)
        clip: true

        scale: root.isOpen ? 1.0 : 0.94
        opacity: root.isOpen ? 1.0 : 0.0

        Behavior on scale {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            SpringAnimation {
                spring: 8.5
                damping: 0.88
                mass: 0.48
                epsilon: 0.01
            }
        }

        Behavior on opacity {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
        }

        layer.enabled: !GamemodeService.gamemodeActive
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.45)
            shadowBlur: 0.55
            shadowVerticalOffset: 4
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            enabled: root.isOpen
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: (mouse) => mouse.accepted = true
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 4

            // Cabecera con indicación de contexto
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                color: "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 6

                    Text {
                        text: {
                            if (root.mode === "anchors") {
                                if (root.targetNoteTitle) {
                                    return I18n.t("notes.suggestions.headings_of", "Secciones de:") + " " + root.targetNoteTitle;
                                }
                                return I18n.t("notes.suggestions.headings_current", "Secciones de esta nota");
                            }
                            return I18n.t("notes.suggestions.refer_note", "Vincular a nota");
                        }
                        font.family: Theme.fontFamilyDisplay
                        font.pixelSize: 11
                        font.bold: true
                        color: Theme.accent
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: root.mode === "notes"
                        text: "# para anclas"
                        font.family: Theme.fontFamilyMonospace
                        font.pixelSize: 10
                        color: Theme.muted
                        opacity: 0.8
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
            }

            // Lista deslizable
            Flickable {
                id: menuFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width - (scrollBar.visible ? scrollBar.width : 0)
                contentHeight: Math.max(1, menuColumn.implicitHeight)

                ScrollBar.vertical: CustomScrollBar {
                    id: scrollBar
                }

                // Estado vacío
                Text {
                    visible: root.items.length === 0
                    anchors.centerIn: parent
                    text: root.mode === "anchors"
                        ? I18n.t("notes.suggestions.no_headings", "No hay encabezados disponibles")
                        : I18n.t("notes.suggestions.no_notes", "No se encontraron notas")
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: Theme.muted
                }

                Column {
                    id: menuColumn
                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: root.items
                        delegate: Item {
                            id: itemDelegate
                            required property var modelData
                            required property int index
                            readonly property bool isHighlighted: index === root.highlightedNavIndex
                            width: menuColumn.width
                            height: 46

                            Rectangle {
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                anchors.topMargin: 2
                                anchors.bottomMargin: 2
                                radius: 8
                                color: itemDelegate.isHighlighted
                                    ? Qt.hsva(Theme.accent.hsvHue < 0 ? 0 : Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.16)
                                    : (itemMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06) : "transparent")
                                border.color: itemDelegate.isHighlighted
                                    ? Qt.hsva(Theme.accent.hsvHue < 0 ? 0 : Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.45)
                                    : "transparent"
                                border.width: 1

                                Behavior on color {
                                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                    ColorAnimation { duration: 70 }
                                }
                                Behavior on border.color {
                                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                    ColorAnimation { duration: 70 }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                // Icono o Badge de Encabezado
                                Item {
                                    Layout.preferredWidth: 26
                                    Layout.preferredHeight: 26
                                    Layout.alignment: Qt.AlignVCenter

                                    // Badge de Nivel H1..H6
                                    Rectangle {
                                        visible: root.mode === "anchors"
                                        anchors.centerIn: parent
                                        width: 26
                                        height: 20
                                        radius: 5
                                        color: Qt.hsva(Theme.accent.hsvHue < 0 ? 0 : Theme.accent.hsvHue, Theme.accent.hsvSaturation * 0.8, Theme.accent.hsvValue, itemDelegate.isHighlighted ? 0.35 : 0.18)

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.tag || "H"
                                            font.family: Theme.fontFamilyDisplay
                                            font.pixelSize: 11
                                            font.bold: true
                                            color: itemDelegate.isHighlighted ? Theme.accent : Theme.text
                                        }
                                    }

                                    // Icono para notas existentes
                                    Image {
                                        id: noteIcon
                                        visible: root.mode === "notes" && !modelData.isCreateNew
                                        anchors.centerIn: parent
                                        width: 18
                                        height: 18
                                        source: Theme.iconsPath + "edit-note.svg"
                                        sourceSize: Qt.size(18, 18)
                                    }

                                    MultiEffect {
                                        anchors.fill: noteIcon
                                        source: noteIcon
                                        colorization: 1.0
                                        colorizationColor: itemDelegate.isHighlighted ? Theme.accent : Theme.text
                                        visible: noteIcon.visible && noteIcon.status === Image.Ready
                                    }

                                    // Icono '+' para crear nueva nota
                                    Rectangle {
                                        visible: root.mode === "notes" && !!modelData.isCreateNew
                                        anchors.centerIn: parent
                                        width: 22
                                        height: 22
                                        radius: 6
                                        color: Qt.hsva(Theme.accent.hsvHue < 0 ? 0 : Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.25)

                                        Text {
                                            anchors.centerIn: parent
                                            text: "+"
                                            font.pixelSize: 15
                                            font.bold: true
                                            color: Theme.accent
                                        }
                                    }
                                }

                                // Textos principales
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 1

                                    Text {
                                        Layout.fillWidth: true
                                        text: {
                                            if (modelData.isCreateNew) {
                                                return I18n.t("notes.suggestions.create_note", "Crear nota:") + " \"" + modelData.title + "\"";
                                            }
                                            return modelData.title || "";
                                        }
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: itemDelegate.isHighlighted ? Theme.accent : Theme.text
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: {
                                            if (root.mode === "anchors") {
                                                return "#" + (modelData.slug || "");
                                            }
                                            if (modelData.isCreateNew) {
                                                return I18n.t("notes.suggestions.create_note_desc", "Nueva nota con este título");
                                            }
                                            return modelData.slug || "";
                                        }
                                        font.family: Theme.fontFamilyMonospace
                                        font.pixelSize: 10
                                        color: Theme.muted
                                        opacity: 0.75
                                        elide: Text.ElideRight
                                    }
                                }

                                // Badge de tipo
                                Rectangle {
                                    visible: !modelData.isCreateNew
                                    Layout.preferredHeight: 18
                                    Layout.preferredWidth: badgeText.implicitWidth + 8
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: 4
                                    color: itemDelegate.isHighlighted
                                        ? Qt.hsva(Theme.accent.hsvHue < 0 ? 0 : Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.22)
                                        : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)

                                    Text {
                                        id: badgeText
                                        anchors.centerIn: parent
                                        text: root.mode === "anchors" ? modelData.tag : ".md"
                                        font.family: Theme.fontFamilyMonospace
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: itemDelegate.isHighlighted ? Theme.accent : Theme.muted
                                    }
                                }
                            }

                            MouseArea {
                                id: itemMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.triggerItem(index)
                            }
                        }
                    }
                }
            }
        }
    }
}
