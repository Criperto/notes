// WebClipModal.qml — Modal interactivo para capturar páginas web y artículos a Markdown
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
    z: 9998

    signal closed()
    signal noteClipped(var result)

    property bool isOpen: false
    property bool isClosing: false
    property bool isClipping: false
    property string errorMessage: ""

    property bool downloadImages: true
    property bool mainContentOnly: true

    Behavior on opacity {
        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    function open(initialUrl) {
        errorMessage = "";
        isClipping = false;
        var toUse = (initialUrl && typeof initialUrl === "string") ? initialUrl.trim() : "";
        if (!toUse) {
            var clip = (typeof Quickshell !== "undefined" && Quickshell.clipboardText) ? Quickshell.clipboardText.trim() : "";
            if (clip.startsWith("http://") || clip.startsWith("https://")) {
                toUse = clip;
            }
        }
        urlInput.text = toUse;
        isOpen = true;
        isClosing = false;
        urlInput.forceActiveFocus();
        if (toUse) {
            urlInput.selectAll();
        }
    }

    function close() {
        if (isClipping) return;
        isClosing = true;
        closeTimer.restart();
    }

    Timer {
        id: closeTimer
        interval: 180
        onTriggered: {
            root.isOpen = false;
            root.isClosing = false;
            root.closed();
        }
    }

    function startClip() {
        var u = urlInput.text.trim();
        if (!u || isClipping) return;
        if (!u.startsWith("http://") && !u.startsWith("https://")) {
            u = "https://" + u;
            urlInput.text = u;
        }

        errorMessage = "";
        isClipping = true;

        NotesService.clipWebUrl(u, {
            downloadImages: root.downloadImages,
            fullMode: !root.mainContentOnly
        }, function(ok, res) {
            root.isClipping = false;
            if (ok && res && res.ok) {
                root.noteClipped(res);
                root.close();
            } else {
                root.errorMessage = (res && res.error) ? res.error : I18n.t("notes.clip.error_generic", "No se pudo recortar la página web.");
            }
        });
    }

    // ── Fondo oscuro y desenfoque ─────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (!root.isClipping) root.close();
            }
        }
    }

    // ── Tarjeta central ───────────────────────────────────────────────────
    ClippingRectangle {
        id: dialogCard
        anchors.centerIn: parent
        width: Math.min(500, parent.width - 40)
        height: cardCol.implicitHeight + 40
        radius: 18
        color: Theme.surfaceContainer
        border.color: Theme.outlineVariant
        border.width: 1

        scale: (root.isOpen && !root.isClosing) ? 1.0 : 0.94
        Behavior on scale {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            SpringAnimation {
                spring: 4.5
                damping: 0.75
                mass: 0.6
                epsilon: 0.01
            }
        }

        MouseArea {
            anchors.fill: parent
            // Evita que el clic en la tarjeta cierre el modal
            onClicked: {}
        }

        ColumnLayout {
            id: cardCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 20
            spacing: 16

            // Encabezado
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: 10
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16)

                    Image {
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        source: Theme.iconsPath + "web-clip.svg"
                        sourceSize: Qt.size(22, 22)
                        smooth: true
                        mipmap: true
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: Theme.primary
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: I18n.t("notes.clip.title", "Clipper web")
                        color: Theme.text
                        font.family: Theme.fontFamilyDisplay
                        font.pixelSize: Theme.fontSizeTitle
                        font.bold: true
                    }

                    Text {
                        text: I18n.t("notes.clip.subtitle", "Descarga y limpia artículos a Markdown offline")
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                // Botón Cerrar (X)
                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 8
                    color: closeMa.containsMouse ? Theme.surfaceContainerHigh : "transparent"

                    Image {
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        source: Theme.iconsPath + "close.svg"
                        sourceSize: Qt.size(18, 18)
                        smooth: true
                        mipmap: true
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: closeMa.containsMouse ? Theme.text : Theme.textSecondary
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

            // Separador horizontal sutil
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.outlineVariant
                opacity: 0.5
            }

            // Campo de entrada de URL
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: I18n.t("notes.clip.url_label", "Dirección web (URL)")
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    font.bold: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: 10
                    color: Theme.surface
                    border.color: urlInput.activeFocus ? Theme.primary : Theme.outlineVariant
                    border.width: urlInput.activeFocus ? 2 : 1

                    Behavior on border.color {
                        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                        ColorAnimation { duration: 140 }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        spacing: 8

                        Image {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            source: Theme.iconsPath + "link.svg"
                            sourceSize: Qt.size(20, 20)
                            smooth: true
                            mipmap: true
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: urlInput.activeFocus ? Theme.primary : Theme.textSecondary
                            }
                        }

                        TextInput {
                            id: urlInput
                            Layout.fillWidth: true
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            selectByMouse: true
                            selectionColor: Theme.primary
                            selectedTextColor: Theme.textOn(Theme.primary)
                            clip: true
                            enabled: !root.isClipping

                            CustomTextCursor {}

                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 1
                                text: I18n.t("notes.clip.placeholder", "https://ejemplo.com/articulo")
                                color: Theme.textTertiary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                visible: !urlInput.text && !urlInput.inputMethodComposing
                            }

                            Keys.onReturnPressed: root.startClip()
                            Keys.onEnterPressed: root.startClip()
                            Keys.onEscapePressed: root.close()
                        }

                        // Botón de pegar desde portapapeles
                        Rectangle {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            radius: 6
                            color: pasteMa.containsMouse ? Theme.surfaceContainerHigh : "transparent"
                            visible: !root.isClipping

                            Image {
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                source: Theme.iconsPath + "content-paste.svg"
                                sourceSize: Qt.size(16, 16)
                                smooth: true
                                mipmap: true
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: Theme.textSecondary
                                }
                            }

                            MouseArea {
                                id: pasteMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (typeof Quickshell !== "undefined" && Quickshell.clipboardText) {
                                        urlInput.text = Quickshell.clipboardText.trim();
                                        urlInput.forceActiveFocus();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Opciones de configuración (Checkboxes)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                // Opción 1: Descargar imágenes
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    radius: 8
                    color: imgOptMa.containsMouse ? Theme.surfaceContainerHigh : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        anchors.rightMargin: 8
                        spacing: 10

                        Image {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            source: Theme.iconsPath + (root.downloadImages ? "check-box.svg" : "check-box-outline-blank.svg")
                            sourceSize: Qt.size(20, 20)
                            smooth: true
                            mipmap: true
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: root.downloadImages ? Theme.primary : Theme.textSecondary
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: I18n.t("notes.clip.opt_images", "Descargar imágenes a la carpeta de la nota (offline)")
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody - 1
                        }
                    }

                    MouseArea {
                        id: imgOptMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: !root.isClipping
                        onClicked: root.downloadImages = !root.downloadImages
                    }
                }

                // Opción 2: Solo contenido principal
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    radius: 8
                    color: contentOptMa.containsMouse ? Theme.surfaceContainerHigh : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        anchors.rightMargin: 8
                        spacing: 10

                        Image {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            source: Theme.iconsPath + (root.mainContentOnly ? "check-box.svg" : "check-box-outline-blank.svg")
                            sourceSize: Qt.size(20, 20)
                            smooth: true
                            mipmap: true
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: root.mainContentOnly ? Theme.primary : Theme.textSecondary
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: I18n.t("notes.clip.opt_readability", "Extraer solo el artículo principal (modo lectura)")
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody - 1
                        }
                    }

                    MouseArea {
                        id: contentOptMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: !root.isClipping
                        onClicked: root.mainContentOnly = !root.mainContentOnly
                    }
                }
            }

            // Banner de error (si ocurre alguno)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: errorText.implicitHeight + 16
                radius: 8
                color: Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.12)
                border.color: Theme.red
                border.width: 1
                visible: root.errorMessage !== ""

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    Image {
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                        source: Theme.iconsPath + "error.svg"
                        sourceSize: Qt.size(18, 18)
                        smooth: true
                        mipmap: true
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: Theme.red
                        }
                    }

                    Text {
                        id: errorText
                        Layout.fillWidth: true
                        text: root.errorMessage
                        color: Theme.red
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.Wrap
                    }
                }
            }

            // Indicador de progreso (mientras descarga)
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                visible: root.isClipping

                Image {
                    id: loadingSpinner
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    source: Theme.iconsPath + "refresh.svg"
                    sourceSize: Qt.size(20, 20)
                    smooth: true
                    mipmap: true
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: Theme.primary
                    }

                    // NumberAnimation estándar para evitar coil whine y loops de render thread
                    NumberAnimation on rotation {
                        from: 0
                        to: 360
                        duration: 1000
                        loops: Animation.Infinite
                        running: root.isClipping && Theme.animationsEnabled && !GamemodeService.gamemodeActive
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: I18n.t("notes.clip.loading", "Descargando y procesando contenido web...")
                    color: Theme.primary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }
            }

            // Botones de acción inferiores
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 12

                Item { Layout.fillWidth: true }

                // Botón Cancelar
                Rectangle {
                    Layout.preferredWidth: cancelText.implicitWidth + 28
                    Layout.preferredHeight: 38
                    radius: 10
                    color: cancelMa.containsMouse ? Theme.surfaceContainerHigh : "transparent"
                    border.color: Theme.outlineVariant
                    border.width: 1
                    enabled: !root.isClipping

                    Text {
                        id: cancelText
                        anchors.centerIn: parent
                        text: I18n.t("notes.clip.cancel", "Cancelar")
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        font.bold: true
                    }

                    MouseArea {
                        id: cancelMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
                    }
                }

                // Botón Recortar
                Rectangle {
                    readonly property bool canClip: urlInput.text.trim().length > 0 && !root.isClipping
                    Layout.preferredWidth: clipBtnText.implicitWidth + 32
                    Layout.preferredHeight: 38
                    radius: 10
                    color: canClip ? (clipBtnMa.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary) : Theme.surfaceContainerHigh
                    opacity: canClip ? 1.0 : 0.6

                    Behavior on color {
                        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                        ColorAnimation { duration: 120 }
                    }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        Image {
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 18
                            source: Theme.iconsPath + "web-clip.svg"
                            sourceSize: Qt.size(18, 18)
                            smooth: true
                            mipmap: true
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: parent.parent.canClip ? Theme.textOn(Theme.primary) : Theme.textSecondary
                            }
                        }

                        Text {
                            id: clipBtnText
                            text: I18n.t("notes.clip.action", "Recortar")
                            color: parent.parent.canClip ? Theme.textOn(Theme.primary) : Theme.textSecondary
                            font.family: Theme.fontFamilyDisplay
                            font.pixelSize: Theme.fontSizeBody
                            font.bold: true
                        }
                    }

                    MouseArea {
                        id: clipBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: parent.canClip ? Qt.PointingHandCursor : Qt.ArrowCursor
                        enabled: parent.canClip
                        onClicked: root.startClip()
                    }
                }
            }
        }
    }

    Shortcut {
        sequence: "Esc"
        enabled: root.isOpen && !root.isClosing && !root.isClipping
        onActivated: root.close()
    }
}
