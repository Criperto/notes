import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Notas
import "."
import "MarkdownParser.js" as MD
import "BlockModel.js" as BlockModel
import "Inline.js" as Inline
import "History.js" as History
import "Anchors.js" as Anchors
import "ListParser.js" as LP
import "Selection.js" as Sel
import "MermaidTemplates.js" as MermaidTemplates

Flickable {
    id: root

    property bool readOnly: false
    property string markdown: ""
    signal markdownEdited(string md)
    signal contentModified()

    property bool isDirty: false
    readonly property bool hasPendingChanges: isDirty || (activeBlockBid !== -1 && _activeBlockDirty)
    onContentModified: root.isDirty = true
    onMarkdownEdited: (newMd) => root.isDirty = true

    // ── Congelamiento de layout para cierre fluido ──────────────
    property bool freezeLayout: false
    property real _frozenColumnWidth: 0
    onFreezeLayoutChanged: {
        if (freezeLayout && blocksColumn.width > 0) {
            _frozenColumnWidth = blocksColumn.width;
        } else if (!freezeLayout) {
            _frozenColumnWidth = 0;
        }
    }

    // ── Caché de alturas y ventana deslizante (viewport + overscan) ──
    property var _measuredHeights: ({})
    property var _imageDimensions: ({})
    readonly property real overscanPx: 1200
    property point visibleChunk: Qt.point(0, 30)
    readonly property int visibleChunkStart: visibleChunk.x
    readonly property int visibleChunkEnd: visibleChunk.y

    function _storeImageDimension(src, w, h) {
        if (!src || w <= 0 || h <= 0) return;
        if (!_imageDimensions) _imageDimensions = ({});
        if (!_imageDimensions[src] || _imageDimensions[src].w !== w || _imageDimensions[src].h !== h) {
            var copy = Object.assign({}, _imageDimensions);
            copy[src] = { w: w, h: h };
            _imageDimensions = copy;
        }
    }

    function compensateScroll(delta) {
        if (delta === 0 || !root) return;
        if (scrollAnim && scrollAnim.running) {
            scrollAnim.to = Math.max(0, scrollAnim.to + delta);
            return;
        }
        var maxScroll = Math.max(0, (blocksColumn.implicitHeight + 120) - root.height);
        var targetY = Math.max(0, Math.min(root.contentY + delta, maxScroll));
        if (root.contentY !== targetY) {
            root.contentY = targetY;
        }
    }

    function ensureBlockAndRectVisible(bid, localRect) {
        var idx = _findBlockIndex(bid);
        if (idx === -1) return;
        var loader = blocksRepeater.itemAt(idx);
        if (!loader) return;

        var blockY = blocksColumn.y + loader.y;
        var curY = localRect ? (blockY + localRect.y) : blockY;
        var curH = localRect ? (localRect.height || 24) : 24;

        var topMargin = 28;
        var bottomMargin = 48;

        if (curY < root.contentY + topMargin) {
            root.contentY = Math.max(0, curY - topMargin);
        } else if (curY + curH > root.contentY + root.height - bottomMargin) {
            var maxScroll = Math.max(0, (blocksColumn.implicitHeight + 120) - root.height);
            root.contentY = Math.min(maxScroll, curY + curH - root.height + bottomMargin);
        }
    }

    function goToDocumentStart() {
        if (blocksModel.count === 0) return;
        var firstBid = blocksModel.get(0).bid;
        root.contentY = 0;
        root.requestEditBlock(firstBid, 0);
    }

    function goToDocumentEnd() {
        if (blocksModel.count === 0) return;
        var lastBid = blocksModel.get(blocksModel.count - 1).bid;
        var maxScroll = Math.max(0, (blocksColumn.implicitHeight + 120) - root.height);
        root.contentY = maxScroll;
        root.requestEditBlock(lastBid, -1);
    }

    function pageUp() {
        var pageStep = root.height * 0.85;
        root.contentY = Math.max(0, root.contentY - pageStep);
        var targetY = root.contentY + 40;
        var bid = root._findBlockNearY(targetY);
        if (bid !== -1) {
            root.requestEditBlock(bid, { x: root.preferredCursorX, y: 0 });
        }
    }

    function pageDown() {
        var pageStep = root.height * 0.85;
        var maxScroll = Math.max(0, (blocksColumn.implicitHeight + 120) - root.height);
        root.contentY = Math.min(maxScroll, root.contentY + pageStep);
        var targetY = root.contentY + 40;
        var bid = root._findBlockNearY(targetY);
        if (bid !== -1) {
            root.requestEditBlock(bid, { x: root.preferredCursorX, y: 0 });
        }
    }

    function _commitInlineFormattedSubEdit(bid, textEdit, newPlainText, newSelStart, newSelEnd) {
        var loader = root._getDelegateItemForBid(bid);
        if (loader && loader.item && typeof loader.item.commitInlineSubEdit === "function") {
            loader.item.commitInlineSubEdit(textEdit, newPlainText, newSelStart, newSelEnd);
        } else if (loader && loader.item && typeof loader.item.onRawEdited === "function") {
            loader.item.onRawEdited(newPlainText);
        } else {
            root.onBlockRawChanged(bid, newPlainText);
        }
        if (textEdit) {
            if (typeof newSelStart === "number" && typeof newSelEnd === "number") {
                textEdit.select(newSelStart, newSelEnd);
            }
        }
    }

    Timer {
        id: chunkWindowTimer
        interval: 32
        repeat: false
        onTriggered: root._recalcChunkWindow()
    }

    onContentYChanged: {
        if (slashMenu && slashMenu.isOpen) {
            slashMenu.close();
        }
        if (blocksModel.count > 35) {
            if (!chunkWindowTimer.running) {
                chunkWindowTimer.start();
            }
        }
    }

    onHeightChanged: {
        if (blocksModel.count > 35) {
            if (!chunkWindowTimer.running) {
                chunkWindowTimer.start();
            }
        }
    }

    onMovementEnded: {
        if (blocksModel.count > 35) {
            root._recalcChunkWindow();
        }
    }

    onFlickEnded: {
        if (blocksModel.count > 35) {
            root._recalcChunkWindow();
        }
    }

    function _recalcChunkWindow() {
        var total = blocksModel.count;
        if (total === 0) {
            if (root.visibleChunk.x !== 0 || root.visibleChunk.y !== 0) {
                root.visibleChunk = Qt.point(0, 0);
            }
            return;
        }
        if (total <= 35) {
            if (root.visibleChunk.x !== 0 || root.visibleChunk.y !== total - 1) {
                root.visibleChunk = Qt.point(0, total - 1);
            }
            return;
        }

        var topY = Math.max(0, root.contentY - root.overscanPx);
        var bottomY = root.contentY + Math.max(root.height, 600) + root.overscanPx;

        var startIdx = 0;
        var endIdx = total - 1;
        var foundStart = false;

        for (var i = 0; i < total; i++) {
            var ldr = blocksRepeater.itemAt(i);
            if (!ldr) continue;
            var ldrBottom = blocksColumn.y + ldr.y + ldr.height;
            if (!foundStart && ldrBottom >= topY) {
                startIdx = Math.max(0, i - 6);
                foundStart = true;
            }
            var ldrTop = blocksColumn.y + ldr.y;
            if (foundStart && ldrTop > bottomY) {
                endIdx = Math.min(total - 1, i + 6);
                break;
            }
        }

        if (!foundStart) {
            startIdx = 0;
            endIdx = Math.min(total - 1, 30);
        }

        if (root.visibleChunk.x !== startIdx || root.visibleChunk.y !== endIdx) {
            root.visibleChunk = Qt.point(startIdx, endIdx);
        }
    }


    property var contextMenu: null
    property var slashMenu: null
    property bool manualSpellActive: true
    readonly property bool spellActive: {
        if (root.readOnly) return false;
        if (typeof SpellConfig === "undefined" || !SpellConfig.enabled) return false;
        var mode = (typeof NotesConfig !== "undefined" && NotesConfig.spellcheckMode) ? NotesConfig.spellcheckMode : "auto";
        if (mode === "off") return false;
        return manualSpellActive;
    }

    function toggleSpellCheck() {
        manualSpellActive = !manualSpellActive;
    }

    property int activeBlockBid: -1
    property string documentLead: ""
    property var docHistory: null
    property bool _internalChange: false
    property bool _activeBlockDirty: false
    property var tooltipLayer: null
    property var editorModal: null

    // ── Memoria de columna horizontal para navegación vertical con flechas (Up/Down) ──
    property real preferredCursorX: -1

    function getPreferredCursorX(curX) {
        if (preferredCursorX >= 0) return preferredCursorX;
        if (typeof curX === "number" && curX >= 0) {
            preferredCursorX = curX;
            return curX;
        }
        return -1;
    }

    function resetPreferredCursorX() {
        if (preferredCursorX !== -1) {
            preferredCursorX = -1;
        }
    }

    // ── Selección múltiple de bloques ───────────────────────────
    property var selectedBids: ({})
    property int selAnchorBid: -1
    property int selAnchorPos: -1
    property int selCurrentBid: -1
    property int selCurrentPos: -1
    readonly property bool hasBlockSelection: Sel.count(selectedBids) > 0

    // ── Resaltado de búsqueda en tiempo real ────────────────────────────────
    property string searchQuery: ""
    property int activeMatchBid: -1
    property int activeMatchUnit: -1
    property int activeMatchOrdinal: -1
    readonly property color searchHighlightColor: Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.38)
    readonly property color searchActiveColor: Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.85)

    // ── Coincidencia activa de búsqueda ───────────────────────────────
    // Helpers para que cada delegate resuelva fondo/ordinal/fg de su unidad sin
    // repetir condicionales. Unidad -1 o bid distinto → resaltado suave parejo.
    function _isSearchUnitActive(bid, unit) {
        return bid !== undefined && bid !== -1 && unit !== undefined && unit !== -1
            && root.activeMatchBid === bid && root.activeMatchUnit === unit && root.activeMatchOrdinal >= 0;
    }
    function searchActiveBg(bid, unit) {
        return root._isSearchUnitActive(bid, unit) ? ("" + root.searchActiveColor) : "";
    }
    function searchActiveOrdinal(bid, unit) {
        return root._isSearchUnitActive(bid, unit) ? root.activeMatchOrdinal : -1;
    }
    function searchActiveFg(bid, unit) {
        return root._isSearchUnitActive(bid, unit) ? ("" + Theme.textOn(Theme.accent)) : "";
    }

    // ── Imágenes inline: existencia para no pintar <img> inexistentes ──
    // Se pasa como imageExists a Inline.inlineToHtml junto a probeTick para
    // re-evaluar al completar el probe.
    function imageExistsFn(absPath) {
        return NotesService.imageExistsCached(absPath);
    }
    readonly property string imgBaseFolder: {
        var _ = NotesService.filesVersion;
        return NotesService.resolveNoteBaseDir(NotesService.activeNote);
    }

    // ── Estado de formatos activos para la toolbar ──────────────────────────
    property int formatStateSeq: 0
    property bool _syncingSelection: false

    Timer {
        id: formatStateCoalesceTimer
        interval: 16
        repeat: false
        onTriggered: {
            root.formatStateSeq++;
        }
    }

    function updateFormatState() {
        if (!formatStateCoalesceTimer.running) {
            formatStateCoalesceTimer.restart();
        }
    }

    function updateFormatStateImmediate() {
        formatStateCoalesceTimer.stop();
        root.formatStateSeq++;
    }

    onActiveBlockBidChanged: updateFormatState()
    onSelectedBidsChanged: updateFormatState()

    function clearBlockSelection() {
        root.resetPreferredCursorX();
        if (hasBlockSelection) {
            root._syncingSelection = true;
            for (var bid in selectedBids) {
                var l = _getDelegateItemForBid(parseInt(bid, 10));
                if (l && l.item && typeof l.item.clearTextSelection === "function") {
                    l.item.clearTextSelection();
                }
            }
            selectedBids = ({});
            root._syncingSelection = false;
        }
        selAnchorBid = -1;
        selAnchorPos = -1;
        selCurrentBid = -1;
        selCurrentPos = -1;
        root.updateFormatState();
    }

    function clearAllSelections(exceptBid, exceptSubIdx) {
        root._syncingSelection = true;
        if (root.hasBlockSelection) {
            root.selectedBids = ({});
        }
        for (var i = 0; i < blocksRepeater.count; i++) {
            var ldr = blocksRepeater.itemAt(i);
            if (!ldr || !ldr.item) continue;
            var b = blocksModel.get(i);
            var bBid = b ? b.bid : -1;
            if (exceptBid !== undefined && bBid === exceptBid) {
                if (typeof ldr.item.clearOtherItemsSelection === "function") {
                    ldr.item.clearOtherItemsSelection(exceptSubIdx);
                }
            } else {
                if (typeof ldr.item.clearTextSelection === "function") {
                    ldr.item.clearTextSelection();
                }
            }
        }
        root._syncingSelection = false;
        root.updateFormatState();
    }

    function clearSelectionExcept(keepBid, keepSubIdx) {
        clearAllSelections(keepBid, keepSubIdx);
    }

    function notifySingleInputSelection(bid, subIdx) {
        if (root._syncingSelection) return;
        clearSelectionExcept(bid, subIdx);
    }

    function isSelectionStartBlock(bid) {
        if (!root.hasBlockSelection) return true;
        var anchorIdx = _findBlockIndex(root.selAnchorBid);
        var curIdx = _findBlockIndex(root.selCurrentBid);
        if (anchorIdx === -1 || curIdx === -1) return true;
        var startIdx = Math.min(anchorIdx, curIdx);
        var startB = blocksModel.get(startIdx);
        return startB ? (startB.bid === bid) : false;
    }

    function isSelectionEndBlock(bid) {
        if (!root.hasBlockSelection) return true;
        var anchorIdx = _findBlockIndex(root.selAnchorBid);
        var curIdx = _findBlockIndex(root.selCurrentBid);
        if (anchorIdx === -1 || curIdx === -1) return true;
        var endIdx = Math.max(anchorIdx, curIdx);
        var endB = blocksModel.get(endIdx);
        return endB ? (endB.bid === bid) : false;
    }

    function handleTeardropDrag(isStart, globalX, globalY) {
        var ptInContent = contentItem.mapFromItem(null, globalX, globalY);
        if (isStart) {
            var curEndBid = (root.selAnchorBid !== -1 && root.selCurrentBid !== -1)
                ? (root._findBlockIndex(root.selAnchorBid) > root._findBlockIndex(root.selCurrentBid) ? root.selAnchorBid : root.selCurrentBid)
                : root.selCurrentBid;
            root.handleCrossBlockDrag(curEndBid, ptInContent.y, ptInContent.x);
        } else {
            var curStartBid = (root.selAnchorBid !== -1 && root.selCurrentBid !== -1)
                ? (root._findBlockIndex(root.selAnchorBid) < root._findBlockIndex(root.selCurrentBid) ? root.selAnchorBid : root.selCurrentBid)
                : root.selAnchorBid;
            root.handleCrossBlockDrag(curStartBid, ptInContent.y, ptInContent.x);
        }
    }

    function _setBlockSelection(bids) {
        selectedBids = Sel.toMap(bids);
        root.updateFormatState();
    }

    property bool isDraggingSelection: false

    function startCrossBlockDrag(anchorBid, anchorPos) {
        root.clearBlockSelection();
        root.selAnchorBid = anchorBid;
        root.selAnchorPos = (typeof anchorPos === "number") ? anchorPos : 0;
        root.selCurrentBid = anchorBid;
        root.selCurrentPos = root.selAnchorPos;
        root.isDraggingSelection = true;
    }

    function _findBlockAndCharNear(x, y) {
        var bid = _findBlockNearY(y);
        var charPos = 0;
        if (bid !== -1) {
            var loader = _getDelegateItemForBid(bid);
            if (loader && loader.item) {
                var lx = Math.max(0, Math.min(loader.width, x - blocksColumn.x));
                var ly = y - blocksColumn.y - loader.y;
                if (ly < 0) {
                    charPos = 0;
                } else if (ly > loader.height) {
                    charPos = (typeof loader.item.getTextLength === "function") ? loader.item.getTextLength() : 0;
                } else if (typeof loader.item.getCharPosAt === "function") {
                    charPos = loader.item.getCharPosAt(lx, ly);
                }
            } else if (loader) {
                var bidx = _findBlockIndex(bid);
                if (bidx !== -1) {
                    var bdata = blocksModel.get(bidx);
                    charPos = (y > blocksColumn.y + loader.y + loader.height / 2) ? (bdata.raw || "").length : 0;
                }
            }
        }
        return { bid: bid, pos: charPos };
    }

    function handleCrossBlockDrag(anchorBid, targetY, targetX) {
        if (root.selAnchorBid === -1) root.selAnchorBid = anchorBid;
        root.isDraggingSelection = true;

        var targetInfo = root._findBlockAndCharNear(targetX !== undefined ? targetX : (blocksColumn.x + blocksColumn.width / 2), targetY);
        var curBid = targetInfo.bid;
        var curPos = targetInfo.pos;
        if (curBid === -1) return;

        root.selCurrentBid = curBid;
        root.selCurrentPos = curPos;

        var anchorIdx = root._findBlockIndex(root.selAnchorBid);
        var curIdx = root._findBlockIndex(curBid);
        if (anchorIdx === -1 || curIdx === -1) return;

        var startIdx = Math.min(anchorIdx, curIdx);
        var endIdx = Math.max(anchorIdx, curIdx);

        root._syncingSelection = true;
        if (startIdx === endIdx) {
            for (var k0 = 0; k0 < blocksRepeater.count; k0++) {
                if (k0 !== startIdx) {
                    var outLoader0 = blocksRepeater.itemAt(k0);
                    if (outLoader0 && outLoader0.item && typeof outLoader0.item.clearTextSelection === "function") {
                        outLoader0.item.clearTextSelection();
                    }
                }
            }
            var sLoader = blocksRepeater.itemAt(startIdx);
            if (sLoader && sLoader.item && typeof sLoader.item.selectRange === "function") {
                sLoader.item.selectRange(root.selAnchorPos, curPos);
            }
            if (root.hasBlockSelection) root.selectedBids = ({});
            root._syncingSelection = false;
            root.updateFormatState();
            return;
        }

        var newSelectedBids = {};
        for (var i = startIdx; i <= endIdx; i++) {
            var b = blocksModel.get(i);
            if (b) newSelectedBids[b.bid] = true;
        }
        root.selectedBids = newSelectedBids;

        for (var k = 0; k < blocksRepeater.count; k++) {
            if (k < startIdx || k > endIdx) {
                var outLoader = blocksRepeater.itemAt(k);
                if (outLoader && outLoader.item && typeof outLoader.item.clearTextSelection === "function") {
                    outLoader.item.clearTextSelection();
                }
            }
        }

        if (anchorIdx < curIdx) {
            var startLoader = blocksRepeater.itemAt(anchorIdx);
            if (startLoader && startLoader.item && typeof startLoader.item.selectRange === "function") {
                startLoader.item.selectRange(root.selAnchorPos, startLoader.item.getTextLength());
            }
            for (var m = anchorIdx + 1; m < curIdx; m++) {
                var midLoader = blocksRepeater.itemAt(m);
                if (midLoader && midLoader.item && typeof midLoader.item.selectAllText === "function") {
                    midLoader.item.selectAllText();
                }
            }
            var endLoader = blocksRepeater.itemAt(curIdx);
            if (endLoader && endLoader.item && typeof endLoader.item.selectRange === "function") {
                endLoader.item.selectRange(0, curPos);
            }
        } else {
            var topLoader = blocksRepeater.itemAt(curIdx);
            if (topLoader && topLoader.item && typeof topLoader.item.selectRange === "function") {
                topLoader.item.selectRange(curPos, topLoader.item.getTextLength());
            }
            for (var n = curIdx + 1; n < anchorIdx; n++) {
                var midLoader2 = blocksRepeater.itemAt(n);
                if (midLoader2 && midLoader2.item && typeof midLoader2.item.selectAllText === "function") {
                    midLoader2.item.selectAllText();
                }
            }
            var botLoader = blocksRepeater.itemAt(anchorIdx);
            if (botLoader && botLoader.item && typeof botLoader.item.selectRange === "function") {
                botLoader.item.selectRange(0, root.selAnchorPos);
            }
        }
        root._syncingSelection = false;
        root.updateFormatState();
    }

    function endCrossBlockDrag() {
        root.isDraggingSelection = false;
        if (root.hasBlockSelection) {
            root.confirmActiveBlock();
            root.forceActiveFocus();
        }
        root.updateFormatStateImmediate();
    }

    function extendKeyboardSelectionDown(fromBid, fromPos) {
        var baseBid = (root.hasBlockSelection && root.selCurrentBid !== -1) ? root.selCurrentBid : fromBid;
        var fromIdx = _findBlockIndex(baseBid);
        if (fromIdx === -1 || fromIdx >= blocksModel.count - 1) return;
        var nextBlock = blocksModel.get(fromIdx + 1);
        if (!nextBlock) return;

        if (!root.hasBlockSelection) {
            root.selAnchorBid = fromBid;
            root.selAnchorPos = (typeof fromPos === "number") ? fromPos : 0;
            root.confirmActiveBlock();
            root.forceActiveFocus();
        }
        root.selCurrentBid = nextBlock.bid;
        var nextLoader = _getDelegateItemForBid(nextBlock.bid);
        var nextLen = (nextLoader && nextLoader.item && typeof nextLoader.item.getTextLength === "function") ? nextLoader.item.getTextLength() : (nextBlock.raw || "").length;
        root.selCurrentPos = nextLen;

        var anchorIdx = _findBlockIndex(root.selAnchorBid);
        var curIdx = fromIdx + 1;
        var newSelectedBids = {};
        var startIdx = Math.min(anchorIdx, curIdx);
        var endIdx = Math.max(anchorIdx, curIdx);
        for (var i = startIdx; i <= endIdx; i++) {
            var b = blocksModel.get(i);
            if (b) newSelectedBids[b.bid] = true;
        }
        root.selectedBids = newSelectedBids;

        root._syncingSelection = true;
        for (var m = startIdx; m <= endIdx; m++) {
            var ldr = blocksRepeater.itemAt(m);
            if (ldr && ldr.item && typeof ldr.item.selectAllText === "function") {
                ldr.item.selectAllText();
            }
        }
        root._syncingSelection = false;
        root.updateFormatState();
        root.scrollToBid(nextBlock.bid);
    }

    function extendKeyboardSelectionUp(fromBid, fromPos) {
        var baseBid = (root.hasBlockSelection && root.selCurrentBid !== -1) ? root.selCurrentBid : fromBid;
        var fromIdx = _findBlockIndex(baseBid);
        if (fromIdx <= 0) return;
        var prevBlock = blocksModel.get(fromIdx - 1);
        if (!prevBlock) return;

        if (!root.hasBlockSelection) {
            root.selAnchorBid = fromBid;
            root.selAnchorPos = (typeof fromPos === "number") ? fromPos : 0;
            root.confirmActiveBlock();
            root.forceActiveFocus();
        }
        root.selCurrentBid = prevBlock.bid;
        root.selCurrentPos = 0;

        var anchorIdx = _findBlockIndex(root.selAnchorBid);
        var curIdx = fromIdx - 1;
        var newSelectedBids = {};
        var startIdx = Math.min(anchorIdx, curIdx);
        var endIdx = Math.max(anchorIdx, curIdx);
        for (var i = startIdx; i <= endIdx; i++) {
            var b = blocksModel.get(i);
            if (b) newSelectedBids[b.bid] = true;
        }
        root.selectedBids = newSelectedBids;

        root._syncingSelection = true;
        for (var m = startIdx; m <= endIdx; m++) {
            var ldr = blocksRepeater.itemAt(m);
            if (ldr && ldr.item && typeof ldr.item.selectAllText === "function") {
                ldr.item.selectAllText();
            }
        }
        root._syncingSelection = false;
        root.updateFormatState();
        root.scrollToBid(prevBlock.bid);
    }

    function _getBlockListSnapshot() {
        var list = [];
        for (var i = 0; i < blocksModel.count; i++) {
            var b = blocksModel.get(i);
            list.push({
                bid: b.bid,
                type: b.type,
                raw: b.raw || "",
                sep: (b.sep !== undefined) ? b.sep : "\n\n"
            });
        }
        return list;
    }

    function selectAllBlocks() {
        confirmActiveBlock();
        if (blocksModel.count === 0) return;
        var list = _getBlockListSnapshot();
        _setBlockSelection(Sel.rangeBids(list, list[0].bid, list[list.length - 1].bid));
        for (var i = 0; i < blocksRepeater.count; i++) {
            var loader = blocksRepeater.itemAt(i);
            if (loader && loader.item && typeof loader.item.selectAllText === "function") {
                loader.item.selectAllText();
            }
        }
        root.forceActiveFocus();
    }

    function copyText(str) {
        if (str === undefined || str === null || str === "") return;
        if (typeof Quickshell.clipboardText !== "undefined") {
            Quickshell.clipboardText = str;
        }
        copyTextProc.copy(str);
    }

    Process {
        id: copyTextProc
        property string pendingText: ""
        command: ["wl-copy"]
        stdinEnabled: true
        onStarted: {
            write(pendingText);
            pendingText = "";
            stdinEnabled = false;
        }
        onExited: (exitCode, exitStatus) => {
            stdinEnabled = true;
            if (exitCode !== 0) {
                console.warn("[BlockEditor] wl-copy falló, código:", exitCode);
            }
        }

        function copy(txt) {
            pendingText = txt;
            stdinEnabled = true;
            running = true;
        }

        Component.onDestruction: { running = false; }
    }

    function getSelectedText() {
        if (!hasBlockSelection) {
            if (root.activeBlockBid !== -1) {
                var curLoader = _getDelegateItemForBid(root.activeBlockBid);
                if (curLoader && curLoader.item && typeof curLoader.item.getSelectedText === "function") {
                    return curLoader.item.getSelectedText();
                }
            }
            return "";
        }
        var list = _getBlockListSnapshot();
        if (root.selAnchorBid !== -1 && root.selCurrentBid !== -1 && root.selAnchorPos !== -1 && root.selCurrentPos !== -1) {
            var extracted = Sel.extractSelectedText(list, root.selAnchorBid, root.selAnchorPos, root.selCurrentBid, root.selCurrentPos);
            if (extracted !== "") {
                return extracted;
            }
        }
        var parts = [];
        for (var i = 0; i < blocksModel.count; i++) {
            var b = blocksModel.get(i);
            if (root.selectedBids && root.selectedBids[b.bid] === true) {
                var loader = _getDelegateItemForBid(b.bid);
                var txt = "";
                if (loader && loader.item && typeof loader.item.getSelectedText === "function") {
                    txt = loader.item.getSelectedText();
                }
                if (txt === "" && loader && loader.item && typeof loader.item.getTextContent === "function") {
                    txt = loader.item.getTextContent();
                }
                if (txt === "") txt = b.raw || "";
                parts.push(txt);
            }
        }
        return parts.join("\n\n");
    }

    function copySelectedText() {
        var out = getSelectedText();
        if (out !== "") {
            copyText(out);
        }
        return out;
    }

    // F23: punto único de pegado. Si el portapapeles no trae texto (o solo
    // espacios) se delega al modal para pegar imagen (misma vía que el botón).
    // Política: si hay texto E imagen a la vez, gana el texto; la imagen queda
    // disponible con Ctrl+Shift+V. Devuelve true si consumió el evento para que
    // el TextEdit no haga su pegado nativo (que con una imagen no hace nada y
    // encima acepta la tecla, bloqueando la rama del modal).
    function handlePaste(targetEdit) {
        if (!targetEdit) return false;

        NotesService.checkClipboardForImage(
            function() {
                console.log("[PasteImg] Imagen detectada en portapapeles -> delegando a pasteClipboardImage()");
                if (root.editorModal && typeof root.editorModal.pasteClipboardImage === "function") {
                    root.editorModal.pasteClipboardImage();
                } else if (NotesService.activeNote) {
                    var nKey = NotesService.activeNote.key || NotesService.activeNote.slug;
                    NotesService.attachImage(nKey, "clipboard", function(tag, err) {
                        if (!err && tag) root.insertImageBlock(tag, "imagen");
                    });
                }
            },
            function() {
                var clipText = (typeof Quickshell.clipboardText === "string") ? Quickshell.clipboardText : "";
                if (!clipText || clipText.trim() === "") {
                    if (root.editorModal && typeof root.editorModal.pasteClipboardImage === "function") {
                        root.editorModal.pasteClipboardImage();
                    }
                    return;
                }

                var trimmed = clipText.trim();
                // Si el texto es una ruta local o URI file:// hacia una imagen, adjuntarla como imagen
                if (/^(file:\/\/|\/).+\.(png|jpe?g|webp|gif|svg|bmp)$/i.test(trimmed) && NotesService.activeNote) {
                    var cleanPath = trimmed.startsWith("file://") ? decodeURIComponent(trimmed.substring(7)) : trimmed;
                    var nKey2 = NotesService.activeNote.key || NotesService.activeNote.slug;
                    NotesService.attachImage(nKey2, cleanPath, function(tag, err) {
                        if (!err && tag) root.insertImageBlock(tag, "imagen");
                    });
                    return;
                }

                clipText = clipText.replace(/[\u2028\u2029]/g, "\n");

                var s = targetEdit.selectionStart;
                var e = targetEdit.selectionEnd;
                var isUrl = /^https?:\/\/[^\s]+$/.test(trimmed);

                if (s !== e && isUrl) {
                    var sel = targetEdit.selectedText;
                    var mdLink = "[" + sel + "](" + trimmed + ")";
                    targetEdit.remove(s, e);
                    targetEdit.insert(s, mdLink);
                    targetEdit.select(s + mdLink.length, s + mdLink.length);
                    return;
                }

                // Multi-block paste: si el texto pegado contiene múltiples párrafos o bloques compuestos
                if (clipText.indexOf("\n\n") !== -1 || /^(?:```|~~~|\||[-*+]\s|\d+\.\s|>)/m.test(clipText)) {
                    var curBid = root.activeBlockBid;
                    var blockIdx = root._findBlockIndex(curBid);
                    if (blockIdx !== -1) {
                        var curBlock = root.blocksModel.get(blockIdx);
                        if (curBlock && curBlock.type === "paragraph") {
                            var fullCurrent = Inline.plainText(targetEdit);
                            var preText = fullCurrent.substring(0, targetEdit.cursorPosition);
                            var postText = fullCurrent.substring(targetEdit.cursorPosition);
                            var combined = (preText ? preText + "\n\n" : "") + clipText + (postText ? "\n\n" + postText : "");
                            var resBlocks = BlockModel.splitBlocks(combined);
                            if (resBlocks.blocks && resBlocks.blocks.length > 1) {
                                root._saveSnapshot();
                                root.blocksModel.remove(blockIdx);
                                for (var b = 0; b < resBlocks.blocks.length; b++) {
                                    root.blocksModel.insert(blockIdx + b, resBlocks.blocks[b]);
                                }
                                var lastInserted = resBlocks.blocks[resBlocks.blocks.length - 1];
                                root.safeFocusDelegate(lastInserted.bid);
                                root._saveSnapshot();
                                return;
                            }
                        }
                    }
                }

                if (s !== e) {
                    targetEdit.remove(s, e);
                }
                targetEdit.insert(targetEdit.cursorPosition, clipText);
            }
        );
        return true;
    }

    function handleAutoPair(targetEdit, event) {
        if (!targetEdit || !event || !event.text) return false;
        var ch = event.text;
        if (ch.length !== 1) return false;

        var s = targetEdit.selectionStart;
        var e = targetEdit.selectionEnd;

        // 1. Envolver selección si hay texto seleccionado
        if (s !== e) {
            var open = "";
            var close = "";
            if (ch === "(" || ch === ")") { open = "("; close = ")"; }
            else if (ch === "[" || ch === "]") { open = "["; close = "]"; }
            else if (ch === "{" || ch === "}") { open = "{"; close = "}"; }
            else if (ch === '"') { open = '"'; close = '"'; }
            else if (ch === "`") { open = "`"; close = "`"; }
            else if (ch === "*") { open = "*"; close = "*"; }
            else if (ch === "_") { open = "_"; close = "_"; }
            else if (ch === "~") { open = "~"; close = "~"; }
            else if (ch === "=") { open = "="; close = "="; }

            if (open !== "") {
                var sel = targetEdit.selectedText;
                targetEdit.remove(s, e);
                targetEdit.insert(s, open + sel + close);
                targetEdit.select(s + open.length, s + open.length + sel.length);
                event.accepted = true;
                return true;
            }
            return false;
        }

        // 2. Autocierre o salto sobre cierre cuando no hay selección
        var nextChar = targetEdit.getText(s, s + 1);

        // Salto sobre cierre existente
        if ((ch === ")" || ch === "]" || ch === "}" || ch === '"' || ch === "`") && nextChar === ch) {
            targetEdit.cursorPosition = s + 1;
            event.accepted = true;
            return true;
        }

        // Autocierre de pares solo si el siguiente carácter es espacio o fin de texto
        if (nextChar === "" || /\s/.test(nextChar)) {
            var pairClose = "";
            if (ch === "(") pairClose = ")";
            else if (ch === "[") pairClose = "]";
            else if (ch === "{") pairClose = "}";
            else if (ch === '"') pairClose = '"';
            else if (ch === "`") pairClose = "`";

            if (pairClose !== "") {
                targetEdit.insert(s, ch + pairClose);
                targetEdit.cursorPosition = s + 1;
                event.accepted = true;
                return true;
            }
        }

        return false;
    }

    function handleBackspaceAutoPair(targetEdit) {
        if (!targetEdit) return false;
        if (targetEdit.selectionStart !== targetEdit.selectionEnd) return false;
        var p = targetEdit.cursorPosition;
        if (p <= 0 || p >= targetEdit.length) return false;

        var prev1 = targetEdit.getText(p - 1, p);
        var next1 = targetEdit.getText(p, p + 1);

        // Pares de 1 carácter: (), [], {}, "", '', ``, **, ~~, ==
        if ((prev1 === "(" && next1 === ")") ||
            (prev1 === "[" && next1 === "]") ||
            (prev1 === "{" && next1 === "}") ||
            (prev1 === '"' && next1 === '"') ||
            (prev1 === "'" && next1 === "'") ||
            (prev1 === "`" && next1 === "`") ||
            (prev1 === "*" && next1 === "*") ||
            (prev1 === "~" && next1 === "~") ||
            (prev1 === "=" && next1 === "=")) {
            // Chequear si es par doble: **|**, ~~|~~, ==|==
            if (p >= 2 && p + 2 <= targetEdit.length) {
                var prev2 = targetEdit.getText(p - 2, p);
                var next2 = targetEdit.getText(p, p + 2);
                if ((prev2 === "**" && next2 === "**") ||
                    (prev2 === "~~" && next2 === "~~") ||
                    (prev2 === "==" && next2 === "==")) {
                    targetEdit.remove(p - 2, p + 2);
                    targetEdit.cursorPosition = p - 2;
                    return true;
                }
            }
            targetEdit.remove(p - 1, p + 1);
            targetEdit.cursorPosition = p - 1;
            return true;
        }

        // Par HTML: <u>|</u>
        if (p >= 3 && p + 4 <= targetEdit.length) {
            var prevU = targetEdit.getText(p - 3, p);
            var nextU = targetEdit.getText(p, p + 4);
            if (prevU.toLowerCase() === "<u>" && nextU.toLowerCase() === "</u>") {
                targetEdit.remove(p - 3, p + 4);
                targetEdit.cursorPosition = p - 3;
                return true;
            }
        }
        return false;
    }

    function deleteSelectedBlocks(replacementText) {
        if (!hasBlockSelection) {
            if (root.activeBlockBid !== -1) {
                var curLoader = _getDelegateItemForBid(root.activeBlockBid);
                if (curLoader && curLoader.item && typeof curLoader.item.deleteSelectedText === "function") {
                    curLoader.item.deleteSelectedText();
                }
            }
            return;
        }
        var list = _getBlockListSnapshot();
        var res = Sel.removeSelected(list, selectedBids, function() {
            return { bid: BlockModel.getNextBid(), type: "paragraph", raw: (typeof replacementText === "string" ? replacementText : ""), sep: "\n\n" };
        });
        blocksModel.clear();
        for (var k = 0; k < res.blocks.length; k++) {
            blocksModel.append({
                bid: res.blocks[k].bid,
                type: res.blocks[k].type,
                raw: res.blocks[k].raw || "",
                sep: (res.blocks[k].sep !== undefined) ? res.blocks[k].sep : "\n\n"
            });
        }
        clearBlockSelection();
        _saveSnapshot();
        contentModified();
        debouncedMarkdownTimer.restart();
        var f = blocksModel.get(Math.max(0, res.focusIndex));
        if (f) {
            root.activeBlockBid = f.bid;
            root.safeFocusDelegate(f.bid, (typeof replacementText === "string" ? replacementText.length : 0));
        }
    }

    function safeFocusDelegate(bid, cursorPos) {
        Qt.callLater(() => {
            try {
                if (root && typeof root._focusDelegateForBid === "function") {
                    root._focusDelegateForBid(bid, cursorPos);
                }
            } catch (e) {
                // Ignore if component is unmounted during evaluation
            }
        });
    }

    contentWidth: width
    contentHeight: Math.max(blocksColumn.implicitHeight + 120, root.height)
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    // Barra de scroll vertical con el estilo global
    ScrollBar.vertical: CustomScrollBar {}

    WheelHandler {
        target: null
        acceptedDevices: PointerDevice.AllDevices
        acceptedModifiers: Qt.ControlModifier
        grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType | PointerHandler.ApprovesTakeOverByAnything
        onWheel: (event) => {
            if (event.modifiers & Qt.ControlModifier) {
                var delta = event.angleDelta ? event.angleDelta.y : 0;
                if (delta > 0) {
                    EditorMetrics.zoomIn();
                    event.accepted = true;
                } else if (delta < 0) {
                    EditorMetrics.zoomOut();
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            } else {
                event.accepted = false;
            }
        }
    }

    ListModel {
        id: blocksModel
        onCountChanged: {
            chunkWindowTimer.restart();
        }
    }

    readonly property int blocksCount: blocksModel.count
    function getBlockAt(index) {
        if (index >= 0 && index < blocksModel.count) {
            return blocksModel.get(index);
        }
        return null;
    }

    Timer {
        id: debouncedMarkdownTimer
        interval: 300
        repeat: false
        onTriggered: {
            root._internalChange = true;
            root.markdownEdited(root.getMarkdown());
            root._internalChange = false;
        }
    }

    Timer {
        id: typingSnapshotTimer
        interval: 600
        repeat: false
        onTriggered: root._saveSnapshot()
    }

    Shortcut {
        sequences: [ StandardKey.Undo ]
        onActivated: root.undo()
    }

    Shortcut {
        sequences: [ StandardKey.Redo ]
        onActivated: root.redo()
    }

    Shortcut {
        sequences: [ StandardKey.SelectAll ]
        enabled: root.activeBlockBid !== -1 || root.hasBlockSelection
        onActivated: {
            if (root.activeBlockBid !== -1) {
                var te = root._getTextEditForBid(root.activeBlockBid);
                if (te && (te.selectionEnd - te.selectionStart < te.length)) {
                    te.selectAll();
                    return;
                }
            }
            root.selectAllBlocks();
        }
    }

    Keys.onPressed: (event) => {
        var isCtrl = (event.modifiers & Qt.ControlModifier);
        var isShift = (event.modifiers & Qt.ShiftModifier);
        var isAlt = (event.modifiers & Qt.AltModifier);

        if (isCtrl && !isShift && !isAlt && event.key === Qt.Key_Home) {
            root.goToDocumentStart();
            event.accepted = true;
            return;
        }
        if (isCtrl && !isShift && !isAlt && event.key === Qt.Key_End) {
            root.goToDocumentEnd();
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_PageUp) {
            root.pageUp();
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_PageDown) {
            root.pageDown();
            event.accepted = true;
            return;
        }

        if (!root.hasBlockSelection) return;

        if (isShift && !isCtrl && !isAlt && event.key === Qt.Key_Down) {
            root.extendKeyboardSelectionDown(root.selCurrentBid, 0);
            event.accepted = true;
            return;
        }

        if (isShift && !isCtrl && !isAlt && event.key === Qt.Key_Up) {
            root.extendKeyboardSelectionUp(root.selCurrentBid, 0);
            event.accepted = true;
            return;
        }

        if ((isCtrl && !isShift && !isAlt && event.key === Qt.Key_V) ||
            (isShift && !isCtrl && !isAlt && event.key === Qt.Key_Insert)) {
            if (root.readOnly) {
                event.accepted = true;
                return;
            }
            var pasteText = (typeof Quickshell.clipboardText === "string") ? Quickshell.clipboardText : "";
            if (pasteText && typeof root.deleteSelectedBlocks === "function") {
                root.deleteSelectedBlocks(pasteText);
                event.accepted = true;
                return;
            }
        }

        if (isCtrl && !isShift && !isAlt && event.key === Qt.Key_C) {
            root.copySelectedText();
            event.accepted = true;
            return;
        }

        if (isCtrl && !isShift && !isAlt && event.key === Qt.Key_X) {
            root.copySelectedText();
            if (!root.readOnly) {
                root.deleteSelectedBlocks();
            }
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            if (root.readOnly) {
                event.accepted = true;
                return;
            }
            root.deleteSelectedBlocks();
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Escape) {
            root.clearBlockSelection();
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Up || event.key === Qt.Key_Left) {
            var firstBid = -1;
            for (var u = 0; u < blocksModel.count; u++) {
                var bU = blocksModel.get(u);
                if (root.selectedBids[bU.bid] === true) {
                    firstBid = bU.bid;
                    break;
                }
            }
            root.clearBlockSelection();
            if (firstBid !== -1) {
                root.requestEditBlock(firstBid, 0);
            }
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Down || event.key === Qt.Key_Right) {
            var lastBid = -1;
            for (var d = blocksModel.count - 1; d >= 0; d--) {
                var bD = blocksModel.get(d);
                if (root.selectedBids[bD.bid] === true) {
                    lastBid = bD.bid;
                    break;
                }
            }
            root.clearBlockSelection();
            if (lastBid !== -1) {
                root.requestEditBlock(lastBid);
            }
            event.accepted = true;
            return;
        }

        if (!isCtrl && !isAlt && event.text && event.text.length > 0 && event.text >= " ") {
            root.deleteSelectedBlocks();
            if (root.activeBlockBid !== -1) {
                var teInput = root._getTextEditForBid(root.activeBlockBid);
                if (teInput) {
                    teInput.text = event.text;
                    teInput.cursorPosition = event.text.length;
                    root.onBlockRawChanged(root.activeBlockBid, event.text);
                }
            }
            event.accepted = true;
            return;
        }
    }

    onMarkdownChanged: {
        if (!root._internalChange) {
            root.loadMarkdown(root.markdown);
        }
    }

    function loadMarkdown(md) {
        if (scrollAnim && scrollAnim.running) {
            scrollAnim.stop();
        }
        root.contentY = 0;
        var res = BlockModel.splitBlocks(md);
        root.documentLead = res.lead;
        blocksModel.clear();
        root._measuredHeights = ({});
        root._imageDimensions = ({});
        for (var i = 0; i < res.blocks.length; i++) {
            blocksModel.append(res.blocks[i]);
        }
        if (blocksModel.count === 0) {
            blocksModel.append({
                bid: BlockModel.getNextBid(),
                type: "paragraph",
                raw: "",
                sep: "\n\n"
            });
        }
        root.visibleChunk = Qt.point(0, Math.min(Math.max(0, blocksModel.count - 1), 30));
        if (blocksModel.count > 35) {
            chunkWindowTimer.restart();
        }
        root.docHistory = History.createHistory(md);
        root.activeBlockBid = -1;
        root._activeBlockDirty = false;
        root.isDirty = false;
        Qt.callLater(() => {
            root.contentY = 0;
        });
    }

    function restoreMarkdown(newMd) {
        if (newMd === undefined || newMd === null) return;
        if (root.activeBlockBid !== -1) {
            root.confirmActiveBlock();
        }
        _saveSnapshot();
        var res = BlockModel.splitBlocks(newMd);
        root.documentLead = res.lead;
        blocksModel.clear();
        root._measuredHeights = ({});
        root._imageDimensions = ({});
        for (var i = 0; i < res.blocks.length; i++) {
            blocksModel.append(res.blocks[i]);
        }
        if (blocksModel.count === 0) {
            blocksModel.append({
                bid: BlockModel.getNextBid(),
                type: "paragraph",
                raw: "",
                sep: "\n\n"
            });
        }
        root.activeBlockBid = -1;
        root._activeBlockDirty = false;
        root.isDirty = true;
        _saveSnapshot();
        root.markdownEdited(newMd);
    }

    function persistUndoHistory(notePath) {
        if (!notePath || !root.docHistory) return;
        var serialized = History.serialize(root.docHistory, 2 * 1024 * 1024);
        if (!serialized) return;
        if (typeof Sys !== "undefined" && typeof Sys.saveHistoryUndo === "function") {
            Sys.saveHistoryUndo(notePath, serialized);
        }
    }

    function loadPersistedUndoHistory(notePath, currentMd) {
        if (!notePath || !root.docHistory) return;
        if (typeof Sys !== "undefined" && typeof Sys.loadHistoryUndo === "function") {
            var raw = Sys.loadHistoryUndo(notePath);
            if (raw && raw.trim().length > 0) {
                var ok = History.restore(root.docHistory, raw, currentMd);
                if (ok && typeof NotesService !== "undefined" && NotesService.debug) {
                    console.log("[BlockEditor] Pila de undo restaurada de forma síncrona para:", notePath);
                }
            }
        }
    }

    function moveBlockUp(bid) {
        var idx = _findBlockIndex(bid);
        if (idx <= 0) return;
        _saveSnapshot();
        blocksModel.move(idx, idx - 1, 1);
        safeFocusDelegate(bid);
        _saveSnapshot();
    }

    function moveBlockDown(bid) {
        var idx = _findBlockIndex(bid);
        if (idx === -1 || idx >= blocksModel.count - 1) return;
        _saveSnapshot();
        blocksModel.move(idx, idx + 1, 1);
        safeFocusDelegate(bid);
        _saveSnapshot();
    }

    function clearEditor() {
        if (scrollAnim && scrollAnim.running) {
            scrollAnim.stop();
        }
        root.contentY = 0;
        if (root.activeBlockBid !== -1) {
            root.confirmActiveBlock();
        }
        root.activeBlockBid = -1;
        root._activeBlockDirty = false;
        root.isDirty = false;
        root.clearBlockSelection();
        blocksModel.clear();
        root._measuredHeights = ({});
        root._imageDimensions = ({});
        root.visibleChunk = Qt.point(0, 30);
        root.markdown = "";
        root.documentLead = "";
        root._frozenColumnWidth = 0;
    }

    function getMarkdown() {
        if (!root.hasPendingChanges && typeof root.markdown === "string" && root.markdown !== "") {
            return root.markdown;
        }
        var activeRaw = null;
        var activeIdx = -1;
        if (root.activeBlockBid !== -1) {
            activeIdx = _findBlockIndex(root.activeBlockBid);
            if (activeIdx !== -1) {
                var activeBlock = blocksModel.get(activeIdx);
                var loader = _getDelegateItemForBid(root.activeBlockBid);
                var curRaw = null;
                if (loader && loader.item && loader.item.blockData) {
                    var delBid = loader.item.blockData.bid;
                    var delType = loader.item.blockData.type;
                    if (delBid === root.activeBlockBid && delType === activeBlock.type) {
                        if (typeof loader.item.getRaw === "function") {
                            curRaw = loader.item.getRaw();
                        } else {
                            var textEdit = _getTextEditForBid(root.activeBlockBid);
                            if (textEdit) {
                                curRaw = Inline.plainText(textEdit);
                            }
                        }
                    }
                }
                if (typeof curRaw === "string") {
                    activeRaw = _stripQtHtml(curRaw);
                } else {
                    activeRaw = (activeBlock ? activeBlock.raw : "") || "";
                }
            }
        }
        var blist = [];
        for (var i = 0; i < blocksModel.count; i++) {
            var b = blocksModel.get(i);
            if (i === activeIdx && activeRaw !== null) {
                blist.push({
                    bid: b.bid,
                    type: b.type,
                    raw: activeRaw,
                    sep: b.sep
                });
            } else {
                blist.push(b);
            }
        }
        return BlockModel.joinBlocks(blist, root.documentLead);
    }

    function requestEditBlock(bid, cursorPos) {
        if (root.readOnly) {
            root.clearBlockSelection();
            var bIdx = _findBlockIndex(bid);
            if (bIdx !== -1) {
                var blk = blocksModel.get(bIdx);
                if (blk && (blk.type === "hr" || blk.type === "image" || blk.type === "table" || blk.type === "mermaid" || blk.type === "math" || blk.type === "code")) {
                    return;
                }
            }
            if (root.activeBlockBid === bid) {
                if (cursorPos !== undefined) {
                    root.safeFocusDelegate(bid, cursorPos);
                }
                return;
            }
            root.activeBlockBid = bid;
            root._activeBlockDirty = false;
            root.safeFocusDelegate(bid, cursorPos);
            return;
        }
        root.clearBlockSelection();
        if (root.activeBlockBid === bid) {
            if (cursorPos !== undefined) {
                root.safeFocusDelegate(bid, cursorPos);
            }
            return;
        }
        root.confirmActiveBlock();
        root.activeBlockBid = bid;
        root._activeBlockDirty = false;
        root.safeFocusDelegate(bid, cursorPos);
    }

    function _getTextEditForBid(bid) {
        var loader = _getDelegateItemForBid(bid);
        if (loader && loader.item && typeof loader.item.getTextEdit === "function") {
            return loader.item.getTextEdit();
        }
        return null;
    }

    function _stripQtHtml(str) {
        return MD.sanitizeQtHtml(str);
    }

    function confirmActiveBlock() {
        if (root.activeBlockBid === -1) return;
        if (root.readOnly) {
            root.activeBlockBid = -1;
            return;
        }
        var idx = _findBlockIndex(root.activeBlockBid);
        if (idx === -1) {
            root.activeBlockBid = -1;
            return;
        }

        var item = blocksModel.get(idx);
        var loader = _getDelegateItemForBid(root.activeBlockBid);
        var curRaw = null;

        if (loader && loader.item && loader.item.blockData) {
            var delBid = loader.item.blockData.bid;
            var delType = loader.item.blockData.type;
            if (delBid === root.activeBlockBid && delType === item.type) {
                if (typeof loader.item.getRaw === "function") {
                    curRaw = loader.item.getRaw();
                } else {
                    var textEdit = _getTextEditForBid(root.activeBlockBid);
                    if (textEdit) {
                        curRaw = Inline.plainText(textEdit);
                    }
                }
            }
        }
        if (curRaw === null || typeof curRaw !== "string") {
            curRaw = (item ? item.raw : "") || "";
        }

        curRaw = _stripQtHtml(curRaw);
        var oldRaw = (item ? item.raw : "") || "";
        var hasTextChanged = (curRaw !== oldRaw);

        // Si no hubo cambios en este bloque, desactivar sin tocar modelo, sin guardar snapshot y sin emitir markdownEdited
        if (!root._activeBlockDirty && !hasTextChanged) {
            root.activeBlockBid = -1;
            return;
        }

        root._activeBlockDirty = false;
        blocksModel.setProperty(idx, "raw", curRaw);

        var reparsed = BlockModel.reparseBlock(curRaw, item.bid);

        if (reparsed.length === 0) {
            if (blocksModel.count <= 1) {
                blocksModel.setProperty(idx, "type", "paragraph");
                blocksModel.setProperty(idx, "raw", "");
            } else {
                blocksModel.remove(idx);
            }
        } else if (reparsed.length === 1) {
            blocksModel.setProperty(idx, "type", reparsed[0].type);
            blocksModel.setProperty(idx, "raw", reparsed[0].raw);
            var s0 = (reparsed[0].sep !== undefined && reparsed[0].sep !== "") ? reparsed[0].sep : (item.sep || "\n\n");
            blocksModel.setProperty(idx, "sep", s0);
        } else {
            var origSep = item.sep || "\n\n";
            var lastRep = reparsed[reparsed.length - 1];
            if (!lastRep.sep || lastRep.sep.length < origSep.length) {
                lastRep.sep = origSep;
            }
            blocksModel.remove(idx);
            for (var k = 0; k < reparsed.length; k++) {
                blocksModel.insert(idx + k, reparsed[k]);
            }
        }

        if (blocksModel.count === 0) {
            blocksModel.append({
                bid: BlockModel.getNextBid(),
                type: "paragraph",
                raw: "",
                sep: "\n\n"
            });
        }

        root.activeBlockBid = -1;
        _saveSnapshot();
        debouncedMarkdownTimer.stop();
        root._internalChange = true;
        root.markdownEdited(root.getMarkdown());
        root._internalChange = false;
    }

    function convertBlockType(bid, newType, newRaw, cursorPos) {
        var idx = _findBlockIndex(bid);
        if (idx === -1) return;
        var newBid = BlockModel.getNextBid();
        root.activeBlockBid = newBid;
        blocksModel.setProperty(idx, "bid", newBid);
        blocksModel.setProperty(idx, "raw", newRaw);
        blocksModel.setProperty(idx, "type", newType);
        root.onBlockRawChanged(newBid, newRaw);
        _saveSnapshot();
        root.safeFocusDelegate(newBid, (cursorPos === undefined) ? 0 : cursorPos);
    }

    function onBlockRawChanged(bid, newRaw) {
        var idx = _findBlockIndex(bid);
        if (idx !== -1) {
            root._activeBlockDirty = true;
            blocksModel.setProperty(idx, "raw", newRaw);

            // Autoformato al vuelo si escribe prefijo de lista o cita seguido de espacio
            var item = blocksModel.get(idx);
            if (item && item.type === "paragraph") {
                var auto = BlockModel.detectAutoformat(newRaw);
                if (auto.matched && auto.type !== "code") {
                    var te = root._getTextEditForBid(bid);
                    var cur = te ? te.cursorPosition : newRaw.length;
                    root.convertBlockType(bid, auto.type, newRaw, BlockModel.cursorAfterAutoformat(auto, cur));
                    return;
                }
            }

            // Notificar cambio inmediato y diferir unión completa de markdown (P2-8)
            root.contentModified();
            debouncedMarkdownTimer.restart();
            typingSnapshotTimer.restart();
        }
    }

    function handleBlockEnter(bid, cursorPos) {
        var idx = _findBlockIndex(bid);
        if (idx === -1) return;

        var item = blocksModel.get(idx);
        var raw = item.raw || "";

        // Si el bloque de lista o cita está vacío, salir de la lista/cita
        if (item.type !== "paragraph" && (raw.trim() === "" || (item.type === "quote" && raw.replace(/^[ \t]*>[ \t]?/gm, "").trim() === ""))) {
            blocksModel.setProperty(idx, "type", "paragraph");
            blocksModel.setProperty(idx, "raw", "");
            root.activeBlockBid = item.bid;
            _saveSnapshot();
            root.safeFocusDelegate(item.bid, 0);
            return;
        }

        var trimmedLine = raw.trim();

        // Si el párrafo sólo contiene una viñeta vacía (- , * , 1. , - [ ] ), vaciarlo en vez de crear nuevos bloques
        if (item.type === "paragraph" && /^\s*([-*+](\s*\[[ xX]\])?|\d+[.)])\s*$/.test(trimmedLine)) {
            blocksModel.setProperty(idx, "raw", "");
            root.onBlockRawChanged(bid, "");
            root.activeBlockBid = item.bid;
            _saveSnapshot();
            root.safeFocusDelegate(item.bid, 0);
            return;
        }

        // Si el cursor está al inicio (cursorPos === 0) y el bloque de arriba es una viñeta vacía,
        // subir el texto a la viñeta de arriba en lugar de empujar hacia abajo
        if (cursorPos === 0 && idx > 0) {
            var prevBlock = blocksModel.get(idx - 1);
            if (prevBlock && prevBlock.type === "list") {
                var prevListItems = LP.parseList(prevBlock.raw || "");
                if (prevListItems && prevListItems.length > 0) {
                    var lastPIdx = prevListItems.length - 1;
                    if ((prevListItems[lastPIdx].text || "").trim() === "") {
                        prevListItems[lastPIdx].text = raw;
                        var mergedRaw = LP.serializeList(prevListItems);
                        var newBid = BlockModel.getNextBid();
                        root.activeBlockBid = newBid;
                        blocksModel.setProperty(idx - 1, "bid", newBid);
                        blocksModel.setProperty(idx - 1, "raw", mergedRaw);
                        blocksModel.remove(idx);
                        _saveSnapshot();
                        root.contentModified();
                        debouncedMarkdownTimer.restart();
                        root.safeFocusDelegate(newBid, 0);
                        return;
                    }
                }
            }
        }

        // Detección de creación de bloque de código, mermaid o math: ``` o ```lang + Enter
        var codeAuto = BlockModel.detectAutoformat(trimmedLine);
        if (item.type === "paragraph" && codeAuto.matched && codeAuto.type === "code") {
            var fence = codeAuto.fence || "```";
            var lang = codeAuto.lang || "";
            var isMermaid = lang.toLowerCase() === "mermaid";
            var isMath = lang.toLowerCase() === "math" || lang.toLowerCase() === "latex";
            var codeRaw = isMermaid ? (fence + "mermaid\nflowchart TD\n    A[Inicio] --> B[Fin]\n" + fence)
                        : (isMath ? (fence + lang + "\n\\frac{a}{b}\n" + fence) : (fence + lang + "\n\n" + fence));
            blocksModel.setProperty(idx, "type", isMermaid ? "mermaid" : (isMath ? "math" : "code"));
            blocksModel.setProperty(idx, "raw", codeRaw);
            root.activeBlockBid = item.bid;
            _saveSnapshot();
            var innerPos = (isMermaid || isMath) ? 0 : (fence + lang + "\n").length;
            root.safeFocusDelegate(item.bid, innerPos);
            return;
        }

        if (item.type === "paragraph" && codeAuto.matched && codeAuto.type === "math") {
            var mathRaw = "$$\n\\frac{a}{b}\n$$";
            blocksModel.setProperty(idx, "type", "math");
            blocksModel.setProperty(idx, "raw", mathRaw);
            root.activeBlockBid = item.bid;
            _saveSnapshot();
            root.safeFocusDelegate(item.bid, 0);
            return;
        }

        // Detección de creación de tabla al estilo Typora: | col1 | col2 | col3 | + Enter
        if (item.type === "paragraph" && trimmedLine.startsWith("|") && trimmedLine.endsWith("|") && trimmedLine.length > 2) {
            var pipeCells = trimmedLine.substring(1, trimmedLine.length - 1).split("|").map(function(s) { return s.trim(); });
            if (pipeCells.length >= 2) {
                var colCount = pipeCells.length;
                var headerRow = "| " + pipeCells.join(" | ") + " |";
                var delimRow = "| " + Array(colCount).fill("---").join(" | ") + " |";
                var dataRow = "| " + Array(colCount).fill(" ").join(" | ") + " |";
                var tableRaw = headerRow + "\n" + delimRow + "\n" + dataRow;

                // Actualizar raw antes de type para que al instanciar BlockTable ya tenga el markdown completo
                blocksModel.setProperty(idx, "raw", tableRaw);
                blocksModel.setProperty(idx, "type", "table");
                root.activeBlockBid = item.bid;
                root.onBlockRawChanged(item.bid, tableRaw);
                _saveSnapshot();
                root.safeFocusDelegate(item.bid, 0);
                return;
            }
        }

        var firstPart = raw.substring(0, cursorPos);
        var secondPart = raw.substring(cursorPos);

        // Actualizar el primer bloque
        blocksModel.setProperty(idx, "raw", firstPart);
        var repFirst = BlockModel.reparseBlock(firstPart, item.bid);
        if (repFirst.length > 0) {
            blocksModel.setProperty(idx, "type", repFirst[0].type);
        } else {
            blocksModel.setProperty(idx, "type", "paragraph");
        }

        // Crear el bloque siguiente con el resto del contenido
        var nextBid = BlockModel.getNextBid();
        var nextType = "paragraph";
        var repSec = BlockModel.reparseBlock(secondPart, nextBid);
        if (repSec.length > 0) {
            nextType = repSec[0].type;
        }

        var origSep = item.sep || "\n\n";
        blocksModel.setProperty(idx, "sep", "\n\n");
        blocksModel.insert(idx + 1, {
            bid: nextBid,
            type: nextType,
            raw: secondPart,
            sep: origSep
        });

        root.activeBlockBid = nextBid;
        _saveSnapshot();
        root.safeFocusDelegate(nextBid, 0);
    }

    function insertParagraphAfter(bid) {
        var idx = _findBlockIndex(bid);
        if (idx === -1) return;

        root.confirmActiveBlock();
        var nextBid = BlockModel.getNextBid();
        var origSep = blocksModel.get(idx).sep || "\n\n";
        blocksModel.setProperty(idx, "sep", "\n\n");
        blocksModel.insert(idx + 1, {
            bid: nextBid,
            type: "paragraph",
            raw: "",
            sep: origSep
        });

        root.activeBlockBid = nextBid;
        _saveSnapshot();
        root.safeFocusDelegate(nextBid, 0);
    }

    function exitFenceBlock(bid) {
        insertParagraphAfter(bid);
    }

    function deleteBlock(bid) {
        var idx = _findBlockIndex(bid);
        if (idx === -1) return;

        if (blocksModel.count <= 1) {
            var newBid = BlockModel.getNextBid();
            root.activeBlockBid = newBid;
            blocksModel.setProperty(0, "bid", newBid);
            blocksModel.setProperty(0, "type", "paragraph");
            blocksModel.setProperty(0, "raw", "");
            blocksModel.setProperty(0, "sep", "\n\n");
            _saveSnapshot();
            root.contentModified();
            debouncedMarkdownTimer.restart();
            root.safeFocusDelegate(newBid, 0);
            return;
        }

        blocksModel.remove(idx);
        _saveSnapshot();
        root.contentModified();
        debouncedMarkdownTimer.restart();

        if (idx < blocksModel.count) {
            var next = blocksModel.get(idx);
            root.activeBlockBid = next.bid;
            root.safeFocusDelegate(next.bid, 0);
        } else if (idx > 0) {
            var prev = blocksModel.get(idx - 1);
            root.activeBlockBid = prev.bid;
            root.safeFocusDelegate(prev.bid, -1);
        } else {
            root.activeBlockBid = -1;
        }
    }

    function unbulletListItem(bid, itemIdx) {
        var idx = _findBlockIndex(bid);
        if (idx === -1) return;

        var item = blocksModel.get(idx);
        var curRaw = item.raw || "";
        var listItems = LP.parseList(curRaw);
        if (!listItems || itemIdx < 0 || itemIdx >= listItems.length) return;

        var targetItem = listItems[itemIdx];
        var unbulletedText = targetItem.text !== undefined ? targetItem.text : "";

        if (listItems.length <= 1) {
            // Un solo ítem en la lista: convertir directamente el bloque a párrafo
            root.convertBlockType(bid, "paragraph", unbulletedText);
            return;
        }

        var itemsBefore = listItems.slice(0, itemIdx);
        var itemsAfter = listItems.slice(itemIdx + 1);

        var origSep = item.sep || "\n\n";
        var pBid = BlockModel.getNextBid();

        if (itemsBefore.length > 0 && itemsAfter.length > 0) {
            // Ítem en el medio: dividir en Lista -> Párrafo -> Lista
            var beforeRaw = LP.serializeList(itemsBefore);
            var afterRaw = LP.serializeList(itemsAfter);
            var nextListBid = BlockModel.getNextBid();

            blocksModel.setProperty(idx, "raw", beforeRaw);
            blocksModel.setProperty(idx, "sep", "\n\n");
            blocksModel.insert(idx + 1, {
                bid: pBid,
                type: "paragraph",
                raw: unbulletedText,
                sep: "\n\n"
            });
            blocksModel.insert(idx + 2, {
                bid: nextListBid,
                type: "list",
                raw: afterRaw,
                sep: origSep
            });
        } else if (itemsBefore.length === 0) {
            // Era el primer ítem: insertar Párrafo antes y actualizar la Lista existente después
            var afterRaw = LP.serializeList(itemsAfter);
            blocksModel.setProperty(idx, "raw", afterRaw);
            blocksModel.insert(idx, {
                bid: pBid,
                type: "paragraph",
                raw: unbulletedText,
                sep: "\n\n"
            });
        } else {
            // Era el último ítem: actualizar la Lista existente antes e insertar Párrafo después
            var beforeRaw = LP.serializeList(itemsBefore);
            blocksModel.setProperty(idx, "raw", beforeRaw);
            blocksModel.setProperty(idx, "sep", "\n\n");
            blocksModel.insert(idx + 1, {
                bid: pBid,
                type: "paragraph",
                raw: unbulletedText,
                sep: origSep
            });
        }

        root.activeBlockBid = pBid;
        _saveSnapshot();
        root.contentModified();
        debouncedMarkdownTimer.restart();
        root.safeFocusDelegate(pBid, 0);
    }

    function handleBlockBackspaceAtStart(bid) {
        var idx = _findBlockIndex(bid);
        if (idx === -1) return;

        var item = blocksModel.get(idx);
        if ((item.raw || "").trim() === "") {
            // Eliminar bloque vacío si hay más de uno
            if (blocksModel.count <= 1) return;
            blocksModel.remove(idx);
            if (idx > 0) {
                var prev = blocksModel.get(idx - 1);
                root.activeBlockBid = prev.bid;
                root.safeFocusDelegate(prev.bid, -1);
            } else if (blocksModel.count > 0) {
                var first = blocksModel.get(0);
                root.activeBlockBid = first.bid;
                root.safeFocusDelegate(first.bid, 0);
            } else {
                root.activeBlockBid = -1;
            }
            _saveSnapshot();
        } else if (idx > 0) {
            var prevBlock = blocksModel.get(idx - 1);
            if (!BlockModel.canMergeBlocks(item.type, prevBlock.type)) {
                // No fusionar tipos incompatibles (hr, code, table, image, html)
                root.activeBlockBid = prevBlock.bid;
                root.safeFocusDelegate(prevBlock.bid, -1);
                return;
            }

            if (prevBlock.type === "list") {
                var prevItems = LP.parseList(prevBlock.raw || "");
                if (prevItems && prevItems.length > 0) {
                    var lastIdx = prevItems.length - 1;
                    var lastIt = prevItems[lastIdx];
                    var prevCleanLen = (lastIt.text || "").length;
                    var isLastEmpty = (lastIt.text || "").trim() === "";

                    lastIt.text = (lastIt.text || "") + (item.raw || "");
                    var newMergedRaw = LP.serializeList(prevItems);

                    var newBid = BlockModel.getNextBid();
                    root.activeBlockBid = newBid;
                    blocksModel.setProperty(idx - 1, "bid", newBid);
                    blocksModel.setProperty(idx - 1, "raw", newMergedRaw);
                    blocksModel.remove(idx);
                    _saveSnapshot();
                    root.contentModified();
                    debouncedMarkdownTimer.restart();
                    var focusPos = isLastEmpty ? 0 : prevCleanLen;
                    root.safeFocusDelegate(newBid, focusPos);
                    return;
                }
            }

            // Unir con el bloque anterior
            var prevClean = (prevBlock.raw || "");
            if (prevBlock.type === "heading") {
                prevClean = prevClean.replace(/^[ \t]*#{1,6}[ \t]*/, "");
            }
            var prevCursorPos = prevClean.length;
            var merged = (prevBlock.raw || "") + item.raw;
            var newMergeBid = BlockModel.getNextBid();
            root.activeBlockBid = newMergeBid;
            blocksModel.setProperty(idx - 1, "bid", newMergeBid);
            blocksModel.setProperty(idx - 1, "raw", merged);
            var rep = BlockModel.reparseBlock(merged, newMergeBid);
            if (rep.length > 0) {
                blocksModel.setProperty(idx - 1, "type", rep[0].type);
            }
            blocksModel.remove(idx);
            _saveSnapshot();
            root.contentModified();
            debouncedMarkdownTimer.restart();
            root.safeFocusDelegate(newMergeBid, prevCursorPos);
        }
    }

    function handleBlockDeleteAtEnd(bid) {
        var idx = _findBlockIndex(bid);
        if (idx === -1 || idx >= blocksModel.count - 1) return;

        var currentItem = blocksModel.get(idx);
        var nextItem = blocksModel.get(idx + 1);

        if (!BlockModel.canMergeBlocks(currentItem.type, nextItem.type)) {
            // No fusionar tipos incompatibles
            root.activeBlockBid = nextItem.bid;
            root.safeFocusDelegate(nextItem.bid, 0);
            return;
        }

        var curLen = (currentItem.raw || "").length;
        var merged = (currentItem.raw || "") + (nextItem.raw || "");

        blocksModel.setProperty(idx, "raw", merged);
        var rep = BlockModel.reparseBlock(merged, currentItem.bid);
        if (rep.length > 0) {
            blocksModel.setProperty(idx, "type", rep[0].type);
        }
        blocksModel.remove(idx + 1);

        root.activeBlockBid = currentItem.bid;
        _saveSnapshot();
        root.safeFocusDelegate(currentItem.bid, curLen);
    }

    function focusPreviousBlock(bid, targetPos) {
        var idx = _findBlockIndex(bid);
        if (idx > 0) {
            root.confirmActiveBlock();
            var prev = blocksModel.get(idx - 1);
            root.activeBlockBid = prev.bid;
            var pos = (targetPos !== undefined) ? targetPos : -1;
            root.safeFocusDelegate(prev.bid, pos);
        } else if (idx === 0) {
            if (root.editorModal && typeof root.editorModal.focusTitleInput === "function") {
                root.confirmActiveBlock();
                root.editorModal.focusTitleInput();
            }
        }
    }

    function focusNextBlock(bid, targetPos) {
        var idx = _findBlockIndex(bid);
        if (idx !== -1 && idx < blocksModel.count - 1) {
            root.confirmActiveBlock();
            var next = blocksModel.get(idx + 1);
            root.activeBlockBid = next.bid;
            var pos = (targetPos !== undefined) ? targetPos : 0;
            root.safeFocusDelegate(next.bid, pos);
        }
    }

    // ── F78: Ejecución e inserción de comandos '/' estilo Notion ─────────────────
    function handleSlashCommandExecution(cmd, triggerInfo) {
        if (!cmd || root.activeBlockBid === -1) return;
        var textEdit = _getTextEditForBid(root.activeBlockBid);
        var idx = _findBlockIndex(root.activeBlockBid);
        if (idx === -1) return;

        var curItem = blocksModel.get(idx);
        var isBlockEmpty = true;
        if (textEdit && triggerInfo && typeof triggerInfo.slashIndex === "number" && typeof triggerInfo.endIndex === "number") {
            var s = Math.max(0, triggerInfo.slashIndex);
            var e = Math.min(textEdit.length, triggerInfo.endIndex);
            textEdit.remove(s, e);
            var remaining = Inline.plainText(textEdit);
            isBlockEmpty = (remaining.trim() === "");
        } else if (curItem) {
            isBlockEmpty = (!curItem.raw || curItem.raw.trim() === "" || curItem.raw.trim().startsWith("/"));
        }

        root.applySlashCommand(cmd.id, {
            consumeEmptyBlock: isBlockEmpty,
            calloutType: cmd.calloutType || "",
            blockBid: root.activeBlockBid
        });
    }

    function applySlashCommand(cmdId, opts) {
        if (!cmdId || root.activeBlockBid === -1) return;
        var idx = _findBlockIndex(root.activeBlockBid);
        if (idx === -1) return;

        var curItem = blocksModel.get(idx);
        var consume = opts ? Boolean(opts.consumeEmptyBlock) : false;

        // 1. Encabezados (h1, h2, h3)
        if (cmdId === "h1" || cmdId === "h2" || cmdId === "h3") {
            var lvl = parseInt(cmdId.charAt(1), 10);
            var prefix = "#".repeat(lvl) + " ";
            if (consume && curItem) {
                blocksModel.setProperty(idx, "type", "heading");
                blocksModel.setProperty(idx, "raw", prefix);
                root.onBlockRawChanged(curItem.bid, prefix);
                root.safeFocusDelegate(curItem.bid, prefix.length);
            } else {
                root.applyAction(cmdId);
            }
            _saveSnapshot();
            root.updateFormatState();
            return;
        }

        // 2. Listas (bullet, numbered, task)
        if (cmdId === "bullet_list" || cmdId === "numbered_list" || cmdId === "task_list") {
            if (consume && curItem) {
                var listPfx = "- ";
                if (cmdId === "numbered_list") listPfx = "1. ";
                else if (cmdId === "task_list") listPfx = "- [ ] ";

                blocksModel.setProperty(idx, "type", "list");
                blocksModel.setProperty(idx, "raw", listPfx);
                root.onBlockRawChanged(curItem.bid, listPfx);
                var ldr = _getDelegateItemForBid(curItem.bid);
                if (ldr && ldr.item && typeof ldr.item._reloadFromRaw === "function") {
                    ldr.item._reloadFromRaw();
                }
                root.safeFocusDelegate(curItem.bid, listPfx.length);
            } else {
                root.applyAction(cmdId);
            }
            _saveSnapshot();
            root.updateFormatState();
            return;
        }

        // 3. Bloque de código
        if (cmdId === "code_block") {
            if (consume && curItem) {
                var codeRaw = "```\n\n```";
                blocksModel.setProperty(idx, "type", "code");
                blocksModel.setProperty(idx, "raw", codeRaw);
                root.onBlockRawChanged(curItem.bid, codeRaw);
                _saveSnapshot();
                root.safeFocusDelegate(curItem.bid, 4);
            } else {
                root.applyAction("code_block");
            }
            root.updateFormatState();
            return;
        }

        // 4. Cita estándar
        if (cmdId === "quote") {
            if (consume && curItem) {
                var qRaw = "> ";
                blocksModel.setProperty(idx, "type", "quote");
                blocksModel.setProperty(idx, "raw", qRaw);
                root.onBlockRawChanged(curItem.bid, qRaw);
                root.safeFocusDelegate(curItem.bid, 2);
            } else {
                root.applyAction("quote");
            }
            _saveSnapshot();
            root.updateFormatState();
            return;
        }

        // 5. Callouts estilo GitHub
        if (cmdId.startsWith("callout_")) {
            var cType = (opts && opts.calloutType) ? opts.calloutType : cmdId.substring(8).toUpperCase();
            var cRaw = "> [!" + cType + "]\n> ";
            if (consume && curItem) {
                blocksModel.setProperty(idx, "type", "quote");
                blocksModel.setProperty(idx, "raw", cRaw);
                root.onBlockRawChanged(curItem.bid, cRaw);
                root.safeFocusDelegate(curItem.bid, cRaw.length);
            } else {
                var qBid = BlockModel.getNextBid();
                var insertPos = (idx !== -1) ? idx + 1 : blocksModel.count;
                blocksModel.insert(insertPos, { bid: qBid, type: "quote", raw: cRaw, sep: "\n\n" });
                root.activeBlockBid = qBid;
                root.safeFocusDelegate(qBid, cRaw.length);
            }
            _saveSnapshot();
            root.updateFormatState();
            return;
        }

        // 6. Tabla
        if (cmdId === "table") {
            root.confirmActiveBlock();
            var col1 = (typeof I18n !== "undefined" && typeof I18n.t === "function") ? I18n.t("notes.table_col1", "Columna 1") : "Columna 1";
            var col2 = (typeof I18n !== "undefined" && typeof I18n.t === "function") ? I18n.t("notes.table_col2", "Columna 2") : "Columna 2";
            var tblTpl = "| " + col1 + " | " + col2 + " |\n| :--- | :--- |\n|  |  |\n|  |  |";

            if (consume && curItem) {
                blocksModel.setProperty(idx, "type", "table");
                blocksModel.setProperty(idx, "raw", tblTpl);
                root.onBlockRawChanged(curItem.bid, tblTpl);
                root.safeFocusDelegate(curItem.bid, 0);
            } else {
                var tblBid = BlockModel.getNextBid();
                var insertPos = (idx !== -1) ? idx + 1 : blocksModel.count;
                blocksModel.insert(insertPos, { bid: tblBid, type: "table", raw: tblTpl, sep: "\n\n" });
                root.activeBlockBid = tblBid;
                root.safeFocusDelegate(tblBid, 0);
            }
            _saveSnapshot();
            root.updateFormatState();
            return;
        }

        // 7. Diagrama Mermaid
        if (cmdId === "mermaid") {
            root.confirmActiveBlock();
            var mermaidTpl = "```mermaid\nflowchart TD\n    A[Inicio] --> B[Fin]\n```";
            if (consume && curItem) {
                blocksModel.setProperty(idx, "type", "mermaid");
                blocksModel.setProperty(idx, "raw", mermaidTpl);
                root.onBlockRawChanged(curItem.bid, mermaidTpl);
                root.safeFocusDelegate(curItem.bid, 0);
            } else {
                var mBid = BlockModel.getNextBid();
                var insertPos = (idx !== -1) ? idx + 1 : blocksModel.count;
                blocksModel.insert(insertPos, { bid: mBid, type: "mermaid", raw: mermaidTpl, sep: "\n\n" });
                root.activeBlockBid = mBid;
                root.safeFocusDelegate(mBid, 0);
            }
            _saveSnapshot();
            root.updateFormatState();
            return;
        }

        // 7b. Fórmula Matemática LaTeX
        if (cmdId === "math" || cmdId === "latex") {
            root.confirmActiveBlock();
            var mathTpl = "$$\n\\frac{a}{b}\n$$";
            if (consume && curItem) {
                blocksModel.setProperty(idx, "type", "math");
                blocksModel.setProperty(idx, "raw", mathTpl);
                root.onBlockRawChanged(curItem.bid, mathTpl);
                root.safeFocusDelegate(curItem.bid, 0);
            } else {
                var mathBid = BlockModel.getNextBid();
                var mathInsertPos = (idx !== -1) ? idx + 1 : blocksModel.count;
                blocksModel.insert(mathInsertPos, { bid: mathBid, type: "math", raw: mathTpl, sep: "\n\n" });
                root.activeBlockBid = mathBid;
                root.safeFocusDelegate(mathBid, 0);
            }
            _saveSnapshot();
            root.updateFormatState();
            return;
        }

        // 8. Línea divisoria (hr)
        if (cmdId === "hr") {
            root.confirmActiveBlock();
            if (consume && curItem) {
                blocksModel.setProperty(idx, "type", "hr");
                blocksModel.setProperty(idx, "raw", "---");
                root.onBlockRawChanged(curItem.bid, "---");
                var nextP = { bid: BlockModel.getNextBid(), type: "paragraph", raw: "", sep: "\n\n" };
                blocksModel.insert(idx + 1, nextP);
                root.activeBlockBid = nextP.bid;
                root.safeFocusDelegate(nextP.bid, 0);
            } else {
                root.applyAction("hr");
            }
            _saveSnapshot();
            root.updateFormatState();
            return;
        }
    }

    function applyAction(actionId) {
        // ── Caso A: Múltiples bloques seleccionados ─────────────────────────
        if (root.hasBlockSelection) {
            var selBidsList = [];
            for (var k = 0; k < blocksModel.count; k++) {
                var bItem = blocksModel.get(k);
                if (bItem && root.selectedBids && root.selectedBids[bItem.bid] === true) {
                    selBidsList.push({ idx: k, item: bItem });
                }
            }
            if (selBidsList.length > 0) {
                // Formatos inline sobre todos los bloques seleccionados
                if (actionId === "bold" || actionId === "italic" || actionId === "underline" || actionId === "strike" || actionId === "inline_code" || actionId === "highlight") {
                    var marker = "**";
                    if (actionId === "italic") marker = "*";
                    else if (actionId === "underline") marker = "<u>";
                    else if (actionId === "strike") marker = "~~";
                    else if (actionId === "inline_code") marker = "`";
                    else if (actionId === "highlight") marker = "==";

                    for (var sIdx = 0; sIdx < selBidsList.length; sIdx++) {
                        var selB = selBidsList[sIdx];
                        var bType = selB.item.type;
                        if (bType !== "paragraph" && bType !== "heading" && bType !== "quote" && bType !== "list") {
                            continue;
                        }
                        var bRaw = selB.item.raw || "";
                        var te = _getTextEditForBid(selB.item.bid);
                        var newRaw = bRaw;

                        if (bType === "paragraph") {
                            var pTxt = te ? Inline.plainText(te) : bRaw;
                            var sPos = te ? te.selectionStart : 0;
                            var ePos = te ? te.selectionEnd : pTxt.length;
                            if (sPos === ePos) { sPos = 0; ePos = pTxt.length; }
                            var wrapRes = Inline.toggleWrap(pTxt, sPos, ePos, marker);
                            newRaw = wrapRes.text;
                            if (te) {
                                if (te.textFormat === TextEdit.RichText) te.text = Inline.formatForLiveEditing(wrapRes.text, { cursorPos: te.cursorPosition, selStart: wrapRes.newSelStart, selEnd: wrapRes.newSelEnd });
                                else te.text = wrapRes.text;
                                te.select(wrapRes.newSelStart, wrapRes.newSelEnd);
                            }
                        } else if (bType === "heading") {
                            var hMatch = bRaw.match(/^([ \t]*#{1,6}[ \t]+)([\s\S]*)$/);
                            var hPrefix = hMatch ? hMatch[1] : "# ";
                            var hBody = hMatch ? hMatch[2] : bRaw;
                            var sPos = 0;
                            var ePos = hBody.length;
                            if (te) {
                                sPos = te.selectionStart;
                                ePos = te.selectionEnd;
                                if (sPos === ePos) { sPos = 0; ePos = hBody.length; }
                            }
                            var wrapRes = Inline.toggleWrap(hBody, sPos, ePos, marker);
                            newRaw = hPrefix + wrapRes.text;
                            if (te) {
                                if (te.textFormat === TextEdit.RichText) te.text = Inline.formatForLiveEditing(wrapRes.text, { cursorPos: te.cursorPosition, selStart: wrapRes.newSelStart, selEnd: wrapRes.newSelEnd });
                                else te.text = wrapRes.text;
                                te.select(wrapRes.newSelStart, wrapRes.newSelEnd);
                            }
                        } else if (bType === "quote") {
                            var qLines = bRaw.split("\n");
                            var wrappedLines = qLines.map(function(qLine) {
                                var qm = qLine.match(/^([ \t]*>[ \t]?)(.*)$/);
                                if (qm) {
                                    var w = Inline.toggleWrap(qm[2], 0, qm[2].length, marker);
                                    return qm[1] + w.text;
                                } else {
                                    var w = Inline.toggleWrap(qLine, 0, qLine.length, marker);
                                    return w.text;
                                }
                            });
                            newRaw = wrappedLines.join("\n");
                            if (te) {
                                var cleanQ = newRaw.replace(/^[ \t]*>[ \t]?/gm, "");
                                if (te.textFormat === TextEdit.RichText) te.text = Inline.formatForLiveEditing(cleanQ, { cursorPos: te.cursorPosition, selStart: te.selectionStart, selEnd: te.selectionEnd });
                                else te.text = cleanQ;
                            }
                        } else if (bType === "list") {
                            var parsedItems = LP.parseList(bRaw);
                            for (var pi = 0; pi < parsedItems.length; pi++) {
                                var it = parsedItems[pi];
                                var w = Inline.toggleWrap(it.text, 0, it.text.length, marker);
                                it.text = w.text;
                            }
                            newRaw = LP.serializeList(parsedItems);
                        }

                        blocksModel.setProperty(selB.idx, "raw", newRaw);
                        root.onBlockRawChanged(selB.item.bid, newRaw);
                        var loader = _getDelegateItemForBid(selB.item.bid);
                        if (loader && loader.item && typeof loader.item._syncTextFromModel === "function") {
                            loader.item._syncTextFromModel();
                        } else if (loader && loader.item && typeof loader.item._reloadFromRaw === "function") {
                            loader.item._reloadFromRaw();
                        }
                    }
                    _saveSnapshot();
                    root.updateFormatState();
                    return;
                }

                // Acciones de listas / tareas sobre múltiples bloques
                if (actionId === "task_list" || actionId === "bullet_list" || actionId === "ordered_list") {
                    var allAlreadyTarget = true;
                    for (var t = 0; t < selBidsList.length; t++) {
                        var bi = selBidsList[t].item;
                        if (bi.type !== "list") { allAlreadyTarget = false; break; }
                        var pList = LP.parseList(bi.raw || "");
                        if (!pList || pList.length === 0) { allAlreadyTarget = false; break; }
                        if (actionId === "task_list" && !pList.every(function(it) { return it.isTask; })) { allAlreadyTarget = false; break; }
                        if (actionId === "bullet_list" && !pList.every(function(it) { return !it.isTask && (it.marker === "-" || it.marker === "*" || it.marker === "+"); })) { allAlreadyTarget = false; break; }
                        if (actionId === "ordered_list" && !pList.every(function(it) { return !it.isTask && (it.marker.indexOf(".") !== -1 || it.marker.indexOf(")") !== -1); })) { allAlreadyTarget = false; break; }
                    }

                    if (allAlreadyTarget) {
                        // TOGGLE OFF: Quitar lista y convertir todos a párrafos
                        for (var u = 0; u < selBidsList.length; u++) {
                            var uItem = selBidsList[u].item;
                            var uIdx = selBidsList[u].idx;
                            var uParsed = LP.parseList(uItem.raw || "");
                            var uText = (uParsed && uParsed.length > 0) ? uParsed.map(function(it) { return it.text; }).join("\n") : (uItem.raw || "");
                            uText = uText.replace(/^(\s*[-*+]\s*(\[[ xX]\])?\s*|\s*\d+[\.\)]\s*)/gm, "");
                            blocksModel.setProperty(uIdx, "type", "paragraph");
                            blocksModel.setProperty(uIdx, "raw", uText);
                            root.onBlockRawChanged(uItem.bid, uText);
                        }
                    } else {
                        // APLICAR A TODOS: Convertir a la lista seleccionada limpiando prefijos previos
                        var ordNum = 1;
                        for (var a = 0; a < selBidsList.length; a++) {
                            var aItem = selBidsList[a].item;
                            var aIdx = selBidsList[a].idx;
                            var aParsed = (aItem.type === "list") ? LP.parseList(aItem.raw || "") : null;
                            var aLines = [];
                            if (aParsed && aParsed.length > 0) {
                                aLines = aParsed.map(function(it) { return it.text; });
                            } else {
                                aLines = (aItem.raw || "").split("\n").map(function(l) {
                                    return l.replace(/^(\s*[-*+]\s*(\[[ xX]\])?\s*|\s*\d+[\.\)]\s*|\s*>[ \t]?|\s*#{1,6}[ \t]+)/, "");
                                });
                            }
                            var formattedLines = aLines.map(function(l) {
                                if (actionId === "task_list") return "- [ ] " + l;
                                if (actionId === "bullet_list") return "- " + l;
                                if (actionId === "ordered_list") return (ordNum++) + ". " + l;
                                return l;
                            });
                            var aRaw = formattedLines.join("\n");
                            blocksModel.setProperty(aIdx, "type", "list");
                            blocksModel.setProperty(aIdx, "raw", aRaw);
                            root.onBlockRawChanged(aItem.bid, aRaw);
                        }
                    }
                    _saveSnapshot();
                    root.updateFormatState();
                    return;
                }

                // Cita (quote) sobre múltiples bloques
                if (actionId === "quote") {
                    var allQuotes = selBidsList.every(function(s) { return s.item.type === "quote"; });
                    for (var q = 0; q < selBidsList.length; q++) {
                        var qItem = selBidsList[q].item;
                        var qIdx = selBidsList[q].idx;
                        if (allQuotes) {
                            var unq = (qItem.raw || "").replace(/^[ \t]*>[ \t]?/gm, "");
                            blocksModel.setProperty(qIdx, "type", "paragraph");
                            blocksModel.setProperty(qIdx, "raw", unq);
                            root.onBlockRawChanged(qItem.bid, unq);
                        } else {
                            var cleanQ = (qItem.raw || "").replace(/^[ \t]*>[ \t]?/gm, "");
                            var newQ = "> " + cleanQ;
                            blocksModel.setProperty(qIdx, "type", "quote");
                            blocksModel.setProperty(qIdx, "raw", newQ);
                            root.onBlockRawChanged(qItem.bid, newQ);
                        }
                    }
                    _saveSnapshot();
                    root.updateFormatState();
                    return;
                }

                // Encabezados (h1..h6) sobre múltiples bloques
                // F22: coherente con isFormatActive — vale para heading y para ítems de lista.
                if (actionId.startsWith("h") && actionId.length === 2) {
                    var lvl = parseInt(actionId[1], 10);
                    var hpfx = "#".repeat(lvl) + " ";
                    var allH = selBidsList.every(function(s) {
                        if (s.item.type === "heading") return (s.item.raw || "").startsWith(hpfx);
                        if (s.item.type === "list") {
                            var li = LP.parseList(s.item.raw || "");
                            return li && li.length > 0 && LP.allItemsMatchHeading(li, 0, li.length - 1, lvl);
                        }
                        return false;
                    });
                    for (var h = 0; h < selBidsList.length; h++) {
                        var hItem = selBidsList[h].item;
                        var hIdx = selBidsList[h].idx;
                        if (hItem.type === "list") {
                            var lParsed = LP.parseList(hItem.raw || "");
                            if (!lParsed || lParsed.length === 0) continue;
                            for (var li2 = 0; li2 < lParsed.length; li2++) {
                                var curT = lParsed[li2].text || "";
                                var stripped = LP.stripHeadingPrefix(curT);
                                lParsed[li2].text = allH ? stripped : (hpfx + stripped);
                            }
                            var lRaw = LP.serializeList(lParsed);
                            blocksModel.setProperty(hIdx, "raw", lRaw);
                            root.onBlockRawChanged(hItem.bid, lRaw);
                            var lLoader = _getDelegateItemForBid(hItem.bid);
                            if (lLoader && lLoader.item && typeof lLoader.item._reloadFromRaw === "function") {
                                lLoader.item._reloadFromRaw();
                            }
                            continue;
                        }
                        if (hItem.type === "quote") continue; // F22: no destruir citas acá (lo cubre F25)
                        var cleanH = (hItem.raw || "").replace(/^[ \t]*#{1,6}[ \t]*/gm, "");
                        if (allH) {
                            blocksModel.setProperty(hIdx, "type", "paragraph");
                            blocksModel.setProperty(hIdx, "raw", cleanH);
                            root.onBlockRawChanged(hItem.bid, cleanH);
                        } else {
                            var newH = hpfx + cleanH;
                            blocksModel.setProperty(hIdx, "type", "heading");
                            blocksModel.setProperty(hIdx, "raw", newH);
                            root.onBlockRawChanged(hItem.bid, newH);
                        }
                    }
                    _saveSnapshot();
                    root.updateFormatState();
                    return;
                }
            }
        }

        // ── Caso B: Bloque activo individual ────────────────────────────────
        if (root.activeBlockBid === -1) {
            if (blocksModel.count === 0) {
                var newB = { bid: BlockModel.getNextBid(), type: "paragraph", raw: "", sep: "\n\n" };
                blocksModel.append(newB);
                root.activeBlockBid = newB.bid;
            } else {
                root.activeBlockBid = blocksModel.get(blocksModel.count - 1).bid;
            }
        }

        var textEdit = _getTextEditForBid(root.activeBlockBid);
        var idx = _findBlockIndex(root.activeBlockBid);

        function _getPlainText(te) {
            return Inline.plainText(te);
        }

        if (actionId === "bold" || actionId === "italic" || actionId === "underline" || actionId === "strike" || actionId === "inline_code" || actionId === "highlight") {
            var marker = "**";
            if (actionId === "italic") marker = "*";
            else if (actionId === "underline") marker = "<u>";
            else if (actionId === "strike") marker = "~~";
            else if (actionId === "inline_code") marker = "`";
            else if (actionId === "highlight") marker = "==";

            if (textEdit) {
                var s = textEdit.selectionStart;
                var e = textEdit.selectionEnd;
                var plainTxt = _getPlainText(textEdit);
                var res = Inline.toggleWrap(plainTxt, s, e, marker);
                if (textEdit.textFormat === TextEdit.RichText) {
                    textEdit.text = Inline.formatForLiveEditing(res.text, {
                        cursorPos: textEdit.cursorPosition,
                        selStart: res.newSelStart,
                        selEnd: res.newSelEnd
                    });
                } else {
                    textEdit.text = res.text;
                }
                textEdit.select(res.newSelStart, res.newSelEnd);
                root._commitInlineFormattedSubEdit(root.activeBlockBid, textEdit, res.text, res.newSelStart, res.newSelEnd);
            }
            root.updateFormatState();
        } else if (actionId === "h1" || actionId === "h2" || actionId === "h3" || actionId === "h4" || actionId === "h5" || actionId === "h6") {
            var targetLevel = 1;
            if (actionId === "h2") targetLevel = 2;
            else if (actionId === "h3") targetLevel = 3;
            else if (actionId === "h4") targetLevel = 4;
            else if (actionId === "h5") targetLevel = 5;
            else if (actionId === "h6") targetLevel = 6;

            var curItem = (idx !== -1) ? blocksModel.get(idx) : null;
            // F22: aplicar/alternar encabezado sobre ítems de lista (rango seleccionado).
            if (curItem && curItem.type === "list") {
                var lParsedB = LP.parseList(curItem.raw || "");
                if (lParsedB && lParsedB.length > 0) {
                    var bFrom = 0;
                    var bTo = lParsedB.length - 1;
                    var bLoader = _getDelegateItemForBid(root.activeBlockBid);
                    if (bLoader && bLoader.item && typeof bLoader.item.selectedItemRange === "function") {
                        try {
                            var bRg = bLoader.item.selectedItemRange();
                            if (bRg && typeof bRg.from === "number" && typeof bRg.to === "number") {
                                bFrom = Math.max(0, Math.min(bRg.from, bRg.to));
                                bTo = Math.min(lParsedB.length - 1, Math.max(bRg.from, bRg.to));
                            }
                        } catch (e) {}
                    } else if (bLoader && bLoader.item && typeof bLoader.item.activeItemIndex === "number") {
                        var bAi = bLoader.item.activeItemIndex;
                        if (bAi >= 0 && bAi < lParsedB.length) { bFrom = bAi; bTo = bAi; }
                    }
                    var bAll = LP.allItemsMatchHeading(lParsedB, bFrom, bTo, targetLevel);
                    var bPfx = "#".repeat(targetLevel) + " ";
                    for (var bi = bFrom; bi <= bTo; bi++) {
                        var bCur = lParsedB[bi].text || "";
                        var bStrip = LP.stripHeadingPrefix(bCur);
                        lParsedB[bi].text = bAll ? bStrip : (bPfx + bStrip);
                    }
                    var bRaw = LP.serializeList(lParsedB);
                    blocksModel.setProperty(idx, "raw", bRaw);
                    root.onBlockRawChanged(root.activeBlockBid, bRaw);
                    var bLdr = _getDelegateItemForBid(root.activeBlockBid);
                    if (bLdr && bLdr.item && typeof bLdr.item._reloadFromRaw === "function") {
                        bLdr.item._reloadFromRaw();
                    }
                    root.safeFocusDelegate(root.activeBlockBid, 0);
                    _saveSnapshot();
                    root.updateFormatState();
                    return;
                }
            }
            var clean = (curItem ? (curItem.raw || "") : _getPlainText(textEdit)).replace(/^[ \t]*#{1,6}[ \t]*/, "");
            var isSameHeading = (curItem && curItem.type === "heading" && curItem.raw && curItem.raw.startsWith("#".repeat(targetLevel) + " "));

            if (isSameHeading) {
                // Alternar: quitar encabezado y volver a párrafo
                if (idx !== -1) {
                    blocksModel.setProperty(idx, "type", "paragraph");
                    blocksModel.setProperty(idx, "raw", clean);
                }
                root.onBlockRawChanged(root.activeBlockBid, clean);
                root.safeFocusDelegate(root.activeBlockBid, 0);
            } else {
                var prefix = "#".repeat(targetLevel) + " ";
                var newRaw = prefix + clean;
                if (idx !== -1) {
                    blocksModel.setProperty(idx, "type", "heading");
                    blocksModel.setProperty(idx, "raw", newRaw);
                }
                root.onBlockRawChanged(root.activeBlockBid, newRaw);
                root.safeFocusDelegate(root.activeBlockBid, 0);
            }
            _saveSnapshot();
            root.updateFormatState();
        } else if (actionId === "bullet_list" || actionId === "ordered_list" || actionId === "task_list") {
            var curItem = (idx !== -1) ? blocksModel.get(idx) : null;
            if (!curItem) return;

            if (curItem.type === "list") {
                var curParsed = LP.parseList(curItem.raw || "");
                var isTaskNow = curParsed.length > 0 && curParsed.every(function(it) { return it.isTask; });
                var isBulletNow = curParsed.length > 0 && curParsed.every(function(it) { return !it.isTask && (it.marker === "-" || it.marker === "*" || it.marker === "+"); });
                var isOrderedNow = curParsed.length > 0 && curParsed.every(function(it) { return !it.isTask && (it.marker.indexOf(".") !== -1 || it.marker.indexOf(")") !== -1); });

                var isSame = (actionId === "task_list" && isTaskNow) ||
                             (actionId === "bullet_list" && isBulletNow) ||
                             (actionId === "ordered_list" && isOrderedNow);

                if (isSame) {
                    // TOGGLE OFF: Quitar lista y convertir a párrafo
                    var unlisted = curParsed.map(function(it) { return it.text; }).join("\n");
                    blocksModel.setProperty(idx, "type", "paragraph");
                    blocksModel.setProperty(idx, "raw", unlisted);
                    root.onBlockRawChanged(curItem.bid, unlisted);
                    root.safeFocusDelegate(curItem.bid, 0);
                } else {
                    // Cambiar tipo de lista (ej: de viñeta a checklist, o viceversa)
                    for (var li = 0; li < curParsed.length; li++) {
                        if (actionId === "task_list") {
                            curParsed[li].isTask = true;
                            curParsed[li].marker = "-";
                        } else if (actionId === "bullet_list") {
                            curParsed[li].isTask = false;
                            curParsed[li].marker = "-";
                        } else if (actionId === "ordered_list") {
                            curParsed[li].isTask = false;
                            curParsed[li].marker = (li + 1) + ".";
                        }
                    }
                    var newSerialized = LP.serializeList(curParsed);
                    blocksModel.setProperty(idx, "raw", newSerialized);
                    root.onBlockRawChanged(curItem.bid, newSerialized);
                    var ldr = _getDelegateItemForBid(curItem.bid);
                    if (ldr && ldr.item && typeof ldr.item._reloadFromRaw === "function") {
                        ldr.item._reloadFromRaw();
                    }
                    root.safeFocusDelegate(curItem.bid, 0);
                }
            } else {
                // Convertir párrafo / otro bloque a lista
                var baseText = _getPlainText(textEdit);
                if (!baseText && curItem.raw) baseText = curItem.raw;
                var rawLines = baseText.split("\n").map(function(l) {
                    return l.replace(/^(\s*[-*+]\s*(\[[ xX]\])?\s*|\s*\d+[\.\)]\s*|\s*>[ \t]?|\s*#{1,6}[ \t]+)/, "");
                });
                var listLines = rawLines.map(function(l, i) {
                    if (actionId === "task_list") return "- [ ] " + l;
                    if (actionId === "bullet_list") return "- " + l;
                    if (actionId === "ordered_list") return (i + 1) + ". " + l;
                    return l;
                });
                var newRawList = listLines.join("\n");
                blocksModel.setProperty(idx, "type", "list");
                blocksModel.setProperty(idx, "raw", newRawList);
                root.onBlockRawChanged(curItem.bid, newRawList);
                root.safeFocusDelegate(curItem.bid, 0);
            }
            _saveSnapshot();
            root.updateFormatState();
        } else if (actionId === "quote") {
            var curItem = (idx !== -1) ? blocksModel.get(idx) : null;
            if (curItem && curItem.type === "quote") {
                // TOGGLE OFF
                var unquoted = (curItem.raw || "").replace(/^[ \t]*>[ \t]?/gm, "");
                blocksModel.setProperty(idx, "type", "paragraph");
                blocksModel.setProperty(idx, "raw", unquoted);
                root.onBlockRawChanged(curItem.bid, unquoted);
                root.safeFocusDelegate(curItem.bid, 0);
            } else {
                var text = (curItem && curItem.raw) ? curItem.raw : _getPlainText(textEdit);
                var clean = text.replace(/^[ \t]*>[ \t]?/gm, "");
                var newRaw = "> " + clean;
                if (idx !== -1) {
                    blocksModel.setProperty(idx, "type", "quote");
                    blocksModel.setProperty(idx, "raw", newRaw);
                }
                root.onBlockRawChanged(root.activeBlockBid, newRaw);
                root.safeFocusDelegate(root.activeBlockBid, 0);
            }
            _saveSnapshot();
            root.updateFormatState();
        } else if (actionId === "code_block") {
            var curItem = (idx !== -1) ? blocksModel.get(idx) : null;
            if (curItem && (curItem.type === "code" || curItem.type === "mermaid")) {
                // Desenvolver bloque de código/mermaid a párrafo
                var codeLines = (curItem.raw || "").split("\n");
                if (codeLines.length >= 2 && /^[ \t]*(`{3,}|~{3,})/.test(codeLines[0])) {
                    codeLines.shift();
                    if (codeLines.length > 0 && /^[ \t]*(`{3,}|~{3,})[ \t]*$/.test(codeLines[codeLines.length - 1])) {
                        codeLines.pop();
                    }
                }
                var unwrapped = codeLines.join("\n");
                blocksModel.setProperty(idx, "type", "paragraph");
                blocksModel.setProperty(idx, "raw", unwrapped);
                root.onBlockRawChanged(curItem.bid, unwrapped);
                _saveSnapshot();
                root.safeFocusDelegate(curItem.bid, 0);
            } else if (curItem) {
                // Envolver bloque activo en bloque de código
                var plain = "";
                if (curItem.type === "paragraph") {
                    plain = textEdit ? _getPlainText(textEdit) : (curItem.raw || "");
                } else if (curItem.type === "heading") {
                    plain = (curItem.raw || "").replace(/^[ \t]*#{1,6}[ \t]*/, "");
                } else if (curItem.type === "quote") {
                    plain = (curItem.raw || "").replace(/^[ \t]*>[ \t]?/gm, "");
                } else if (curItem.type === "list") {
                    var listItems = LP.parseList(curItem.raw || "");
                    if (listItems && listItems.length > 0) {
                        plain = listItems.map(function(it) { return it.text; }).join("\n");
                    } else {
                        plain = curItem.raw || "";
                    }
                } else {
                    plain = curItem.raw || "";
                }
                var codeRaw = plain.trim() === "" ? "```\n\n```" : "```\n" + plain + "\n```";
                blocksModel.setProperty(idx, "type", "code");
                blocksModel.setProperty(idx, "raw", codeRaw);
                root.onBlockRawChanged(curItem.bid, codeRaw);
                _saveSnapshot();
                root.safeFocusDelegate(curItem.bid, 4);
            } else {
                // Insertar nuevo bloque de código
                var codeBid = BlockModel.getNextBid();
                var newCodeBlock = { bid: codeBid, type: "code", raw: "```\n\n```", sep: "\n\n" };
                blocksModel.append(newCodeBlock);
                root.activeBlockBid = codeBid;
                _saveSnapshot();
                root.safeFocusDelegate(codeBid, 4);
            }
            root.updateFormatState();
        } else if (actionId === "mermaid" || (typeof actionId === "string" && actionId.startsWith("mermaid:"))) {
            root.confirmActiveBlock();
            var mermaidTpl = "```mermaid\nflowchart TD\n    A[Inicio] --> B[Fin]\n```";
            if (typeof actionId === "string" && actionId.startsWith("mermaid:")) {
                var tplKey = actionId.substring(8);
                mermaidTpl = MermaidTemplates.getTemplate(tplKey);
            }
            var mBid = BlockModel.getNextBid();
            var insertPos = (idx !== -1) ? idx + 1 : blocksModel.count;
            blocksModel.insert(insertPos, { bid: mBid, type: "mermaid", raw: mermaidTpl, sep: "\n\n" });
            root.activeBlockBid = mBid;
            root.safeFocusDelegate(mBid, 0);
            _saveSnapshot();
            root.updateFormatState();
        } else if (actionId === "math") {
            root.confirmActiveBlock();
            var mathTpl = "$$\n\\frac{a}{b}\n$$";
            var mathBid = BlockModel.getNextBid();
            var insertPos = (idx !== -1) ? idx + 1 : blocksModel.count;
            blocksModel.insert(insertPos, { bid: mathBid, type: "math", raw: mathTpl, sep: "\n\n" });
            root.activeBlockBid = mathBid;
            root.safeFocusDelegate(mathBid, 0);
            _saveSnapshot();
            root.updateFormatState();
        } else if (actionId === "hr") {
            root.confirmActiveBlock();
            var curIdx = _findBlockIndex(root.activeBlockBid);
            var insertPos = (curIdx !== -1) ? curIdx + 1 : blocksModel.count;
            var hrBid = BlockModel.getNextBid();
            blocksModel.insert(insertPos, { bid: hrBid, type: "hr", raw: "---", sep: "\n\n" });
            if (insertPos === blocksModel.count - 1) {
                var nextP = { bid: BlockModel.getNextBid(), type: "paragraph", raw: "", sep: "\n\n" };
                blocksModel.append(nextP);
                root.activeBlockBid = nextP.bid;
                root.safeFocusDelegate(nextP.bid, 0);
            }
            _saveSnapshot();
            root.updateFormatState();
        } else if (actionId === "table") {
            root.confirmActiveBlock();
            var tblBid = BlockModel.getNextBid();
            var col1 = I18n.t("notes.table_col1", "Columna 1");
            var col2 = I18n.t("notes.table_col2", "Columna 2");
            var tblTpl = "| " + col1 + " | " + col2 + " |\n| :--- | :--- |\n|  |  |\n|  |  |";
            var insertPos = (idx !== -1) ? idx + 1 : blocksModel.count;
            blocksModel.insert(insertPos, { bid: tblBid, type: "table", raw: tblTpl, sep: "\n\n" });
            root.activeBlockBid = tblBid;
            root.safeFocusDelegate(tblBid, 0);
            _saveSnapshot();
            root.updateFormatState();
        } else if (actionId === "link") {
            if (textEdit) {
                var selText = textEdit.selectedText;
                var isUrl = /^https?:\/\//i.test(selText);
                var linkPlaceholder = I18n.t("notes.editor.link_text", "texto");
                if (isUrl) {
                    var sPos = textEdit.selectionStart;
                    var ePos = textEdit.selectionEnd;
                    textEdit.remove(sPos, ePos);
                    textEdit.insert(sPos, "[" + linkPlaceholder + "](" + selText + ")");
                    textEdit.select(sPos + 1, sPos + 1 + linkPlaceholder.length);
                } else if (selText) {
                    var sPos2 = textEdit.selectionStart;
                    var ePos2 = textEdit.selectionEnd;
                    textEdit.remove(sPos2, ePos2);
                    textEdit.insert(sPos2, "[" + selText + "](url)");
                    textEdit.select(sPos2 + selText.length + 3, sPos2 + selText.length + 6);
                } else {
                    var cPos = textEdit.cursorPosition;
                    textEdit.insert(cPos, "[" + linkPlaceholder + "](url)");
                    textEdit.select(cPos + 1, cPos + 1 + linkPlaceholder.length);
                }
                var updatedRaw = _getPlainText(textEdit);
                root._commitInlineFormattedSubEdit(root.activeBlockBid, textEdit, updatedRaw, textEdit.selectionStart, textEdit.selectionEnd);
            }
            root.updateFormatState();
        }
    }

    function isFormatActive(actionId) {
        if (root.readOnly) return false;
        var _ = root.formatStateSeq;

        // Caso A: Múltiples bloques seleccionados
        if (root.hasBlockSelection) {
            var bids = Object.keys(root.selectedBids || {});
            if (bids.length > 0) {
                if (actionId === "h1" || actionId === "h2" || actionId === "h3" ||
                    actionId === "bullet_list" || actionId === "ordered_list" || actionId === "task_list" ||
                    actionId === "quote" || actionId === "code_block" || actionId === "table") {
                    var allMatch = true;
                    for (var i = 0; i < bids.length; i++) {
                        var bidNum = parseInt(bids[i], 10);
                        var bIdx = _findBlockIndex(bidNum);
                        if (bIdx === -1) { allMatch = false; break; }
                        var bItem = blocksModel.get(bIdx);
                        if (!bItem) { allMatch = false; break; }
                        // F22: h1/h2/h3 también valen dentro de ítems de lista (y líneas de cita).
                        if (actionId === "h1" || actionId === "h2" || actionId === "h3") {
                            var wantLvl = (actionId === "h1") ? 1 : (actionId === "h2" ? 2 : 3);
                            var wantPfx = (wantLvl === 1) ? "# " : (wantLvl === 2 ? "## " : "### ");
                            if (bItem.type === "heading") {
                                if (!((bItem.raw || "").startsWith(wantPfx))) { allMatch = false; break; }
                            } else if (bItem.type === "list") {
                                var hItems = LP.parseList(bItem.raw || "");
                                if (!hItems || hItems.length === 0 || !LP.allItemsMatchHeading(hItems, 0, hItems.length - 1, wantLvl)) { allMatch = false; break; }
                            } else if (bItem.type === "quote") {
                                var qLines = (bItem.raw || "").split("\n");
                                var nonEmpty = 0;
                                var qOk = true;
                                for (var ql = 0; ql < qLines.length; ql++) {
                                    var qc = qLines[ql].replace(/^[ \t]*>[ \t]?/, "");
                                    if (qc.trim() === "") continue;
                                    nonEmpty++;
                                    if (LP.headingLevelOf(qc) !== wantLvl) { qOk = false; break; }
                                }
                                if (nonEmpty === 0 || !qOk) { allMatch = false; break; }
                            } else { allMatch = false; break; }
                            continue;
                        }
                        if (actionId === "quote" && bItem.type !== "quote") { allMatch = false; break; }
                        if (actionId === "code_block" && bItem.type !== "code") { allMatch = false; break; }
                        if (actionId === "mermaid" && bItem.type !== "mermaid") { allMatch = false; break; }
                        if (actionId === "math" && bItem.type !== "math") { allMatch = false; break; }
                        if (actionId === "table" && bItem.type !== "table") { allMatch = false; break; }
                        if (actionId === "task_list") {
                            if (bItem.type !== "list") { allMatch = false; break; }
                            var items1 = LP.parseList(bItem.raw || "");
                            if (!items1 || items1.length === 0 || !items1.every(function(it) { return it.isTask; })) { allMatch = false; break; }
                        }
                        if (actionId === "bullet_list") {
                            if (bItem.type !== "list") { allMatch = false; break; }
                            var items2 = LP.parseList(bItem.raw || "");
                            if (!items2 || items2.length === 0 || !items2.every(function(it) { return !it.isTask && (it.marker === "-" || it.marker === "*" || it.marker === "+"); })) { allMatch = false; break; }
                        }
                        if (actionId === "ordered_list") {
                            if (bItem.type !== "list") { allMatch = false; break; }
                            var items3 = LP.parseList(bItem.raw || "");
                            if (!items3 || items3.length === 0 || !items3.every(function(it) { return !it.isTask && (it.marker.indexOf(".") !== -1 || it.marker.indexOf(")") !== -1); })) { allMatch = false; break; }
                        }
                    }
                    return allMatch;
                }

                // Inline format sobre bloques seleccionados
                var selTxt = getSelectedText();
                if (selTxt) {
                    var detSel = Inline.detectFormats(selTxt);
                    return !!detSel[actionId];
                }
            }
            return false;
        }

        // Caso B: Bloque activo individual
        if (root.activeBlockBid !== -1) {
            var idx = _findBlockIndex(root.activeBlockBid);
            if (idx === -1) return false;
            var b = blocksModel.get(idx);
            if (!b) return false;

            // F22: h1/h2/h3 valen para encabezados sueltos Y para ítems de lista
            // (bullet_list y h2 pueden estar activos a la vez; no son excluyentes).
            if (actionId === "h1" || actionId === "h2" || actionId === "h3") {
                var wantLvlB = (actionId === "h1") ? 1 : (actionId === "h2" ? 2 : 3);
                if (b.type === "heading") {
                    var wantPfxB = (wantLvlB === 1) ? "# " : (wantLvlB === 2 ? "## " : "### ");
                    return (b.raw || "").startsWith(wantPfxB);
                }
                if (b.type === "list") {
                    var hItemsB = LP.parseList(b.raw || "");
                    if (!hItemsB || hItemsB.length === 0) return false;
                    var loaderH = _getDelegateItemForBid(root.activeBlockBid);
                    var rFrom = 0;
                    var rTo = hItemsB.length - 1;
                    if (loaderH && loaderH.item && typeof loaderH.item.selectedItemRange === "function") {
                        try {
                            var rg = loaderH.item.selectedItemRange();
                            if (rg && typeof rg.from === "number" && typeof rg.to === "number") {
                                rFrom = Math.max(0, Math.min(rg.from, rg.to));
                                rTo = Math.min(hItemsB.length - 1, Math.max(rg.from, rg.to));
                            }
                        } catch (e) {}
                    } else if (loaderH && loaderH.item && typeof loaderH.item.activeItemIndex === "number") {
                        var ai = loaderH.item.activeItemIndex;
                        if (ai >= 0 && ai < hItemsB.length) { rFrom = ai; rTo = ai; }
                    }
                    return LP.allItemsMatchHeading(hItemsB, rFrom, rTo, wantLvlB);
                }
                if (b.type === "quote") {
                    var qbLines = (b.raw || "").split("\n");
                    var qbCount = 0;
                    for (var qb = 0; qb < qbLines.length; qb++) {
                        var qbClean = qbLines[qb].replace(/^[ \t]*>[ \t]?/, "");
                        if (qbClean.trim() === "") continue;
                        qbCount++;
                        if (LP.headingLevelOf(qbClean) !== wantLvlB) return false;
                    }
                    return qbCount > 0;
                }
                return false;
            }
            if (actionId === "quote") return b.type === "quote";
            if (actionId === "code_block") return b.type === "code";
            if (actionId === "mermaid") return b.type === "mermaid";
            if (actionId === "math") return b.type === "math";
            if (actionId === "table") return b.type === "table";

            if (actionId === "task_list" || actionId === "bullet_list" || actionId === "ordered_list") {
                if (b.type !== "list") return false;
                var listItems = LP.parseList(b.raw || "");
                if (!listItems || listItems.length === 0) return false;
                var loader = _getDelegateItemForBid(root.activeBlockBid);
                var itemIdx = (loader && loader.item && typeof loader.item.activeItemIndex === "number") ? loader.item.activeItemIndex : 0;
                var curListItem = (itemIdx >= 0 && itemIdx < listItems.length) ? listItems[itemIdx] : listItems[0];
                if (actionId === "task_list") return !!curListItem.isTask;
                if (actionId === "bullet_list") return !curListItem.isTask && (curListItem.marker === "-" || curListItem.marker === "*" || curListItem.marker === "+");
                if (actionId === "ordered_list") return !curListItem.isTask && (curListItem.marker.indexOf(".") !== -1 || curListItem.marker.indexOf(")") !== -1);
                return false;
            }

            var te = _getTextEditForBid(root.activeBlockBid);
            if (te) {
                var rawText = Inline.plainText(te);
                var s = te.selectionStart;
                var e = te.selectionEnd;
                var cur = te.cursorPosition;
                var det = Inline.detectFormats(rawText, s, e, cur);
                return !!det[actionId];
            }
        }

        return false;
    }

    function insertImageBlock(src, alt) {
        var prevBid = root.activeBlockBid;
        root.confirmActiveBlock();

        var imgBid = BlockModel.getNextBid();
        var raw = "![" + (alt || "imagen") + "](" + src + ")";
        var curIdx = _findBlockIndex(prevBid);

        // Si el bloque donde estaba el cursor era un párrafo vacío, reemplazarlo directamente
        if (curIdx !== -1 && curIdx < blocksModel.count) {
            var curBlock = blocksModel.get(curIdx);
            if (curBlock && curBlock.type === "paragraph" && (curBlock.raw || "").trim() === "") {
                blocksModel.setProperty(curIdx, "bid", imgBid);
                blocksModel.setProperty(curIdx, "type", "image");
                blocksModel.setProperty(curIdx, "raw", raw);
                root.contentModified();
                _saveSnapshot();
                return;
            }
        }

        var insertIdx = (curIdx !== -1) ? (curIdx + 1) : blocksModel.count;
        blocksModel.insert(insertIdx, {
            bid: imgBid,
            type: "image",
            raw: raw,
            sep: "\n\n"
        });
        root.contentModified();
        _saveSnapshot();
    }

    function undo() {
        if (typingSnapshotTimer.running || debouncedMarkdownTimer.running) {
            root._saveSnapshot();
        }
        typingSnapshotTimer.stop();
        if (History.canUndo(root.docHistory)) {
            var prevSnapshot = History.undo(root.docHistory);
            if (prevSnapshot !== null) {
                root._applySnapshot(prevSnapshot);
            }
        }
    }

    function redo() {
        typingSnapshotTimer.stop();
        if (History.canRedo(root.docHistory)) {
            var nextSnapshot = History.redo(root.docHistory);
            if (nextSnapshot !== null) {
                root._applySnapshot(nextSnapshot);
            }
        }
    }

    function handleLink(link) {
        if (!link) return;
        if (link.startsWith("http://") || link.startsWith("https://") || link.startsWith("mailto:") || link.startsWith("file://")) {
            Quickshell.execDetached(["xdg-open", link]);
            return;
        }

        if (link.startsWith("./") || link.startsWith("../") || /\.(pdf|png|jpe?g|webp|gif|svg|txt|md)$/i.test(link)) {
            var baseDir = (NotesService.activeNote && NotesService.activeNote.baseFolder) ? NotesService.activeNote.baseFolder : NotesService.notesDir;
            var resolvedFile = link.startsWith("/") ? link : (baseDir + "/" + link);
            Quickshell.execDetached(["xdg-open", resolvedFile]);
            return;
        }

        var curSlug = NotesService.activeNote ? (NotesService.activeNote.slug || NotesService.activeNote.id || "") : "";
        var parsed = Anchors.parseInternalLink(link, curSlug);
        if (!parsed) return;

        if (parsed.isSameNote) {
            if (parsed.anchor) scrollToAnchor(parsed.anchor);
            return;
        }

        if (parsed.slug) {
            var targetNote = NotesService.getNote(parsed.slug);
            if (targetNote) {
                NotesService.openNoteBySlug(parsed.slug);
                if (parsed.anchor) {
                    Qt.callLater(() => {
                        scrollToAnchor(parsed.anchor);
                    });
                }
            } else {
                console.warn("[BlockEditor] Nota no encontrada para enlace:", link, "slug:", parsed.slug);
                if (root.editorModal && typeof root.editorModal.showToast === "function") {
                    var targetSlug = parsed.slug;
                    root.editorModal.showToast(
                        I18n.t("notes.link.not_found", "Nota no encontrada: ") + targetSlug,
                        I18n.t("notes.create", "Crear"),
                        function() {
                            NotesService.createNote("text", targetSlug);
                        }
                    );
                }
            }
        }
    }

    function scrollToBid(bid) {
        if (bid === -1 || bid === undefined) return;
        var del = _getDelegateItemForBid(bid);
        if (!del) return;

        var targetY = blocksColumn.y + del.y;
        var maxScroll = Math.max(0, contentHeight - height);
        var clampedY = Math.max(0, Math.min(targetY - 10, maxScroll));

        if (scrollAnim && scrollAnim.running) {
            scrollAnim.stop();
        }

        if (Theme.animationsEnabled && !GamemodeService.gamemodeActive) {
            scrollAnim.to = clampedY;
            scrollAnim.duration = Math.min(520, Math.max(220, 180 + Math.abs(contentY - clampedY) * 0.25));
            scrollAnim.restart();
        } else {
            contentY = clampedY;
            if (blocksModel.count > 35) {
                root._recalcChunkWindow();
            }
        }
    }

    function scrollToAnchor(id) {
        if (!id) return;
        var rawList = [];
        for (var i = 0; i < blocksModel.count; i++) rawList.push(blocksModel.get(i));
        var idx = Anchors.buildAnchorIndex(rawList);
        var target = idx[id.toLowerCase()];
        if (!target) return;
        scrollToBid(target.bid);
    }

    NumberAnimation {
        id: scrollAnim
        target: root
        property: "contentY"
        easing.type: Easing.InOutCubic
        onFinished: {
            if (blocksModel.count > 35) {
                root._recalcChunkWindow();
            }
        }
    }

    function focusEnd() {
        if (blocksModel.count === 0) {
            var newB = { bid: BlockModel.getNextBid(), type: "paragraph", raw: "", sep: "\n\n" };
            blocksModel.append(newB);
            root.activeBlockBid = newB.bid;
            root.safeFocusDelegate(newB.bid, 0);
        } else {
            var last = blocksModel.get(blocksModel.count - 1);
            root.requestEditBlock(last.bid);
        }
    }

    function _findBlockIndex(bid) {
        if (bid === undefined || bid === -1) return -1;
        for (var i = 0; i < blocksModel.count; i++) {
            var b = blocksModel.get(i);
            if (b && b.bid === bid) return i;
        }
        return -1;
    }

    function _saveSnapshot() {
        typingSnapshotTimer.stop();
        var cur = root.getMarkdown();
        var cursorPos = 0;
        var textEdit = _getTextEditForBid(root.activeBlockBid);
        if (textEdit) {
            cursorPos = textEdit.cursorPosition;
        }
        var activeIdx = _findBlockIndex(root.activeBlockBid);
        var subIdx = -1;
        var cRow = -1;
        var cCol = -1;
        var ldr = root._getDelegateItemForBid(root.activeBlockBid);
        var item = ldr ? ldr.item : null;
        if (item) {
            if (typeof item.activeItemIndex === "number") subIdx = item.activeItemIndex;
            if (typeof item.focusedRow === "number") cRow = item.focusedRow;
            if (typeof item.focusedCol === "number") cCol = item.focusedCol;
        }
        var state = {
            md: cur,
            activeBid: root.activeBlockBid,
            activeIndex: activeIdx,
            cursorPos: cursorPos,
            subIndex: subIdx,
            cellRow: cRow,
            cellCol: cCol,
            contentY: root.contentY
        };
        History.pushState(root.docHistory, state);
        root._internalChange = true;
        root.markdownEdited(cur);
        root._internalChange = false;
    }

    function _applySnapshot(snapshot) {
        if (!snapshot) return;
        typingSnapshotTimer.stop();
        var targetMd = (typeof snapshot === "object" && snapshot !== null) ? (snapshot.md || "") : snapshot;
        var res = BlockModel.splitBlocks(targetMd);
        root.documentLead = res.lead;

        var newBlocks = res.blocks;
        if (newBlocks.length === 0) {
            newBlocks.push({
                bid: BlockModel.getNextBid(),
                type: "paragraph",
                raw: "",
                sep: "\n\n"
            });
        }

        var commonLen = Math.min(blocksModel.count, newBlocks.length);
        for (var i = 0; i < commonLen; i++) {
            var cur = blocksModel.get(i);
            var nb = newBlocks[i];
            if (cur.type !== nb.type) blocksModel.setProperty(i, "type", nb.type);
            if (cur.raw !== nb.raw) blocksModel.setProperty(i, "raw", nb.raw);
            if (cur.sep !== nb.sep) blocksModel.setProperty(i, "sep", nb.sep);
            nb.bid = cur.bid;
        }

        if (blocksModel.count > newBlocks.length) {
            while (blocksModel.count > newBlocks.length) {
                blocksModel.remove(blocksModel.count - 1);
            }
        } else if (newBlocks.length > blocksModel.count) {
            for (var j = blocksModel.count; j < newBlocks.length; j++) {
                blocksModel.append(newBlocks[j]);
            }
        }

        if (typeof snapshot === "object" && snapshot !== null) {
            if (snapshot.contentY !== undefined) {
                root.contentY = snapshot.contentY;
            }
            var targetBid = -1;
            if (snapshot.activeIndex !== undefined && snapshot.activeIndex >= 0 && snapshot.activeIndex < blocksModel.count) {
                targetBid = blocksModel.get(snapshot.activeIndex).bid;
            } else if (snapshot.activeBid !== undefined && snapshot.activeBid !== -1) {
                var foundIdx = _findBlockIndex(snapshot.activeBid);
                if (foundIdx !== -1) {
                    targetBid = snapshot.activeBid;
                }
            }
            if (targetBid !== -1) {
                root.activeBlockBid = targetBid;
                root.safeFocusDelegate(targetBid, snapshot.cursorPos);
                if ((typeof snapshot.subIndex === "number" && snapshot.subIndex >= 0) ||
                    (typeof snapshot.cellRow === "number" && snapshot.cellRow >= -1)) {
                    Qt.callLater(() => {
                        var ldr2 = root._getDelegateItemForBid(targetBid);
                        var item2 = ldr2 ? ldr2.item : null;
                        if (item2) {
                            if (typeof snapshot.cellRow === "number" && typeof snapshot.cellCol === "number" && typeof item2.focusCell === "function" && snapshot.cellCol >= 0) {
                                item2.focusCell(snapshot.cellRow, snapshot.cellCol, snapshot.cursorPos);
                            } else if (typeof snapshot.subIndex === "number" && snapshot.subIndex >= 0 && typeof item2.focusItemAt === "function") {
                                item2.focusItemAt(snapshot.subIndex, snapshot.cursorPos);
                            }
                        }
                    });
                }
            } else {
                root.activeBlockBid = -1;
            }
        } else {
            root.activeBlockBid = -1;
        }

        root._internalChange = true;
        root.markdownEdited(targetMd);
        root._internalChange = false;
    }

    function _getDelegateItemForBid(bid) {
        var idx = _findBlockIndex(bid);
        if (idx !== -1 && idx < blocksRepeater.count) {
            return blocksRepeater.itemAt(idx);
        }
        return null;
    }

    function _focusDelegateForBid(bid, cursorPos) {
        var item = _getDelegateItemForBid(bid);
        if (item && item.item && typeof item.item.focusInput === "function") {
            item.item.focusInput(cursorPos);
        } else {
            Qt.callLater(() => {
                if (!root || typeof root._getDelegateItemForBid !== "function") return;
                var it2 = root._getDelegateItemForBid(bid);
                if (it2 && it2.item && typeof it2.item.focusInput === "function") {
                    it2.item.focusInput(cursorPos);
                }
            });
        }
    }

    // ── Renderizado en columna virtualizada por chunks ────────────────────────
    Column {
        id: blocksColumn
        readonly property real pageMaxWidth: EditorMetrics.pageWidth
        readonly property real naturalPageW: Math.min(root.width - 24, pageMaxWidth)
        readonly property real pageW: (root.freezeLayout && root._frozenColumnWidth > 0) ? root._frozenColumnWidth : naturalPageW
        width: pageW
        x: Math.round((root.width - pageW) / 2)
        y: 12
        spacing: 6

        Repeater {
            id: blocksRepeater
            model: blocksModel

            delegate: Loader {
                id: blockLoader
                width: blocksColumn.width

                readonly property var blockItemData: model
                readonly property bool blockIsEditing: root.activeBlockBid === model.bid
                readonly property bool isSelected: !!(root.selectedBids && root.selectedBids[model.bid] === true)
                readonly property bool isSearchTarget: root.activeMatchBid === model.bid

                // Intersección con la ventana visible por rango atómico (evita binding loops)
                readonly property bool inViewportChunk: (blocksModel.count <= 35) || (index >= root.visibleChunk.x && index <= root.visibleChunk.y)

                property bool _everActivated: false
                readonly property bool shouldBeActive: inViewportChunk ||
                                                       (blocksModel.count <= 150 && _everActivated) ||
                                                       (model.type === "image" && _everActivated) ||
                                                       blockIsEditing || isSelected || isSearchTarget

                active: shouldBeActive

                onActiveChanged: {
                    if (active && !_everActivated) {
                        _everActivated = true;
                    }
                }

                height: {
                    if (item && item.implicitHeight > 0) {
                        if (model.type === "image" && item.isLayoutReady === false) {
                            var cachedImg = root._measuredHeights ? root._measuredHeights[model.bid] : 0;
                            if (cachedImg && cachedImg > 0) return cachedImg;
                        }
                        return item.implicitHeight;
                    }
                    var cached = root._measuredHeights ? root._measuredHeights[model.bid] : 0;
                    if (cached && cached > 0) return cached;
                    return BlockModel.estimateBlockHeight(model.type, model.raw, blocksColumn.width);
                }

                property real _liveHeight: (item && item.implicitHeight > 0) ? item.implicitHeight : 0
                on_LiveHeightChanged: {
                    if (_liveHeight > 0 && root._measuredHeights) {
                        if (model.type === "image" && item && item.isLayoutReady === false) {
                            return;
                        }
                        root._measuredHeights[model.bid] = _liveHeight;
                    }
                }

                // Scroll Anchoring: Si la altura cambia en un bloque estrictamente superior al viewport,
                // compensar root.contentY para que los elementos en pantalla no salten ni se desplacen.
                property real _lastReportedHeight: 0
                Component.onCompleted: {
                    _lastReportedHeight = height;
                }
                onHeightChanged: {
                    if (_lastReportedHeight > 0 && height > 0) {
                        var delta = height - _lastReportedHeight;
                        if (delta !== 0) {
                            var blockTopInFlickable = blocksColumn.y + y;
                            if (blockTopInFlickable + _lastReportedHeight <= root.contentY) {
                                root.compensateScroll(delta);
                            }
                        }
                    }
                    _lastReportedHeight = height;
                }

                onLoaded: {
                    if (blockIsEditing && item && typeof item.focusInput === "function") {
                        item.focusInput();
                    }
                }

                sourceComponent: {
                    switch (model.type) {
                        case "heading": return headingComp;
                        case "paragraph": return paragraphComp;
                        case "list": return listComp;
                        case "table": return tableComp;
                        case "image": return imageComp;
                        case "quote": return quoteComp;
                        case "hr": return hrComp;
                        case "code": return codeComp;
                        case "mermaid": return mermaidComp;
                        case "math": return mathComp;
                        default: return rawComp;
                    }
                }

                Binding {
                    target: blockLoader.item
                    property: "blockData"
                    value: blockLoader.blockItemData
                    when: blockLoader.status === Loader.Ready
                }

                Binding {
                    target: blockLoader.item
                    property: "isEditing"
                    value: blockLoader.blockIsEditing
                    when: blockLoader.status === Loader.Ready
                }

                Binding {
                    target: blockLoader.item
                    property: "editor"
                    value: root
                    when: blockLoader.status === Loader.Ready
                }

                Binding {
                    target: blockLoader.item
                    property: "isSelected"
                    value: blockLoader.isSelected
                    when: blockLoader.status === Loader.Ready
                }

                Binding {
                    target: blockLoader.item
                    property: "inViewportChunk"
                    value: blockLoader.inViewportChunk
                    when: blockLoader.status === Loader.Ready
                    restoreMode: Binding.RestoreNone
                }
            }
        }
    }

    Component { id: paragraphComp; BlockParagraph {} }
    Component { id: headingComp; BlockHeading {} }
    Component { id: listComp; BlockList {} }
    Component { id: tableComp; BlockTable {} }
    Component { id: imageComp; BlockImage {} }
    Component { id: quoteComp; BlockQuote {} }
    Component { id: hrComp; BlockHr {} }
    Component { id: codeComp; BlockCode {} }
    Component { id: mermaidComp; BlockMermaid {} }
    Component { id: mathComp; BlockMath {} }
    Component { id: rawComp; BlockRaw {} }

    function _findBlockNearY(y) {
        if (blocksModel.count === 0) return -1;
        var relY = y - blocksColumn.y;
        var bestBid = -1;
        var minDiff = 999999;
        for (var i = 0; i < blocksRepeater.count; i++) {
            var loader = blocksRepeater.itemAt(i);
            if (loader) {
                var lTop = loader.y;
                var lBottom = loader.y + loader.height;
                if (relY >= lTop && relY <= lBottom) {
                    return blocksModel.get(i).bid;
                }
                var diff = Math.min(Math.abs(relY - lTop), Math.abs(relY - lBottom));
                if (diff < minDiff) {
                    minDiff = diff;
                    bestBid = blocksModel.get(i).bid;
                }
            }
        }
        return bestBid !== -1 ? bestBid : blocksModel.get(blocksModel.count - 1).bid;
    }

    function _focusFromEmptyArea(cx, cy) {
        if (blocksModel.count === 0) { root.focusEnd(); return; }

        var lastIdx = blocksModel.count - 1;
        var last = blocksModel.get(lastIdx);
        var lastLoader = blocksRepeater.itemAt(lastIdx);
        var belowLast = lastLoader && cy > (blocksColumn.y + lastLoader.y + lastLoader.height);

        if (belowLast) {
            // Click debajo de todo el contenido
            var needsNewParagraph = (last.type === "table" || last.type === "code" || last.type === "image"
                                  || last.type === "hr"    || last.type === "html" || last.type === "raw"
                                  || last.type === "mermaid" || last.type === "math");
            if (needsNewParagraph) root.insertParagraphAfter(last.bid);
            else root.requestEditBlock(last.bid);
            return;
        }

        // Click en un margen lateral o entre bloques: cursor en la línea más cercana del bloque más cercano
        var bid = root._findBlockNearY(cy);
        var idx = root._findBlockIndex(bid);
        var loader = (idx !== -1) ? blocksRepeater.itemAt(idx) : null;
        if (loader) {
            var bType = blocksModel.get(idx).type;
            if (bType === "list" || bType === "table" || bType === "image" || bType === "hr" || bType === "mermaid" || bType === "math") {
                root.requestEditBlock(bid);
            } else {
                var lx = Math.max(0, Math.min(loader.width - 1, cx - blocksColumn.x));
                var ly = Math.max(0, Math.min(loader.height - 1, cy - blocksColumn.y - loader.y));
                root.requestEditBlock(bid, { x: lx, y: ly });
            }
        } else {
            root.requestEditBlock(bid);
        }
    }

    // Activación y selección desde cualquier área vacía o márgenes del lienzo
    MouseArea {
        id: emptyAreaMa
        anchors.fill: parent
        z: -1
        cursorShape: Qt.IBeamCursor

        property bool selecting: false
        property real startY: 0
        property real lastMouseY: 0
        preventStealing: selecting

        onPressed: (mouse) => {
            root.clearBlockSelection();
            startY = mouse.y;
            lastMouseY = mouse.y;
            var anchor = root._findBlockAndCharNear(mouse.x, mouse.y);
            root.selAnchorBid = anchor.bid;
            root.selAnchorPos = anchor.pos;
            selecting = false;
        }

        onPositionChanged: (mouse) => {
            lastMouseY = mouse.y;
            if (!(mouse.buttons & Qt.LeftButton)) return;
            if (!selecting && Math.abs(mouse.y - startY) < 4) return;
            if (!selecting) {
                selecting = true;
                if (!root.readOnly) {
                    root.confirmActiveBlock();
                } else {
                    root.activeBlockBid = -1;
                }
                root.forceActiveFocus();
                root.interactive = false;
            }
            root.handleCrossBlockDrag(root.selAnchorBid, mouse.y, mouse.x);
        }

        onReleased: (mouse) => {
            root.interactive = true;
            if (!selecting) {
                if (!root.readOnly) {
                    root._focusFromEmptyArea(mouse.x, mouse.y);
                }
            } else {
                root.endCrossBlockDrag();
            }
            selecting = false;
        }

        onCanceled: {
            root.interactive = true;
            selecting = false;
        }

        Timer {
            id: selAutoScrollTimer
            interval: 16
            repeat: true
            running: emptyAreaMa.selecting
            onTriggered: {
                var viewTop = root.contentY;
                var viewBottom = root.contentY + root.height;
                if (emptyAreaMa.lastMouseY < viewTop + 30) {
                    root.contentY = Math.max(0, root.contentY - 14);
                    root.handleCrossBlockDrag(root.selAnchorBid, emptyAreaMa.lastMouseY, blocksColumn.x + blocksColumn.width / 2);
                } else if (emptyAreaMa.lastMouseY > viewBottom - 30) {
                    root.contentY = Math.min(Math.max(0, root.contentHeight - root.height), root.contentY + 14);
                    root.handleCrossBlockDrag(root.selAnchorBid, emptyAreaMa.lastMouseY, blocksColumn.x + blocksColumn.width / 2);
                }
            }
        }
    }
}
