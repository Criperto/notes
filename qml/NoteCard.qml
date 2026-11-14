// NoteCard.qml — Tarjeta de nota con altura dinámica y preview de bloques/imágenes (Fase 9)
import "."
import Notas
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "PreviewLogic.js" as PreviewLogic
import "Inline.js" as Inline

Rectangle {
    id: root

    property var noteData: null
    property bool isMorphing: false
    property bool isCurrent: false

    onPreviewImgUrlChanged: {
        previewImgValid = false;
    }

    opacity: isMorphing ? 0.0 : 1.0
    enabled: !isMorphing

    signal clicked(var cardItem)
    signal contextMenuRequested(var cardItem, var mouse)
    signal deleteRequested
    signal pinToggled

    readonly property bool isHovered: cardMa.containsMouse

    readonly property color cardBgColor: Qt.hsva(Theme.surface.hsvHue,
                                                  Math.min(1, Theme.surface.hsvSaturation),
                                                  Math.min(1, Theme.surface.hsvValue + 0.03),
                                                  0.55)

    radius: 16
    color: cardBgColor

    Accessible.role: Accessible.ListItem
    Accessible.name: (root.noteData && root.noteData.title) ? root.noteData.title : I18n.t("card.untitled", "Sin título")

    border.color: isCurrent
        ? ((Theme.themeMode === "pywal" && Theme.pywalAvailable)
            ? Theme.color2
            : Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.6))
        : Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.08)
    border.width: root.isCurrent ? 1.5 : 1
    clip: true

    // ── F26 (FLIP): desplazamiento de reacomodo. No toca x/y/width/height bindeados
    // y no agrega layer.enabled (ya hay muchas capas). Lo maneja NotesContent.
    transform: Translate { id: slideShift }
    SpringAnimation {
        id: slideAnimX
        target: slideShift
        property: "x"
        to: 0
        spring: 3.0
        damping: 0.45
        mass: 0.9
        epsilon: 0.25
        onStopped: root._slideCleanup()
    }
    SpringAnimation {
        id: slideAnimY
        target: slideShift
        property: "y"
        to: 0
        spring: 3.0
        damping: 0.45
        mass: 0.9
        epsilon: 0.25
        onStopped: root._slideCleanup()
    }
    function _slideCleanup() {
        if (slideAnimX.running || slideAnimY.running) return;
        if (Math.abs(slideShift.x) < 0.5 && Math.abs(slideShift.y) < 0.5) {
            slideShift.x = 0;
            slideShift.y = 0;
        }
        if (root.z > 0 && root.z <= 6) root.z = 0;
    }
    // dx/dy = nuevaPos - fotoAntes (viene de computeSlideDeltas). Se invierte para
    // arrancar en la posición visual previa (la foto ya incluye el shift vigente).
    // delayMs: escalonado en cascada; la tarjeta de abajo espera a que la de arriba
    // empiece a acomodarse y recién entonces sigue su lugar (parte ya desplazada).
    Timer {
        id: slideDelayTimer
        repeat: false
        onTriggered: {
            slideAnimX.start();
            slideAnimY.start();
        }
    }
    function slideFrom(dx, dy, isTop, delayMs) {
        if (!(Theme.animationsEnabled && !GamemodeService.gamemodeActive)) {
            slideShift.x = 0;
            slideShift.y = 0;
            return;
        }
        slideDelayTimer.stop();
        slideAnimX.stop();
        slideAnimY.stop();
        slideShift.x = -dx;
        slideShift.y = -dy;
        root.z = isTop ? 6 : 5;
        if (delayMs > 0) {
            slideDelayTimer.interval = delayMs;
            slideDelayTimer.start();
        } else {
            slideAnimX.start();
            slideAnimY.start();
        }
    }
    function slideCancel() {
        slideDelayTimer.stop();
        slideAnimX.stop();
        slideAnimY.stop();
        slideShift.x = 0;
        slideShift.y = 0;
        if (root.z > 0 && root.z <= 6) root.z = 0;
    }

    // ── Altura dinámica (Masonry, clamp [110, 316]) ─────────────────────────
    implicitHeight: Math.min(316, Math.max(110, cardCol.implicitHeight + 28))
    height: implicitHeight

    // ── Resolución y validación de imagen de preview (carrusel / estática) ───
    readonly property var candidateImageUrls: (NotesConfig.showImagePreviews) ? PreviewLogic.getPreviewImages(root.noteData) : []
    readonly property int candidateCount: candidateImageUrls.length
    readonly property string previewImgUrl: candidateCount > 0 ? candidateImageUrls[0] : ""
    property bool previewImgValid: false

    property int currentImageIdx: 0
    property bool isLayerATop: true

    onCandidateImageUrlsChanged: {
        currentImageIdx = 0;
        isLayerATop = true;
        previewImgValid = false;
        if (candidateCount > 0 && imgLayerA) {
            imgLayerA.source = root.resolveImgSource(candidateImageUrls[0]);
            imgLayerB.source = "";
        }
    }

    onPreviewImgValidChanged: {
        if (previewImgValid && candidateCount > 0 && imgLayerA) {
            imgLayerA.source = root.resolveImgSource(candidateImageUrls[0]);
        }
    }

    Timer {
        id: cycleTimer
        interval: 3000
        repeat: true
        running: NotesConfig.showImagePreviews && NotesConfig.cyclePreviewImages && root.candidateCount > 1 && !root.isMorphing && root.previewImgValid
        onTriggered: {
            var nextIdx = (root.currentImageIdx + 1) % root.candidateCount;
            root.currentImageIdx = nextIdx;
            var nextSrc = root.resolveImgSource(root.candidateImageUrls[nextIdx]);
            if (root.isLayerATop) {
                imgLayerB.source = nextSrc;
                root.isLayerATop = false;
            } else {
                imgLayerA.source = nextSrc;
                root.isLayerATop = true;
            }
        }
    }

    readonly property var visibleTags: {
        if (!root.noteData || !root.noteData.tags || !Array.isArray(root.noteData.tags)) return [];
        var t = root.noteData.tags;
        if (t.length <= 3) return t;
        return [t[0], t[1], t[2], "+" + (t.length - 3)];
    }

    readonly property bool isTxt: !!(root.noteData && root.noteData.format === "txt")

    readonly property string baseFileName: {
        if (!root.noteData || !root.noteData.fileName) return "";
        var fn = root.noteData.fileName;
        if (/\.md$/i.test(fn)) fn = fn.substring(0, fn.length - 3);
        else if (/\.txt$/i.test(fn)) fn = fn.substring(0, fn.length - 4);
        return fn;
    }

    readonly property bool showFileName: {
        if (!root.noteData) return false;
        var rawTitle = root.noteData.title || "";
        return root.baseFileName !== "" && root.baseFileName !== rawTitle;
    }

    function resolveImgSource(src) {
        if (!src) return "";
        if (src.startsWith("http://") || src.startsWith("https://") || src.startsWith("file://")) {
            return src;
        }
        if (src.startsWith("/")) {
            return "file://" + encodeURI(src);
        }
        var baseDir = NotesService.notesDir;
        if (root.noteData && root.noteData.baseFolder) {
            baseDir = root.noteData.baseFolder;
        }
        return "file://" + encodeURI(baseDir + "/" + src);
    }

    Image {
        id: candidateImage
        visible: false
        asynchronous: true
        cache: false
        // Solo se intenta cargar si existe (o es remota); si no, ni se pide
        // y no hay warning "Cannot open". imageStateFor re-evalúa al completar
        // el probe (imageProbeReady/_imageExists).
        source: {
            if (!NotesConfig.showImagePreviews || !root.previewImgUrl) return "";
            var base = (root.noteData && root.noteData.baseFolder) ? root.noteData.baseFolder : NotesService.notesDir;
            var st = NotesService.imageStateFor(root.previewImgUrl, base);
            return (st === "yes" || st === "remote") ? root.resolveImgSource(root.previewImgUrl) : "";
        }
        onStatusChanged: {
            if (status === Image.Ready) {
                var w = implicitWidth;
                var h = implicitHeight;
                var aspect = w / Math.max(1, h);
                if (w >= PreviewLogic.PREVIEW_IMG_MIN_W && h >= PreviewLogic.PREVIEW_IMG_MIN_H && aspect <= PreviewLogic.PREVIEW_IMG_MAX_ASPECT) {
                    root.previewImgValid = true;
                } else if (root.previewImgUrl.startsWith("assets/") || root.previewImgUrl.startsWith("/")) {
                    root.previewImgValid = true;
                } else {
                    root.previewImgValid = false;
                }
            } else if (status === Image.Error || status === Image.Null) {
                root.previewImgValid = false;
            }
        }
    }

    MouseArea {
        id: cardMa
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                root.contextMenuRequested(root, mouse);
                return;
            }
            if (NotesService.debug) console.log("[NoteCard] Clic para abrir tarjeta:", root.noteData ? (root.noteData.slug || root.noteData.title) : "sin datos");
            root.clicked(root);
        }
    }

    ColumnLayout {
        id: cardCol
        anchors.fill: parent
        anchors.margins: 14
        spacing: 0

        // ── Encabezado de la tarjeta (Título y Subtítulo) ────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    readonly property string rawTitle: root.noteData ? (root.noteData.title || I18n.t("notes.card.untitled", "Sin título")) : I18n.t("notes.card.untitled", "Sin título")
                    text: (NotesService.searchQuery && NotesService.searchQuery.trim() !== "")
                        ? Inline.highlightInHtml(Inline.escapeHtml(rawTitle), NotesService.searchQuery, Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35))
                        : rawTitle
                    textFormat: (NotesService.searchQuery && NotesService.searchQuery.trim() !== "") ? Text.RichText : Text.PlainText
                    color: Theme.text
                    font.family: Theme.fontFamilyDisplay
                    font.pixelSize: Theme.fontSizeTitle - 1
                    font.bold: true
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    maximumLineCount: 2
                }

                Text {
                    Layout.fillWidth: true
                    // Subtítulo limpio (sin >, #, **, viñetas ni links crudos)
                    text: PreviewLogic.cleanSubtitle(root.noteData ? (root.noteData.subtitle || "") : "")
                    color: Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.8)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody - 1
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    visible: text !== ""
                }
            }

            // Badge discreto TXT
            Rectangle {
                visible: root.isTxt
                Layout.preferredWidth: 34
                Layout.preferredHeight: 18
                radius: 4
                color: Qt.rgba(Theme.muted.r, Theme.muted.g, Theme.muted.b, 0.16)
                border.color: Qt.rgba(Theme.muted.r, Theme.muted.g, Theme.muted.b, 0.35)
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "TXT"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeCaption - 2
                    font.bold: true
                }
            }

            // Botón Fijar / Pin — siempre en el layout, fade de opacidad
            Rectangle {
                width: 28; height: 28; radius: 8
                color: pinMa.containsMouse ? Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.22) : "transparent"
                opacity: (root.noteData && root.noteData.pinned) ? 1.0 : (root.isHovered || root.isCurrent || pinMa.containsMouse ? 1.0 : 0.0)

                Behavior on opacity {
                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }

                Behavior on color {
                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                    ColorAnimation { duration: 140 }
                }

                Image {
                    anchors.centerIn: parent
                    width: 14; height: 14
                    source: Theme.iconsPath + "push-pin.svg"
                    sourceSize: Qt.size(14, 14)
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: pinMa.containsMouse ? Theme.accent : (root.noteData && root.noteData.pinned ? Theme.accent : Theme.muted)
                        Behavior on colorizationColor {
                            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                            ColorAnimation { duration: 140 }
                        }
                    }
                }

                MouseArea {
                    id: pinMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (mouse) => {
                        mouse.accepted = true;
                        if (NotesService.debug) console.log("[NoteCard] Clic en fijar/desfijar para:", root.noteData ? root.noteData.slug : "sin datos");
                        root.pinToggled();
                    }
                }
            }
        }

        // Espaciador superior
        Item { Layout.preferredHeight: 8 }

        // ── Contenedor recortado de preview con degradado de opacidad puro (Fase 9) ──
        Item {
            id: previewContainer
            Layout.fillWidth: true
            Layout.fillHeight: !root.previewImgValid
            implicitHeight: Math.min(root.previewImgValid ? 60 : 136, previewTextItem.implicitHeight)
            clip: true
            visible: previewTextItem.text.length > 0

            readonly property bool isOverflowing: previewTextItem.implicitHeight > height

            Item {
                id: textLayerItem
                anchors.fill: parent

                Text {
                    id: previewTextItem
                    width: parent.width
                    readonly property string rawPreview: root.noteData ? (root.noteData.preview || (root.noteData.body || "").substring(0, 400)) : ""
                    // Sin el bloque ya usado como subtítulo y sin
                    // sintaxis propia (==, [[ ]], imágenes); el markdown común
                    // lo renderiza MarkdownText. En .txt va literal escapado.
                    readonly property string dedupPreview: root.isTxt ? rawPreview : PreviewLogic.stripDuplicateLead(rawPreview, root.noteData ? (root.noteData.subtitle || "") : "")
                    readonly property string paintPreview: root.isTxt ? Inline.escapeHtml(dedupPreview) : PreviewLogic.cleanCardText(dedupPreview)
                    readonly property bool hasGridQuery: NotesService.searchQuery && NotesService.searchQuery.trim() !== ""
                    text: previewTextItem.hasGridQuery
                        ? Inline.highlightInHtml(paintPreview, NotesService.searchQuery, Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35))
                        : paintPreview
                    textFormat: (previewTextItem.hasGridQuery || root.isTxt) ? Text.RichText : Text.MarkdownText
                    color: Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.85)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.Wrap
                }

                layer.enabled: previewContainer.isOverflowing
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: previewMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }
            }

            Item {
                id: previewMask
                anchors.fill: parent
                visible: false
                layer.enabled: true

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#ffffffff" }
                        GradientStop { position: 0.65; color: "#ffffffff" }
                        GradientStop { position: 1.0; color: "#00ffffff" }
                    }
                }
            }
        }

        // Espaciador si hay imagen válida
        Item {
            Layout.preferredHeight: 8
            visible: NotesConfig.showImagePreviews && root.previewImgValid
        }

        // ── Previsualización de imagen válida (Debajo del texto con ClippingRectangle y Fade) ───────────
        ClippingRectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 120
            radius: 8
            clip: true
            visible: NotesConfig.showImagePreviews && root.previewImgValid
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04)

            Image {
                id: imgLayerA
                anchors.fill: parent
                source: (root.candidateCount > 0 && root.previewImgValid) ? root.resolveImgSource(root.candidateImageUrls[0]) : ""
                sourceSize.width: 600
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: root.isLayerATop ? 1.0 : 0.0

                Behavior on opacity {
                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                    NumberAnimation { duration: 400; easing.type: Easing.InOutQuad }
                }
            }

            Image {
                id: imgLayerB
                anchors.fill: parent
                sourceSize.width: 600
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: root.isLayerATop ? 0.0 : 1.0

                Behavior on opacity {
                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                    NumberAnimation { duration: 400; easing.type: Easing.InOutQuad }
                }
            }
        }

        // Espaciador inferior
        Item { Layout.preferredHeight: 8 }

        // ── Línea divisoria sutil ─────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.08)
        }

        // ── Etiquetas / Tags de la nota ───────────────────────────────────
        Flow {
            Layout.fillWidth: true
            spacing: 4
            visible: root.visibleTags.length > 0

            Repeater {
                model: root.visibleTags
                Rectangle {
                    height: 18
                    radius: 4
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                    width: tagLabel.implicitWidth + 8

                    Text {
                        id: tagLabel
                        anchors.centerIn: parent
                        text: String(modelData).startsWith("+") ? String(modelData) : ("#" + modelData)
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeCaption - 1
                    }
                }
            }
        }

        Item {
            Layout.preferredHeight: root.visibleTags.length > 0 ? 6 : 0
            visible: Layout.preferredHeight > 0
        }

        // ── Información del archivo (Footer) ──────────────────────────────
        // Aire extra sobre la fila (≥8px de la divisoria) y entre el texto
        // y el botón (≥12px); el hover (28px) ya queda a 14px del borde.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: root.baseFileName
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall - 1
                    font.bold: false
                    elide: Text.ElideRight
                    visible: root.showFileName
                }

                Text {
                    Layout.fillWidth: true
                    text: root.noteData ? PreviewLogic.formatRelative(root.noteData.fileModified || root.noteData.modified || root.noteData.created || "") : ""
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall - 1
                    elide: Text.ElideRight
                }
            }

            // Botón eliminar tarjeta — siempre en layout, fade de opacidad
            Rectangle {
                width: 28; height: 28; radius: 8
                color: delMa.containsMouse ? Qt.rgba(1, 0.2, 0.2, 0.22) : "transparent"
                opacity: (root.isHovered || root.isCurrent || delMa.containsMouse) ? 1.0 : 0.0

                Behavior on opacity {
                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }

                Behavior on color {
                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                    ColorAnimation { duration: 140 }
                }

                Image {
                    anchors.centerIn: parent
                    width: 12; height: 12
                    source: Theme.iconsPath + "delete.svg"
                    sourceSize: Qt.size(12, 12)
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: delMa.containsMouse ? Theme.danger : Theme.muted
                        Behavior on colorizationColor {
                            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                            ColorAnimation { duration: 140 }
                        }
                    }
                }

                MouseArea {
                    id: delMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (mouse) => {
                        mouse.accepted = true;
                        if (NotesService.debug) console.log("[NoteCard] Clic en borrar tarjeta para:", root.noteData ? root.noteData.slug : "sin datos");
                        root.deleteRequested();
                    }
                }
            }
        }
    }
}
