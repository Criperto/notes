import QtQuick
import QtQuick.Effects
import Notas
import "."
import "Inline.js" as Inline
import "ImageProbe.js" as ImageProbe
import "PreviewLogic.js" as PreviewLogic

Item {
    id: root

    property string rawText: ""
    property var editor: null
    property var blockData: null
    property int cellUnitIndex: 0
    property int cellAlignment: Text.AlignLeft
    property real fontPixelSize: EditorMetrics.caption
    property bool fontBold: false
    property bool isReadOnly: false

    signal linkClicked(string url)
    signal editRequested()
    signal contextMenuRequested(real mouseX, real mouseY)
    signal cellSelectionActivated(var textEditItem)
    signal previewContextMenuRequested(var textEditItem, real mouseX, real mouseY)

    readonly property string baseFolder: root.editor ? root.editor.imgBaseFolder : ""
    readonly property var segments: Inline.extractTableCellSegments(root.rawText)
    readonly property bool hasMedia: root.segments && root.segments.length > 0
    readonly property real contentHeight: root.hasMedia ? mediaCol.implicitHeight : plainText.paintedHeight

    implicitHeight: contentHeight
    height: implicitHeight

    function _cellPressed(ma, textEdit, mouse) {
        if (!root.isReadOnly) {
            if (mouse.button === Qt.RightButton) {
                root.contextMenuRequested(mouse.x, mouse.y);
            }
            return;
        }
        if (mouse.button === Qt.RightButton) {
            if (textEdit.selectionStart === textEdit.selectionEnd) {
                var rPos = textEdit.positionAt(mouse.x, mouse.y);
                if (rPos >= 0 && rPos <= textEdit.length) {
                    textEdit.cursorPosition = rPos;
                }
            }
            root.cellSelectionActivated(textEdit);
            root.previewContextMenuRequested(textEdit, mouse.x, mouse.y);
            mouse.accepted = true;
            return;
        }
        ma.pressedLink = textEdit.linkAt(mouse.x, mouse.y) || "";
        ma.startX = mouse.x;
        ma.startY = mouse.y;
        ma.didDrag = false;
        ma.dragging = true;
        ma.anchorPos = Math.max(0, Math.min(textEdit.length, textEdit.positionAt(mouse.x, mouse.y)));
        if (textEdit.selectionStart !== textEdit.selectionEnd) {
            textEdit.deselect();
        }
        textEdit.cursorPosition = ma.anchorPos;
        root.cellSelectionActivated(textEdit);
    }

    function _cellMoved(ma, textEdit, mouse) {
        if (!root.isReadOnly || !ma.dragging || ma.anchorPos < 0) return;
        if (!ma.didDrag && Math.abs(mouse.x - ma.startX) < 3 && Math.abs(mouse.y - ma.startY) < 3) return;
        ma.didDrag = true;
        var pos = Math.max(0, Math.min(textEdit.length, textEdit.positionAt(mouse.x, mouse.y)));
        textEdit.select(ma.anchorPos, pos);
        root.cellSelectionActivated(textEdit);
    }

    function _cellReleased(ma, textEdit, mouse) {
        if (mouse.button === Qt.RightButton) return;
        if (!root.isReadOnly) {
            var link = textEdit.linkAt(mouse.x, mouse.y);
            if (link && link !== "") {
                root.linkClicked(link);
                return;
            }
            root.editRequested();
            return;
        }
        var wasDrag = ma.didDrag;
        var pLink = ma.pressedLink;
        ma.dragging = false;
        ma.didDrag = false;
        ma.anchorPos = -1;
        ma.pressedLink = "";
        if (!wasDrag) {
            if (pLink !== "") {
                root.linkClicked(pLink);
            } else if (textEdit.selectionStart !== textEdit.selectionEnd) {
                textEdit.deselect();
            }
        } else if (textEdit.selectionStart !== textEdit.selectionEnd) {
            textEdit.forceActiveFocus();
            root.cellSelectionActivated(textEdit);
        }
    }

    function _cellDoubleClicked(ma, textEdit, mouse) {
        if (!root.isReadOnly || mouse.button !== Qt.LeftButton) return;
        ma.dragging = false;
        ma.didDrag = false;
        ma.anchorPos = -1;
        ma.pressedLink = "";
        textEdit.forceActiveFocus();
        var pos = Math.max(0, Math.min(textEdit.length, textEdit.positionAt(mouse.x, mouse.y)));
        textEdit.cursorPosition = pos;
        textEdit.selectWord();
        root.cellSelectionActivated(textEdit);
    }

    function _cellCanceled(ma) {
        ma.dragging = false;
        ma.didDrag = false;
        ma.anchorPos = -1;
        ma.pressedLink = "";
    }

    function _inlineOpts() {
        return {
            zoom: EditorMetrics.zoom,
            textColor: "" + Theme.text,
            mathColor: "" + Theme.text,
            mathPtSize: Math.max(8.0, EditorMetrics.body * 0.75),
            linkColor: "" + Theme.accent,
            highlightBg: EditorMetrics.highlightBg,
            codeBg: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08),
            codeColor: Theme.text,
            kbdBezel: Theme.lightMode ? "#dcdcdc" : ("" + Theme.accent),
            kbdShadow1: Theme.lightMode ? "#9f9f9f" : ("" + Qt.darker(Theme.accent, 1.55)),
            kbdShadow2: Theme.lightMode ? "#b0b0b0" : ("" + Qt.darker(Theme.accent, 1.25)),
            kbdPlate: Theme.lightMode ? "#ffffff" : ("" + Theme.surface),
            kbdText: Theme.lightMode ? "#1c1c1c" : ("" + Theme.color15),
            fontFamilyMonospace: Theme.fontFamilyMonospace || "JetBrains Mono",
            lightMode: Theme.lightMode,
            baseFolder: root.baseFolder,
            imageSkipMissing: true,
            imageExists: root.editor ? root.editor.imageExistsFn : null,
            probeTick: NotesService.imageProbeSeq,
            searchQuery: root.editor ? root.editor.searchQuery : "",
            searchHighlightBg: root.editor ? ("" + root.editor.searchHighlightColor) : "",
            searchHighlightActiveBg: (root.editor && root.blockData) ? root.editor.searchActiveBg(root.blockData.bid, root.cellUnitIndex) : "",
            searchActiveOrdinal: (root.editor && root.blockData) ? root.editor.searchActiveOrdinal(root.blockData.bid, root.cellUnitIndex) : -1,
            searchHighlightActiveFg: (root.editor && root.blockData) ? root.editor.searchActiveFg(root.blockData.bid, root.cellUnitIndex) : ""
        };
    }

    // ── Vía rápida: celda de solo texto / LaTeX / kbd / enlaces ──────────────
    TextEdit {
        id: plainText
        visible: !root.hasMedia
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        readOnly: true
        cursorVisible: false
        cursorDelegate: Item { width: 0; height: 0 }
        persistentSelection: true
        activeFocusOnTab: false
        selectByMouse: false
        text: !root.hasMedia ? Inline.inlineToHtml(root.rawText, root._inlineOpts()) : ""
        textFormat: TextEdit.RichText
        font.family: Theme.fontFamily
        font.pixelSize: root.fontPixelSize
        font.bold: root.fontBold
        color: Theme.text
        selectionColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
        selectedTextColor: Theme.text
        wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
        horizontalAlignment: root.cellAlignment

        HoverHandler {
            enabled: plainText.visible && plainText.hoveredLink !== ""
            cursorShape: Qt.PointingHandCursor
        }

        MouseArea {
            id: plainMa
            anchors.fill: parent
            enabled: plainText.visible
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: plainText.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
            preventStealing: root.isReadOnly && dragging
            property bool dragging: false
            property bool didDrag: false
            property int anchorPos: -1
            property real startX: 0
            property real startY: 0
            property string pressedLink: ""
            onPressed: (mouse) => root._cellPressed(plainMa, plainText, mouse)
            onPositionChanged: (mouse) => root._cellMoved(plainMa, plainText, mouse)
            onReleased: (mouse) => root._cellReleased(plainMa, plainText, mouse)
            onDoubleClicked: (mouse) => root._cellDoubleClicked(plainMa, plainText, mouse)
            onCanceled: root._cellCanceled(plainMa)
        }
    }

    // ── Vía multimedia: imágenes + texto intercalado con escala de zoom ───────
    Column {
        id: mediaCol
        visible: root.hasMedia
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Math.max(4, Math.round(6 * (EditorMetrics.zoom || 1.0)))

        Repeater {
            model: root.hasMedia ? root.segments : []

            delegate: Item {
                id: segDelegate
                width: mediaCol.width
                implicitHeight: isImageSeg ? imgWrapper.height : segText.paintedHeight
                height: implicitHeight

                readonly property bool isImageSeg: modelData && modelData.type === "image"
                readonly property string imgSrc: isImageSeg ? (modelData.src || "") : ""
                readonly property string imgAlt: isImageSeg ? (modelData.alt || "") : ""
                readonly property string imgLink: isImageSeg ? (modelData.link || "") : ""
                readonly property int reqWidth: (isImageSeg && modelData.width > 0) ? modelData.width : 0
                readonly property int reqHeight: (isImageSeg && modelData.height > 0) ? modelData.height : 0

                TextEdit {
                    id: segText
                    visible: !segDelegate.isImageSeg
                    width: parent.width
                    readOnly: true
                    cursorVisible: false
                    cursorDelegate: Item { width: 0; height: 0 }
                    persistentSelection: true
                    activeFocusOnTab: false
                    selectByMouse: false
                    text: !segDelegate.isImageSeg && modelData ? Inline.inlineToHtml(modelData.text || "", root._inlineOpts()) : ""
                    textFormat: TextEdit.RichText
                    font.family: Theme.fontFamily
                    font.pixelSize: root.fontPixelSize
                    font.bold: root.fontBold
                    color: Theme.text
                    selectionColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
                    selectedTextColor: Theme.text
                    wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                    horizontalAlignment: root.cellAlignment

                    HoverHandler {
                        enabled: segText.visible && segText.hoveredLink !== ""
                        cursorShape: Qt.PointingHandCursor
                    }

                    MouseArea {
                        id: segMa
                        anchors.fill: parent
                        enabled: segText.visible
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: segText.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
                        preventStealing: root.isReadOnly && dragging
                        property bool dragging: false
                        property bool didDrag: false
                        property int anchorPos: -1
                        property real startX: 0
                        property real startY: 0
                        property string pressedLink: ""
                        onPressed: (mouse) => root._cellPressed(segMa, segText, mouse)
                        onPositionChanged: (mouse) => root._cellMoved(segMa, segText, mouse)
                        onReleased: (mouse) => root._cellReleased(segMa, segText, mouse)
                        onDoubleClicked: (mouse) => root._cellDoubleClicked(segMa, segText, mouse)
                        onCanceled: root._cellCanceled(segMa)
                    }
                }

                Item {
                    id: imgWrapper
                    visible: segDelegate.isImageSeg
                    width: targetW
                    height: targetH
                    x: {
                        if (root.cellAlignment === Text.AlignHCenter) return Math.max(0, Math.round((parent.width - width) / 2));
                        if (root.cellAlignment === Text.AlignRight) return Math.max(0, parent.width - width);
                        return 0;
                    }

                    readonly property string imgState: {
                        var _ = NotesService.imageProbeSeq;
                        return segDelegate.isImageSeg
                            ? NotesService.imageStateFor(segDelegate.imgSrc, root.baseFolder)
                            : "no";
                    }
                    readonly property bool loadable: imgState === "yes" || imgState === "remote"
                    readonly property string localPath: segDelegate.isImageSeg
                        ? ImageProbe.resolveLocal(root.baseFolder, segDelegate.imgSrc)
                        : ""
                    readonly property string fileUrl: segDelegate.isImageSeg
                        ? ImageProbe.toFileUrl(root.baseFolder, segDelegate.imgSrc)
                        : ""
                    readonly property real zoomFactor: (typeof EditorMetrics !== "undefined" && EditorMetrics.zoom) ? EditorMetrics.zoom : 1.0
                    readonly property real availW: Math.max(36, segDelegate.width)

                    readonly property var _headerDim: {
                        if (!segDelegate.isImageSeg || !imgWrapper.localPath) return null;
                        var cache = (root.editor && root.editor._imageDimensions) ? root.editor._imageDimensions : null;
                        if (cache && cache[segDelegate.imgSrc] && cache[segDelegate.imgSrc].w > 0 && cache[segDelegate.imgSrc].h > 0) {
                            return cache[segDelegate.imgSrc];
                        }
                        if (typeof Sys !== "undefined" && typeof Sys.imageDimensions === "function") {
                            var dim = Sys.imageDimensions(imgWrapper.localPath);
                            if (dim && dim.valid && dim.width > 0 && dim.height > 0) {
                                return { w: dim.width, h: dim.height };
                            }
                        }
                        return null;
                    }

                    readonly property real naturalW: imgItem.implicitWidth > 0 ? imgItem.implicitWidth : (_headerDim ? _headerDim.w : 0)
                    readonly property real naturalH: imgItem.implicitHeight > 0 ? imgItem.implicitHeight : (_headerDim ? _headerDim.h : 0)
                    readonly property bool isBadge: segDelegate.isImageSeg && (
                        PreviewLogic.isBadgeLike(segDelegate.imgSrc, segDelegate.imgAlt) ||
                        (naturalH > 0 && naturalH <= 36)
                    )
                    readonly property real maxImgH: Math.max(120, Math.round(480 * zoomFactor))

                    readonly property real targetW: {
                        if (segDelegate.reqWidth > 0) {
                            return Math.min(availW, Math.max(24, Math.round(segDelegate.reqWidth * zoomFactor)));
                        }
                        if (isBadge) {
                            return naturalW > 0 ? Math.min(availW, Math.round(naturalW * zoomFactor)) : Math.min(availW, Math.round(120 * zoomFactor));
                        }
                        if (naturalW > 0 && naturalH > 0) {
                            var w = Math.min(availW, Math.round(naturalW * zoomFactor));
                            var h = Math.round(w * (naturalH / naturalW));
                            if (h > maxImgH) {
                                h = maxImgH;
                                w = Math.round(h * (naturalW / naturalH));
                            }
                            return Math.max(24, w);
                        }
                        return Math.min(availW, Math.round(240 * zoomFactor));
                    }

                    readonly property real targetH: {
                        if (imgItem.status === Image.Error || imgState === "no") {
                            return Math.max(Math.round(52 * zoomFactor), errBox.implicitHeight + 12);
                        }
                        if (segDelegate.reqWidth > 0 && segDelegate.reqHeight > 0) {
                            return Math.max(16, Math.round(targetW * segDelegate.reqHeight / segDelegate.reqWidth));
                        }
                        if (isBadge) {
                            return naturalH > 0 ? Math.max(16, Math.round(naturalH * zoomFactor)) : Math.round(24 * zoomFactor);
                        }
                        if (naturalW > 0 && naturalH > 0) {
                            return Math.max(20, Math.min(maxImgH, Math.round(targetW * naturalH / naturalW)));
                        }
                        return Math.round(110 * zoomFactor);
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: imgWrapper.isBadge ? 4 : 6
                        color: imgWrapper.isBadge ? "transparent" : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.03)
                        border.color: imgWrapper.isBadge ? "transparent" : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
                        border.width: imgWrapper.isBadge ? 0 : 1
                        clip: true

                        AnimatedImage {
                            id: imgItem
                            anchors.fill: parent
                            asynchronous: true
                            cache: true
                            fillMode: Image.PreserveAspectFit
                            playing: Theme.animationsEnabled && !GamemodeService.gamemodeActive && root.visible && Qt.application.active
                            paused: GamemodeService.gamemodeActive || !playing
                            source: (segDelegate.isImageSeg && imgWrapper.loadable) ? imgWrapper.fileUrl : ""

                            onStatusChanged: {
                                if (status === Image.Ready && implicitWidth > 0 && implicitHeight > 0) {
                                    if (root.editor && typeof root.editor._storeImageDimension === "function") {
                                        root.editor._storeImageDimension(segDelegate.imgSrc, implicitWidth, implicitHeight);
                                    }
                                }
                            }
                        }

                        Column {
                            id: errBox
                            anchors.centerIn: parent
                            width: Math.max(24, parent.width - 12)
                            spacing: 3
                            visible: segDelegate.isImageSeg && (imgItem.status === Image.Error || imgWrapper.imgState === "no")

                            Image {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 18; height: 18
                                source: Theme.iconsPath + "broken-image.svg"
                                sourceSize: Qt.size(18, 18)
                                layer.enabled: visible && !GamemodeService.gamemodeActive
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: Theme.danger
                                }
                            }

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: I18n.t("notes.image_load_error", "No se pudo cargar la imagen")
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: EditorMetrics.caption
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: segDelegate.isImageSeg
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) {
                                root.contextMenuRequested(mouse.x, mouse.y);
                                return;
                            }
                            if (segDelegate.imgLink !== "") {
                                root.linkClicked(segDelegate.imgLink);
                                return;
                            }
                            if (root.isReadOnly && imgItem.status === Image.Ready && root.editor && typeof root.editor.openImageZoom === "function") {
                                root.editor.openImageZoom(imgItem.source.toString(), imgWrapper, imgWrapper.naturalW, imgWrapper.naturalH);
                                return;
                            }
                            root.editRequested();
                        }
                    }

                    HoverHandler {
                        id: cellImgHover
                        enabled: segDelegate.isImageSeg && imgWrapper.loadable && imgItem.status === Image.Ready && !imgWrapper.isBadge
                    }

                    ImageCopyButton {
                        z: 10
                        available: segDelegate.isImageSeg && imgWrapper.loadable && imgItem.status === Image.Ready && !imgWrapper.isBadge
                        showZoomButton: true
                        hoveredOutside: cellImgHover.hovered
                        localPath: imgWrapper.localPath
                        targetImageItem: imgItem
                        onZoomRequested: {
                            if (root.editor && typeof root.editor.openImageZoom === "function") {
                                root.editor.openImageZoom(imgItem.source.toString(), imgWrapper, imgWrapper.naturalW, imgWrapper.naturalH);
                            }
                        }
                    }
                }
            }
        }
    }
}
