import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Notas
import "."
import "PreviewLogic.js" as PreviewLogic

Item {
    id: root

    property var blockData: null
    property bool isEditing: false
    property var editor: null
    property bool showRawSource: false
    property bool isSelected: false
    property bool inViewportChunk: true

    function selectRange(start, end) {}
    function selectAllText() {}
    function clearTextSelection() {}
    function getCharPosAt(lx, ly) { return 0; }
    function getTextLength() { return root.blockData ? (root.blockData.raw || "").length : 0; }
    function getSelectedText() { return root.blockData ? (root.blockData.raw || "") : ""; }
    function getTextContent() { return root.blockData ? (root.blockData.raw || "") : ""; }
    function deleteSelectedText() {}

    property int _cardsReadySeq: 0
    function notifyCardReady() {
        _cardsReadySeq++;
    }

    readonly property bool isRawActive: root.showRawSource || root.imagesList.length === 0
    readonly property bool isLayoutReady: {
        var _ = _cardsReadySeq;
        if (isRawActive || imagesList.length === 0) return true;
        for (var i = 0; i < imagesList.length; i++) {
            var src = imagesList[i].src;
            var cachedDim = (root.editor && root.editor._imageDimensions) ? root.editor._imageDimensions[src] : null;
            if (cachedDim && cachedDim.w > 0 && cachedDim.h > 0) continue;
            var card = imagesRepeater ? imagesRepeater.itemAt(i) : null;
            if (!card || !card.isCardReady) return false;
        }
        return true;
    }

    onIsEditingChanged: {
        if (!root.isEditing) {
            root.showRawSource = false;
        } else {
            if (!root.isRawActive && imageFocusProxy) {
                imageFocusProxy.forceActiveFocus();
            }
        }
    }

    readonly property var imagesList: {
        if (!blockData || !blockData.raw) return [];
        var res = [];
        var regex = /(?:\[!\[([^\]]*)\]\(([^)]+)\)\]\(([^)]+)\)|!\[([^\]]*)\]\(([^)]+)\))/g;
        var m;
        while ((m = regex.exec(blockData.raw)) !== null) {
            res.push({
                alt: m[1] || m[4] || "",
                src: m[2] || m[5] || "",
                link: m[3] || ""
            });
        }
        return res;
    }

    readonly property string imgBaseDir: {
        var _ = NotesService.filesVersion;
        return NotesService.resolveNoteBaseDir(NotesService.activeNote);
    }

    implicitWidth: parent ? parent.width : 400
    implicitHeight: isRawActive ? (rawEditor.paintedHeight + 16) : (imagesFlow.implicitHeight + 12)

    function getTextEdit() {
        return rawEditor;
    }

    function commitInlineSubEdit(textEdit, newPlain, selStart, selEnd) {
        if (root.editor && root.blockData) {
            root.editor.onBlockRawChanged(root.blockData.bid, newPlain);
        }
        if (textEdit && typeof selStart === "number" && typeof selEnd === "number") {
            textEdit.select(selStart, selEnd);
        }
    }

    function focusInput(cursorPos) {
        if (root.isRawActive) {
            if (rawEditor) {
                rawEditor.forceActiveFocus();
                if (typeof cursorPos === "number") {
                    rawEditor.cursorPosition = Math.max(0, Math.min(rawEditor.text.length, cursorPos));
                } else {
                    rawEditor.cursorPosition = rawEditor.text.length;
                }
            }
        } else {
            if (imageFocusProxy) {
                imageFocusProxy.forceActiveFocus();
            }
        }
    }

    function resolveSource(src) {
        if (!src) return "";
        if (src.startsWith("http://") || src.startsWith("https://") || src.startsWith("file://")) {
            return src;
        }
        if (src.startsWith("/")) {
            return "file://" + encodeURI(src);
        }
        return "file://" + encodeURI(root.imgBaseDir + "/" + src);
    }

    // Proxy de foco para navegación fluida con flechas cuando la imagen está renderizada
    Item {
        id: imageFocusProxy
        anchors.fill: parent
        visible: !root.isRawActive && root.imagesList.length > 0
        focus: root.isEditing && !root.isRawActive

        Keys.onUpPressed: (event) => {
            if (root.editor && root.blockData) {
                root.editor.focusPreviousBlock(root.blockData.bid);
                event.accepted = true;
            }
        }

        Keys.onDownPressed: (event) => {
            if (root.editor && root.blockData) {
                root.editor.focusNextBlock(root.blockData.bid);
                event.accepted = true;
            }
        }

        Keys.onLeftPressed: (event) => {
            if (root.editor && root.blockData) {
                root.editor.focusPreviousBlock(root.blockData.bid);
                event.accepted = true;
            }
        }

        Keys.onRightPressed: (event) => {
            if (root.editor && root.blockData) {
                root.editor.focusNextBlock(root.blockData.bid);
                event.accepted = true;
            }
        }

        Keys.onReturnPressed: (event) => {
            if (root.editor && root.blockData) {
                root.editor.insertParagraphAfter(root.blockData.bid);
                event.accepted = true;
            }
        }
        Keys.onEnterPressed: (event) => Keys.onReturnPressed(event)

        Keys.onEscapePressed: (event) => {
            if (root.editor) {
                root.editor.confirmActiveBlock();
                event.accepted = true;
            }
        }

        Keys.onDeletePressed: (event) => {
            if (root.editor && root.blockData) {
                root.editor.handleBlockDeleteAtEnd(root.blockData.bid);
                event.accepted = true;
            }
        }

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_F2 || event.key === Qt.Key_E) {
                if (root.editor && root.editor.readOnly) return;
                root.showRawSource = true;
                Qt.callLater(() => {
                    if (rawEditor) {
                        rawEditor.forceActiveFocus();
                        rawEditor.cursorPosition = rawEditor.text.length;
                    }
                });
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Backspace) {
                if (root.editor && root.blockData) {
                    root.editor.handleBlockBackspaceAtStart(root.blockData.bid);
                    event.accepted = true;
                    return;
                }
            }
            if ((event.modifiers & Qt.ControlModifier) && !event.isAutoRepeat) {
                if (event.key === Qt.Key_Z && !(event.modifiers & Qt.ShiftModifier)) {
                    if (root.editor && typeof root.editor.undo === "function") { root.editor.undo(); event.accepted = true; return; }
                } else if (event.key === Qt.Key_Y || (event.key === Qt.Key_Z && (event.modifiers & Qt.ShiftModifier))) {
                    if (root.editor && typeof root.editor.redo === "function") { root.editor.redo(); event.accepted = true; return; }
                }
            }
        }
    }

    // Vista renderizada de imágenes con relación de aspecto completa
    Flow {
        id: imagesFlow
        visible: !root.isRawActive && root.imagesList.length > 0
        width: (root.imagesList.length === 1 && imagesRepeater.count > 0 && imagesRepeater.itemAt(0) && !imagesRepeater.itemAt(0).isBadge)
            ? Math.min(parent.width, imagesRepeater.itemAt(0).width)
            : parent.width
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 6

        Repeater {
            id: imagesRepeater
            model: root.imagesList

            delegate: Item {
                id: imgCard
                // No se setea source hasta saber que existe (o remota).
                // imageStateFor lee imageProbeReady/_imageExists: re-evalúa solo.
                readonly property bool loadable: {
                    var st = NotesService.imageStateFor(modelData.src, root.imgBaseDir);
                    return st === "yes" || st === "remote";
                }
                readonly property bool isCardReady: {
                    if (!loadable) return true;
                    if (imgItem.status === Image.Ready || imgItem.status === Image.Error) return true;
                    var cachedDim = (root.editor && root.editor._imageDimensions) ? root.editor._imageDimensions[modelData.src] : null;
                    if (cachedDim && cachedDim.w > 0 && cachedDim.h > 0) return true;
                    return false;
                }
                onIsCardReadyChanged: {
                    if (isCardReady) root.notifyCardReady();
                }
                Component.onCompleted: {
                    if (isCardReady) root.notifyCardReady();
                }

                readonly property bool isBadge: {
                    if (PreviewLogic.isBadgeLike(modelData.src, modelData.alt)) return true;
                    var cachedDim = (root.editor && root.editor._imageDimensions) ? root.editor._imageDimensions[modelData.src] : null;
                    if (cachedDim && cachedDim.h > 0 && cachedDim.h <= 36) return true;
                    if (imgItem.implicitHeight > 0 && imgItem.implicitHeight <= 36) return true;
                    return false;
                }

                readonly property real availW: (root.width > 0) ? root.width : (parent ? parent.width : 400)
                readonly property real zoomFactor: (typeof EditorMetrics !== "undefined" && EditorMetrics.zoom) ? EditorMetrics.zoom : 1.0
                readonly property real maxH: Math.round(560 * zoomFactor)
                readonly property real naturalW: {
                    if (imgItem.implicitWidth > 0) return imgItem.implicitWidth;
                    var cachedDim = (root.editor && root.editor._imageDimensions) ? root.editor._imageDimensions[modelData.src] : null;
                    if (cachedDim && cachedDim.w > 0) return cachedDim.w;
                    return 0;
                }
                readonly property real naturalH: {
                    if (imgItem.implicitHeight > 0) return imgItem.implicitHeight;
                    var cachedDim = (root.editor && root.editor._imageDimensions) ? root.editor._imageDimensions[modelData.src] : null;
                    if (cachedDim && cachedDim.h > 0) return cachedDim.h;
                    return 0;
                }

                readonly property real targetW: {
                    if (isBadge) {
                        return naturalW > 0 ? Math.min(availW, Math.round(naturalW * zoomFactor)) : 120;
                    }
                    if (naturalW > 0 && naturalH > 0) {
                        var maxCardW = (root.imagesList.length > 1 && naturalW >= availW * 0.45)
                            ? Math.min((availW - 10) / 2, availW) : availW;
                        var w = Math.min(maxCardW, Math.round(naturalW * zoomFactor));
                        var h = Math.round(w * (naturalH / naturalW));
                        if (h > maxH) {
                            h = maxH;
                            w = Math.round(h * (naturalW / naturalH));
                        }
                        return Math.max(24, w);
                    }
                    return root.imagesList.length > 1 ? Math.min((availW - 10) / 2, 400) : Math.min(availW, 600);
                }
                readonly property real targetH: {
                    if (isBadge) return naturalH > 0 ? Math.round(naturalH * zoomFactor) : 24;
                    if (naturalW > 0 && naturalH > 0) {
                        var h = Math.round(targetW * (naturalH / naturalW));
                        return Math.max(24, Math.min(maxH, h));
                    }
                    return 180;
                }

                width: targetW
                height: targetH

                Rectangle {
                    anchors.fill: parent
                    radius: imgCard.isBadge ? 4 : 8
                    color: imgCard.isBadge ? "transparent" : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04)
                    border.color: (root.isEditing && !root.isRawActive)
                        ? Theme.accent
                        : (imgCard.isBadge ? "transparent" : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08))
                    border.width: (root.isEditing && !root.isRawActive) ? 1.5 : (imgCard.isBadge ? 0 : 1)
                    clip: true

                    AnimatedImage {
                        id: imgItem
                        anchors.fill: parent
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                        playing: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                        paused: GamemodeService.gamemodeActive
                        source: imgCard.loadable ? root.resolveSource(modelData.src) : ""

                        onStatusChanged: {
                            if (status === Image.Ready && implicitWidth > 0 && implicitHeight > 0) {
                                if (root.editor && typeof root.editor._storeImageDimension === "function") {
                                    root.editor._storeImageDimension(modelData.src, implicitWidth, implicitHeight);
                                }
                            }
                        }
                    }

                    // Estado de error si la imagen no existe o falla (F7: con
                    // source vacío por faltante conocido también se muestra)
                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        visible: imgItem.status === Image.Error || !imgCard.loadable

                        Image {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 24; height: 24
                            source: Theme.iconsPath + "broken-image.svg"
                            sourceSize: Qt.size(24, 24)
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: Theme.danger
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: I18n.t("notes.image_load_error", "No se pudo cargar la imagen")
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: EditorMetrics.caption
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: modelData.link ? Qt.PointingHandCursor : Qt.PointingHandCursor
                    onClicked: {
                        if (modelData.link) {
                            Quickshell.execDetached(["xdg-open", modelData.link]);
                        } else if (!root.editor || !root.editor.readOnly) {
                            root.showRawSource = true;
                            if (root.editor && root.blockData) {
                                root.editor.requestEditBlock(root.blockData.bid);
                            }
                            Qt.callLater(() => {
                                if (rawEditor) {
                                    rawEditor.forceActiveFocus();
                                }
                            });
                        }
                    }
                }
            }
        }
    }

    // Modo de edición cruda de imagen (solo visible con confirmación o si no hay imagen válida)
    TextEdit {
        id: rawEditor
        visible: root.isRawActive
        readOnly: !root.isEditing || (root.editor && root.editor.readOnly)
        cursorVisible: activeFocus && root.isEditing && (!root.editor || !root.editor.readOnly)
        width: parent.width
        textFormat: TextEdit.PlainText
        text: (root.blockData && typeof root.blockData.raw === "string") ? root.blockData.raw : ""
        color: Theme.text
        font.family: "monospace"
        font.pixelSize: EditorMetrics.fs(Theme.fontSizeCaption + 1)
        wrapMode: TextEdit.Wrap
        selectByMouse: true
        activeFocusOnTab: false
        CustomTextCursor {}

        onTextChanged: {
            if (root.editor && root.editor.readOnly) return;
            if (root.isEditing && root.editor && root.blockData) {
                root.editor.onBlockRawChanged(root.blockData.bid, rawEditor.text);
            }
        }

        Keys.onReturnPressed: (event) => {
            if (event.modifiers & Qt.ControlModifier) {
                root.showRawSource = false;
                if (root.editor) {
                    root.editor.confirmActiveBlock();
                    event.accepted = true;
                }
            } else {
                rawEditor.insert(rawEditor.cursorPosition, "\n");
                event.accepted = true;
            }
        }

        Keys.onEnterPressed: (event) => {
            Keys.onReturnPressed(event);
        }

        Keys.onUpPressed: (event) => {
            if (event.modifiers & Qt.ShiftModifier) {
                event.accepted = false;
                return;
            }
            var pos = rawEditor.cursorPosition;
            var txt = rawEditor.text;
            var lineStart = txt.lastIndexOf("\n", pos - 1);
            if (lineStart === -1) {
                root.showRawSource = false;
                if (root.editor && root.blockData) {
                    root.editor.focusPreviousBlock(root.blockData.bid);
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            } else {
                event.accepted = false;
            }
        }

        Keys.onDownPressed: (event) => {
            if (event.modifiers & Qt.ShiftModifier) {
                event.accepted = false;
                return;
            }
            var pos = rawEditor.cursorPosition;
            var txt = rawEditor.text;
            var lineEnd = txt.indexOf("\n", pos);
            if (lineEnd === -1) {
                root.showRawSource = false;
                if (root.editor && root.blockData) {
                    root.editor.focusNextBlock(root.blockData.bid);
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            } else {
                event.accepted = false;
            }
        }

        Keys.onLeftPressed: (event) => {
            if (event.modifiers & Qt.ShiftModifier) {
                event.accepted = false;
                return;
            }
            if (rawEditor.cursorPosition === 0 && rawEditor.selectionStart === rawEditor.selectionEnd) {
                root.showRawSource = false;
                if (root.editor && root.blockData) {
                    root.editor.focusPreviousBlock(root.blockData.bid);
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            } else {
                event.accepted = false;
            }
        }

        Keys.onRightPressed: (event) => {
            if (event.modifiers & Qt.ShiftModifier) {
                event.accepted = false;
                return;
            }
            if (rawEditor.cursorPosition === rawEditor.text.length && rawEditor.selectionStart === rawEditor.selectionEnd) {
                root.showRawSource = false;
                if (root.editor && root.blockData) {
                    root.editor.focusNextBlock(root.blockData.bid);
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            } else {
                event.accepted = false;
            }
        }

        Keys.onEscapePressed: (event) => {
            root.showRawSource = false;
            if (root.editor) {
                root.editor.confirmActiveBlock();
                event.accepted = true;
            }
        }

        // F23: Ctrl+V / Shift+Insert con imagen → misma vía que el botón.
        Keys.onPressed: (event) => {
            if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_V) {
                if (root.editor && root.editor.editorModal && typeof root.editor.editorModal.pasteClipboardImage === "function") {
                    root.editor.editorModal.pasteClipboardImage();
                    event.accepted = true;
                    return;
                }
            }

            if (((event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_V) ||
                ((event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_Insert)) {
                if (root.editor && typeof root.editor.handlePaste === "function") {
                    if (root.editor.handlePaste(rawEditor)) {
                        event.accepted = true;
                        return;
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            propagateComposedEvents: true
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton && root.editor && root.editor.contextMenu) {
                    rawEditor.forceActiveFocus();
                    root.editor.contextMenu.open(rawEditor);
                }
            }
        }
    }
}
