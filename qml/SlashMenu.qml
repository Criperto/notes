import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Notas

Item {
    id: root

    property bool isOpen: false
    property var commands: []
    property var triggerInfo: null
    property var targetInput: null
    property int highlightedNavIndex: -1

    readonly property real menuWidth: 340
    readonly property real menuHeight: Math.min(360, Math.max(64, (commands.length * 48) + (commands.length === 0 ? 56 : 12)))

    signal commandSelected(var cmd, var triggerInfo)

    visible: isOpen || menuBox.scale > 0.05
    anchors.fill: parent
    z: 99998

    onHighlightedNavIndexChanged: {
        if (highlightedNavIndex >= 0 && menuFlickable) {
            var itemY = highlightedNavIndex * 48;
            if (itemY < menuFlickable.contentY) {
                menuFlickable.contentY = itemY;
            } else if (itemY + 48 > menuFlickable.contentY + menuFlickable.height) {
                menuFlickable.contentY = (itemY + 48) - menuFlickable.height;
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

    function open(input, trigger, cmds) {
        if (!input) return;
        targetInput = input;
        triggerInfo = trigger;
        commands = cmds || [];
        highlightedNavIndex = commands.length > 0 ? 0 : -1;
        updatePosition(input, trigger);
        isOpen = true;
    }

    function update(trigger, cmds) {
        if (!isOpen) return;
        triggerInfo = trigger;
        commands = cmds || [];
        if (highlightedNavIndex >= commands.length) {
            highlightedNavIndex = Math.max(0, commands.length - 1);
        } else if (highlightedNavIndex < 0 && commands.length > 0) {
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
        commands = [];
        targetInput = null;
        triggerInfo = null;
    }

    function selectNextItem() {
        if (!commands || commands.length === 0) return;
        highlightedNavIndex = (highlightedNavIndex + 1) % commands.length;
    }

    function selectPreviousItem() {
        if (!commands || commands.length === 0) return;
        highlightedNavIndex = (highlightedNavIndex - 1 + commands.length) % commands.length;
    }

    function triggerSelectedItem() {
        if (highlightedNavIndex >= 0 && highlightedNavIndex < commands.length) {
            triggerItem(highlightedNavIndex);
            return true;
        }
        return false;
    }

    function triggerItem(index) {
        if (index >= 0 && index < commands.length) {
            var cmd = commands[index];
            var trig = triggerInfo;
            close();
            root.commandSelected(cmd, trig);
        }
    }

    function updatePosition(input, trigger) {
        if (!input) return;
        var curPos = (trigger && typeof trigger.slashIndex === "number")
            ? trigger.slashIndex
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

        // Si hay espacio abajo, ubicar debajo de la línea. Si no, arriba.
        // Nunca superponer la línea de texto donde el usuario escribe.
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

        // Clic dentro de la caja no cierra el menú
        MouseArea {
            anchors.fill: parent
            z: -1
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: (mouse) => mouse.accepted = true
        }

        Flickable {
            id: menuFlickable
            anchors.fill: parent
            anchors.margins: 6
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width - (scrollBar.visible ? scrollBar.width : 0)
            contentHeight: menuColumn.implicitHeight

            ScrollBar.vertical: CustomScrollBar {
                id: scrollBar
            }

            Column {
                id: menuColumn
                width: parent.width
                spacing: 0

                Repeater {
                    model: root.commands
                    delegate: Item {
                        id: itemDelegate
                        required property var modelData
                        required property int index
                        readonly property bool isHighlighted: index === root.highlightedNavIndex
                        width: menuColumn.width
                        height: 48

                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            anchors.topMargin: 2
                            anchors.bottomMargin: 2
                            radius: 8
                            color: itemDelegate.isHighlighted
                                ? Qt.hsva(Theme.accent.hsvHue < 0 ? 0 : Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.14)
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
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            Item {
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22
                                Layout.alignment: Qt.AlignVCenter

                                Image {
                                    id: iconImg
                                    anchors.fill: parent
                                    source: modelData.icon ? (Theme.iconsPath + modelData.icon) : ""
                                    sourceSize: Qt.size(22, 22)
                                    visible: false
                                }

                                MultiEffect {
                                    anchors.fill: iconImg
                                    source: iconImg
                                    colorization: 1.0
                                    colorizationColor: itemDelegate.isHighlighted ? Theme.accent : Theme.text
                                    visible: iconImg.status === Image.Ready
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: (typeof I18n !== "undefined" && typeof I18n.t === "function")
                                        ? I18n.t(modelData.titleKey, modelData.fallbackTitle)
                                        : modelData.fallbackTitle
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.bold: true
                                    color: itemDelegate.isHighlighted ? Theme.accent : Theme.text
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: (typeof I18n !== "undefined" && typeof I18n.t === "function")
                                        ? I18n.t(modelData.descKey, modelData.fallbackDesc)
                                        : modelData.fallbackDesc
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.muted
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                visible: !!(modelData.badge && modelData.badge !== "")
                                Layout.preferredHeight: 20
                                Layout.preferredWidth: badgeText.implicitWidth + 10
                                Layout.alignment: Qt.AlignVCenter
                                radius: 4
                                color: itemDelegate.isHighlighted
                                    ? Qt.hsva(Theme.accent.hsvHue < 0 ? 0 : Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.22)
                                    : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)

                                Text {
                                    id: badgeText
                                    anchors.centerIn: parent
                                    text: modelData.badge || ""
                                    font.family: Theme.fontFamilyMonospace || "Google Sans Code"
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
                            onEntered: root.highlightedNavIndex = index
                            onClicked: root.triggerItem(index)
                        }
                    }
                }

                // Estado vacío cuando la búsqueda no coincide
                Item {
                    visible: root.commands.length === 0
                    width: menuColumn.width
                    height: 56

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        Image {
                            source: Theme.iconsPath + "search.svg"
                            sourceSize: Qt.size(16, 16)
                            opacity: 0.5
                            visible: status === Image.Ready
                        }
                        Text {
                            text: (typeof I18n !== "undefined" && typeof I18n.t === "function")
                                ? I18n.t("notes.slash.no_results", "No se encontraron comandos")
                                : "No se encontraron comandos"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.muted
                        }
                    }
                }
            }
        }
    }
}
