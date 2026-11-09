import QtQuick
import Notas
import "."
import "Inline.js" as Inline
import "SpellLogic.js" as SpellLogic
import "SlashLogic.js" as SlashLogic
import "SlashCommands.js" as SlashCommands
import "ReferenceLogic.js" as ReferenceLogic

Item {
    id: root

    property var blockData: null
    property bool isEditing: false
    property var editor: null
    property bool isSelected: false
    property bool inViewportChunk: true
    readonly property bool spellActive: (root.editor && root.editor.spellActive !== undefined) ? root.editor.spellActive : false
    property var spellRanges: []

    implicitWidth: parent ? parent.width : 400
    // F24: misma altura en vista y edición (antes +12 vs +8 → salto de 4px).
    implicitHeight: ((isEditing || isSelected) && editInput.length > 0) ? (editInput.paintedHeight + 10) : (viewText.paintedHeight + 10)

    property bool _syncingModel: false
    property string _lastAppliedHtml: ""
    property bool liveFormattingEnabled: true
    property bool _isDestroyed: false

    Component.onDestruction: {
        _isDestroyed = true;
        spellCheckTimer.stop();
        if (typeof SpellService !== "undefined") {
            SpellService.cancelOwner(root);
        }
    }

    Timer {
        id: spellCheckTimer
        interval: 350
        repeat: false
        onTriggered: _runSpellCheck()
    }

    Connections {
        target: (typeof SpellService !== "undefined") ? SpellService : null
        function onCacheRevisionChanged() {
            if (root.spellActive && (root.inViewportChunk || root.isEditing || root.isSelected)) {
                spellCheckTimer.restart();
            }
        }
        function onAvailableChanged() {
            if (root.spellActive && SpellService.available && (root.inViewportChunk || root.isEditing || root.isSelected)) {
                spellCheckTimer.restart();
            }
        }
    }

    onSpellActiveChanged: {
        if (spellActive && (root.inViewportChunk || root.isEditing || root.isSelected)) {
            spellCheckTimer.restart();
        } else if (!spellActive) {
            root.spellRanges = [];
            if (spellOverlay) spellOverlay.requestUpdate();
        }
    }

    onInViewportChunkChanged: {
        if (inViewportChunk && root.spellActive && (!root.spellRanges || root.spellRanges.length === 0)) {
            spellCheckTimer.restart();
        }
    }

    onSpellRangesChanged: {
        if (root.spellRanges && root.spellRanges.length > 0 && editInput) {
            if (editInput.length === 0 || !root.isEditing) {
                _syncTextFromModel();
            }
        }
        if (spellOverlay) spellOverlay.requestUpdate();
    }

    function _runSpellCheck() {
        if (!root.spellActive || !root.blockData || !root.blockData.raw || typeof SpellService === "undefined" || !SpellService.available) {
            if (root.spellRanges && root.spellRanges.length > 0) root.spellRanges = [];
            return;
        }
        var plain = getRaw();
        if (!plain || plain.trim() === "") {
            if (root.spellRanges && root.spellRanges.length > 0) root.spellRanges = [];
            return;
        }
        var tokens = SpellLogic.tokenize(plain, {
            ignoreUppercase: (typeof SpellConfig !== "undefined") ? SpellConfig.ignoreUppercase : true,
            ignoreWithDigits: (typeof SpellConfig !== "undefined") ? SpellConfig.ignoreWithDigits : true,
            ignoreCamelCase: (typeof SpellConfig !== "undefined") ? SpellConfig.ignoreCamelCase : true,
            ignoreSnakeCase: (typeof SpellConfig !== "undefined") ? SpellConfig.ignoreSnakeCase : true
        });
        if (tokens.length === 0) {
            if (root.spellRanges && root.spellRanges.length > 0) root.spellRanges = [];
            return;
        }
        var words = tokens.map(function(t) { return t.word; });
        SpellService.checkWordsBatch(words, function(results) {
            if (root._isDestroyed) return;
            var badRanges = [];
            for (var i = 0; i < tokens.length; i++) {
                var t = tokens[i];
                var res = results[t.word];
                if (res && res.ok === false) {
                    badRanges.push({
                        start: t.start,
                        end: t.end,
                        word: t.word,
                        suggestions: res.suggestions || []
                    });
                }
            }
            root.spellRanges = badRanges;
            if (badRanges.length > 0 && editInput) {
                if (editInput.length === 0 || !root.isEditing) {
                    _syncTextFromModel();
                }
            }
            if (spellOverlay) spellOverlay.requestUpdate();
        }, root, { text: plain });
    }

    function _openContextMenuAt(targetItem, clickPos, fromKeyboard) {
        if (!root.editor || !root.editor.contextMenu) return;
        var pos = (clickPos !== undefined && clickPos >= 0) ? clickPos : (editInput ? editInput.cursorPosition : -1);
        var err = (root.spellActive && (!root.editor || !root.editor.readOnly)) ? SpellLogic.findRangeAt(root.spellRanges, pos) : null;
        var extras = [];
        if (err) {
            extras.push({
                kind: "header",
                text: (typeof I18n !== "undefined" ? I18n.t("notes.spell.suggestions", "Sugerencias") : "Sugerencias") + " (" + err.word + "):"
            });
            var sugs = err.suggestions || [];
            if (sugs.length === 0) {
                extras.push({
                    text: typeof I18n !== "undefined" ? I18n.t("notes.spell.no_suggestions", "Sin sugerencias") : "Sin sugerencias",
                    enabled: false
                });
            } else {
                var maxSugs = Math.min(5, sugs.length);
                for (var i = 0; i < maxSugs; i++) {
                    (function(sugItem) {
                        var rawWord = (typeof sugItem === "object" && sugItem && sugItem.word) ? sugItem.word : String(sugItem || "");
                        var langBadge = (typeof sugItem === "object" && sugItem && sugItem.lang) ? sugItem.lang.substring(0, 2).toUpperCase() : "";
                        var formattedSug = SpellLogic.matchCapitalization(err.word, rawWord);
                        extras.push({
                            text: formattedSug,
                            shortcut: langBadge,
                            bold: true,
                            onTriggered: function() {
                                _replaceWordAtRange(err, formattedSug);
                            }
                        });
                    })(sugs[i]);
                }
            }
            extras.push({ kind: "separator" });
            extras.push({
                text: typeof I18n !== "undefined" ? I18n.t("notes.spell.ignore", "Ignorar palabra") : "Ignorar palabra",
                onTriggered: function() {
                    if (typeof SpellService !== "undefined") SpellService.ignoreWord(err.word);
                }
            });
            extras.push({
                text: typeof I18n !== "undefined" ? I18n.t("notes.spell.add_to_dict", "Agregar al diccionario") : "Agregar al diccionario",
                onTriggered: function() {
                    if (typeof SpellService !== "undefined") SpellService.addToDictionary(err.word);
                }
            });
        }
        if (fromKeyboard && typeof root.editor.contextMenu.toggleAtTextCursor === "function") {
            root.editor.contextMenu.toggleAtTextCursor(targetItem, extras);
        } else if (fromKeyboard && typeof root.editor.contextMenu.openAtTextCursor === "function") {
            root.editor.contextMenu.openAtTextCursor(targetItem, extras);
        } else {
            root.editor.contextMenu.open(targetItem, extras);
        }
    }

    function _replaceWordAtRange(range, replacement) {
        if (!range || !replacement || !editInput) return;
        if (editInput.text === "") _syncTextFromModel();
        if (!root.isEditing && root.editor && root.blockData) {
            root.editor.requestEditBlock(root.blockData.bid, range.start);
        }
        if (root.editor && root.blockData && typeof root.editor.clearSelectionExcept === "function") {
            root.editor.clearSelectionExcept(root.blockData.bid);
        }
        var maxLen = editInput.length;
        var s = Math.max(0, Math.min(range.start, maxLen));
        var e = Math.max(s, Math.min(range.end, maxLen));
        editInput.forceActiveFocus();
        editInput.select(s, e);
        editInput.remove(s, e);
        editInput.insert(s, replacement);
        var endPos = s + replacement.length;
        var selectWordAction = function() {
            if (!editInput) return;
            var curLen = editInput.length;
            var clampedEnd = Math.max(0, Math.min(endPos, curLen));
            var clampedStart = Math.max(0, Math.min(s, clampedEnd));
            editInput.forceActiveFocus();
            editInput.cursorPosition = clampedEnd;
            editInput.select(clampedStart, clampedEnd);
            if (root.editor && root.blockData && typeof root.editor.notifySingleInputSelection === "function") {
                root.editor.notifySingleInputSelection(root.blockData.bid);
            }
            if (root.editor && typeof root.editor.updateFormatState === "function") {
                root.editor.updateFormatState();
            }
        };
        selectWordAction();
        Qt.callLater(selectWordAction);
        spellCheckTimer.restart();
    }

    function _updateLiveFormatting() {
        if (!root.liveFormattingEnabled || !root.isEditing || root._syncingModel || !editInput) return;
        if (root.editor && (root.editor.readOnly || root.editor._syncingSelection || root.editor.isDraggingSelection || root.editor.hasBlockSelection)) return;
        if (editInput.inputMethodComposing) return;
        var raw = Inline.plainText(editInput);
        if (!raw || !/[*_~=`<\[]/.test(raw)) return;

        var newFormatted = Inline.formatForLiveEditing(raw, {
            cursorPos: editInput.cursorPosition,
            selStart: editInput.selectionStart,
            selEnd: editInput.selectionEnd,
            dimColor: "" + Theme.muted,
            linkColor: "" + Theme.accent,
            hideSyntax: Boolean(root.editor && root.editor.readOnly)
        });
        if (root._lastAppliedHtml !== newFormatted) {
            root._lastAppliedHtml = newFormatted;
            var s = editInput.selectionStart;
            var e = editInput.selectionEnd;
            var curPos = editInput.cursorPosition;
            root._syncingModel = true;
            editInput.text = newFormatted;
            if (s !== e) {
                editInput.select(Math.min(editInput.length, s), Math.min(editInput.length, e));
            } else {
                editInput.cursorPosition = Math.min(editInput.length, curPos);
            }
            root._syncingModel = false;
        }
    }

    Timer {
        id: liveFormatTimer
        interval: 250
        repeat: false
        onTriggered: root._updateLiveFormatting()
    }

    function _syncTextFromModel() {
        if (!root.blockData) return;
        var curPos = editInput ? editInput.cursorPosition : -1;
        var formatted = Inline.formatForLiveEditing(root.blockData.raw, {
            cursorPos: curPos,
            selStart: editInput ? editInput.selectionStart : -1,
            selEnd: editInput ? editInput.selectionEnd : -1,
            dimColor: "" + Theme.muted,
            linkColor: "" + Theme.accent,
            hideSyntax: Boolean(root.editor && root.editor.readOnly)
        });
        var curRaw = Inline.plainText(editInput);
        if (curRaw !== root.blockData.raw || editInput.text === "") {
            var oldPos = editInput.cursorPosition;
            var oldSelStart = editInput.selectionStart;
            var oldSelEnd = editInput.selectionEnd;
            root._syncingModel = true;
            root._lastAppliedHtml = formatted;
            editInput.text = formatted;
            if (oldSelStart !== oldSelEnd) {
                editInput.select(Math.min(editInput.length, oldSelStart), Math.min(editInput.length, oldSelEnd));
            } else {
                editInput.cursorPosition = Math.min(editInput.length, oldPos);
            }
            root._syncingModel = false;
        }
    }

    onBlockDataChanged: {
        if (root.isEditing || root.isSelected) {
            _syncTextFromModel();
        }
        if (root.spellActive && (root.inViewportChunk || root.isEditing || root.isSelected)) {
            spellCheckTimer.restart();
        }
    }

    onIsEditingChanged: {
        if (root.isEditing) {
            _syncTextFromModel();
        } else {
            var sm = root.editor ? root.editor.slashMenu : null;
            if (sm && sm.isOpen && sm.targetInput === editInput) {
                sm.close();
            }
            var lsm = root.editor ? root.editor.linkSuggestionMenu : null;
            if (lsm && lsm.isOpen && lsm.targetInput === editInput) {
                lsm.close();
            }
        }
    }

    onIsSelectedChanged: {
        if (root.isSelected && !root.isEditing) {
            _syncTextFromModel();
        } else if (!root.isSelected && !root.isEditing) {
            clearTextSelection();
        }
    }

    Component.onCompleted: {
        if (root.isEditing) {
            _syncTextFromModel();
        }
        if (root.spellActive && (root.inViewportChunk || root.isEditing || root.isSelected)) {
            spellCheckTimer.restart();
        }
    }

    function getRaw() {
        if (root.isEditing && editInput) {
            return Inline.plainText(editInput);
        }
        return root.blockData ? (root.blockData.raw || "") : "";
    }

    function getTextEdit() {
        return editInput;
    }

    function commitInlineSubEdit(textEdit, newPlain, selStart, selEnd) {
        if (root.blockData && root.editor) {
            root.editor.onBlockRawChanged(root.blockData.bid, newPlain);
        }
        if (textEdit && typeof selStart === "number" && typeof selEnd === "number") {
            textEdit.select(selStart, selEnd);
        }
    }

    function selectRange(start, end) {
        if (!editInput) return;
        if (editInput.text === "") _syncTextFromModel();
        var s = Math.max(0, Math.min(editInput.length, Math.min(start, end)));
        var e = Math.max(0, Math.min(editInput.length, Math.max(start, end)));
        editInput.select(s, e);
    }

    function selectAllText() {
        if (!editInput) return;
        if (editInput.text === "") _syncTextFromModel();
        editInput.selectAll();
    }

    function clearTextSelection() {
        if (!editInput) return;
        editInput.deselect();
    }

    function getCharPosAt(lx, ly) {
        if (!editInput) return 0;
        if (editInput.text === "") _syncTextFromModel();
        return editInput.positionAt(lx, ly);
    }

    function getTextLength() {
        if (!editInput) return 0;
        if (editInput.text === "") _syncTextFromModel();
        return editInput.length;
    }

    function getSelectedText() {
        if (!editInput) return "";
        return editInput.selectedText;
    }

    function getTextContent() {
        if (!editInput) return "";
        return Inline.plainText(editInput);
    }

    function deleteSelectedText() {
        if (!editInput) return;
        var s = editInput.selectionStart;
        var e = editInput.selectionEnd;
        if (s !== e) {
            editInput.remove(s, e);
        }
    }

    function focusInput(cursorPos) {
        if (editInput) {
            _syncTextFromModel();
            editInput.forceActiveFocus();
            if (editInput.selectionStart !== editInput.selectionEnd) return;
            if (root.editor && (root.editor.isDraggingSelection || root.editor.hasBlockSelection || root.editor._syncingSelection)) return;
            if (typeof cursorPos === "object" && cursorPos !== null && typeof cursorPos.x === "number") {
                if (cursorPos.fromBottom === true || (typeof cursorPos.y === "number" && cursorPos.y > 1000)) {
                    var lastRect = editInput.positionToRectangle(editInput.length);
                    var targetY = lastRect.y + (lastRect.height > 0 ? lastRect.height / 2 : 10);
                    editInput.cursorPosition = editInput.positionAt(cursorPos.x, targetY);
                } else if (cursorPos.fromTop === true) {
                    var firstRect = editInput.positionToRectangle(0);
                    var targetY0 = firstRect.y + (firstRect.height > 0 ? firstRect.height / 2 : 10);
                    editInput.cursorPosition = editInput.positionAt(cursorPos.x, targetY0);
                } else if (typeof cursorPos.y === "number") {
                    editInput.cursorPosition = editInput.positionAt(cursorPos.x, cursorPos.y);
                } else {
                    var firstRect2 = editInput.positionToRectangle(0);
                    var targetY02 = firstRect2.y + (firstRect2.height > 0 ? firstRect2.height / 2 : 10);
                    editInput.cursorPosition = editInput.positionAt(cursorPos.x, targetY02);
                }
            } else if (cursorPos === -1 || cursorPos === undefined || cursorPos > editInput.length) {
                editInput.cursorPosition = editInput.length;
            } else {
                editInput.cursorPosition = Math.max(0, Math.min(editInput.length, cursorPos));
            }
            root._updateLiveFormatting();
        }
    }

    // MouseArea para activación y selección por arrastre desde modo lectura
    MouseArea {
        id: viewMa
        anchors.fill: parent
        z: 5
        enabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: viewText.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
        preventStealing: dragging

        property bool dragging: false
        property bool pressedOnLink: false
        property int anchorPos: -1
        property real startX: 0
        property real startY: 0
        property bool isCrossDragging: false
        property bool _doubleClickedRecently: false

        onPressed: (mouse) => {
            _doubleClickedRecently = false;
            if (root.editor && typeof root.editor.resetPreferredCursorX === "function") {
                root.editor.resetPreferredCursorX();
            }
            if (mouse.button === Qt.RightButton) {
                var ptEditR = mapToItem(editInput, mouse.x, mouse.y);
                var posR = editInput.positionAt(ptEditR.x, ptEditR.y);
                _openContextMenuAt(editInput, posR);
                return;
            }
            var ptView = mapToItem(viewText, mouse.x, mouse.y);
            var link = viewText.linkAt(ptView.x, ptView.y);
            pressedOnLink = (link && link !== "");
            if (pressedOnLink) return;
            if (root.editor && root.blockData && typeof root.editor.clearSelectionExcept === "function") {
                root.editor.clearSelectionExcept(root.blockData.bid);
            }
            dragging = true;
            isCrossDragging = false;
            startX = mouse.x;
            startY = mouse.y;
            if (editInput.text === "") _syncTextFromModel();
            var ptEdit = mapToItem(editInput, mouse.x, mouse.y);
            if (root.isEditing) {
                editInput.forceActiveFocus();
                var clickPos = editInput.positionAt(ptEdit.x, ptEdit.y);
                if (clickPos >= 0 && clickPos <= editInput.length) {
                    editInput.cursorPosition = clickPos;
                    anchorPos = clickPos;
                } else {
                    anchorPos = editInput.positionAt(ptEdit.x, ptEdit.y);
                }
            } else {
                anchorPos = editInput.positionAt(ptEdit.x, ptEdit.y);
            }
            if (root.editor && root.blockData) {
                root.editor.requestEditBlock(root.blockData.bid, { x: ptEdit.x, y: ptEdit.y });
                if (typeof root.editor.startCrossBlockDrag === "function") {
                    root.editor.startCrossBlockDrag(root.blockData.bid, anchorPos);
                }
            }
        }

        onPositionChanged: (mouse) => {
            if (!dragging || anchorPos < 0) return;
            if (!isCrossDragging && Math.abs(mouse.x - startX) < 3 && Math.abs(mouse.y - startY) < 3) return;

            // Detectar si el arrastre se salió verticalmente de este bloque
            if (mouse.y < -4 || mouse.y > height + 4 || isCrossDragging) {
                if (!isCrossDragging) {
                    isCrossDragging = true;
                }
                if (root.editor && typeof root.editor.handleCrossBlockDrag === "function") {
                    var ptInContent = mapToItem(root.editor.contentItem, mouse.x, mouse.y);
                    root.editor.handleCrossBlockDrag(root.blockData.bid, ptInContent.y, ptInContent.x);
                    return;
                }
            }

            var ptEdit = mapToItem(editInput, mouse.x, mouse.y);
            editInput.select(anchorPos, editInput.positionAt(ptEdit.x, ptEdit.y));
        }

        onReleased: (mouse) => {
            if (_doubleClickedRecently || (editInput && editInput.selectionStart !== editInput.selectionEnd)) {
                _doubleClickedRecently = false;
            } else if (!isCrossDragging && Math.abs(mouse.x - startX) < 4 && Math.abs(mouse.y - startY) < 4) {
                var ptEditRel = mapToItem(editInput, mouse.x, mouse.y);
                var posRel = editInput.positionAt(ptEditRel.x, ptEditRel.y);
                if (posRel >= 0 && posRel <= editInput.length) {
                    editInput.cursorPosition = posRel;
                }
            }
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
            _doubleClickedRecently = true;
            if (root.editor && root.blockData && typeof root.editor.clearSelectionExcept === "function") {
                root.editor.clearSelectionExcept(root.blockData.bid);
            }
            if (!root.isEditing && root.editor && root.blockData) {
                root.editor.requestEditBlock(root.blockData.bid);
            }
            editInput.forceActiveFocus();
            var ptEdit = mapToItem(editInput, mouse.x, mouse.y);
            var pos = editInput.positionAt(ptEdit.x, ptEdit.y);
            if (pos >= 0 && pos <= editInput.length) {
                editInput.cursorPosition = pos;
                editInput.selectWord();
            }
        }

        onClicked: (mouse) => {
            if (pressedOnLink) {
                var ptView = mapToItem(viewText, mouse.x, mouse.y);
                var link = viewText.linkAt(ptView.x, ptView.y);
                if (link && link !== "") {
                    triggerLinkEffect(ptView.x, ptView.y, link);
                    if (root.editor && typeof root.editor.handleLink === "function") {
                        root.editor.handleLink(link);
                    }
                }
            }
        }
    }

    function _findLinkBoundingBox(viewItem, clickX, clickY, linkUrl) {
        if (!viewItem || !linkUrl) return null;
        var x = clickX;
        var y = clickY;
        if (viewItem.linkAt(x, y) !== linkUrl) {
            var offsets = [[0, 1], [0, -1], [1, 0], [-1, 0], [0, 2], [0, -2]];
            var found = false;
            for (var o = 0; o < offsets.length; o++) {
                if (viewItem.linkAt(x + offsets[o][0], y + offsets[o][1]) === linkUrl) {
                    x += offsets[o][0];
                    y += offsets[o][1];
                    found = true;
                    break;
                }
            }
            if (!found) return null;
        }

        var leftX = x;
        while (leftX > 4 && viewItem.linkAt(leftX - 4, y) === linkUrl) leftX -= 4;
        while (leftX > 0 && viewItem.linkAt(leftX - 1, y) === linkUrl) leftX -= 1;

        var rightX = x;
        var maxW = viewItem.width;
        while (rightX + 4 < maxW && viewItem.linkAt(rightX + 4, y) === linkUrl) rightX += 4;
        while (rightX + 1 < maxW && viewItem.linkAt(rightX + 1, y) === linkUrl) rightX += 1;

        var topY = y;
        while (topY > 2 && viewItem.linkAt(x, topY - 2) === linkUrl) topY -= 2;
        while (topY > 0 && viewItem.linkAt(x, topY - 1) === linkUrl) topY -= 1;

        var bottomY = y;
        var maxH = viewItem.height;
        while (bottomY + 2 < maxH && viewItem.linkAt(x, bottomY + 2) === linkUrl) bottomY += 2;
        while (bottomY + 1 < maxH && viewItem.linkAt(x, bottomY + 1) === linkUrl) bottomY += 1;

        var w = Math.max(8, rightX - leftX + 1);
        var h = Math.max(12, bottomY - topY + 1);
        return { x: leftX, y: topY, width: w, height: h };
    }

    function triggerLinkEffect(clickX, clickY, linkUrl) {
        var box = _findLinkBoundingBox(viewText, clickX, clickY, linkUrl);
        if (box) {
            linkPressOverlay.targetX = box.x;
            linkPressOverlay.targetY = box.y;
            linkPressOverlay.targetW = box.width;
            linkPressOverlay.targetH = box.height;
            linkPressOverlay.active = true;
            linkTimer.restart();
        }
    }

    Rectangle {
        id: linkPressMask
        visible: linkPressOverlay.active
        x: linkPressOverlay.targetX - 2
        y: linkPressOverlay.targetY - 1
        width: linkPressOverlay.targetW + 4
        height: linkPressOverlay.targetH + 2
        radius: 3
        color: (root.editor && root.editor.backgroundColor) ? root.editor.backgroundColor : Theme.surface
    }

    Item {
        id: linkPressOverlay
        visible: active
        z: 10
        property bool active: false
        property real targetX: 0
        property real targetY: 0
        property real targetW: 0
        property real targetH: 0

        x: targetX - 3
        y: targetY - 2
        width: targetW + 6
        height: targetH + 4

        scale: active ? 0.91 : 1.0
        transformOrigin: Item.Center

        Behavior on scale {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            SpringAnimation {
                spring: 8.5
                damping: 0.88
                mass: 0.45
                epsilon: 0.05
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
            border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
            border.width: 1
        }

        ShaderEffectSource {
            anchors.centerIn: parent
            width: linkPressOverlay.targetW
            height: linkPressOverlay.targetH
            sourceItem: viewText
            sourceRect: Qt.rect(linkPressOverlay.targetX, linkPressOverlay.targetY, linkPressOverlay.targetW, linkPressOverlay.targetH)
            live: false
        }
    }

    // Vista renderizada (no edición)
    Text {
        id: viewText
        visible: !root.isEditing && !root.isSelected
        width: parent.width
        textFormat: Text.RichText
        text: root.blockData ? Inline.inlineToHtml(root.blockData.raw, {
            zoom: EditorMetrics.zoom,
            textColor: "" + Theme.text,
            mathColor: "" + Theme.text,
            mathPtSize: Math.max(8.0, EditorMetrics.body * 0.75),
            fontFamilyMonospace: Theme.fontFamilyMonospace || "Google Sans Code",
            linkColor: "" + Theme.accent, highlightBg: EditorMetrics.highlightBg,
            baseFolder: root.editor ? root.editor.imgBaseFolder : "",
            imageSkipMissing: true,
            imageExists: root.editor ? root.editor.imageExistsFn : null,
            probeTick: NotesService.imageProbeSeq,
            searchQuery: root.editor ? root.editor.searchQuery : "",
            searchHighlightBg: root.editor ? ("" + root.editor.searchHighlightColor) : "",
            searchHighlightActiveBg: root.editor ? root.editor.searchActiveBg(root.blockData.bid, 0) : "",
            searchActiveOrdinal: root.editor ? root.editor.searchActiveOrdinal(root.blockData.bid, 0) : -1,
            searchHighlightActiveFg: root.editor ? root.editor.searchActiveFg(root.blockData.bid, 0) : ""
        }) : ""
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: EditorMetrics.body
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        lineHeight: EditorMetrics.lineHeight

        onLinkActivated: (link) => {
            if (root.editor && typeof root.editor.handleLink === "function") {
                root.editor.handleLink(link);
            }
        }

        Timer {
            id: linkTimer
            interval: 160
            repeat: false
            onTriggered: {
                linkPressOverlay.active = false;
            }
        }

        HoverHandler {
            enabled: parent.hoveredLink !== ""
            cursorShape: Qt.PointingHandCursor
        }
    }

    // Vista de edición en vivo (estilo Typora)
    TextEdit {
        id: editInput
        persistentSelection: true
        overwriteMode: root.editor ? root.editor.overwriteMode : false
        visible: root.isEditing || root.isSelected
        readOnly: !root.isEditing || (root.editor && root.editor.readOnly)
        cursorVisible: activeFocus && root.isEditing && (!root.editor || !root.editor.readOnly)
        width: parent.width
        textFormat: TextEdit.RichText
        text: ""
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: EditorMetrics.body
        wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
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
            if (root.isEditing && !root._syncingModel && root.liveFormattingEnabled) {
                root._updateLiveFormatting();
            }
        }
        onSelectionEndChanged: {
            if (root.editor && !root.editor._syncingSelection && !root.editor.hasBlockSelection && !root.editor.isDraggingSelection) {
                if (editInput.selectionStart !== editInput.selectionEnd && root.blockData && typeof root.editor.notifySingleInputSelection === "function") {
                    root.editor.notifySingleInputSelection(root.blockData.bid);
                }
                if (typeof root.editor.updateFormatState === "function") root.editor.updateFormatState();
            }
            if (root.isEditing && !root._syncingModel && root.liveFormattingEnabled) {
                root._updateLiveFormatting();
            }
        }
        onCursorPositionChanged: {
            if (root.editor && !root.editor._syncingSelection && !root.editor.hasBlockSelection && !root.editor.isDraggingSelection) {
                if (editInput.activeFocus && editInput.selectionStart === editInput.selectionEnd && root.blockData && typeof root.editor.notifySingleInputSelection === "function") {
                    root.editor.notifySingleInputSelection(root.blockData.bid);
                }
                if (typeof root.editor.updateFormatState === "function") root.editor.updateFormatState();
            }
            if (root.isEditing && !root._syncingModel && root.liveFormattingEnabled) {
                root._updateLiveFormatting();
            }
            if (root.isEditing && root.editor && !root.editor.readOnly && !root._syncingModel) {
                var sm = root.editor.slashMenu;
                var rawCleanCur = Inline.plainText(editInput);
                if (sm && sm.isOpen) {
                    var trigger = SlashLogic.detectTrigger(rawCleanCur, editInput.cursorPosition);
                    if (trigger.triggered) {
                        var cmds = SlashLogic.filterCommands(SlashCommands.getAllCommands(), trigger.query, I18n);
                        sm.update(trigger, cmds);
                    } else {
                        sm.close();
                    }
                }
                var lsm = root.editor.linkSuggestionMenu;
                if (lsm && lsm.isOpen) {
                    var wTrigger = ReferenceLogic.detectWikilinkTrigger(rawCleanCur, editInput.cursorPosition);
                    if (wTrigger.triggered) {
                        if (wTrigger.mode === "anchor") {
                            var headings = wTrigger.isCurrentNote
                                ? (root.editor.getActiveHeadings ? root.editor.getActiveHeadings() : [])
                                : (root.editor.getNoteHeadings ? root.editor.getNoteHeadings(wTrigger.noteTitle) : []);
                            var filteredH = ReferenceLogic.filterHeadings(headings, wTrigger.query);
                            lsm.update(wTrigger, "anchors", filteredH, wTrigger.noteTitle);
                        } else {
                            var notesList = (typeof NotesService !== "undefined" && NotesService.notes) ? NotesService.notes : [];
                            var filteredN = ReferenceLogic.filterNotes(notesList, wTrigger.query);
                            lsm.update(wTrigger, "notes", filteredN, "");
                        }
                    } else {
                        lsm.close();
                    }
                }
            }
        }

        onTextChanged: {
            if (root._syncingModel || (root.editor && root.editor.readOnly)) return;
            if (root.isEditing && root.editor && root.blockData) {
                var rawClean = Inline.plainText(editInput);
                if (rawClean !== root.blockData.raw) {
                    root.editor.onBlockRawChanged(root.blockData.bid, rawClean);
                }
                if (root.liveFormattingEnabled && !editInput.inputMethodComposing && /[*_~=`]/.test(rawClean)) {
                    liveFormatTimer.restart();
                }
                if (root.spellActive) {
                    spellCheckTimer.restart();
                }

                // F78: Detección interactiva de slash commands estilo Notion
                if (!editInput.inputMethodComposing) {
                    var trigger = SlashLogic.detectTrigger(rawClean, editInput.cursorPosition);
                    var sm = root.editor ? root.editor.slashMenu : null;
                    if (trigger.triggered) {
                        var cmds = SlashLogic.filterCommands(SlashCommands.getAllCommands(), trigger.query, I18n);
                        if (sm) {
                            if (sm.isOpen) {
                                sm.update(trigger, cmds);
                            } else {
                                sm.open(editInput, trigger, cmds);
                            }
                        }
                    } else {
                        if (sm && sm.isOpen) {
                            sm.close();
                        }
                    }

                    // Detección interactiva de Wikilinks y Anclas
                    var wTrigger = ReferenceLogic.detectWikilinkTrigger(rawClean, editInput.cursorPosition);
                    var lsm = root.editor ? root.editor.linkSuggestionMenu : null;
                    if (wTrigger.triggered) {
                        if (lsm) {
                            if (wTrigger.mode === "anchor") {
                                var headings = wTrigger.isCurrentNote
                                    ? (root.editor.getActiveHeadings ? root.editor.getActiveHeadings() : [])
                                    : (root.editor.getNoteHeadings ? root.editor.getNoteHeadings(wTrigger.noteTitle) : []);
                                var filteredH = ReferenceLogic.filterHeadings(headings, wTrigger.query);
                                if (lsm.isOpen) {
                                    lsm.update(wTrigger, "anchors", filteredH, wTrigger.noteTitle);
                                } else {
                                    lsm.open(editInput, wTrigger, "anchors", filteredH, wTrigger.noteTitle);
                                }
                            } else {
                                var notesList = (typeof NotesService !== "undefined" && NotesService.notes) ? NotesService.notes : [];
                                var filteredN = ReferenceLogic.filterNotes(notesList, wTrigger.query);
                                if (lsm.isOpen) {
                                    lsm.update(wTrigger, "notes", filteredN, "");
                                } else {
                                    lsm.open(editInput, wTrigger, "notes", filteredN, "");
                                }
                            }
                        }
                    } else if (lsm && lsm.isOpen && lsm.targetInput === editInput) {
                        lsm.close();
                    }
                }
            }
        }


        Keys.onTabPressed: (event) => {
            if (root.editor && root.editor.readOnly) {
                event.accepted = true;
                return;
            }
            var sm = root.editor ? root.editor.slashMenu : null;
            if (sm && sm.isOpen) {
                if (sm.triggerSelectedItem()) {
                    event.accepted = true;
                    return;
                }
            }
            var pos = editInput.cursorPosition;
            var isLineStart = (pos === 0 || editInput.text.charAt(pos - 1) === "\n");
            if (isLineStart) {
                event.accepted = true;
                return;
            }
            if (editInput.selectionStart !== editInput.selectionEnd) {
                editInput.remove(editInput.selectionStart, editInput.selectionEnd);
            }
            editInput.insert(editInput.cursorPosition, "  ");
            event.accepted = true;
        }

        Keys.onReturnPressed: (event) => {
            if (root.editor && root.editor.readOnly) {
                event.accepted = true;
                return;
            }
            var lsm = root.editor ? root.editor.linkSuggestionMenu : null;
            if (lsm && lsm.isOpen) {
                if (lsm.triggerSelectedItem()) {
                    event.accepted = true;
                    return;
                }
                lsm.close();
                event.accepted = true;
                return;
            }
            var sm = root.editor ? root.editor.slashMenu : null;
            if (sm && sm.isOpen) {
                if (sm.triggerSelectedItem()) {
                    event.accepted = true;
                    return;
                }
                sm.close();
                event.accepted = true;
                return;
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
            if (event.modifiers & Qt.ShiftModifier) {
                editInput.insert(editInput.cursorPosition, "  \n");
                event.accepted = true;
            } else {
                if (root.editor) {
                    root.editor.handleBlockEnter(root.blockData.bid, editInput.cursorPosition);
                    event.accepted = true;
                }
            }
        }

        Keys.onEnterPressed: (event) => {
            Keys.onReturnPressed(event);
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

            var sm = root.editor ? root.editor.slashMenu : null;
            if (sm && sm.isOpen) {
                if (event.key === Qt.Key_Escape) {
                    sm.close();
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Up) {
                    sm.selectPreviousItem();
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Down) {
                    sm.selectNextItem();
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) {
                    if (sm.triggerSelectedItem()) {
                        event.accepted = true;
                        return;
                    }
                    sm.close();
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
                _openContextMenuAt(editInput, editInput.cursorPosition, true);
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

            if (root.editor && typeof root.editor.handleAutoPair === "function") {
                if (root.editor.handleAutoPair(editInput, event)) {
                    return;
                }
            }

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
                if (root.editor && typeof root.editor.handleBackspaceAutoPair === "function") {
                    if (root.editor.handleBackspaceAutoPair(editInput)) {
                        event.accepted = true;
                        return;
                    }
                }
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
            var lsm = root.editor ? root.editor.linkSuggestionMenu : null;
            if (lsm && lsm.isOpen) {
                lsm.selectPreviousItem();
                event.accepted = true;
                return;
            }
            var sm = root.editor ? root.editor.slashMenu : null;
            if (sm && sm.isOpen) {
                sm.selectPreviousItem();
                event.accepted = true;
                return;
            }
            if (event.modifiers & Qt.AltModifier) {
                if (root.editor && root.blockData && typeof root.editor.moveBlockUp === "function") {
                    root.editor.moveBlockUp(root.blockData.bid);
                    event.accepted = true;
                    return;
                }
            }
            var cm = root.editor ? root.editor.contextMenu : null;
            if (cm && cm.visible && !cm.isClosing) {
                cm.selectPreviousItem();
                event.accepted = true;
                return;
            }
            var curX = editInput.positionToRectangle(editInput.cursorPosition).x;
            var targetX = (root.editor && typeof root.editor.getPreferredCursorX === "function") ? root.editor.getPreferredCursorX(curX) : curX;
            if (event.modifiers & Qt.ShiftModifier) {
                var curYShift = editInput.positionToRectangle(editInput.cursorPosition).y;
                var topYShift = editInput.positionToRectangle(0).y;
                if (curYShift <= topYShift + 4) {
                    if (editInput.cursorPosition === 0) {
                        if (root.editor && root.blockData && typeof root.editor.extendKeyboardSelectionUp === "function") {
                            root.editor.extendKeyboardSelectionUp(root.blockData.bid, editInput.cursorPosition);
                            event.accepted = true;
                            return;
                        }
                    } else {
                        var anchorUp = (editInput.selectionStart === editInput.cursorPosition) ? editInput.selectionEnd : editInput.selectionStart;
                        editInput.select(anchorUp, 0);
                        event.accepted = true;
                        return;
                    }
                }
                event.accepted = false;
                return;
            }
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
            var lsm = root.editor ? root.editor.linkSuggestionMenu : null;
            if (lsm && lsm.isOpen) {
                lsm.selectNextItem();
                event.accepted = true;
                return;
            }
            var sm = root.editor ? root.editor.slashMenu : null;
            if (sm && sm.isOpen) {
                sm.selectNextItem();
                event.accepted = true;
                return;
            }
            if (event.modifiers & Qt.AltModifier) {
                if (root.editor && root.blockData && typeof root.editor.moveBlockDown === "function") {
                    root.editor.moveBlockDown(root.blockData.bid);
                    event.accepted = true;
                    return;
                }
            }
            var cm = root.editor ? root.editor.contextMenu : null;
            if (cm && cm.visible && !cm.isClosing) {
                cm.selectNextItem();
                event.accepted = true;
                return;
            }
            var curXDown = editInput.positionToRectangle(editInput.cursorPosition).x;
            var targetXDown = (root.editor && typeof root.editor.getPreferredCursorX === "function") ? root.editor.getPreferredCursorX(curXDown) : curXDown;
            if (event.modifiers & Qt.ShiftModifier) {
                var curYShiftDown = editInput.positionToRectangle(editInput.cursorPosition).y;
                var botYShiftDown = editInput.positionToRectangle(editInput.length).y;
                if (curYShiftDown >= botYShiftDown - 4) {
                    if (editInput.cursorPosition === editInput.length) {
                        if (root.editor && root.blockData && typeof root.editor.extendKeyboardSelectionDown === "function") {
                            root.editor.extendKeyboardSelectionDown(root.blockData.bid, editInput.cursorPosition);
                            event.accepted = true;
                            return;
                        }
                    } else {
                        var anchorDown = (editInput.selectionStart === editInput.cursorPosition) ? editInput.selectionEnd : editInput.selectionStart;
                        editInput.select(anchorDown, editInput.length);
                        event.accepted = true;
                        return;
                    }
                }
                event.accepted = false;
                return;
            }
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
            var lsm = root.editor ? root.editor.linkSuggestionMenu : null;
            if (lsm && lsm.isOpen) {
                lsm.close();
                event.accepted = true;
                return;
            }
            var sm = root.editor ? root.editor.slashMenu : null;
            if (sm && sm.isOpen) {
                sm.close();
                event.accepted = true;
                return;
            }
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
                    var pos = editInput.positionAt(mouse.x, mouse.y);
                    _openContextMenuAt(editInput, pos);
                }
            }
        }
    }

    SpellOverlay {
        id: spellOverlay
        visible: (root.isEditing || root.isSelected) && root.spellActive && root.spellRanges && root.spellRanges.length > 0
        textItem: editInput
        ranges: root.spellRanges
        active: root.spellActive
        waveColor: Theme.color3
    }
}
