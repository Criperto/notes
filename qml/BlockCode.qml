import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Controls
import Notas
import "Inline.js" as Inline
import "BlockModel.js" as BlockModel
import "."

Rectangle {
    id: root

    property var blockData: null
    property bool isEditing: false
    property var editor: null
    property bool copiedRecently: false
    property bool isSelected: false
    property bool inViewportChunk: true
    readonly property bool inPreviewMode: !!(root.editor && root.editor.readOnly)
    readonly property bool showEditView: (root.isEditing || root.isSelected) && !root.inPreviewMode

    onIsSelectedChanged: {
        if (root.isSelected && !root.isEditing && !root.inPreviewMode) {
            _syncTextFromModel();
        } else if (!root.isSelected && !root.isEditing) {
            clearTextSelection();
        }
    }


    readonly property string lang: {
        if (!blockData || !blockData.raw) return "";
        var firstLine = blockData.raw.split("\n")[0];
        var m = firstLine.match(/^[ \t]*(`{3,}|~{3,})([a-zA-Z0-9_-]*)/);
        return m ? m[2] : "";
    }

    readonly property string pureCodeText: {
        if (!blockData || !blockData.raw) return "";
        var lines = blockData.raw.split("\n");
        if (lines.length >= 2 && /^[ \t]*(`{3,}|~{3,})/.test(lines[0])) {
            lines.shift();
            if (lines.length > 0 && /^[ \t]*(`{3,}|~{3,})[ \t]*$/.test(lines[lines.length - 1])) {
                lines.pop();
            }
        }
        return lines.join("\n");
    }

    implicitWidth: parent ? parent.width : 400
    implicitHeight: root.showEditView
        ? (editInput.paintedHeight + 40)
        : (headerRow.height + previewInput.paintedHeight + (codeHScrollBar.isShowing ? codeHScrollBar.reservedSpace : 0) + 38)

    radius: 10
    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)
    border.color: isSelected ? Theme.accent : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
    border.width: 1

    property bool _syncingModel: false

    function _activeInput() {
        return root.showEditView ? editInput : previewInput;
    }

    function _applyHorizontalWheel(flick, deltaX, deltaY) {
        if (!flick || flick.contentWidth <= flick.width) return false;
        var rawDelta = (deltaX !== 0) ? deltaX : deltaY;
        if (!rawDelta) return false;
        var maxX = Math.max(0, flick.contentWidth - flick.width);
        var nextX = Math.max(0, Math.min(maxX, flick.contentX - rawDelta * 0.6));
        if (Math.abs(nextX - flick.contentX) > 0.01) {
            flick.contentX = nextX;
        }
        return true;
    }

    function _syncTextFromModel() {
        if (!editInput || !root.blockData) return;
        _syncingModel = true;
        var targetText = root.blockData.raw || "";
        if (editInput.text !== targetText) {
            editInput.text = targetText;
        }
        _syncingModel = false;
    }

    function selectRange(start, end) {
        if (root.showEditView) {
            _syncTextFromModel();
        }
        var inp = _activeInput();
        if (!inp) return;
        var s = Math.max(0, Math.min(inp.length, Math.min(start, end)));
        var e = Math.max(0, Math.min(inp.length, Math.max(start, end)));
        inp.select(s, e);
    }

    function selectAllText() {
        if (root.showEditView) {
            _syncTextFromModel();
        }
        var inp = _activeInput();
        if (!inp) return;
        inp.selectAll();
    }

    function clearTextSelection() {
        if (editInput) editInput.deselect();
        if (previewInput) previewInput.deselect();
    }

    function getCharPosAt(lx, ly) {
        var inp = _activeInput();
        if (!inp) return 0;
        var pt = root.mapToItem(inp, lx, ly);
        return inp.positionAt(pt.x, pt.y);
    }

    function getTextLength() {
        var inp = _activeInput();
        return inp ? inp.length : 0;
    }

    function getSelectedText() {
        var inp = _activeInput();
        return inp ? inp.selectedText : "";
    }

    function getTextContent() {
        if (root.showEditView) {
            return editInput ? Inline.plainText(editInput) : "";
        }
        return root.pureCodeText;
    }

    function deleteSelectedText() {
        if (root.inPreviewMode || !editInput) return;
        var s = editInput.selectionStart;
        var e = editInput.selectionEnd;
        if (s !== e) {
            editInput.remove(s, e);
        }
    }

    onBlockDataChanged: {
        if (!root.isEditing) {
            _syncTextFromModel();
        }
    }

    onIsEditingChanged: {
        if (root.isEditing) {
            _syncTextFromModel();
        }
    }


    Component.onCompleted: {
        if (root.isEditing) {
            _syncTextFromModel();
        }
    }

    function getRaw() {
        if (root.isEditing && editInput) {
            return Inline.plainText(editInput);
        }
        return root.blockData ? (root.blockData.raw || "") : "";
    }

    function getTextEdit() {
        return _activeInput();
    }

    function commitInlineSubEdit(textEdit, newText, selStart, selEnd) {
        if (!editInput) return;
        editInput.text = newText;
        if (typeof selStart === "number" && typeof selEnd === "number") {
            editInput.select(selStart, selEnd);
        }
        if (root.editor && root.blockData) {
            root.editor.onBlockRawChanged(root.blockData.bid, newText);
        }
    }

    function focusInput(cursorPos) {
        if (editInput) {
            _syncTextFromModel();
            editInput.forceActiveFocus();
            if (editInput.selectionStart !== editInput.selectionEnd) return;
            if (typeof cursorPos === "object" && cursorPos !== null && typeof cursorPos.x === "number") {
                if (cursorPos.fromBottom === true || (typeof cursorPos.y === "number" && cursorPos.y > 1000)) {
                    var lastRect = editInput.positionToRectangle(editInput.length);
                    var targetY = lastRect.y + (lastRect.height > 0 ? lastRect.height / 2 : 10);
                    editInput.cursorPosition = editInput.positionAt(cursorPos.x, targetY);
                } else {
                    var firstRect = editInput.positionToRectangle(0);
                    var targetY0 = firstRect.y + (firstRect.height > 0 ? firstRect.height / 2 : 10);
                    editInput.cursorPosition = editInput.positionAt(cursorPos.x, targetY0);
                }
            } else if (cursorPos !== undefined && cursorPos >= 0) {
                editInput.cursorPosition = Math.min(editInput.text.length, cursorPos);
            } else {
                editInput.cursorPosition = editInput.text.length;
            }
        }
    }

    Timer {
        id: copiedTimer
        interval: 1600
        onTriggered: root.copiedRecently = false
    }

    // Cabecera superior con lenguaje y botón de copiar
    RowLayout {
        id: headerRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 10
        height: 24
        visible: !root.showEditView

        Text {
            text: root.lang ? root.lang.toLowerCase() : "code"
            color: Theme.muted
            font.family: Theme.fontFamilyMonospace || "monospace"
            font.pixelSize: EditorMetrics.caption
            Layout.fillWidth: true
        }

        Rectangle {
            id: copyBtn
            width: copyRow.implicitWidth + 12
            height: 22
            radius: 6
            color: copyMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12) : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)

            RowLayout {
                id: copyRow
                anchors.centerIn: parent
                spacing: 4

                Image {
                    width: 12; height: 12
                    source: Theme.iconsPath + (root.copiedRecently ? "check.svg" : "content-copy.svg")
                    sourceSize: Qt.size(12, 12)
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: root.copiedRecently ? Theme.success : Theme.muted
                    }
                }

                Text {
                    text: root.copiedRecently ? I18n.t("notes.editor.copied", "Copiado") : I18n.t("notes.editor.copy", "Copiar")
                    color: root.copiedRecently ? Theme.success : Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: EditorMetrics.fs(Theme.fontSizeCaption - 1)
                }
            }

            MouseArea {
                id: copyMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.editor && typeof root.editor.copyText === "function") {
                        root.editor.copyText(root.pureCodeText);
                    } else {
                        if (typeof Quickshell.clipboardText !== "undefined") {
                            Quickshell.clipboardText = root.pureCodeText;
                        }
                        if (typeof Sys === "undefined" || typeof Sys.hasCommand !== "function" || Sys.hasCommand("wl-copy")) {
                            Quickshell.execDetached(["wl-copy", "--", root.pureCodeText]);
                        }
                    }
                    root.copiedRecently = true;
                    copiedTimer.restart();
                }
            }
        }
    }

    // Vista de código renderizada con scroll horizontal dedicado y selección directa sin arrastrar el viewport
    Flickable {
        id: codeFlickable
        visible: !root.showEditView
        anchors.top: headerRow.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        clip: true
        interactive: false
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick
        contentWidth: Math.max(width, previewInput.paintedWidth + 20)
        contentHeight: previewInput.paintedHeight + (codeHScrollBar.isShowing ? codeHScrollBar.reservedSpace : 0)

        ScrollBar.horizontal: CustomScrollBar {
            id: codeHScrollBar
            orientation: Qt.Horizontal
        }

        // Scroll horizontal con Shift + Rueda vertical/horizontal
        WheelHandler {
            id: codeShiftWheelHandler
            target: null
            acceptedModifiers: Qt.ShiftModifier
            acceptedDevices: PointerDevice.AllDevices
            onWheel: (event) => {
                var dx = event.angleDelta ? event.angleDelta.x : 0;
                var dy = event.angleDelta ? event.angleDelta.y : 0;
                if (dx === 0 && dy === 0 && event.pixelDelta) {
                    dx = event.pixelDelta.x;
                    dy = event.pixelDelta.y;
                }
                if (root._applyHorizontalWheel(codeFlickable, dy !== 0 ? dy : dx, 0)) {
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            }
        }

        // Scroll horizontal directo (rueda horizontal de mouse / tilt-wheel / trackpad)
        WheelHandler {
            id: codeHorizWheelHandler
            target: null
            orientation: Qt.Horizontal
            acceptedModifiers: Qt.NoModifier
            acceptedDevices: PointerDevice.AllDevices
            onWheel: (event) => {
                var dx = (event.angleDelta && event.angleDelta.x !== 0)
                    ? event.angleDelta.x
                    : (event.pixelDelta ? event.pixelDelta.x : 0);
                if (dx !== 0 && root._applyHorizontalWheel(codeFlickable, dx, 0)) {
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            }
        }

        TextEdit {
            id: previewInput
            width: Math.max(codeFlickable.width, paintedWidth + 20)
            height: Math.max(codeFlickable.height, paintedHeight)
            readOnly: true
            cursorVisible: false
            selectByMouse: false
            persistentSelection: true
            wrapMode: TextEdit.NoWrap
            activeFocusOnTab: false
            color: Theme.text
            font.family: Theme.fontFamilyMonospace || "monospace"
            font.pixelSize: EditorMetrics.fs(Theme.fontSizeCaption + 1)
            textFormat: (root.editor && root.editor.searchQuery) ? TextEdit.RichText : TextEdit.PlainText
            text: (root.editor && root.editor.searchQuery)
                ? Inline.highlightInHtml(Inline.escapeHtml(root.pureCodeText).replace(/\n/g, "<br/>"), root.editor.searchQuery, "" + root.editor.searchHighlightColor,
                    (root.blockData ? root.editor.searchActiveBg(root.blockData.bid, 0) : ""),
                    (root.blockData ? root.editor.searchActiveOrdinal(root.blockData.bid, 0) : -1),
                    (root.blockData ? root.editor.searchActiveFg(root.blockData.bid, 0) : ""))
                : root.pureCodeText

            CustomTextCursor {
                multiSelectionMode: root.editor ? root.editor.hasBlockSelection : false
                showStartBoundary: !root.editor || !root.editor.hasBlockSelection || root.editor.isSelectionStartBlock(root.blockData ? root.blockData.bid : -1)
                showEndBoundary: !root.editor || !root.editor.hasBlockSelection || root.editor.isSelectionEndBlock(root.blockData ? root.blockData.bid : -1)
                externalHandleDragCallback: function(isStart, gx, gy) {
                    if (root.editor && typeof root.editor.handleTeardropDrag === "function") {
                        root.editor.handleTeardropDrag(isStart, gx, gy);
                    }
                }
            }

            onSelectionStartChanged: {
                if (root.editor && !root.editor._syncingSelection && !root.editor.hasBlockSelection && !root.editor.isDraggingSelection) {
                    if (previewInput.selectionStart !== previewInput.selectionEnd && root.blockData && typeof root.editor.notifySingleInputSelection === "function") {
                        root.editor.notifySingleInputSelection(root.blockData.bid);
                    }
                    if (typeof root.editor.updateFormatState === "function") root.editor.updateFormatState();
                }
            }
            onSelectionEndChanged: {
                if (root.editor && !root.editor._syncingSelection && !root.editor.hasBlockSelection && !root.editor.isDraggingSelection) {
                    if (previewInput.selectionStart !== previewInput.selectionEnd && root.blockData && typeof root.editor.notifySingleInputSelection === "function") {
                        root.editor.notifySingleInputSelection(root.blockData.bid);
                    }
                    if (typeof root.editor.updateFormatState === "function") root.editor.updateFormatState();
                }
            }

            Keys.onPressed: (event) => {
                var isCtrl = !!(event.modifiers & Qt.ControlModifier);
                var isShift = !!(event.modifiers & Qt.ShiftModifier);
                var isAlt = !!(event.modifiers & Qt.AltModifier);

                if (isCtrl && !isShift && !isAlt && event.key === Qt.Key_Home) {
                    if (root.editor && typeof root.editor.goToDocumentStart === "function") {
                        root.editor.goToDocumentStart();
                        event.accepted = true;
                        return;
                    }
                }
                if (isCtrl && !isShift && !isAlt && event.key === Qt.Key_End) {
                    if (root.editor && typeof root.editor.goToDocumentEnd === "function") {
                        root.editor.goToDocumentEnd();
                        event.accepted = true;
                        return;
                    }
                }
                if (event.key === Qt.Key_PageUp) {
                    if (root.editor && typeof root.editor.pageUp === "function") {
                        root.editor.pageUp();
                        event.accepted = true;
                        return;
                    }
                }
                if (event.key === Qt.Key_PageDown) {
                    if (root.editor && typeof root.editor.pageDown === "function") {
                        root.editor.pageDown();
                        event.accepted = true;
                        return;
                    }
                }
                if (root.editor && root.editor.hasBlockSelection) {
                    if ((isCtrl && !isShift && !isAlt && event.key === Qt.Key_C) ||
                        (isCtrl && !isShift && !isAlt && event.key === Qt.Key_Insert)) {
                        root.editor.copySelectedText();
                        event.accepted = true;
                        return;
                    }
                    if (event.key === Qt.Key_Escape) {
                        root.editor.clearBlockSelection();
                        event.accepted = true;
                        return;
                    }
                }
                if ((isCtrl && !isShift && !isAlt && event.key === Qt.Key_C) ||
                    (isCtrl && !isShift && !isAlt && event.key === Qt.Key_Insert)) {
                    if (previewInput.selectionStart !== previewInput.selectionEnd) {
                        if (root.editor && typeof root.editor.copyText === "function") {
                            root.editor.copyText(previewInput.selectedText);
                        } else {
                            previewInput.copy();
                        }
                        event.accepted = true;
                        return;
                    }
                }
                if (isCtrl && !isShift && !isAlt && event.key === Qt.Key_A) {
                    if (root.editor && typeof root.editor.selectAllDocument === "function") {
                        root.editor.selectAllDocument();
                    } else {
                        previewInput.selectAll();
                    }
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Escape) {
                    previewInput.deselect();
                    event.accepted = true;
                    return;
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.IBeamCursor

                property bool dragging: false
                property bool isCrossDragging: false
                property bool _doubleClickedRecently: false
                property int anchorPos: -1
                property real startX: 0
                property real startY: 0

                onPressed: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        previewInput.forceActiveFocus();
                        if (root.editor && root.editor.contextMenu) {
                            root.editor.contextMenu.open(previewInput);
                        }
                        mouse.accepted = true;
                        return;
                    }
                    if (root.editor && root.blockData && typeof root.editor.clearSelectionExcept === "function") {
                        root.editor.clearSelectionExcept(root.blockData.bid);
                    }
                    dragging = true;
                    isCrossDragging = false;
                    startX = mouse.x;
                    startY = mouse.y;
                    anchorPos = previewInput.positionAt(mouse.x, mouse.y);
                    if (root.inPreviewMode) {
                        previewInput.forceActiveFocus();
                        previewInput.deselect();
                        if (anchorPos >= 0 && anchorPos <= previewInput.length) {
                            previewInput.cursorPosition = anchorPos;
                        }
                    }
                }

                onPositionChanged: (mouse) => {
                    if (!dragging || anchorPos < 0) return;
                    if (!isCrossDragging && Math.abs(mouse.x - startX) < 3 && Math.abs(mouse.y - startY) < 3) return;

                    var ptRoot = mapToItem(root, mouse.x, mouse.y);
                    if (ptRoot.y < -4 || ptRoot.y > root.height + 4 || isCrossDragging) {
                        if (!isCrossDragging) {
                            isCrossDragging = true;
                        }
                        if (root.editor && typeof root.editor.handleCrossBlockDrag === "function") {
                            var ptInContent = mapToItem(root.editor.contentItem, mouse.x, mouse.y);
                            root.editor.handleCrossBlockDrag(root.blockData.bid, ptInContent.y, ptInContent.x);
                            return;
                        }
                    }

                    if (root.inPreviewMode) {
                        var maxX = Math.max(0, codeFlickable.contentWidth - codeFlickable.width);
                        if (maxX > 0) {
                            var fx = mouse.x - codeFlickable.contentX;
                            if (fx > codeFlickable.width - 20) {
                                codeFlickable.contentX = Math.min(maxX, codeFlickable.contentX + 16);
                            } else if (fx < 20) {
                                codeFlickable.contentX = Math.max(0, codeFlickable.contentX - 16);
                            }
                        }
                        previewInput.select(anchorPos, previewInput.positionAt(mouse.x, mouse.y));
                    }
                }

                onReleased: (mouse) => {
                    if (mouse.button === Qt.RightButton) return;
                    var wasShortClick = !isCrossDragging && Math.abs(mouse.x - startX) < 4 && Math.abs(mouse.y - startY) < 4;
                    if (wasShortClick && !_doubleClickedRecently && !root.inPreviewMode) {
                        if (root.editor && root.blockData) {
                            root.editor.requestEditBlock(root.blockData.bid, { x: mouse.x, y: mouse.y });
                        }
                    }
                    _doubleClickedRecently = false;
                    dragging = false;
                    anchorPos = -1;
                    if (isCrossDragging || (root.editor && root.editor.isDraggingSelection)) {
                        isCrossDragging = false;
                        if (root.editor && typeof root.editor.endCrossBlockDrag === "function") {
                            root.editor.endCrossBlockDrag();
                        }
                    }
                }

                onCanceled: {
                    dragging = false;
                    anchorPos = -1;
                    isCrossDragging = false;
                    if (root.editor && typeof root.editor.endCrossBlockDrag === "function") {
                        root.editor.endCrossBlockDrag();
                    }
                }

                onDoubleClicked: (mouse) => {
                    if (mouse.button !== Qt.LeftButton) return;
                    _doubleClickedRecently = true;
                    if (root.editor && root.blockData && typeof root.editor.clearSelectionExcept === "function") {
                        root.editor.clearSelectionExcept(root.blockData.bid);
                    }
                    if (!root.inPreviewMode) {
                        if (root.editor && root.blockData) {
                            root.editor.requestEditBlock(root.blockData.bid, { x: mouse.x, y: mouse.y });
                        }
                        return;
                    }
                    previewInput.forceActiveFocus();
                    var pos = previewInput.positionAt(mouse.x, mouse.y);
                    if (pos >= 0 && pos <= previewInput.length) {
                        previewInput.cursorPosition = pos;
                        previewInput.selectWord();
                    }
                }
            }
        }
    }

    // Vista de edición cruda con scroll horizontal sin desborde
    Flickable {
        id: editFlickable
        visible: root.showEditView
        anchors.fill: parent
        anchors.margins: 12
        clip: true
        interactive: false
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick
        contentWidth: Math.max(width, editInput.paintedWidth + 24)
        contentHeight: Math.max(height, editInput.paintedHeight)

        ScrollBar.horizontal: CustomScrollBar {
            id: editHScrollBar
            orientation: Qt.Horizontal
        }

        WheelHandler {
            id: editShiftWheelHandler
            target: null
            acceptedModifiers: Qt.ShiftModifier
            acceptedDevices: PointerDevice.AllDevices
            onWheel: (event) => {
                var dx = event.angleDelta ? event.angleDelta.x : 0;
                var dy = event.angleDelta ? event.angleDelta.y : 0;
                if (dx === 0 && dy === 0 && event.pixelDelta) {
                    dx = event.pixelDelta.x;
                    dy = event.pixelDelta.y;
                }
                if (root._applyHorizontalWheel(editFlickable, dy !== 0 ? dy : dx, 0)) {
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            }
        }

        WheelHandler {
            id: editHorizWheelHandler
            target: null
            orientation: Qt.Horizontal
            acceptedModifiers: Qt.NoModifier
            acceptedDevices: PointerDevice.AllDevices
            onWheel: (event) => {
                var dx = (event.angleDelta && event.angleDelta.x !== 0)
                    ? event.angleDelta.x
                    : (event.pixelDelta ? event.pixelDelta.x : 0);
                if (dx !== 0 && root._applyHorizontalWheel(editFlickable, dx, 0)) {
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            }
        }

        TextEdit {
            id: editInput
            persistentSelection: true
            overwriteMode: root.editor ? root.editor.overwriteMode : false
            width: Math.max(editFlickable.width, paintedWidth + 20)
            readOnly: !root.isEditing || (root.editor && root.editor.readOnly)
            cursorVisible: activeFocus && root.isEditing && (!root.editor || !root.editor.readOnly)
            textFormat: TextEdit.PlainText
            text: ""
            color: Theme.text
            font.family: Theme.fontFamilyMonospace || "monospace"
            font.pixelSize: EditorMetrics.fs(Theme.fontSizeCaption + 1)
            wrapMode: TextEdit.NoWrap
            selectByMouse: true
            activeFocusOnTab: false
        CustomTextCursor {
            multiSelectionMode: root.editor ? root.editor.hasBlockSelection : false
            showStartBoundary: !root.editor || !root.editor.hasBlockSelection || root.editor.isSelectionStartBlock(root.blockData ? root.blockData.bid : -1)
            showEndBoundary: !root.editor || !root.editor.hasBlockSelection || root.editor.isSelectionEndBlock(root.blockData ? root.blockData.bid : -1)
            externalHandleDragCallback: function(isStart, gx, gy) {
                if (root.editor && typeof root.editor.handleTeardropDrag === "function") {
                    root.editor.handleTeardropDrag(isStart, gx, gy);
                }
            }
        }

        onSelectionStartChanged: {
            if (root.editor && !root.editor._syncingSelection && !root.editor.hasBlockSelection && !root.editor.isDraggingSelection) {
                if (editInput.selectionStart !== editInput.selectionEnd && root.blockData && typeof root.editor.notifySingleInputSelection === "function") {
                    root.editor.notifySingleInputSelection(root.blockData.bid);
                }
                if (typeof root.editor.updateFormatState === "function") root.editor.updateFormatState();
            }
        }
        onSelectionEndChanged: {
            if (root.editor && !root.editor._syncingSelection && !root.editor.hasBlockSelection && !root.editor.isDraggingSelection) {
                if (editInput.selectionStart !== editInput.selectionEnd && root.blockData && typeof root.editor.notifySingleInputSelection === "function") {
                    root.editor.notifySingleInputSelection(root.blockData.bid);
                }
                if (typeof root.editor.updateFormatState === "function") root.editor.updateFormatState();
            }
        }
        onCursorPositionChanged: {
            if (root.editor && !root.editor._syncingSelection && !root.editor.hasBlockSelection && !root.editor.isDraggingSelection) {
                if (editInput.activeFocus && editInput.selectionStart === editInput.selectionEnd && root.blockData && typeof root.editor.notifySingleInputSelection === "function") {
                    root.editor.notifySingleInputSelection(root.blockData.bid);
                }
                if (typeof root.editor.updateFormatState === "function") root.editor.updateFormatState();
            }
            var cr = editInput.cursorRectangle;
            if (cr.x < editFlickable.contentX) {
                editFlickable.contentX = Math.max(0, cr.x - 20);
            } else if (cr.x + cr.width > editFlickable.contentX + editFlickable.width) {
                editFlickable.contentX = Math.min(editFlickable.contentWidth - editFlickable.width, cr.x + cr.width - editFlickable.width + 20);
            }
        }

        onTextChanged: {
            if (root._syncingModel || (root.editor && root.editor.readOnly)) return;
            if (root.isEditing && root.editor && root.blockData) {
                var cleanText = Inline.plainText(editInput);
                if (cleanText !== root.blockData.raw) {
                    root.editor.onBlockRawChanged(root.blockData.bid, cleanText);
                }
            }
        }

        Keys.onReturnPressed: (event) => {
            if (root.editor && root.editor.readOnly) {
                event.accepted = true;
                return;
            }
            if (event.modifiers & Qt.ControlModifier) {
                if (root.editor && root.blockData && typeof root.editor.insertParagraphAfter === "function") {
                    root.editor.insertParagraphAfter(root.blockData.bid);
                    event.accepted = true;
                    return;
                } else if (root.editor) {
                    root.editor.confirmActiveBlock();
                    event.accepted = true;
                    return;
                }
            }
            var cm = root.editor ? root.editor.contextMenu : null;
            if (cm && cm.visible && !cm.isClosing) {
                if (cm.triggerSelectedItem()) {
                    event.accepted = true;
                    return;
                }
                cm.close();
                event.accepted = true;
                return;
            }
            var ex = BlockModel.fenceExit(editInput.text, editInput.cursorPosition);
            if (ex.exit && root.editor && root.blockData && typeof root.editor.exitFenceBlock === "function") {
                root._syncingModel = true;
                editInput.text = ex.raw;
                root._syncingModel = false;
                root.editor.exitFenceBlock(root.blockData.bid);
                event.accepted = true;
                return;
            }
            var cp = editInput.cursorPosition;
            editInput.insert(cp, "\n");
            editInput.cursorPosition = cp + 1;
            event.accepted = true;
        }

        Keys.onEnterPressed: (event) => {
            Keys.onReturnPressed(event);
        }

        Keys.onTabPressed: (event) => {
            if (root.editor && root.editor.readOnly) {
                event.accepted = true;
                return;
            }
            if (editInput.selectionStart !== editInput.selectionEnd) {
                var s = editInput.selectionStart;
                var e = editInput.selectionEnd;
                var t = editInput.text;
                var lineStart = t.lastIndexOf("\n", s - 1) + 1;
                var lineEnd = t.indexOf("\n", e);
                if (lineEnd === -1) lineEnd = t.length;
                var sub = t.substring(lineStart, lineEnd);
                var indented = sub.split("\n").map(function(l) { return "    " + l; }).join("\n");
                editInput.remove(lineStart, lineEnd);
                editInput.insert(lineStart, indented);
                editInput.select(s + 4, e + (indented.length - sub.length));
            } else {
                var tp = editInput.cursorPosition;
                editInput.insert(tp, "    ");
                editInput.cursorPosition = tp + 4;
            }
            event.accepted = true;
        }

        Keys.onBacktabPressed: (event) => {
            var s = editInput.selectionStart;
            var e = editInput.selectionEnd;
            var t = editInput.text;
            var lineStart = t.lastIndexOf("\n", s - 1) + 1;
            var lineEnd = t.indexOf("\n", e);
            if (lineEnd === -1) lineEnd = t.length;
            var sub = t.substring(lineStart, lineEnd);
            var lines = sub.split("\n");
            var diff = 0;
            var firstLineDiff = 0;
            var unindented = lines.map(function(l, idx) {
                var cut = 0;
                if (l.startsWith("    ")) cut = 4;
                else if (l.startsWith("   ")) cut = 3;
                else if (l.startsWith("  ")) cut = 2;
                else if (l.startsWith(" ")) cut = 1;
                else if (l.startsWith("\t")) cut = 1;
                diff += cut;
                if (idx === 0) firstLineDiff = cut;
                return l.substring(cut);
            }).join("\n");
            editInput.remove(lineStart, lineEnd);
            editInput.insert(lineStart, unindented);
            editInput.select(Math.max(lineStart, s - firstLineDiff), Math.max(lineStart, e - diff));
            event.accepted = true;
        }

        Keys.onPressed: (event) => {
            var isCtrl = !!(event.modifiers & Qt.ControlModifier);
            var isShift = !!(event.modifiers & Qt.ShiftModifier);
            var isAlt = !!(event.modifiers & Qt.AltModifier);

            if (isCtrl && !isShift && !isAlt && event.key === Qt.Key_Home) {
                if (root.editor && typeof root.editor.goToDocumentStart === "function") {
                    root.editor.goToDocumentStart();
                    event.accepted = true;
                    return;
                }
            }
            if (isCtrl && !isShift && !isAlt && event.key === Qt.Key_End) {
                if (root.editor && typeof root.editor.goToDocumentEnd === "function") {
                    root.editor.goToDocumentEnd();
                    event.accepted = true;
                    return;
                }
            }
            if (event.key === Qt.Key_PageUp) {
                if (root.editor && typeof root.editor.pageUp === "function") {
                    root.editor.pageUp();
                    event.accepted = true;
                    return;
                }
            }
            if (event.key === Qt.Key_PageDown) {
                if (root.editor && typeof root.editor.pageDown === "function") {
                    root.editor.pageDown();
                    event.accepted = true;
                    return;
                }
            }
            if (isCtrl && !isShift && !isAlt && event.key === Qt.Key_Delete) {
                if (root.editor && root.editor.readOnly) {
                    event.accepted = true;
                    return;
                }
                if (editInput.selectionStart !== editInput.selectionEnd) {
                    editInput.remove(editInput.selectionStart, editInput.selectionEnd);
                } else if (editInput.cursorPosition < editInput.length) {
                    var pText = Inline.plainText(editInput);
                    var nextW = Inline.findNextWordEnd(pText, editInput.cursorPosition);
                    editInput.remove(editInput.cursorPosition, nextW);
                } else if (editInput.cursorPosition === editInput.length) {
                    if (root.editor && typeof root.editor.handleBlockDeleteAtEnd === "function") {
                        root.editor.handleBlockDeleteAtEnd(root.blockData.bid);
                    }
                }
                event.accepted = true;
                return;
            }

            if (!isCtrl && !isShift && !isAlt && event.key === Qt.Key_Insert) {
                if (root.editor && typeof root.editor.toggleOverwriteMode === "function") {
                    root.editor.toggleOverwriteMode();
                } else {
                    editInput.overwriteMode = !editInput.overwriteMode;
                }
                event.accepted = true;
                return;
            }

            if (root.editor && root.editor.hasBlockSelection) {

                if ((isCtrl && !isShift && !isAlt && event.key === Qt.Key_C) ||
                    (isCtrl && !isShift && !isAlt && event.key === Qt.Key_Insert)) {
                    root.editor.copySelectedText();
                    event.accepted = true;
                    return;
                }
                if ((isCtrl && !isShift && !isAlt && event.key === Qt.Key_X) ||
                    (isShift && !isCtrl && !isAlt && event.key === Qt.Key_Delete)) {
                    root.editor.copySelectedText();
                    if (!root.editor.readOnly && typeof root.editor.replaceSelectedRange === "function") {
                        root.editor.replaceSelectedRange("");
                    }
                    event.accepted = true;
                    return;
                }
                if ((isCtrl && !isShift && !isAlt && event.key === Qt.Key_V) ||
                    (isShift && !isCtrl && !isAlt && event.key === Qt.Key_Insert)) {
                    if (!root.editor.readOnly && typeof root.editor.replaceSelectedRange === "function") {
                        var pasteText = (typeof Quickshell.clipboardText === "string") ? Quickshell.clipboardText : "";
                        root.editor.replaceSelectedRange(pasteText);
                    }
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                    if (!root.editor.readOnly && typeof root.editor.replaceSelectedRange === "function") {
                        root.editor.replaceSelectedRange("");
                    }
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Escape) {
                    root.editor.clearBlockSelection();
                    event.accepted = true;
                    return;
                }
                if (!isCtrl && !isAlt && event.text && event.text.length > 0 && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) {
                    if (!root.editor.readOnly && typeof root.editor.replaceSelectedRange === "function") {
                        root.editor.replaceSelectedRange(event.text);
                    }
                    event.accepted = true;
                    return;
                }
            }

            var cm = root.editor ? root.editor.contextMenu : null;
            if (cm && cm.visible && !cm.isClosing) {
                if (event.key === Qt.Key_Menu || event.nativeScanCode === 135 || event.key === Qt.Key_Escape) {
                    cm.close();
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Up) {
                    cm.selectPreviousItem();
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Down) {
                    cm.selectNextItem();
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (cm.triggerSelectedItem()) {
                        event.accepted = true;
                        return;
                    }
                    cm.close();
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                    event.accepted = true;
                    return;
                }
            }

            if (event.key === Qt.Key_Menu || event.nativeScanCode === 135) {
                if (root.editor && root.editor.contextMenu) {
                    if (typeof root.editor.contextMenu.toggleAtTextCursor === "function") {
                        root.editor.contextMenu.toggleAtTextCursor(editInput);
                    } else if (typeof root.editor.contextMenu.openAtTextCursor === "function") {
                        root.editor.contextMenu.openAtTextCursor(editInput);
                    } else {
                        root.editor.contextMenu.open(editInput);
                    }
                }
                event.accepted = true;
                return;
            }

            if (event.key === Qt.Key_Left || event.key === Qt.Key_Right ||
                event.key === Qt.Key_Home || event.key === Qt.Key_End ||
                event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete ||
                event.key === Qt.Key_Return || event.key === Qt.Key_Enter ||
                event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab ||
                (event.text && event.text.length > 0)) {
                if (root.editor && typeof root.editor.resetPreferredCursorX === "function") {
                    root.editor.resetPreferredCursorX();
                }
            }

            // F23: Ctrl+Shift+V fuerza imagen; Ctrl+V decide por MIME real.
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
                    if (root.editor.handlePaste(editInput)) {
                        event.accepted = true;
                        return;
                    }
                }
            }
            if (event.modifiers & Qt.ControlModifier) {
                if (event.key === Qt.Key_Z) {
                    if (root.editor) {
                        if (event.modifiers & Qt.ShiftModifier) {
                            root.editor.redo();
                        } else {
                            root.editor.undo();
                        }
                    }
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Y) {
                    if (root.editor) root.editor.redo();
                    event.accepted = true;
                    return;
                }
            }

            if (event.key === Qt.Key_Backspace) {
                if (editInput.cursorPosition === 0 && editInput.selectionStart === editInput.selectionEnd) {
                    if (root.editor) {
                        root.editor.handleBlockBackspaceAtStart(root.blockData.bid);
                        event.accepted = true;
                    }
                }
            }
        }

        Keys.onDeletePressed: (event) => {
            if (root.editor && root.editor.readOnly) {
                event.accepted = true;
                return;
            }
            if (editInput.selectionStart !== editInput.selectionEnd) {
                editInput.remove(editInput.selectionStart, editInput.selectionEnd);
                event.accepted = true;
                return;
            }
            if (editInput.cursorPosition === editInput.length) {
                if (root.editor && typeof root.editor.handleBlockDeleteAtEnd === "function") {
                    root.editor.handleBlockDeleteAtEnd(root.blockData.bid);
                    event.accepted = true;
                    return;
                }
            }
            event.accepted = false;
        }

        Keys.onUpPressed: (event) => {
            var cm = root.editor ? root.editor.contextMenu : null;
            if (cm && cm.visible && !cm.isClosing) {
                cm.selectPreviousItem();
                event.accepted = true;
                return;
            }
            if (event.modifiers & Qt.ShiftModifier) {
                event.accepted = false;
                return;
            }
            var curX = editInput.positionToRectangle(editInput.cursorPosition).x;
            var targetX = (root.editor && typeof root.editor.getPreferredCursorX === "function") ? root.editor.getPreferredCursorX(curX) : curX;
            var curY = editInput.positionToRectangle(editInput.cursorPosition).y;
            var topY = editInput.positionToRectangle(0).y;
            if (curY <= topY + 4) {
                if (root.editor && root.blockData) {
                    root.editor.focusPreviousBlock(root.blockData.bid, { x: targetX, fromBottom: true });
                    event.accepted = true;
                } else if (editInput.cursorPosition > 0) {
                    editInput.cursorPosition = 0;
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            } else {
                event.accepted = false;
            }
        }

        Keys.onDownPressed: (event) => {
            var cm = root.editor ? root.editor.contextMenu : null;
            if (cm && cm.visible && !cm.isClosing) {
                cm.selectNextItem();
                event.accepted = true;
                return;
            }
            if (event.modifiers & Qt.ShiftModifier) {
                event.accepted = false;
                return;
            }
            var curXDown = editInput.positionToRectangle(editInput.cursorPosition).x;
            var targetXDown = (root.editor && typeof root.editor.getPreferredCursorX === "function") ? root.editor.getPreferredCursorX(curXDown) : curXDown;
            var curY = editInput.positionToRectangle(editInput.cursorPosition).y;
            var botY = editInput.positionToRectangle(editInput.length).y;
            if (curY >= botY - 4) {
                if (root.editor && root.blockData) {
                    root.editor.focusNextBlock(root.blockData.bid, { x: targetXDown, fromTop: true });
                    event.accepted = true;
                } else if (editInput.cursorPosition < editInput.length) {
                    editInput.cursorPosition = editInput.length;
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            } else {
                event.accepted = false;
            }
        }

        Keys.onLeftPressed: (event) => {
            if (root.editor && typeof root.editor.resetPreferredCursorX === "function") {
                root.editor.resetPreferredCursorX();
            }
            if (event.modifiers & Qt.ShiftModifier) {
                event.accepted = false;
                return;
            }
            if (editInput.cursorPosition === 0 && editInput.selectionStart === editInput.selectionEnd) {
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
            if (root.editor && typeof root.editor.resetPreferredCursorX === "function") {
                root.editor.resetPreferredCursorX();
            }
            if (event.modifiers & Qt.ShiftModifier) {
                event.accepted = false;
                return;
            }
            if (editInput.cursorPosition === editInput.length && editInput.selectionStart === editInput.selectionEnd) {
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
            if (root.editor) {
                root.editor.confirmActiveBlock();
                event.accepted = true;
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            propagateComposedEvents: true
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton && root.editor && root.editor.contextMenu) {
                    editInput.forceActiveFocus();
                    root.editor.contextMenu.open(editInput);
                }
            }
        }
    }
}
}
