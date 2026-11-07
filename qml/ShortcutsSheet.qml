// ShortcutsSheet.qml — Modal accesible con el mapa completo de atajos de teclado
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Effects
import Notas

Item {
    id: root

    visible: isOpen || isClosing || opacity > 0
    opacity: (isOpen && !isClosing) ? 1.0 : 0.0

    anchors.fill: parent
    z: 9999

    signal closed()

    property bool isOpen: false
    property bool isClosing: false

    Behavior on opacity {
        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    function open() {
        isOpen = true;
        isClosing = false;
        closeBtn.forceActiveFocus();
    }

    function close() {
        if (!isOpen) return;
        isClosing = true;
        closeTimer.start();
    }

    Timer {
        id: closeTimer
        interval: 160
        repeat: false
        onTriggered: {
            root.isOpen = false;
            root.isClosing = false;
            root.closed();
        }
    }

    // Atajo ESC para cerrar
    Shortcut {
        enabled: root.isOpen && !root.isClosing
        sequence: "Esc"
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

    // Backdrop desenfocado
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    // Tarjeta Modal Central
    Rectangle {
        id: modalCard
        width: Math.min(parent.width - Theme.s(48), Theme.s(720))
        height: Math.min(parent.height - Theme.s(48), Theme.s(600))
        anchors.centerIn: parent

        color: Theme.surfaceContainer ? Theme.surfaceContainer : Theme.surface
        radius: Theme.s(16)
        border.width: 1
        border.color: Theme.outlineVariant ? Theme.outlineVariant : Qt.rgba(1, 1, 1, 0.1)

        scale: (root.isOpen && !root.isClosing) ? 1.0 : 0.94

        Behavior on scale {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            SpringAnimation {
                spring: 8.5
                damping: 0.88
                mass: 0.45
                epsilon: 0.25
            }
        }

        MouseArea {
            anchors.fill: parent
            // Evita que clics dentro del modal cierren el backdrop
            onClicked: (mouse) => mouse.accepted = true
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.s(20)
            spacing: Theme.s(16)

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

                // Botón Cerrar
                Rectangle {
                    id: closeBtn
                    width: Theme.s(32)
                    height: Theme.s(32)
                    radius: Theme.s(16)
                    color: closeHover.hovered || closeBtn.activeFocus
                        ? Qt.rgba(1, 1, 1, 0.12)
                        : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: Theme.muted
                        font.pixelSize: Theme.fontSizeBody
                    }

                    FocusRing {
                        target: closeBtn
                    }

                    HoverHandler { id: closeHover }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
                    }

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

            // Vista scrolleable con categorías
            Flickable {
                id: scrollContent
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: categoriesCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: categoriesCol
                    width: scrollContent.width
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
