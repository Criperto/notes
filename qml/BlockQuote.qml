import QtQuick
import QtQuick.Effects
import Notas
import "."
import "Inline.js" as Inline
import "QuoteParser.js" as QP
import "CalloutTypes.js" as CalloutTypes
import "SpellLogic.js" as SpellLogic

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
    // F24 / F77: misma altura en vista y edición con escalado proporcional a zoom
    implicitHeight: ((isEditing || isSelected) && editInput.length > 0)
        ? (editInput.paintedHeight + Math.round(14 * EditorMetrics.zoom))
        : (viewCol.implicitHeight + Math.round(14 * EditorMetrics.zoom))

    readonly property string cleanQuoteText: {
        if (!blockData || !blockData.raw) return "";
        return blockData.raw.replace(/^[ \t]*>[ \t]?/gm, "");
    }

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
        var plain = root.cleanQuoteText;
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

    // F77: Detección y propiedades de Callouts estilo GitHub
    readonly property var calloutInfo: QP.parseCallout(blockData ? blockData.raw : "")
    readonly property bool isCallout: calloutInfo !== null
    readonly property string calloutType: isCallout ? calloutInfo.type : ""
    readonly property var calloutTypeDef: isCallout ? CalloutTypes.getType(calloutType) : null
    readonly property color calloutColor: isCallout ? CalloutTypes.getColor(calloutType, Theme) : Theme.accent
    readonly property bool hasCustomTitle: isCallout && calloutInfo.title && calloutInfo.title.trim() !== ""
    readonly property string calloutTitleText: {
        if (!isCallout || !calloutTypeDef) return "";
        if (hasCustomTitle) return calloutInfo.title.trim();
        return (typeof I18n !== "undefined" && typeof I18n.t === "function")
            ? I18n.t(calloutTypeDef.nameKey, calloutTypeDef.fallbackName)
            : calloutTypeDef.fallbackName;
    }

    function _headerHtml(titleText) {
        var opts = {
            zoom: EditorMetrics.zoom,
            textColor: "" + Theme.text,
            mathColor: "" + Theme.text,
            mathPtSize: Math.max(8.0, EditorMetrics.body * 0.75),
            fontFamilyMonospace: Theme.fontFamilyMonospace || "Google Sans Code",
            linkColor: "" + Theme.accent,
            highlightBg: EditorMetrics.highlightBg,
            searchQuery: root.editor ? root.editor.searchQuery : "",
            searchHighlightBg: root.editor ? ("" + root.editor.searchHighlightColor) : "",
            searchHighlightActiveBg: (root.editor && root.blockData) ? root.editor.searchActiveBg(root.blockData.bid, 0) : "",
            searchActiveOrdinal: (root.editor && root.blockData) ? root.editor.searchActiveOrdinal(root.blockData.bid, 0) : -1,
            searchHighlightActiveFg: (root.editor && root.blockData) ? root.editor.searchActiveFg(root.blockData.bid, 0) : ""
        };
        return Inline.inlineToHtml(titleText, opts);
    }

    // F25 / F77: segmentos aplanados para la vista (párrafo / encabezado / ítem de lista),
    // con profundidad visual para barras anidadas. Solo lectura; edición sin cambios.
    readonly property var quoteSegments: {
        if (!blockData || !blockData.raw) return [];
        try {
            if (isCallout) {
                if (!calloutInfo.bodyRaw || calloutInfo.bodyRaw.trim() === "") return [];
                return QP.flattenQuote(QP.parseQuote(calloutInfo.bodyRaw));
            }
            return QP.flattenQuote(QP.parseQuote(blockData.raw));
        } catch (e) {
            return [{ kind: "paragraph", depth: 1, text: cleanQuoteText }];
        }
    }

    // Tamaños de encabezado (reutiliza el único de EditorMetrics, como BlockList).
    readonly property var headingSizes: ({
        1: EditorMetrics.headingSize(1),
        2: EditorMetrics.headingSize(2),
        3: EditorMetrics.headingSize(3),
        4: EditorMetrics.headingSize(4),
        5: EditorMetrics.headingSize(5),
        6: EditorMetrics.headingSize(6)
    })

    property bool _syncingModel: false
    property string _lastAppliedHtml: ""

    function _syncTextFromModel() {
        if (!root.blockData) return;
        var curPos = editInput ? editInput.cursorPosition : -1;
        var formatted = Inline.formatForLiveEditing(root.cleanQuoteText, {
            cursorPos: curPos,
            selStart: editInput ? editInput.selectionStart : -1,
            selEnd: editInput ? editInput.selectionEnd : -1,
            dimColor: "" + Theme.muted,
            linkColor: "" + Theme.accent,
            hideSyntax: Boolean(root.editor && root.editor.readOnly)
        });
        var curRaw = Inline.plainText(editInput);
        if (curRaw !== root.cleanQuoteText || editInput.text === "") {
            var oldPos = editInput.cursorPosition;
            root._syncingModel = true;
            root._lastAppliedHtml = formatted;
            editInput.text = formatted;
            editInput.cursorPosition = Math.min(editInput.length, oldPos);
            root._syncingModel = false;
        }
    }

    function _updateLiveFormatting() {
        if (!root.isEditing || root._syncingModel || !editInput) return;
        if (root.editor && (root.editor.readOnly || root.editor._syncingSelection)) return;
        if (editInput.inputMethodComposing) return;
        var clean = Inline.plainText(editInput);
        if (!clean || !/[*_~=`<\[]/.test(clean)) return;

        var newFormatted = Inline.formatForLiveEditing(clean, {
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

    function getRaw() {
        if (root.isEditing && editInput) {
            var clean = Inline.plainText(editInput);
            // F25: si el usuario no cambió nada, devolver el raw original byte a byte
            // (preserva `>>` vs `> >` y espacios variables; la forma canónica `> `
            // normalizaría y el archivo cambiaría sin haber editado).
            if (root.blockData && clean === root.cleanQuoteText) {
                return root.blockData.raw || "";
            }
            var lines = clean.split("\n");
            return lines.map(function(l) { return "> " + l; }).join("\n");
        }
        return root.blockData ? (root.blockData.raw || "") : "";
    }

    // F25 / F77: enlace bajo un punto de la vista segmentada (para viewMa).
    function quoteLinkAt(mx, my) {
        if (root.isCallout && calloutTitleLabel.visible && calloutTitleLabel.textFormat === Text.RichText) {
            var pt0 = mapToItem(calloutTitleLabel, mx, my);
            var l0 = calloutTitleLabel.linkAt(pt0.x, pt0.y);
            if (l0 && l0 !== "") return l0;
        }
        for (var i = 0; i < segmentsRepeater.count; i++) {
            var del = segmentsRepeater.itemAt(i);
            if (del && typeof del.linkAtGlobal === "function") {
                var lk = del.linkAtGlobal(mx, my);
                if (lk && lk !== "") return lk;
            }
        }
        return "";
    }

    function getTextEdit() {
        return editInput;
    }

    function commitInlineSubEdit(textEdit, newPlain, selStart, selEnd) {
        var lines = newPlain.split("\n");
        var fullRaw = lines.map(function(l) { return "> " + l; }).join("\n");
        if (root.blockData && root.editor) {
            root.editor.onBlockRawChanged(root.blockData.bid, fullRaw);
        }
        if (textEdit && typeof selStart === "number" && typeof selEnd === "number") {
            textEdit.select(selStart, selEnd);
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
            } else if (cursorPos === -1 || cursorPos === undefined || cursorPos > editInput.length) {
                editInput.cursorPosition = editInput.length;
            } else {
                editInput.cursorPosition = Math.max(0, Math.min(editInput.length, cursorPos));
            }
            root._updateLiveFormatting();
        }
    }

    // Fondo sutil del callout (F77)
    Rectangle {
        id: calloutBg
        visible: root.isCallout && !root.isEditing && !root.isSelected
        anchors.fill: parent
        radius: Math.max(4, Math.round(6 * EditorMetrics.zoom))
        color: root.calloutColor
        opacity: Theme.isDark ? 0.08 : 0.05
    }

    // Barra de acento izquierda
    Rectangle {
        id: quoteBar
        width: root.isCallout ? Math.max(3, Math.round(4 * EditorMetrics.zoom)) : Math.max(2, Math.round(3 * EditorMetrics.zoom))
        height: parent.height - 4
        y: 2
        radius: root.isCallout ? Math.max(1.5, Math.round(2 * EditorMetrics.zoom)) : 1.5
        color: root.isCallout ? root.calloutColor : Theme.accent
    }

    // Vista renderizada segmentada (F25 / F77: encabezado / anidado / lista / callout).
    // Solo lectura; edición sin cambios y .md intacto (ver getRaw).
    Item {
        id: viewCol
        visible: !root.isEditing && !root.isSelected
        anchors.left: quoteBar.right
        anchors.right: parent.right
        anchors.leftMargin: root.isCallout ? Math.round(14 * EditorMetrics.zoom) : Math.round(12 * EditorMetrics.zoom)
        anchors.rightMargin: root.isCallout ? Math.round(12 * EditorMetrics.zoom) : 0
        anchors.top: parent.top
        anchors.topMargin: root.isCallout ? Math.round(8 * EditorMetrics.zoom) : 0
        implicitHeight: contentCol.implicitHeight + (root.isCallout ? Math.round(16 * EditorMetrics.zoom) : 0)

        Column {
            id: contentCol
            width: parent.width
            spacing: root.isCallout ? Math.round(6 * EditorMetrics.zoom) : Math.round(4 * EditorMetrics.zoom)

            // Cabecera del Callout (ícono + título adaptados al zoom del editor)
            Row {
                id: calloutHeader
                visible: root.isCallout
                width: parent.width
                height: Math.max(18, Math.round(24 * EditorMetrics.zoom))
                spacing: Math.max(4, Math.round(8 * EditorMetrics.zoom))

                Item {
                    id: calloutIconBox
                    width: Math.max(14, Math.round(18 * EditorMetrics.zoom))
                    height: width
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        id: calloutIconImg
                        anchors.fill: parent
                        source: root.calloutTypeDef ? (Theme.iconsPath + root.calloutTypeDef.icon) : ""
                        sourceSize: Qt.size(parent.width, parent.height)
                        visible: false
                    }

                    MultiEffect {
                        anchors.fill: calloutIconImg
                        source: calloutIconImg
                        colorization: 1.0
                        colorizationColor: root.calloutColor
                        visible: calloutIconImg.status === Image.Ready
                    }
                }

                Text {
                    id: calloutTitleLabel
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.weight: Font.DemiBold
                    font.pixelSize: Math.round(EditorMetrics.body * 1.05)
                    color: root.calloutColor
                    text: root.hasCustomTitle ? root._headerHtml(root.calloutTitleText) : root.calloutTitleText
                    textFormat: root.hasCustomTitle ? Text.RichText : Text.PlainText
                    onLinkActivated: (link) => {
                        if (root.editor && typeof root.editor.handleLink === "function") root.editor.handleLink(link);
                    }
                    HoverHandler {
                        enabled: parent.hoveredLink !== ""
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }

            Column {
                id: segmentsCol
                width: parent.width
                spacing: 4

                Repeater {
                    id: segmentsRepeater
                    model: root.quoteSegments

                    delegate: Item {
                        id: segWrap
                        width: segmentsCol.width
                        implicitHeight: segRow.implicitHeight

                        readonly property var seg: modelData
                        readonly property int segIndex: index
                        readonly property int effectiveSearchUnitIndex: root.hasCustomTitle ? (segWrap.segIndex + 1) : segWrap.segIndex
                        readonly property int segDepth: (seg && seg.depth) ? seg.depth : 1
                        readonly property string segKind: (seg && seg.kind) ? seg.kind : "paragraph"
                        readonly property string segText: (seg && seg.text) ? seg.text : ""
                        readonly property int segLevel: (seg && seg.level) ? seg.level : 0

                        function linkAtGlobal(mx, my) {
                            var pt;
                            if (segPara.visible) {
                                pt = mapToItem(segPara, mx, my);
                                var l1 = segPara.linkAt(pt.x, pt.y);
                                if (l1 && l1 !== "") return l1;
                            }
                            if (segHead.visible) {
                                pt = mapToItem(segHead, mx, my);
                                var l2 = segHead.linkAt(pt.x, pt.y);
                                if (l2 && l2 !== "") return l2;
                            }
                            if (segItemText.visible) {
                                pt = mapToItem(segItemText, mx, my);
                                var l3 = segItemText.linkAt(pt.x, pt.y);
                                if (l3 && l3 !== "") return l3;
                            }
                            return "";
                        }

                        function segHtml(rawMd, useHeading) {
                            var opts = {
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
                                searchHighlightActiveBg: (root.editor && root.blockData) ? root.editor.searchActiveBg(root.blockData.bid, segWrap.effectiveSearchUnitIndex) : "",
                                searchActiveOrdinal: (root.editor && root.blockData) ? root.editor.searchActiveOrdinal(root.blockData.bid, segWrap.effectiveSearchUnitIndex) : -1,
                                searchHighlightActiveFg: (root.editor && root.blockData) ? root.editor.searchActiveFg(root.blockData.bid, segWrap.effectiveSearchUnitIndex) : ""
                            };
                            if (useHeading) opts.headingSizes = root.headingSizes;
                            return Inline.inlineToHtml(rawMd, opts);
                        }

                        Row {
                            id: segRow
                            width: parent.width
                            spacing: 6

                            // Barras extra para niveles anidados (la primera la da quoteBar).
                            Repeater {
                                model: Math.max(0, segWrap.segDepth - 1)
                                delegate: Rectangle {
                                    width: 3
                                    height: segContent.implicitHeight > 0 ? segContent.implicitHeight : 18
                                    radius: 1.5
                                    color: root.isCallout ? root.calloutColor : Theme.accent
                                    opacity: 0.65
                                }
                            }

                        // Marcador de lista (solo lectura, mismos estilos que BlockList).
                        Item {
                            width: 20
                            height: 22
                            visible: segWrap.segKind === "listItem" && !(segWrap.seg && segWrap.seg.isTask)
                            Text {
                                anchors.centerIn: parent
                                text: {
                                    var mk = (segWrap.seg && segWrap.seg.marker) ? segWrap.seg.marker : "-";
                                    return (mk.indexOf(".") !== -1 || mk.indexOf(")") !== -1) ? mk : "•";
                                }
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: EditorMetrics.body
                                font.bold: true
                            }
                        }

                        Item {
                            width: 22
                            height: 22
                            visible: segWrap.segKind === "listItem" && (segWrap.seg && segWrap.seg.isTask)
                            Image {
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                source: Theme.iconsPath + ((segWrap.seg && segWrap.seg.checked) ? "check-box.svg" : "check-box-outline-blank.svg")
                                sourceSize: Qt.size(16, 16)
                                smooth: true
                                mipmap: true
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: (segWrap.seg && segWrap.seg.checked) ? Theme.accent : Theme.muted
                                }
                            }
                        }

                        Item {
                            id: segContent
                            width: parent.width - x
                            implicitHeight: segContentCol.implicitHeight

                            Column {
                                id: segContentCol
                                width: parent.width
                                spacing: 0

                                Text {
                                    id: segPara
                                    visible: segWrap.segKind === "paragraph"
                                    width: parent.width
                                    textFormat: Text.RichText
                                    text: segWrap.visible ? segWrap.segHtml(Inline.stripImages(segWrap.segText), false) : ""
                                    color: root.isCallout ? Theme.text : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.88)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: EditorMetrics.body
                                    font.italic: !root.isCallout
                                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                    lineHeight: EditorMetrics.lineHeight
                                    onLinkActivated: (link) => {
                                        if (root.editor && typeof root.editor.handleLink === "function") root.editor.handleLink(link);
                                    }
                                    HoverHandler {
                                        enabled: parent.hoveredLink !== ""
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                }

                                Text {
                                    id: segHead
                                    visible: segWrap.segKind === "heading"
                                    width: parent.width
                                    textFormat: Text.RichText
                                    // inlineToHtml consume el `## ` inicial con headingSizes (igual que BlockList).
                                    text: {
                                        if (!segWrap.visible) return "";
                                        var hp = "";
                                        for (var hh = 0; hh < (segWrap.segLevel > 0 ? segWrap.segLevel : 2); hh++) hp += "#";
                                        return segWrap.segHtml(hp + " " + segWrap.segText, true);
                                    }
                                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.92)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: EditorMetrics.headingSize(segWrap.segLevel > 0 ? segWrap.segLevel : 2)
                                    font.bold: true
                                    font.italic: !root.isCallout
                                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                    lineHeight: EditorMetrics.lineHeight
                                    onLinkActivated: (link) => {
                                        if (root.editor && typeof root.editor.handleLink === "function") root.editor.handleLink(link);
                                    }
                                    HoverHandler {
                                        enabled: parent.hoveredLink !== ""
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                }

                                Text {
                                    id: segItemText
                                    visible: segWrap.segKind === "listItem"
                                    width: parent.width
                                    textFormat: Text.RichText
                                    // inlineToHtml consume el `## ` inicial con headingSizes (igual que BlockList).
                                    text: {
                                        if (!segWrap.visible) return "";
                                        var t = Inline.stripImages(segWrap.segText);
                                        return segWrap.segHtml(t, true);
                                    }
                                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.88)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: {
                                        var tt = Inline.stripImages(segWrap.segText);
                                        var hmm = tt.match(/^(#{1,6})[ \t]+/);
                                        if (hmm) return EditorMetrics.headingSize(hmm[1].length);
                                        return EditorMetrics.body;
                                    }
                                    font.bold: {
                                        var t2 = Inline.stripImages(segWrap.segText);
                                        return /^(#{1,6})[ \t]+/.test(t2);
                                    }
                                    font.italic: true
                                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                    lineHeight: EditorMetrics.lineHeight
                                    opacity: (segWrap.seg && segWrap.seg.checked) ? 0.55 : 1.0
                                    font.strikeout: (segWrap.seg && segWrap.seg.checked) ? true : false
                                    onLinkActivated: (link) => {
                                        if (root.editor && typeof root.editor.handleLink === "function") root.editor.handleLink(link);
                                    }
                                    HoverHandler {
                                        enabled: parent.hoveredLink !== ""
                                        cursorShape: Qt.PointingHandCursor
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

    // MouseArea para activación y selección por arrastre desde modo lectura
    MouseArea {
        id: viewMa
        anchors.left: quoteBar.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.isCallout ? Math.round(14 * EditorMetrics.zoom) : Math.round(12 * EditorMetrics.zoom)
        z: 5
        enabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.IBeamCursor
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
            var link = root.quoteLinkAt(mouse.x, mouse.y);
            pressedOnLink = (link && link !== "");
            if (pressedOnLink) return;
            if (root.editor && root.blockData && typeof root.editor.clearSelectionExcept === "function") {
                root.editor.clearSelectionExcept(root.blockData.bid);
            }
            dragging = true;
            isCrossDragging = false;
            startX = mouse.x;
            startY = mouse.y;
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
            if (isCrossDragging) {
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
                var link = root.quoteLinkAt(mouse.x, mouse.y);
                if (link && link !== "") {
                    if (root.editor && typeof root.editor.handleLink === "function") {
                        root.editor.handleLink(link);
                    }
                }
            }
        }
    }

    // Vista de edición estilizada (sin prefijo '>' redundante y con RichText en vivo)
    TextEdit {
        id: editInput
        visible: root.isEditing || root.isSelected
        readOnly: !root.isEditing || (root.editor && root.editor.readOnly)
        cursorVisible: activeFocus && root.isEditing && (!root.editor || !root.editor.readOnly)
        anchors.left: quoteBar.right
        anchors.right: parent.right
        anchors.leftMargin: root.isCallout ? Math.round(14 * EditorMetrics.zoom) : Math.round(12 * EditorMetrics.zoom)
        anchors.top: parent.top
        anchors.topMargin: root.isCallout ? Math.round(8 * EditorMetrics.zoom) : 0
        textFormat: TextEdit.RichText
        text: ""
        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.92)
        font.family: Theme.fontFamily
        font.pixelSize: EditorMetrics.body
        font.italic: !root.isCallout
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
            if (root.isEditing && !root._syncingModel) {
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
            if (root.isEditing && !root._syncingModel) {
                root._updateLiveFormatting();
            }
        }
        onCursorPositionChanged: {
            if (root.editor && !root.editor._syncingSelection && !root.editor.hasBlockSelection && !root.editor.isDraggingSelection) {
                if (editInput.selectionStart === editInput.selectionEnd && root.blockData && typeof root.editor.notifySingleInputSelection === "function") {
                    root.editor.notifySingleInputSelection(root.blockData.bid);
                }
                if (typeof root.editor.updateFormatState === "function") root.editor.updateFormatState();
            }
            if (root.isEditing && !root._syncingModel) {
                root._updateLiveFormatting();
            }
        }

        PointHandler {
            id: editPointHandler
            acceptedButtons: Qt.LeftButton
            property bool isCrossDragging: false
            onActiveChanged: {
                if (!active) {
                    if (isCrossDragging) {
                        isCrossDragging = false;
                        if (root.editor && typeof root.editor.endCrossBlockDrag === "function") {
                            root.editor.endCrossBlockDrag();
                        }
                    }
                }
            }
            onPointChanged: {
                if (!active) return;
                var py = point.position.y;
                if (py < -4 || py > editInput.height + 4 || isCrossDragging) {
                    if (!isCrossDragging) {
                        isCrossDragging = true;
                        if (root.editor && typeof root.editor.startCrossBlockDrag === "function") {
                            var anchor = editInput.selectionStart !== editInput.cursorPosition ? editInput.selectionStart : editInput.selectionEnd;
                            root.editor.startCrossBlockDrag(root.blockData.bid, anchor);
                        }
                    }
                    if (root.editor && typeof root.editor.handleCrossBlockDrag === "function") {
                        var ptInContent = editInput.mapToItem(root.editor.contentItem, point.position.x, point.position.y);
                        root.editor.handleCrossBlockDrag(root.blockData.bid, ptInContent.y, ptInContent.x);
                    }
                }
            }
        }

        onTextChanged: {
            if (root._syncingModel || (root.editor && root.editor.readOnly)) return;
            if (root.isEditing && root.editor && root.blockData) {
                var clean = Inline.plainText(editInput);
                var raw = clean.split("\n").map(function(l) { return "> " + l; }).join("\n");
                if (raw !== root.blockData.raw) {
                    root.editor.onBlockRawChanged(root.blockData.bid, raw);
                }
                if (root.spellActive) {
                    spellCheckTimer.restart();
                }
            }
        }

        Keys.onTabPressed: (event) => {
            if (root.editor && root.editor.readOnly) {
                event.accepted = true;
                return;
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
                editInput.insert(editInput.cursorPosition, "\n");
                event.accepted = true;
                return;
            }

            var clean = Inline.plainText(editInput);
            var pos = editInput.cursorPosition;

            // Caso 1: Cita completamente vacía -> salir de la cita y convertir a párrafo vacío
            if (clean.trim() === "") {
                if (root.editor && root.blockData) {
                    root.editor.convertBlockType(root.blockData.bid, "paragraph", "");
                }
                event.accepted = true;
                return;
            }

            // Calcular inicio y fin de la línea actual
            var lineStart = pos;
            while (lineStart > 0 && clean[lineStart - 1] !== "\n") lineStart--;
            var lineEnd = pos;
            while (lineEnd < clean.length && clean[lineEnd] !== "\n") lineEnd++;
            var curLineText = clean.substring(lineStart, lineEnd);

            // Caso 2: Enter en una línea vacía dentro de una cita multilínea -> salir de la cita (crear párrafo a continuación)
            if (curLineText.trim() === "") {
                var before = clean.substring(0, lineStart > 0 ? lineStart - 1 : 0);
                var after = clean.substring(lineEnd < clean.length ? lineEnd + 1 : lineEnd);
                var newClean = before;
                if (after.length > 0) {
                    newClean = newClean.length > 0 ? (newClean + "\n" + after) : after;
                }
                var newRaw = newClean.split("\n").map(function(l) { return "> " + l; }).join("\n");
                if (root.editor && root.blockData) {
                    root.editor.onBlockRawChanged(root.blockData.bid, newRaw);
                    root.editor.insertParagraphAfter(root.blockData.bid);
                }
                event.accepted = true;
                return;
            }

            // Caso 3: Enter en una línea con texto -> continuar la cita en la siguiente línea sin recortar caracteres
            editInput.insert(pos, "\n");
            event.accepted = true;
        }

        Keys.onEnterPressed: (event) => {
            Keys.onReturnPressed(event);
        }

        Keys.onPressed: (event) => {
            if (root.editor && root.editor.hasBlockSelection) {
                var isCtrl = !!(event.modifiers & Qt.ControlModifier);
                var isShift = !!(event.modifiers & Qt.ShiftModifier);
                var isAlt = !!(event.modifiers & Qt.AltModifier);

                if (isCtrl && !isShift && !isAlt && event.key === Qt.Key_C) {
                    root.editor.copySelectedText();
                    event.accepted = true;
                    return;
                }
                if (isCtrl && !isShift && !isAlt && event.key === Qt.Key_X) {
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
                if (editInput.cursorPosition === 0 && editInput.selectionStart === editInput.selectionEnd) {
                    if (root.editor && root.blockData) {
                        var curClean = Inline.plainText(editInput);
                        if (curClean.trim() === "") {
                            root.editor.convertBlockType(root.blockData.bid, "paragraph", "> ");
                            event.accepted = true;
                            return;
                        } else if (curClean.indexOf("\n") === -1) {
                            // Si es una sola línea con texto, quitar el formato de cita y volver a párrafo
                            root.editor.convertBlockType(root.blockData.bid, "paragraph", curClean);
                            event.accepted = true;
                            return;
                        }
                        root.editor.handleBlockBackspaceAtStart(root.blockData.bid);
                        event.accepted = true;
                        return;
                    }
                }
            }
        }

        Keys.onDeletePressed: (event) => {
            if (root.editor && root.editor.readOnly) {
                event.accepted = true;
                return;
            }
            if (editInput.cursorPosition === editInput.length && editInput.selectionStart === editInput.selectionEnd) {
                if (root.editor && typeof root.editor.handleBlockDeleteAtEnd === "function") {
                    root.editor.handleBlockDeleteAtEnd(root.blockData.bid);
                    event.accepted = true;
                }
            }
        }

        Keys.onUpPressed: (event) => {
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
