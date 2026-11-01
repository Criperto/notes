import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Notas

Rectangle {
    id: root
    visible: opacity > 0
    opacity: 0

    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.55)

    Behavior on opacity {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    signal closed()

    function open() {
        opacity = 1;
        tabIndex = 0;
    }

    function close() {
        opacity = 0;
        closed();
    }

    property int tabIndex: 0
    readonly property var tabs: [
        { id: "editor", title: I18n.t("config.tabs.editor", "Editor"), icon: "edit.svg" },
        { id: "appearance", title: I18n.t("config.tabs.appearance", "Apariencia"), icon: "settings.svg" },
        { id: "language", title: I18n.t("config.tabs.language", "Idioma y Corrección"), icon: "spellcheck.svg" },
        { id: "about", title: I18n.t("config.tabs.about", "Acerca de"), icon: "info.svg" }
    ]

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    // Modal Card
    Rectangle {
        id: card
        width: Math.min(parent.width - 48, 760)
        height: Math.min(parent.height - 48, 560)
        anchors.centerIn: parent
        radius: 16
        color: Theme.surface
        border.color: Theme.border
        border.width: 1

        MouseArea {
            anchors.fill: parent
            // Consumir clics para no cerrar al clickear la tarjeta
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: I18n.t("config.modal.title", "Configuración de Notas")
                    font.family: Theme.fontFamilyDisplay
                    font.pixelSize: Theme.fontSizeTitle
                    font.bold: true
                    color: Theme.text
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 32
                    height: 32
                    radius: 8
                    color: closeArea.containsMouse ? Theme.surfaceHover : "transparent"

                    Image {
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        source: Theme.iconsPath + "close.svg"
                        sourceSize: Qt.size(18, 18)
                    }

                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
                    }
                }
            }

            // Tabs Bar
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: root.tabs
                    delegate: Rectangle {
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        height: 36
                        radius: 8
                        color: root.tabIndex === index ? Theme.surfaceActive : (tabArea.containsMouse ? Theme.surfaceHover : "transparent")

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            Image {
                                width: 16
                                height: 16
                                source: Theme.iconsPath + modelData.icon
                                sourceSize: Qt.size(16, 16)
                            }

                            Text {
                                text: modelData.title
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                font.bold: root.tabIndex === index
                                color: root.tabIndex === index ? Theme.primary : Theme.text
                            }
                        }

                        MouseArea {
                            id: tabArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.tabIndex = index
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.border
            }

            // Tab Content Body
            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.tabIndex

                // Tab 0: Editor
                ColumnLayout {
                    spacing: 16

                    Text {
                        text: I18n.t("config.notes.dir", "Carpeta de notas")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                        color: Theme.text
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 40
                        radius: 8
                        color: Theme.surfaceHover
                        border.color: Theme.border
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12

                            Text {
                                Layout.fillWidth: true
                                text: ConfigBackend.notasDir
                                color: Theme.text
                                font.family: Theme.fontFamilyMonospace
                                font.pixelSize: Theme.fontSizeBody
                                elide: Text.ElideMiddle
                            }
                        }
                    }

                    // Toggles
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: I18n.t("config.notes.show_image_previews", "Previsualizar imágenes en tarjetas")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.text
                        }
                        Item { Layout.fillWidth: true }
                        CheckBox {
                            checked: ConfigBackend.showImagePreviews
                            onToggled: ConfigBackend.showImagePreviews = checked
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: I18n.t("config.notes.cycle_preview_images", "Alternar imágenes de vista previa")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.text
                        }
                        Item { Layout.fillWidth: true }
                        CheckBox {
                            checked: ConfigBackend.cyclePreviewImages
                            enabled: ConfigBackend.showImagePreviews
                            onToggled: ConfigBackend.cyclePreviewImages = checked
                        }
                    }

                    // Zoom
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: I18n.t("config.notes.editor_zoom", "Zoom del editor") + ": " + ConfigBackend.editorZoom + "%"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.text
                        }
                        Item { Layout.fillWidth: true }
                        Slider {
                            from: 50
                            to: 200
                            stepSize: 10
                            value: ConfigBackend.editorZoom
                            onMoved: ConfigBackend.editorZoom = Math.round(value)
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                // Tab 1: Apariencia
                ColumnLayout {
                    spacing: 16

                    Text {
                        text: I18n.t("config.appearance.theme", "Modo de color")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                        color: Theme.text
                    }

                    RowLayout {
                        spacing: 12
                        Repeater {
                            model: [
                                { id: "system", label: "Sistema" },
                                { id: "dark", label: "Oscuro" },
                                { id: "light", label: "Claro" },
                                { id: "pywal", label: "Pywal" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                width: 110
                                height: 38
                                radius: 8
                                color: ConfigBackend.themeMode === modelData.id ? Theme.surfaceActive : Theme.surfaceHover
                                border.color: ConfigBackend.themeMode === modelData.id ? Theme.primary : Theme.border
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: ConfigBackend.themeMode === modelData.id ? Theme.primary : Theme.text
                                    font.bold: ConfigBackend.themeMode === modelData.id
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ConfigBackend.themeMode = modelData.id
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: I18n.t("config.appearance.blur", "Efecto de desenfoque (Blur)")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.text
                        }
                        Item { Layout.fillWidth: true }
                        CheckBox {
                            checked: ConfigBackend.blurEnabled
                            onToggled: ConfigBackend.blurEnabled = checked
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: I18n.t("config.appearance.hide_scrollbars", "Ocultar barras de desplazamiento")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.text
                        }
                        Item { Layout.fillWidth: true }
                        CheckBox {
                            checked: ConfigBackend.hideScrollbars
                            onToggled: ConfigBackend.hideScrollbars = checked
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                // Tab 2: Idioma y Ortografía
                ColumnLayout {
                    spacing: 16

                    Text {
                        text: I18n.t("config.language.interface", "Idioma de la interfaz")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                        color: Theme.text
                    }

                    RowLayout {
                        spacing: 8
                        Repeater {
                            model: [
                                { code: "es_ar", name: "Español (AR)" },
                                { code: "es_es", name: "Español (ES)" },
                                { code: "en", name: "English" },
                                { code: "de", name: "Deutsch" },
                                { code: "fr", name: "Français" },
                                { code: "ja", name: "日本語" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                width: 105
                                height: 34
                                radius: 8
                                color: I18n.currentLanguage === modelData.code ? Theme.surfaceActive : Theme.surfaceHover
                                border.color: I18n.currentLanguage === modelData.code ? Theme.primary : Theme.border
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.name
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: I18n.currentLanguage === modelData.code ? Theme.primary : Theme.text
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        I18n.setLanguage(modelData.code);
                                        ConfigBackend.language = modelData.code;
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: I18n.t("config.notes.spellcheck_enabled", "Corrector ortográfico activado")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.text
                        }
                        Item { Layout.fillWidth: true }
                        CheckBox {
                            checked: ConfigBackend.spellCheckEnabled
                            onToggled: ConfigBackend.spellCheckEnabled = checked
                        }
                    }

                    Text {
                        text: "Diccionarios Hunspell disponibles en el sistema: " + SpellBackend.availableDictionaries.join(", ")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.muted
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "Palabras en tu diccionario personal: " + SpellBackend.personalWords().length
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.muted
                    }

                    Item { Layout.fillHeight: true }
                }

                // Tab 3: Acerca de & Licencia
                ColumnLayout {
                    spacing: 12

                    RowLayout {
                        spacing: 16
                        Rectangle {
                            width: 64
                            height: 64
                            radius: 14
                            color: Theme.surfaceHover

                            Image {
                                anchors.centerIn: parent
                                width: 48
                                height: 48
                                source: "qrc:/qt/qml/Notas/assets/icons/dev.criperto.Notas.svg"
                                sourceSize: Qt.size(48, 48)
                            }
                        }

                        ColumnLayout {
                            spacing: 4
                            Text {
                                text: "Notas"
                                font.family: Theme.fontFamilyDisplay
                                font.pixelSize: Theme.fontSizeTitle
                                font.bold: true
                                color: Theme.text
                            }
                            Text {
                                text: "dev.criperto.Notas • Versión 0.1.0"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.muted
                            }
                            Text {
                                text: "Licencia: GNU General Public License v3.0 or later (GPL-3.0-or-later)"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                                color: Theme.primary
                            }
                        }
                    }

                    Text {
                        text: "Aplicación nativa de notas en Markdown con editor de bloques tipográfico, previsualización en vivo Typora-style, diagrama Mermaid interactivo y persistencia segura en disco."
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.text
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: Theme.surfaceHover
                        border.color: Theme.border
                        border.width: 1

                        Flickable {
                            id: licFlick
                            anchors.fill: parent
                            anchors.margins: 12
                            contentWidth: width - 16
                            contentHeight: licText.implicitHeight
                            clip: true

                            Text {
                                id: licText
                                width: licFlick.contentWidth
                                text: "Este programa es software libre: puede redistribuirlo y/o modificarlo bajo los términos de la Licencia Pública General GNU publicada por la Free Software Foundation, ya sea la versión 3 de la Licencia, o (a su elección) cualquier versión posterior.\n\nEste programa se distribuye con la esperanza de que sea útil, pero SIN NINGUNA GARANTÍA; ni siquiera la garantía implícita de COMERCIABILIDAD o IDONEIDAD PARA UN PROPÓSITO PARTICULAR. Consulte la Licencia Pública General GNU para obtener más detalles.\n\nCopyright (C) 2026 Tomas <dev@criperto.com>"
                                color: Theme.muted
                                font.family: Theme.fontFamilyMonospace
                                font.pixelSize: Theme.fontSizeSmall
                                wrapMode: Text.WordWrap
                            }

                            CustomScrollBar {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                            }
                        }
                    }
                }
            }
        }
    }
}
