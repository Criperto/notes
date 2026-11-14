import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Window
import Notas
import "."
import "ListParser.js" as LP
import "ListHeading.js" as LH
import "Inline.js" as Inline
import "ImageProbe.js" as ImageProbe
import "SpellLogic.js" as SpellLogic
import "ReferenceLogic.js" as ReferenceLogic

Item {
    id: root

    property var blockData: null
    property bool isEditing: false
    property var editor: null
    property bool isSelected: false
    property bool inViewportChunk: true
    readonly property bool spellActive: (root.editor && root.editor.spellActive !== undefined) ? root.editor.spellActive : false
    readonly property alias itemsRepeaterRef: itemsRepeater
    property bool _isDestroyed: false

    Component.onDestruction: {
        _isDestroyed = true;
        if (typeof SpellService !== "undefined") {
            SpellService.cancelOwner(root);
        }
    }

    // Tamaños de encabezado (mismos que BlockHeading) para ítems tipo "* ## título"
    readonly property var headingSizes: ({
        1: EditorMetrics.fs(Theme.fontSizeTitle + 8),
        2: EditorMetrics.fs(Theme.fontSizeTitle + 4),
        3: EditorMetrics.title,
        4: EditorMetrics.fs(Theme.fontSizeBody + 2),
        5: EditorMetrics.body,
        6: EditorMetrics.fs(Theme.fontSizeCaption + 1)
    })

    // Métricas de la primera línea del texto: las celdas de viñeta/número y
    // checkbox miden exactamente eso, con el glifo centrado.
    // Así el marcador queda alineado con la primera línea aunque el ítem crezca.
    readonly property int firstLineH: markerFm.height
    FontMetrics {
        id: markerFm
        font.family: Theme.fontFamily
        font.pixelSize: EditorMetrics.body
    }

    property int activeItemIndex: -1
    property bool _internalSync: false
    property bool _loadingModel: false
    property var _itemsRawArray: []

    implicitWidth: parent ? parent.width : 400
    implicitHeight: listCol.implicitHeight + 8

    ListModel {
        id: itemsModel
    }

    Timer {
        id: focusRetryTimer
        interval: 20
        repeat: false
        property var retryAction: null
        onTriggered: {
            if (retryAction && !root._isDestroyed) retryAction();
        }
    }

    function _reloadFromRaw() {
        if (!root.blockData || !root.blockData.raw) {
            root._itemsRawArray = [];
            itemsModel.clear();
            return;
        }
        root._loadingModel = true;
        var parsed = LP.parseList(root.blockData.raw);
        root._itemsRawArray = parsed;

        var common = Math.min(itemsModel.count, parsed.length);
        for (var i = 0; i < common; i++) {
            var p = parsed[i];
            var cur = itemsModel.get(i);
            var pIndent = p.indent || "";
            var pMarker = p.marker || "-";
            var pSpacing = p.spacing || " ";
            var pIsTask = !!p.isTask;
            var pChecked = !!p.checked;
            var pText = p.text || "";
            if (cur.indent !== pIndent) itemsModel.setProperty(i, "indent", pIndent);
            if (cur.marker !== pMarker) itemsModel.setProperty(i, "marker", pMarker);
            if (cur.spacingStr !== pSpacing) itemsModel.setProperty(i, "spacingStr", pSpacing);
            if (cur.isTask !== pIsTask) itemsModel.setProperty(i, "isTask", pIsTask);
            if (cur.checked !== pChecked) itemsModel.setProperty(i, "checked", pChecked);
            if (cur.text !== pText) itemsModel.setProperty(i, "text", pText);
        }

        if (itemsModel.count > parsed.length) {
            while (itemsModel.count > parsed.length) {
                itemsModel.remove(itemsModel.count - 1);
            }
        } else if (parsed.length > itemsModel.count) {
            for (var j = itemsModel.count; j < parsed.length; j++) {
                var pj = parsed[j];
                itemsModel.append({
                    indent: pj.indent || "",
                    marker: pj.marker || "-",
                    spacingStr: pj.spacing || " ",
                    isTask: !!pj.isTask,
                    checked: !!pj.checked,
                    text: pj.text || ""
                });
            }
        }
        root._loadingModel = false;
        Qt.callLater(function() {
            if (root && !root._isDestroyed && root.spellActive && (root.inViewportChunk || root.isEditing || root.isSelected) && typeof root.triggerAllSpellChecks === "function") {
                root.triggerAllSpellChecks();
            }
        });
    }

    function triggerAllSpellChecks() {
        if (!root.spellActive) return;
        for (var i = 0; i < itemsRepeater.count; i++) {
            var it = itemsRepeater.itemAt(i);
            if (it && typeof it.runSpellCheck === "function") {
                it.runSpellCheck();
            }
        }
    }

    onSpellActiveChanged: {
        if (spellActive && (root.inViewportChunk || root.isEditing || root.isSelected)) {
            root.triggerAllSpellChecks();
        } else if (!spellActive) {
            for (var i = 0; i < itemsRepeater.count; i++) {
                var it = itemsRepeater.itemAt(i);
                if (it) it.spellRanges = [];
            }
        }
    }

    onInViewportChunkChanged: {
        if (inViewportChunk && root.spellActive) {
            root.triggerAllSpellChecks();
        }
    }

    Connections {
        target: (typeof SpellService !== "undefined") ? SpellService : null
        function onCacheRevisionChanged() {
            if (root.spellActive && (root.inViewportChunk || root.isEditing || root.isSelected)) {
                root.triggerAllSpellChecks();
            }
        }
        function onAvailableChanged() {
            if (root.spellActive && SpellService.available && (root.inViewportChunk || root.isEditing || root.isSelected)) {
                root.triggerAllSpellChecks();
            }
        }
    }

    function syncAllLineEdits() {
        for (var i = 0; i < itemsRepeater.count; i++) {
            var it = itemsRepeater.itemAt(i);
            if (it && typeof it.syncText === "function") {
                it.syncText();
            }
        }
    }

    Connections {
        target: root.editor
        ignoreUnknownSignals: true
        function onSearchQueryChanged() {
            root.syncAllLineEdits();
        }
        function onActiveMatchBidChanged() {
            root.syncAllLineEdits();
        }
        function onActiveMatchUnitChanged() {
            root.syncAllLineEdits();
        }
        function onActiveMatchOrdinalChanged() {
            root.syncAllLineEdits();
        }
    }

    onBlockDataChanged: {
        if (!root._internalSync) {
            var curSerialized = LP.serializeList(root._itemsRawArray);
            if (root.blockData && root.blockData.raw === curSerialized) {
                return;
            }
            _reloadFromRaw();
        }
    }

    function hasAnyItemSelection() {
        for (var i = 0; i < itemsRepeater.count; i++) {
            var del = itemsRepeater.itemAt(i);
            if (del && typeof del.getTextEdit === "function") {
                var te = del.getTextEdit();
                if (te && te.selectionStart !== te.selectionEnd) return true;
            }
        }
        return false;
    }

    onIsEditingChanged: {
        if (!isEditing && !isSelected && !hasMultiItemSelection && !hasAnyItemSelection()) {
            _reloadFromRaw();
        }
    }

    onIsSelectedChanged: {
        if (!isSelected && !isEditing && !hasMultiItemSelection && !hasAnyItemSelection()) {
            root.clearTextSelection();
        }
    }

    Component.onCompleted: {
        _reloadFromRaw();
    }

    function _notifyRawChanged() {
        var raw = LP.serializeList(root._itemsRawArray);
        if (root.blockData && root.blockData.raw === raw) return;
        root._internalSync = true;
        if (root.blockData) {
            root.blockData.raw = raw;
        }
        if (root.editor && root.blockData) {
            root.editor.onBlockRawChanged(root.blockData.bid, raw);
        }
        root._internalSync = false;
    }

    function _renumberAllOrdered() {
        if (!root._itemsRawArray) return;
        var indentCounters = {};
        for (var i = 0; i < root._itemsRawArray.length; i++) {
            var it = root._itemsRawArray[i];
            if (!it) continue;
            var ind = it.indent || "";
            var indLen = ind.length;

            // Resetear contadores de cualquier nivel de sangría más profundo
            for (var k in indentCounters) {
                if (k.length > indLen) {
                    delete indentCounters[k];
                }
            }

            var isOrd = it.marker && (it.marker.indexOf(".") !== -1 || it.marker.indexOf(")") !== -1);
            if (isOrd) {
                var thisNum = parseInt(it.marker, 10);
                var prevNum = indentCounters[ind];
                var currentCount;
                if (prevNum === undefined) {
                    // Primer ítem del nivel: respetar el número inicial del usuario (ej. 9.)
                    currentCount = (!isNaN(thisNum) && thisNum > 0) ? thisNum : 1;
                } else if (thisNum === prevNum) {
                    // Colisión producida por inserción con Enter: desplazar siguiente ítem
                    currentCount = prevNum + 1;
                } else {
                    // Número explícito del usuario o secuencia consecutiva: preservar
                    currentCount = !isNaN(thisNum) ? thisNum : (prevNum + 1);
                }
                indentCounters[ind] = currentCount;
                var delim = it.marker.endsWith(")") ? ")" : ".";
                var newMarker = currentCount + delim;
                if (it.marker !== newMarker) {
                    it.marker = newMarker;
                    if (i < itemsModel.count) {
                        itemsModel.setProperty(i, "marker", newMarker);
                    }
                }
            }
        }
    }

    function _renumberOrderedList(startIdx) {
        _renumberAllOrdered();
    }

    function _setItemIndent(itemIdx, newIndent, textEditItem, targetCursorPos) {
        if (!root._itemsRawArray || itemIdx < 0 || itemIdx >= root._itemsRawArray.length) return false;
        var it = root._itemsRawArray[itemIdx];
        if ((it.indent || "") === newIndent) return false;

        var te = textEditItem || (itemIdx < itemsRepeater.count ? itemsRepeater.itemAt(itemIdx).getTextEdit() : null);
        var curPos = (typeof targetCursorPos === "number") ? targetCursorPos : (te ? te.cursorPosition : -1);
        var selS = te ? te.selectionStart : -1;
        var selE = te ? te.selectionEnd : -1;

        it.indent = newIndent;
        if (itemIdx < itemsModel.count) {
            itemsModel.setProperty(itemIdx, "indent", newIndent);
        }

        _renumberAllOrdered();
        _notifyRawChanged();

        if (te) {
            te.forceActiveFocus();
            if (selS !== -1 && selS !== selE) {
                te.select(selS, selE);
            } else if (curPos !== -1) {
                te.cursorPosition = Math.min(te.length, curPos);
            }
        }
        return true;
    }

    function handleItemTab(itemIdx, textEditItem) {
        if (!root._itemsRawArray || itemIdx < 0 || itemIdx >= root._itemsRawArray.length) return false;
        if (itemIdx === 0) return false;

        var prevIndent = root._itemsRawArray[itemIdx - 1].indent || "";
        var curIndent = root._itemsRawArray[itemIdx].indent || "";
        var maxIndentLen = prevIndent.length + 2;

        if (curIndent.length < maxIndentLen && curIndent.length < 6) {
            var newIndent = curIndent + "  ";
            return _setItemIndent(itemIdx, newIndent, textEditItem);
        }
        return false;
    }

    function handleItemBacktab(itemIdx, textEditItem) {
        if (!root._itemsRawArray || itemIdx < 0 || itemIdx >= root._itemsRawArray.length) return false;
        var curIndent = root._itemsRawArray[itemIdx].indent || "";
        if (curIndent.length >= 2) {
            var newIndent = curIndent.substring(2);
            return _setItemIndent(itemIdx, newIndent, textEditItem);
        } else if (curIndent.length === 0) {
            return root.handleItemBackspace(itemIdx, 0, root._itemsRawArray[itemIdx].text || "");
        }
        return false;
    }

    function _insertItem(idx, item) {
        root._loadingModel = true;
        root._itemsRawArray.splice(idx, 0, item);
        itemsModel.insert(idx, {
            indent: item.indent || "",
            marker: item.marker || "-",
            spacingStr: item.spacing || " ",
            isTask: !!item.isTask,
            checked: !!item.checked,
            text: item.text || ""
        });
        _renumberOrderedList(idx + 1);
        root._loadingModel = false;
        root._notifyRawChanged();
    }

    function _removeItem(idx) {
        root._loadingModel = true;
        root._itemsRawArray.splice(idx, 1);
        itemsModel.remove(idx);
        _renumberOrderedList(idx);
        root._loadingModel = false;
        root._notifyRawChanged();
    }

    function _focusItem(idx, pos) {
        if (idx < 0 || root._isDestroyed) return;
        var attempts = 0;
        var attemptFocus = function() {
            if (!root || root._isDestroyed) return;
            var itemDelegate = (idx < itemsRepeater.count) ? itemsRepeater.itemAt(idx) : null;
            if (!itemDelegate || typeof itemDelegate.focusInput !== "function") {
                attempts++;
                if (attempts < 25) {
                    if (attempts % 2 === 0) {
                        focusRetryTimer.retryAction = attemptFocus;
                        focusRetryTimer.restart();
                    } else {
                        Qt.callLater(attemptFocus);
                    }
                }
                return;
            }
            if (root.editor && root.blockData && root.editor.activeBlockBid !== root.blockData.bid) {
                root.editor.requestEditBlock(root.blockData.bid);
            }
            root.activeItemIndex = idx;
            itemDelegate.focusInput(pos);
        };
        attemptFocus();
    }

    // F21: cursorPos/fullTxt vienen del TextEdit en coords. DISPLAY (contenido sin
    // `## `). La partición conserva el encabezado en la primera parte; el ítem nuevo
    // nace SIN encabezado (evita marcadores `##` vacíos en cascada; el usuario lo
    // re-agrega escribiendo `## ` si lo quiere).
    function handleItemReturn(itemIdx, cursorPos, fullTxt) {
        if (!root._itemsRawArray || itemIdx < 0 || itemIdx >= root._itemsRawArray.length) return;
        var curItem = root._itemsRawArray[itemIdx];
        var editorRef = root.editor;
        var bidRef = root.blockData ? root.blockData.bid : -1;
        var dispTxt = (typeof fullTxt === "string") ? fullTxt : "";
        var dispPos = (typeof cursorPos === "number" && cursorPos >= 0) ? Math.min(cursorPos, dispTxt.length) : dispTxt.length;
        var curLevel = LH.splitHeading(curItem.text || "").level;

        if (dispTxt.trim() === "") {
            // Ítem anidado vacío: reducir un nivel de sangría antes de salir
            if (curItem.indent && curItem.indent.length >= 2) {
                root.handleItemBacktab(itemIdx, null);
                return;
            }
            // Ítem vacío nivel 0: salir de la lista y crear párrafo nuevo en esta posición
            if (editorRef && bidRef !== -1 && typeof editorRef.splitListBlock === "function") {
                var beforeRaw = LP.serializeList(root._itemsRawArray.slice(0, itemIdx));
                var afterRaw = LP.serializeList(root._itemsRawArray.slice(itemIdx + 1));
                editorRef.splitListBlock(bidRef, itemIdx, beforeRaw, afterRaw);
                return;
            }
            // Fallback: salir de la lista / eliminar ítem
            if (root._itemsRawArray.length <= 1) {
                if (editorRef && bidRef !== -1) {
                    editorRef.convertBlockType(bidRef, "paragraph", "");
                }
            } else {
                root._removeItem(itemIdx);
                if (itemIdx >= root._itemsRawArray.length) {
                    // Era el último ítem de la lista: crear nuevo párrafo a continuación
                    if (editorRef && bidRef !== -1) {
                        if (typeof editorRef.insertParagraphAfter === "function") {
                            editorRef.insertParagraphAfter(bidRef);
                        } else if (typeof editorRef.handleBlockEnter === "function") {
                            editorRef.handleBlockEnter(bidRef, 0);
                        }
                    }
                } else {
                    root._focusItem(itemIdx, 0);
                }
            }
            return;
        }

        // Si el cursor está al inicio del texto (cursorPos === 0 o solo espacios antes)
        // (coords. display: el prefijo `## ` no cuenta).
        if (dispPos === 0 || dispTxt.substring(0, dispPos).trim() === "") {
            // Enter con el cursor al inicio de un ítem con texto: insertar un ítem vacío ARRIBA y dejar el cursor en el ítem original
            var emptyAbove = {
                indent: curItem.indent,
                marker: curItem.marker,
                spacing: curItem.spacing || " ",
                isTask: curItem.isTask,
                checked: false,
                text: ""
            };
            root._insertItem(itemIdx, emptyAbove);
            root._focusItem(itemIdx + 1, 0);
            return;
        }

        // Dividir texto si Enter se presionó en el medio o al final (display).
        // La primera parte conserva el nivel; la nueva nace sin encabezado.
        var textBefore = LH.composeHeading(curLevel, dispTxt.substring(0, dispPos));
        var textAfter = dispTxt.substring(dispPos);

        curItem.text = textBefore;
        if (itemIdx < itemsModel.count) {
            itemsModel.setProperty(itemIdx, "text", textBefore);
        }

        var nextMarker = curItem.marker;
        var isOrdered = (nextMarker.indexOf(".") !== -1 || nextMarker.indexOf(")") !== -1);
        if (isOrdered) {
            var num = parseInt(nextMarker, 10);
            var delim = nextMarker.endsWith(")") ? ")" : ".";
            nextMarker = (!isNaN(num) ? (num + 1) : 1) + delim;
        }

        var newItem = {
            indent: curItem.indent,
            marker: nextMarker,
            spacing: curItem.spacing || " ",
            isTask: curItem.isTask,
            checked: false,
            text: textAfter
        };

        var insertIdx = itemIdx + 1;
        root._insertItem(insertIdx, newItem);
        root._focusItem(insertIdx, 0);
    }

    // F21: cursorPos/fullTxt en coords. DISPLAY. Con el cursor al inicio de un ítem
    // con encabezado, el primer Backspace QUITA el encabezado (`- ## texto` → `- texto`);
    // recién el siguiente hace lo de siempre (unir con el anterior).
    function handleItemBackspace(itemIdx, cursorPos, fullTxt) {
        if (!root._itemsRawArray || itemIdx < 0 || itemIdx >= root._itemsRawArray.length) return false;
        var editorRef = root.editor;
        var bidRef = root.blockData ? root.blockData.bid : -1;
        var dispTxt = (typeof fullTxt === "string") ? fullTxt : "";
        var dispPos = (typeof cursorPos === "number" && cursorPos >= 0) ? cursorPos : dispTxt.length;
        var atStart = (dispPos === 0 || dispTxt.substring(0, dispPos).trim() === "");

        if (dispPos === 0) {
            var curTaskItem = root._itemsRawArray[itemIdx];
            if (curTaskItem && curTaskItem.isTask) {
                curTaskItem.isTask = false;
                curTaskItem.checked = false;
                if (itemIdx < itemsModel.count) {
                    itemsModel.setProperty(itemIdx, "isTask", false);
                    itemsModel.setProperty(itemIdx, "checked", false);
                }
                root._notifyRawChanged();
                return true;
            }
            // F21: quitar encabezado antes de unir (el marcador no está en el TextEdit,
            // así que el usuario no puede borrarlo a mano: este Backspace lo hace).
            var curH = root._itemsRawArray[itemIdx];
            var curSplit = LH.splitHeading(curH ? (curH.text || "") : "");
            if (curSplit.level > 0) {
                curH.text = curSplit.content;
                if (itemIdx < itemsModel.count) {
                    itemsModel.setProperty(itemIdx, "text", curSplit.content);
                }
                root._notifyRawChanged();
                Qt.callLater(() => {
                    if (!root || root._isDestroyed) return;
                    root._focusItem(itemIdx, 0);
                });
                return true;
            }
        }

        if (atStart) {
            if (dispTxt.trim() === "") {
                if (root._itemsRawArray.length <= 1) {
                    if (editorRef && bidRef !== -1) {
                        editorRef.convertBlockType(bidRef, "paragraph", "");
                    }
                } else {
                    var prevIdx = Math.max(0, itemIdx - 1);
                    root._removeItem(itemIdx);
                    Qt.callLater(() => {
                        if (!root || root._isDestroyed) return;
                        root._focusItem(prevIdx, -1);
                    });
                }
                return true;
            } else if (itemIdx === 0) {
                var curIt = root._itemsRawArray[0];
                if (curIt.indent.length >= 2) {
                    root.handleItemBacktab(0, null);
                    return true;
                } else {
                    // Backspace al principio del primer ítem -> borrar viñeta y convertir a párrafo
                    // (display: el contenido ya viene sin `##`, así no se arrastra el prefijo).
                    root._itemsRawArray[0].text = dispTxt;
                    root._notifyRawChanged();
                    if (editorRef && bidRef !== -1 && typeof editorRef.unbulletListItem === "function") {
                        editorRef.unbulletListItem(bidRef, 0);
                        return true;
                    } else if (editorRef && bidRef !== -1) {
                        editorRef.convertBlockType(bidRef, "paragraph", dispTxt.trim());
                        return true;
                    }
                }
            } else if (itemIdx > 0) {
                var curIt = root._itemsRawArray[itemIdx];
                if (curIt.indent.length >= 2) {
                    root.handleItemBacktab(itemIdx, null);
                    return true;
                }
                // Unir con el anterior: el anterior conserva su encabezado (si lo tenía);
                // el actual aporta su CONTENIDO (su `##` inicial no va en el medio).
                // Foco en display: al final del contenido previo.
                var prevItem = root._itemsRawArray[itemIdx - 1];
                var prevSplit = LH.splitHeading(prevItem.text || "");
                var prevDispLen = (prevSplit.content || "").length;
                prevItem.text += dispTxt;
                if (itemIdx - 1 < itemsModel.count) {
                    itemsModel.setProperty(itemIdx - 1, "text", prevItem.text);
                }
                root._removeItem(itemIdx);
                Qt.callLater(() => {
                    if (!root || root._isDestroyed) return;
                    root._focusItem(itemIdx - 1, prevDispLen);
                });
                return true;
            }
        }
        return false;
    }

    function getRaw() {
        // Recolectar texto fresco de cada delegate activo
        for (var i = 0; i < itemsRepeater.count; i++) {
            var del = itemsRepeater.itemAt(i);
            if (del && typeof del.getCurrentText === "function") {
                root._itemsRawArray[i].text = del.getCurrentText();
            }
        }
        return LP.serializeList(root._itemsRawArray);
    }

    function getTextEdit() {
        if (root.activeItemIndex >= 0 && root.activeItemIndex < itemsRepeater.count) {
            var del = itemsRepeater.itemAt(root.activeItemIndex);
            if (del && typeof del.getTextEdit === "function") {
                return del.getTextEdit();
            }
        }
        if (itemsRepeater.count > 0) {
            var firstDel = itemsRepeater.itemAt(0);
            if (firstDel && typeof firstDel.getTextEdit === "function") {
                return firstDel.getTextEdit();
            }
        }
        return null;
    }

    function commitInlineSubEdit(textEdit, newPlain, selStart, selEnd) {
        if (root.activeItemIndex >= 0 && root.activeItemIndex < itemsModel.count) {
            itemsModel.setProperty(root.activeItemIndex, "text", newPlain);
            root._notifyRawChanged();
            if (textEdit && typeof selStart === "number" && typeof selEnd === "number") {
                textEdit.select(selStart, selEnd);
            }
        }
    }

    function focusInput(cursorPos) {
        if (root.editor && root.blockData && root.editor.activeBlockBid === root.blockData.bid) {
            root.isEditing = true;
        }
        var targetIdx = 0;
        var fromBot = (cursorPos === -1 || (typeof cursorPos === "object" && cursorPos !== null && (cursorPos.fromBottom === true || cursorPos.y > 1000)));
        if (fromBot && itemsRepeater.count > 0) {
            targetIdx = itemsRepeater.count - 1;
        } else if (typeof cursorPos === "object" && cursorPos !== null && (cursorPos.fromTop === true || cursorPos.y === 0)) {
            targetIdx = 0;
        } else if (root.activeItemIndex >= 0 && (itemsRepeater.count === 0 || root.activeItemIndex < itemsRepeater.count)) {
            targetIdx = root.activeItemIndex;
        }
        _focusItem(targetIdx, cursorPos);
    }

    // Confirma la coincidencia activa dentro del ítem indicado, con el cursor
    // justo al final del match. cursorPos viene en coords. RAW del bloque
    // (paintMd con base, como lo calcula la búsqueda F2, incluyendo `## `);
    // se convierte a DISPLAY antes de enfocar el TextEdit (F21).
    function focusSearchMatch(itemIndex, cursorPos) {
        if (itemIndex === undefined || itemIndex === null || itemIndex < 0 || itemIndex >= itemsRepeater.count) {
            root.focusInput(cursorPos);
            return;
        }
        root.activeItemIndex = itemIndex;
        var dispPos = cursorPos;
        try {
            var rawTxt = (root._itemsRawArray && root._itemsRawArray[itemIndex]) ? (root._itemsRawArray[itemIndex].text || "") : "";
            var lv = LH.splitHeading(rawTxt).level;
            if (lv > 0 && typeof cursorPos === "number") {
                var m = rawTxt.match(/^(#{1,6})[ \t]*/);
                var pLen = (m && m[1].length === lv) ? m[0].length : (lv + 1);
                dispPos = Math.max(0, cursorPos - pLen);
            }
        } catch (e) {}
        _focusItem(itemIndex, dispPos);
    }

    function selectRange(start, end) {
        var s = Math.min(start, end);
        var e = Math.max(start, end);
        var isForward = (start <= end);
        var offset = 0;
        for (var i = 0; i < itemsRepeater.count; i++) {
            var del = itemsRepeater.itemAt(i);
            if (!del) continue;
            var len = (typeof del.getTextLength === "function") ? del.getTextLength() : 0;
            var itemStart = offset;
            var itemEnd = offset + len;
            offset += len + 1;

            if (e <= itemStart || s >= itemEnd) {
                if (typeof del.clearTextSelection === "function") del.clearTextSelection();
            } else if (s <= itemStart && e >= itemEnd) {
                if (typeof del.selectAllText === "function") del.selectAllText();
            } else {
                var localS = Math.max(0, s - itemStart);
                var localE = Math.min(len, e - itemStart);
                if (typeof del.selectRange === "function") {
                    if (isForward) {
                        del.selectRange(localS, localE);
                    } else {
                        del.selectRange(localE, localS);
                    }
                }
            }
        }
        updateMultiItemSelectionState();
    }

    function selectAllText() {
        for (var i = 0; i < itemsRepeater.count; i++) {
            var del = itemsRepeater.itemAt(i);
            if (del && typeof del.selectAllText === "function") {
                del.selectAllText();
            }
        }
        updateMultiItemSelectionState();
    }

    function clearTextSelection(exceptItemIdx) {
        for (var i = 0; i < itemsRepeater.count; i++) {
            if (exceptItemIdx !== undefined && i === exceptItemIdx) continue;
            var del = itemsRepeater.itemAt(i);
            if (del && typeof del.clearTextSelection === "function") {
                del.clearTextSelection();
            }
        }
        updateMultiItemSelectionState();
    }

    function clearOtherItemsSelection(keepIndex) {
        clearTextSelection(keepIndex);
        updateMultiItemSelectionState();
    }

    property bool hasMultiItemSelection: false

    function hasMultipleItemsSelected() {
        var count = 0;
        for (var i = 0; i < itemsRepeater.count; i++) {
            var del = itemsRepeater.itemAt(i);
            if (!del) continue;
            var te = (typeof del.getTextEdit === "function") ? del.getTextEdit() : null;
            if (te && typeof te.selectionStart === "number" && typeof te.selectionEnd === "number" && te.selectionStart !== te.selectionEnd) {
                count++;
                if (count > 1) return true;
            }
        }
        return false;
    }

    function updateMultiItemSelectionState() {
        var multi = hasMultipleItemsSelected();
        if (hasMultiItemSelection !== multi) {
            hasMultiItemSelection = multi;
        }
        return multi;
    }

    function isItemSelectionStart(itemIdx) {
        var rg = selectedItemRange();
        if (rg.from === -1 || rg.to === -1 || rg.from === rg.to) return true;
        return itemIdx === rg.from;
    }

    function isItemSelectionEnd(itemIdx) {
        var rg = selectedItemRange();
        if (rg.from === -1 || rg.to === -1 || rg.from === rg.to) return true;
        return itemIdx === rg.to;
    }

    function deleteMultiItemSelection(replacementText) {
        var rg = selectedItemRange();
        if (rg.from === -1 || rg.to === -1) return;
        if (rg.from === rg.to) {
            var sDel = itemsRepeater.itemAt(rg.from);
            if (sDel) {
                var sTe = sDel.getTextEdit();
                if (sTe) {
                    var sS = sTe.selectionStart;
                    var sE = sTe.selectionEnd;
                    if (sS !== sE) sTe.remove(sS, sE);
                    if (replacementText) {
                        sTe.insert(sTe.cursorPosition, replacementText);
                    }
                }
            }
            return;
        }
        var firstDel = itemsRepeater.itemAt(rg.from);
        var lastDel = itemsRepeater.itemAt(rg.to);
        if (!firstDel || !lastDel) return;
        var firstTe = firstDel.getTextEdit();
        var lastTe = lastDel.getTextEdit();
        if (!firstTe || !lastTe) return;

        var prefixTxt = firstTe.getText(0, firstTe.selectionStart);
        var suffixTxt = lastTe.getText(lastTe.selectionEnd, lastTe.length);
        var inserted = (typeof replacementText === "string") ? replacementText : "";
        var mergedDisp = prefixTxt + inserted + suffixTxt;

        root._loadingModel = true;
        root._itemsRawArray[rg.from].text = firstDel.displayToRaw(mergedDisp);
        var removeCount = rg.to - rg.from;
        root._itemsRawArray.splice(rg.from + 1, removeCount);

        for (var r = 0; r < removeCount; r++) {
            itemsModel.remove(rg.from + 1);
        }
        itemsModel.setProperty(rg.from, "text", root._itemsRawArray[rg.from].text);

        _renumberAllOrdered();
        root._loadingModel = false;
        _notifyRawChanged();
        clearTextSelection();

        Qt.callLater(() => {
            if (!root || root._isDestroyed) return;
            root._focusItem(rg.from, prefixTxt.length + inserted.length);
        });
    }

    function extendItemSelectionDown(itemIdx) {
        if (itemIdx < 0 || itemIdx >= itemsRepeater.count - 1) return;
        var nextIdx = itemIdx + 1;
        var curDel = itemsRepeater.itemAt(itemIdx);
        var nextDel = itemsRepeater.itemAt(nextIdx);
        if (!curDel || !nextDel) return;
        var curTe = curDel.getTextEdit();
        var nextTe = nextDel.getTextEdit();
        if (!curTe || !nextTe) return;

        if (curTe.selectionStart === 0 && curTe.selectionEnd === curTe.length) {
            nextTe.select(0, Math.min(nextTe.length, 1));
            nextTe.forceActiveFocus();
        } else {
            var anchor = (curTe.selectionStart === curTe.cursorPosition) ? curTe.selectionEnd : curTe.selectionStart;
            curTe.select(anchor, curTe.length);
            nextTe.select(0, 0);
            nextTe.forceActiveFocus();
        }
        if (root.editor && typeof root.editor.updateFormatState === "function") root.editor.updateFormatState();
    }

    function extendItemSelectionUp(itemIdx) {
        if (itemIdx <= 0) return;
        var prevIdx = itemIdx - 1;
        var curDel = itemsRepeater.itemAt(itemIdx);
        var prevDel = itemsRepeater.itemAt(prevIdx);
        if (!curDel || !prevDel) return;
        var curTe = curDel.getTextEdit();
        var prevTe = prevDel.getTextEdit();
        if (!curTe || !prevTe) return;

        if (curTe.selectionStart === 0 && curTe.selectionEnd === curTe.length) {
            prevTe.select(Math.max(0, prevTe.length - 1), prevTe.length);
            prevTe.forceActiveFocus();
        } else {
            var anchor2 = (curTe.selectionStart === curTe.cursorPosition) ? curTe.selectionEnd : curTe.selectionStart;
            curTe.select(anchor2, 0);
            prevTe.select(prevTe.length, prevTe.length);
            prevTe.forceActiveFocus();
        }
        if (root.editor && typeof root.editor.updateFormatState === "function") root.editor.updateFormatState();
    }

    // F22: rango de ítems comprendidos por la selección intra-bloque.
    // Usa los TextEdit con selección no vacía; si no hay selección, el ítem activo.
    // Devuelve {from, to} inclusivos, clampados al modelo.
    function selectedItemRange() {
        var n = itemsRepeater.count;
        if (n === 0) return { from: 0, to: -1 };
        var lo = -1;
        var hi = -1;
        for (var i = 0; i < n; i++) {
            var del = itemsRepeater.itemAt(i);
            if (!del || typeof del.getTextEdit !== "function") continue;
            var te = null;
            try { te = del.getTextEdit(); } catch (e) { te = null; }
            if (te && typeof te.selectionStart === "number" && typeof te.selectionEnd === "number") {
                if (te.selectionStart !== te.selectionEnd) {
                    if (lo === -1) lo = i;
                    hi = i;
                }
            } else if (del.isSelected) {
                if (lo === -1) lo = i;
                hi = i;
            }
        }
        if (lo !== -1) return { from: lo, to: hi };
        var active = (typeof root.activeItemIndex === "number") ? root.activeItemIndex : 0;
        if (active < 0 || active >= n) active = 0;
        return { from: active, to: active };
    }

    function getItemStartOffset(itemIdx) {
        var offset = 0;
        for (var i = 0; i < itemIdx && i < itemsRepeater.count; i++) {
            var del = itemsRepeater.itemAt(i);
            if (del) {
                var len = (typeof del.getTextLength === "function") ? del.getTextLength() : 0;
                offset += len + 1;
            }
        }
        return offset;
    }

    function getCharPosAt(lx, ly) {
        var n = itemsRepeater.count;
        if (n === 0) return 0;

        var firstDel = itemsRepeater.itemAt(0);
        if (firstDel && ly < firstDel.y) {
            return 0;
        }

        var offset = 0;
        for (var i = 0; i < n; i++) {
            var del = itemsRepeater.itemAt(i);
            if (!del) continue;
            var len = (typeof del.getTextLength === "function") ? del.getTextLength() : 0;
            var itemTop = del.y;
            var itemBottom = del.y + del.height;

            if (ly >= itemTop && ly <= itemBottom) {
                var localPos = (typeof del.getCharPosAt === "function") ? del.getCharPosAt(lx, ly - itemTop) : 0;
                return offset + localPos;
            }

            if (i === n - 1) {
                if (ly > itemBottom) {
                    return offset + len;
                }
            } else {
                var nextDel = itemsRepeater.itemAt(i + 1);
                if (nextDel) {
                    var nextTop = nextDel.y;
                    if (ly > itemBottom && ly < nextTop) {
                        var midY = (itemBottom + nextTop) / 2;
                        if (ly < midY) {
                            return offset + len;
                        } else {
                            return offset + len + 1;
                        }
                    }
                }
            }

            offset += len + 1;
        }

        return offset > 0 ? (offset - 1) : 0;
    }

    function getTextLength() {
        var total = 0;
        for (var i = 0; i < itemsRepeater.count; i++) {
            var del = itemsRepeater.itemAt(i);
            if (!del) continue;
            var len = (typeof del.getTextLength === "function") ? del.getTextLength() : 0;
            total += len + (i < itemsRepeater.count - 1 ? 1 : 0);
        }
        return total;
    }

    function getSelectedText() {
        var parts = [];
        for (var i = 0; i < itemsRepeater.count; i++) {
            var del = itemsRepeater.itemAt(i);
            if (del && typeof del.getSelectedText === "function") {
                var st = del.getSelectedText();
                if (st !== "") parts.push(st);
            }
        }
        return parts.join("\n");
    }

    function getTextContent() {
        var parts = [];
        for (var i = 0; i < itemsRepeater.count; i++) {
            var del = itemsRepeater.itemAt(i);
            if (del && typeof del.getCurrentText === "function") {
                parts.push(del.getCurrentText());
            }
        }
        return parts.join("\n");
    }

    function deleteSelectedText() {
        if (hasMultiItemSelection) {
            deleteMultiItemSelection();
            return;
        }
        for (var i = 0; i < itemsRepeater.count; i++) {
            var del = itemsRepeater.itemAt(i);
            if (del && typeof del.deleteSelectedText === "function") {
                del.deleteSelectedText();
            }
        }
        _notifyRawChanged();
    }

    // Columna de ítems: renderizado y edición in-situ
    Column {
        id: listCol
        width: parent.width
        spacing: 6

        Repeater {
            id: itemsRepeater
            model: itemsModel

            delegate: RowLayout {
                id: itemRow
                width: listCol.width
                spacing: 8

                readonly property var rootBlock: root

                required property int index
                required property string indent
                required property string marker
                required property var spacingStr
                required property bool isTask
                required property bool checked
                required property string text

                property var spellRanges: []
                property bool _isDestroyed: false

                Timer {
                    id: itemSpellCheckTimer
                    interval: 350
                    repeat: false
                    onTriggered: itemRow.runSpellCheck()
                }

                Component.onDestruction: {
                    itemRow._isDestroyed = true;
                    itemSpellCheckTimer.stop();
                    if (typeof SpellService !== "undefined") {
                        SpellService.cancelOwner(itemRow);
                    }
                }

                Component.onCompleted: {
                    var r = itemRow.rootBlock || (typeof root !== "undefined" ? root : null);
                    if (r && r.spellActive && (r.inViewportChunk || r.isEditing || r.isSelected)) {
                        itemSpellCheckTimer.restart();
                    }
                }

                onTextChanged: {
                    itemRow.syncText();
                    var r = itemRow.rootBlock || (typeof root !== "undefined" ? root : null);
                    if (r && r.spellActive && (r.inViewportChunk || r.isEditing || r.isSelected)) {
                        itemSpellCheckTimer.restart();
                    }
                }

                onSpellRangesChanged: {
                    itemRow.syncText();
                    if (spellOverlay) spellOverlay.requestUpdate();
                }

                function runSpellCheck() {
                    var r = itemRow.rootBlock || (typeof root !== "undefined" ? root : null);
                    if (!r || !r.spellActive || !r.inViewportChunk || typeof SpellService === "undefined" || !SpellService.available) {
                        if (itemRow.spellRanges && itemRow.spellRanges.length > 0) itemRow.spellRanges = [];
                        return;
                    }
                    var rawText = (r.isEditing && lineEdit && lineEdit.length > 0) ? Inline.plainText(lineEdit) : LH.splitHeading(itemRow.text || "").content;
                    if (!rawText || rawText.trim() === "") {
                        if (itemRow.spellRanges && itemRow.spellRanges.length > 0) itemRow.spellRanges = [];
                        return;
                    }
                    var tokens = SpellLogic.tokenize(rawText, {
                        ignoreUppercase: (typeof SpellConfig !== "undefined") ? SpellConfig.ignoreUppercase : true,
                        ignoreWithDigits: (typeof SpellConfig !== "undefined") ? SpellConfig.ignoreWithDigits : true,
                        ignoreCamelCase: (typeof SpellConfig !== "undefined") ? SpellConfig.ignoreCamelCase : true,
                        ignoreSnakeCase: (typeof SpellConfig !== "undefined") ? SpellConfig.ignoreSnakeCase : true
                    });
                    if (tokens.length === 0) {
                        if (itemRow.spellRanges && itemRow.spellRanges.length > 0) itemRow.spellRanges = [];
                        return;
                    }
                    var words = tokens.map(function(t) { return t.word; });
                    SpellService.checkWordsBatch(words, function(results) {
                        if (root._isDestroyed || itemRow._isDestroyed) return;
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
                        itemRow.spellRanges = badRanges;
                        if (spellOverlay) spellOverlay.requestUpdate();
                    }, itemRow, { text: rawText });
                }

                function _openContextMenuAt(targetItem, clickPos, fromKeyboard) {
                    var r = itemRow.rootBlock || (typeof root !== "undefined" ? root : null);
                    if (!r || !r.editor || !r.editor.contextMenu) return;
                    var pos = (clickPos !== undefined && clickPos >= 0) ? clickPos : (lineEdit ? lineEdit.cursorPosition : -1);
                    var err = (r.spellActive && (!r.editor || !r.editor.readOnly)) ? SpellLogic.findRangeAt(itemRow.spellRanges, pos) : null;
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
                                            itemRow._replaceWordAtRange(err, formattedSug);
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
                    if (fromKeyboard && typeof r.editor.contextMenu.toggleAtTextCursor === "function") {
                        r.editor.contextMenu.toggleAtTextCursor(targetItem, extras);
                    } else if (fromKeyboard && typeof r.editor.contextMenu.openAtTextCursor === "function") {
                        r.editor.contextMenu.openAtTextCursor(targetItem, extras);
                    } else {
                        r.editor.contextMenu.open(targetItem, extras);
                    }
                }

                function _replaceWordAtRange(range, replacement) {
                    if (!range || !replacement || !lineEdit) return;
                    var r = itemRow.rootBlock || (typeof root !== "undefined" ? root : null);
                    if (r && !r.isEditing && r.editor && r.blockData) {
                        r.editor.requestEditBlock(r.blockData.bid);
                    }
                    if (r) {
                        r.clearOtherItemsSelection(itemRow.index);
                        if (r.editor && r.blockData && typeof r.editor.clearSelectionExcept === "function") {
                            r.editor.clearSelectionExcept(r.blockData.bid, itemRow.index);
                        }
                    }
                    var maxLen = lineEdit.length;
                    var s = Math.max(0, Math.min(range.start, maxLen));
                    var e = Math.max(s, Math.min(range.end, maxLen));
                    lineEdit.forceActiveFocus();
                    lineEdit.select(s, e);
                    lineEdit.remove(s, e);
                    lineEdit.insert(s, replacement);
                    var endPos = s + replacement.length;
                    var selectWordAction = function() {
                        if (itemRow._isDestroyed || (r && r._isDestroyed) || !lineEdit) return;
                        var curLen = lineEdit.length;
                        var clampedEnd = Math.max(0, Math.min(endPos, curLen));
                        var clampedStart = Math.max(0, Math.min(s, clampedEnd));
                        lineEdit.forceActiveFocus();
                        lineEdit.cursorPosition = clampedEnd;
                        lineEdit.select(clampedStart, clampedEnd);
                        if (r && r.editor && r.blockData && typeof r.editor.notifySingleInputSelection === "function") {
                            r.editor.notifySingleInputSelection(r.blockData.bid, itemRow.index);
                        }
                        if (r && r.editor && typeof r.editor.updateFormatState === "function") {
                            r.editor.updateFormatState();
                        }
                    };
                    selectWordAction();
                    Qt.callLater(selectWordAction);
                    itemSpellCheckTimer.restart();
                }

                function focusInput(pos) {
                    var r = itemRow.rootBlock || (typeof root !== "undefined" ? root : null);
                    if (!r) return;
                    if (!r.isEditing && r.editor && r.blockData && r.editor.activeBlockBid !== r.blockData.bid) {
                        r.editor.requestEditBlock(r.blockData.bid, pos);
                    }
                    var applyFocus = () => {
                        if (itemRow._isDestroyed || (r && r._isDestroyed) || !lineEdit) return;
                        lineEdit.forceActiveFocus();
                        if (lineEdit.selectionStart !== lineEdit.selectionEnd) return;
                        if (r && r.editor && (r.editor.isDraggingSelection || r.editor.hasBlockSelection || r.editor._syncingSelection)) return;
                        if (pos === -1) {
                            lineEdit.cursorPosition = lineEdit.length;
                        } else if (typeof pos === "object" && pos !== null && typeof pos.x === "number") {
                            if (pos.fromBottom === true || (typeof pos.y === "number" && pos.y > 1000)) {
                                var lastRect = lineEdit.positionToRectangle(lineEdit.length);
                                var targetY = lastRect.y + (lastRect.height > 0 ? lastRect.height / 2 : 10);
                                lineEdit.cursorPosition = lineEdit.positionAt(pos.x, targetY);
                            } else if (pos.fromTop === true) {
                                var firstRect = lineEdit.positionToRectangle(0);
                                var targetY0 = firstRect.y + (firstRect.height > 0 ? firstRect.height / 2 : 10);
                                lineEdit.cursorPosition = lineEdit.positionAt(pos.x, targetY0);
                            } else if (typeof pos.y === "number") {
                                lineEdit.cursorPosition = lineEdit.positionAt(pos.x, pos.y);
                            } else {
                                var firstRect2 = lineEdit.positionToRectangle(0);
                                var targetY02 = firstRect2.y + (firstRect2.height > 0 ? firstRect2.height / 2 : 10);
                                lineEdit.cursorPosition = lineEdit.positionAt(pos.x, targetY02);
                            }
                        } else if (typeof pos === "number" && pos >= 0) {
                            lineEdit.cursorPosition = Math.min(lineEdit.length, pos);
                        } else {
                            lineEdit.cursorPosition = lineEdit.length;
                        }
                    };
                    if (r && r.isEditing && lineEdit && lineEdit.visible) {
                        applyFocus();
                    }
                    Qt.callLater(applyFocus);
                }

                // F21: nivel de encabezado del ítem (0 = normal). El TextEdit edita solo
                // el contenido; el prefijo `## ` vive en itemRow.text (crudo).
                readonly property int headingLevel: LH.splitHeading(itemRow.text || "").level
                readonly property string headingContent: LH.splitHeading(itemRow.text || "").content
                function rawPrefixLen() {
                    var t = itemRow.text || "";
                    var lv = itemRow.headingLevel || 0;
                    if (lv <= 0) return 0;
                    var m = t.match(/^(#{1,6})[ \t]*/);
                    if (m && m[1].length === lv) return m[0].length;
                    return lv + 1;
                }
                // Display → crudo: re-antepone el nivel guardado, salvo que el usuario
                // haya escrito su propio prefijo `## ` (crear/cambiar/quitar encabezado).
                function displayToRaw(disp) {
                    var d = (typeof disp === "string") ? disp : "";
                    if (/^#{1,6}(\s|$)/.test(d)) return d;
                    var lv = itemRow.headingLevel || 0;
                    try {
                        var rb2 = itemRow.rootBlock;
                        if (rb2 && rb2._itemsRawArray && rb2._itemsRawArray[itemRow.index]) {
                            lv = LH.splitHeading(rb2._itemsRawArray[itemRow.index].text || "").level;
                        }
                    } catch (e2) {}
                    if (lv > 0) return LH.composeHeading(lv, d);
                    return d;
                }
                // Texto base desacoplado del cursor (evita binding loops en TextEdit.text)
                function baseDisplayText(raw) {
                    var sp = LH.splitHeading(raw || "");
                    var content = (root.editor && root.editor.readOnly) ? Inline.stripImages(sp.content) : sp.content;
                    var base = Inline.formatForLiveEditing(content, {
                        cursorPos: -1,
                        selStart: -1,
                        selEnd: -1,
                        dimColor: "" + Theme.muted,
                        linkColor: "" + Theme.accent,
                        hideSyntax: Boolean(root.editor && root.editor.readOnly)
                    });
                    if (sp.level > 0 && root.headingSizes && root.headingSizes[sp.level]) {
                        base = '<span style="font-size: ' + root.headingSizes[sp.level] + 'px;"><b>' + base + '</b></span>';
                    }
                    var q = root.editor ? root.editor.searchQuery : "";
                    if (q && q.trim() !== "") {
                        var hBg = root.editor ? ("" + root.editor.searchHighlightColor) : "";
                        var aBg = (root.editor && root.blockData && typeof root.editor.searchActiveBg === "function") ? root.editor.searchActiveBg(root.blockData.bid, itemRow.index) : "";
                        var ord = (root.editor && root.blockData && typeof root.editor.searchActiveOrdinal === "function") ? root.editor.searchActiveOrdinal(root.blockData.bid, itemRow.index) : -1;
                        var aFg = (root.editor && root.blockData && typeof root.editor.searchActiveFg === "function") ? root.editor.searchActiveFg(root.blockData.bid, itemRow.index) : "";
                        base = Inline.highlightInHtml(base, q, hBg, aBg, ord, aFg);
                    }
                    return base;
                }

                function syncText() {
                    if (!lineEdit) return;
                    if (root.isEditing && root.activeItemIndex === itemRow.index && lineEdit.activeFocus) {
                        return;
                    }
                    var rawT = (itemRow.index >= 0 && itemRow.index < root._itemsRawArray.length)
                        ? (root._itemsRawArray[itemRow.index].text || "")
                        : (itemRow.text || "");
                    var baseT = itemRow.baseDisplayText(rawT);
                    if (lineEdit.text !== baseT) {
                        var s = lineEdit.selectionStart;
                        var e = lineEdit.selectionEnd;
                        lineEdit._syncingLocal = true;
                        lineEdit._lastAppliedHtml = baseT;
                        lineEdit.text = baseT;
                        if (s !== e && lineEdit.length > 0) {
                            lineEdit.select(Math.min(lineEdit.length, s), Math.min(lineEdit.length, e));
                        }
                        lineEdit._syncingLocal = false;
                    }
                }
                // Texto vivo del editor: contenido sin `##`, con tamaño de encabezado.
                function liveDisplayText(raw) {
                    var sp = LH.splitHeading(raw || "");
                    var content = (root.editor && root.editor.readOnly) ? Inline.stripImages(sp.content) : sp.content;
                    var isItemActive = (root.isEditing && root.activeItemIndex === itemRow.index && lineEdit);
                    var curPos = isItemActive ? lineEdit.cursorPosition : -1;
                    var sStart = isItemActive ? lineEdit.selectionStart : -1;
                    var sEnd = isItemActive ? lineEdit.selectionEnd : -1;
                    var base = Inline.formatForLiveEditing(content, {
                        cursorPos: curPos,
                        selStart: sStart,
                        selEnd: sEnd,
                        dimColor: "" + Theme.muted,
                        linkColor: "" + Theme.accent,
                        hideSyntax: Boolean(root.editor && root.editor.readOnly)
                    });
                    if (sp.level > 0 && root.headingSizes && root.headingSizes[sp.level]) {
                        return '<span style="font-size: ' + root.headingSizes[sp.level] + 'px;"><b>' + base + '</b></span>';
                    }
                    return base;
                }
                // F21: solo el ítem activo revela el marcador, y solo con el cursor al
                // inicio sin selección o con el contenido vacío. Ningún otro lo muestra.
                readonly property bool markerReveal: {
                    if (!root.isEditing || itemRow.isSelected) return false;
                    if (root.activeItemIndex !== itemRow.index) return false;
                    if ((itemRow.headingLevel || 0) <= 0) return false;
                    if (!lineEdit) return false;
                    if (lineEdit.selectionStart !== lineEdit.selectionEnd) return false;
                    return lineEdit.cursorPosition === 0 || lineEdit.length === 0;
                }

                function getCurrentText() {
                    // F21: devuelve el CRUDO (con `## `). Si el contenido no cambió,
                    // se devuelve el almacenado intacto (round-trip byte a byte,
                    // preserva espaciados no canónicos mientras no se edite el ítem).
                    if (!lineEdit) return itemRow.text || "";
                    var disp = Inline.plainText(lineEdit);
                    try {
                        var rbG = itemRow.rootBlock;
                        var storedG = (rbG && rbG._itemsRawArray && rbG._itemsRawArray[itemRow.index]) ? rbG._itemsRawArray[itemRow.index].text : null;
                        if (typeof storedG === "string") {
                            if (LH.splitHeading(storedG).content === disp) return storedG;
                        }
                    } catch (eG) {}
                    return itemRow.displayToRaw(disp);
                }

                function getTextEdit() {
                    return lineEdit;
                }

                property bool isSelected: root.isSelected || root.hasMultiItemSelection || (lineEdit && lineEdit.selectionStart !== lineEdit.selectionEnd)

                // start/end en coords. RAW del bloque (con `## `) → display.
                function selectRange(start, end) {
                    if (!lineEdit) return;
                    var pLen = itemRow.rawPrefixLen();
                    var s = Math.max(0, Math.min(lineEdit.length, start - pLen));
                    var e = Math.max(0, Math.min(lineEdit.length, end - pLen));
                    lineEdit.select(s, e);
                }

                function selectAllText() {
                    if (lineEdit) lineEdit.selectAll();
                }

                function clearTextSelection() {
                    if (lineEdit) lineEdit.deselect();
                }

                function getCharPosAt(lx, ly) {
                    if (!lineEdit) return 0;
                    var pt = mapToItem(lineEdit, lx, ly);
                    return lineEdit.positionAt(pt.x, pt.y) + itemRow.rawPrefixLen();
                }

                function getTextLength() {
                    return (lineEdit ? lineEdit.length : 0) + itemRow.rawPrefixLen();
                }

                // Si la selección incluye el inicio lógico del ítem con encabezado,
                // copiar el Markdown CON el prefijo (F21).
                function getSelectedText() {
                    if (!lineEdit) return "";
                    var sel = lineEdit.selectedText;
                    if (sel === "") return "";
                    var lv = itemRow.headingLevel || 0;
                    if (lv > 0 && lineEdit.selectionStart === 0) {
                        if (/^#{1,6}(\s|$)/.test(sel)) return sel;
                        return new Array(lv + 1).join("#") + " " + sel;
                    }
                    return sel;
                }

                function deleteSelectedText() {
                    if (lineEdit && lineEdit.selectionStart !== lineEdit.selectionEnd) {
                        lineEdit.remove(lineEdit.selectionStart, lineEdit.selectionEnd);
                        if (index >= 0 && index < root._itemsRawArray.length) {
                            root._itemsRawArray[index].text = itemRow.displayToRaw(Inline.plainText(lineEdit));
                        }
                    }
                }

                // Sangría visual según espacios iniciales
                Item {
                    Layout.preferredWidth: Math.max(0, (itemRow.indent.length * 8))
                    Layout.fillHeight: true
                    visible: Layout.preferredWidth > 0
                }

                // Checkbox interactivo siempre visible si es tarea
                // (misma columna de 24 que viñetas; caja de primera línea)
                Item {
                    z: 10
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: root.firstLineH
                    Layout.alignment: Qt.AlignTop
                    visible: itemRow.isTask

                    Image {
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        source: Theme.iconsPath + (itemRow.checked ? "check-box.svg" : "check-box-outline-blank.svg")
                        sourceSize: Qt.size(18, 18)
                        smooth: true
                        mipmap: true
                        layer.enabled: visible && !GamemodeService.gamemodeActive
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: itemRow.checked ? Theme.accent : Theme.muted
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: (root.editor && root.editor.readOnly) ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: {
                            if (root.editor && root.editor.readOnly) return;
                            var newChecked = !itemRow.checked;
                            itemsModel.setProperty(itemRow.index, "checked", newChecked);
                            root._itemsRawArray[itemRow.index].checked = newChecked;
                            root._notifyRawChanged();
                        }
                    }
                }

                // Viñeta o número si no es tarea: caja de primera línea con el
                // glifo centrado
                Item {
                    Layout.preferredWidth: Math.max(24, Math.round(markerText.implicitWidth + 4))
                    Layout.preferredHeight: root.firstLineH
                    Layout.alignment: Qt.AlignTop
                    visible: !itemRow.isTask

                    Text {
                        id: markerText
                        anchors.centerIn: parent
                        text: itemRow.marker.indexOf(".") !== -1 || itemRow.marker.indexOf(")") !== -1 ? itemRow.marker : "•"
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: EditorMetrics.body
                        font.bold: true
                    }
                }

                // Imágenes del ítem: el <img> en RichText no escala y
                // desborda; se pintan como Image reales acotadas al ancho.
                readonly property var itemImages: Inline.extractImages(itemRow.text)
                readonly property string itemImgBase: (NotesService.activeNote && NotesService.activeNote.baseFolder) ? NotesService.activeNote.baseFolder : NotesService.notesDir

                Item {
                    Layout.fillWidth: true
                    implicitHeight: textCol.implicitHeight

                    Column {
                        id: textCol
                        width: parent.width
                        spacing: 6

                    // Vista renderizada cuando no se edita el bloque (con soporte completo de enlaces y RichText)
                    Text {
                        id: listViewText
                        visible: !root.isEditing && !itemRow.isSelected && (!root.spellActive || !itemRow.spellRanges || itemRow.spellRanges.length === 0 || lineEdit.length === 0)
                        width: parent.width
                        textFormat: Text.RichText
                        text: Inline.inlineToHtml(Inline.stripImages(itemRow.text), {
                            zoom: EditorMetrics.zoom,
                            textColor: "" + Theme.text,
                            mathColor: "" + Theme.text,
                            mathPtSize: Math.max(8.0, EditorMetrics.body * 0.75),
                            fontFamilyMonospace: Theme.fontFamilyMonospace || "JetBrains Mono",
                            headingSizes: root.headingSizes,
                            linkColor: "" + Theme.accent, highlightBg: EditorMetrics.highlightBg,
                            searchQuery: root.editor ? root.editor.searchQuery : "",
                            searchHighlightBg: root.editor ? ("" + root.editor.searchHighlightColor) : "",
                            searchHighlightActiveBg: (root.editor && root.blockData) ? root.editor.searchActiveBg(root.blockData.bid, itemRow.index) : "",
                            searchActiveOrdinal: (root.editor && root.blockData) ? root.editor.searchActiveOrdinal(root.blockData.bid, itemRow.index) : -1,
                            searchHighlightActiveFg: (root.editor && root.blockData) ? root.editor.searchActiveFg(root.blockData.bid, itemRow.index) : ""
                        })
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: EditorMetrics.body
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        lineHeight: EditorMetrics.lineHeight
                        opacity: (itemRow.isTask && itemRow.checked) ? 0.55 : 1.0
                        font.strikeout: (itemRow.isTask && itemRow.checked)

                        onLinkActivated: (link) => {
                            if (root.editor && typeof root.editor.handleLink === "function") {
                                root.editor.handleLink(link);
                            }
                        }

                        HoverHandler {
                            enabled: parent.hoveredLink !== ""
                            cursorShape: Qt.PointingHandCursor
                        }
                    }

                    // Editor de texto enriquecido in-situ para esta línea
                    // F21: edita SOLO el contenido (sin `## `). El tamaño de encabezado se
                    // mantiene siempre; el marcador es un Text separado (headingMarker) que
                    // solo revela el ítem activo con el cursor al inicio o vacío.
                    TextEdit {
                        id: lineEdit
                        property string _lastAppliedHtml: itemRow.baseDisplayText(itemRow.text)
                        persistentSelection: true
                        overwriteMode: root.editor ? root.editor.overwriteMode : false
                        visible: root.isEditing || itemRow.isSelected || (root.spellActive && itemRow.spellRanges && itemRow.spellRanges.length > 0 && lineEdit.length > 0) || (root.editor && root.blockData && root.editor.activeBlockBid === root.blockData.bid)
                        readOnly: !root.isEditing || (root.editor && root.editor.readOnly)
                        cursorVisible: activeFocus && root.isEditing && (!root.editor || !root.editor.readOnly)
                        width: parent.width
                        textFormat: TextEdit.RichText
                        text: {
                            var _sq = root.editor ? root.editor.searchQuery : "";
                            var _ab = root.editor ? root.editor.activeMatchBid : -1;
                            var _au = root.editor ? root.editor.activeMatchUnit : -1;
                            var _ao = root.editor ? root.editor.activeMatchOrdinal : -1;
                            return itemRow.baseDisplayText(itemRow.text);
                        }
                        onLinkActivated: (link) => {
                            if (root.editor && typeof root.editor.handleLink === "function") {
                                root.editor.handleLink(link);
                            }
                        }
                        leftPadding: itemRow.markerReveal ? (headingMarker.implicitWidth + 5) : 0
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: EditorMetrics.body
                    wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                    selectByMouse: true
                    CustomTextCursor {
                        multiSelectionMode: root.hasMultiItemSelection || (root.editor && root.editor.hasBlockSelection)
                        showStartBoundary: root.isItemSelectionStart(itemRow.index) && (!root.editor || !root.editor.hasBlockSelection || root.editor.isSelectionStartBlock(root.blockData ? root.blockData.bid : -1))
                        showEndBoundary: root.isItemSelectionEnd(itemRow.index) && (!root.editor || !root.editor.hasBlockSelection || root.editor.isSelectionEndBlock(root.blockData ? root.blockData.bid : -1))
                        externalHandleDragCallback: function(isStart, gx, gy) {
                            if (root.editor && typeof root.editor.handleTeardropDrag === "function") {
                                root.editor.handleTeardropDrag(isStart, gx, gy);
                            }
                        }
                    }
                    opacity: (itemRow.isTask && itemRow.checked) ? 0.55 : 1.0
                    font.strikeout: (itemRow.isTask && itemRow.checked)
                    activeFocusOnTab: false

                    onSelectionStartChanged: {
                        root.updateMultiItemSelectionState();
                        if (root.editor && !root.editor._syncingSelection && !root.editor.hasBlockSelection && !root.editor.isDraggingSelection && !root.hasMultiItemSelection && !root.hasMultipleItemsSelected()) {
                            if (lineEdit.selectionStart !== lineEdit.selectionEnd) {
                                root.clearOtherItemsSelection(itemRow.index);
                                if (root.blockData && typeof root.editor.notifySingleInputSelection === "function") {
                                    root.editor.notifySingleInputSelection(root.blockData.bid, itemRow.index);
                                }
                            }
                            if (typeof root.editor.updateFormatState === "function") root.editor.updateFormatState();
                        }
                        if (root.isEditing && !lineEdit._syncingLocal && root.activeItemIndex === itemRow.index) {
                            lineEdit._updateLiveFormatting();
                        }
                    }
                    onSelectionEndChanged: {
                        root.updateMultiItemSelectionState();
                        if (root.editor && !root.editor._syncingSelection && !root.editor.hasBlockSelection && !root.editor.isDraggingSelection && !root.hasMultiItemSelection && !root.hasMultipleItemsSelected()) {
                            if (lineEdit.selectionStart !== lineEdit.selectionEnd) {
                                root.clearOtherItemsSelection(itemRow.index);
                                if (root.blockData && typeof root.editor.notifySingleInputSelection === "function") {
                                    root.editor.notifySingleInputSelection(root.blockData.bid, itemRow.index);
                                }
                            }
                            if (typeof root.editor.updateFormatState === "function") root.editor.updateFormatState();
                        }
                        if (root.isEditing && !lineEdit._syncingLocal && root.activeItemIndex === itemRow.index) {
                            lineEdit._updateLiveFormatting();
                        }
                    }
                    onCursorPositionChanged: {
                        if (root.editor && !root.editor._syncingSelection && !root.editor.hasBlockSelection && !root.editor.isDraggingSelection && !root.hasMultiItemSelection && !root.hasMultipleItemsSelected()) {
                            if (lineEdit.activeFocus && lineEdit.selectionStart === lineEdit.selectionEnd) {
                                root.clearOtherItemsSelection(itemRow.index);
                                if (root.blockData && typeof root.editor.notifySingleInputSelection === "function") {
                                    root.editor.notifySingleInputSelection(root.blockData.bid, itemRow.index);
                                }
                            }
                            if (typeof root.editor.updateFormatState === "function") root.editor.updateFormatState();
                        }
                        root.updateMultiItemSelectionState();
                        if (root.isEditing && !lineEdit._syncingLocal && root.activeItemIndex === itemRow.index) {
                            lineEdit._updateLiveFormatting();
                        }
                    }

                    // F21: marcador `##` revelado (Text separado, fuera del TextEdit editable).
                    // Solo el ítem activo con cursor al inicio o vacío; fundido ≤100ms.
                    Text {
                        id: headingMarker
                        x: 1
                        y: 1
                        text: {
                            var lv = itemRow.headingLevel || 0;
                            if (lv <= 0) return "";
                            var h = "";
                            for (var i = 0; i < lv; i++) h += "#";
                            return h + " ";
                        }
                        color: "#888888"
                        font.family: Theme.fontFamily
                        font.pixelSize: {
                            var lv2 = itemRow.headingLevel || 0;
                            if (lv2 > 0 && root.headingSizes && root.headingSizes[lv2]) return root.headingSizes[lv2];
                            return EditorMetrics.body;
                        }
                        font.bold: true
                        opacity: itemRow.markerReveal ? 1.0 : 0.0
                        Behavior on opacity {
                            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                            NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
                        }
                    }

                    property bool _syncingLocal: false

                    onActiveFocusChanged: {
                        if (activeFocus) {
                            root.activeItemIndex = itemRow.index;
                            if (root.editor && root.blockData && root.editor.activeBlockBid !== root.blockData.bid) {
                                root.editor.requestEditBlock(root.blockData.bid);
                            }
                            lineEdit._updateLiveFormatting();
                        } else {
                            if (lineEdit.selectionStart !== lineEdit.selectionEnd || root.hasMultiItemSelection || (root.editor && (root.editor.hasBlockSelection || root.editor._syncingSelection || root.editor.isDraggingSelection))) {
                                return;
                            }
                            if (itemRow.index >= 0 && itemRow.index < root._itemsRawArray.length) {
                                var rawT = root._itemsRawArray[itemRow.index].text || "";
                                var baseT = itemRow.baseDisplayText(rawT);
                                if (lineEdit._lastAppliedHtml !== baseT && lineEdit.text !== baseT) {
                                    lineEdit._syncingLocal = true;
                                    lineEdit._lastAppliedHtml = baseT;
                                    lineEdit.text = baseT;
                                    lineEdit._syncingLocal = false;
                                }
                            }
                        }
                    }

                    onTextChanged: {
                        if (_syncingLocal || root._loadingModel || (root.editor && root.editor.readOnly)) return;
                        itemSpellCheckTimer.restart();
                        if (itemRow.index >= 0 && itemRow.index < root._itemsRawArray.length) {
                            // F21: el TextEdit trae CONTENIDO (display); se recompone el crudo.
                            var cleanText = Inline.plainText(lineEdit);
                            var storedLv = LH.splitHeading(root._itemsRawArray[itemRow.index].text || "").level;

                            var idxNow = itemRow.index;
                            var sh = LP.detectTaskShorthand(cleanText);
                            if (sh && idxNow >= 0 && idxNow < root._itemsRawArray.length && !root._itemsRawArray[idxNow].isTask) {
                                var it = root._itemsRawArray[idxNow];
                                it.isTask = true;
                                it.checked = sh.checked;
                                // F21: la tarea nueva conserva el encabezado (`- [ ] ## texto`).
                                it.text = (storedLv > 0 && !/^#{1,6}(\s|$)/.test(sh.rest)) ? LH.composeHeading(storedLv, sh.rest) : sh.rest;

                                if (idxNow < itemsModel.count) {
                                    itemsModel.setProperty(idxNow, "isTask", true);
                                    itemsModel.setProperty(idxNow, "checked", sh.checked);
                                    itemsModel.setProperty(idxNow, "text", it.text);
                                }

                                _syncingLocal = true;
                                lineEdit.text = itemRow.liveDisplayText(it.text);
                                lineEdit.cursorPosition = lineEdit.length;
                                _syncingLocal = false;
                                lineEdit.forceActiveFocus();

                                root._notifyRawChanged();
                                return;
                            }

                            // Atajo de cambio de numeración al escribir ej. "5. " o "10) " al inicio del ítem
                            var ordMatch = cleanText.match(/^(\d+[.)])[ \t]+([\s\S]*)$/);
                            if (ordMatch && idxNow >= 0 && idxNow < root._itemsRawArray.length) {
                                var itOrd = root._itemsRawArray[idxNow];
                                var newOrdMarker = ordMatch[1];
                                var restOrd = ordMatch[2];
                                if (itOrd.marker !== newOrdMarker) {
                                    itOrd.marker = newOrdMarker;
                                    itOrd.isTask = false;
                                    itOrd.checked = false;
                                    itOrd.text = (storedLv > 0 && !/^#{1,6}(\s|$)/.test(restOrd)) ? LH.composeHeading(storedLv, restOrd) : restOrd;

                                    if (idxNow < itemsModel.count) {
                                        itemsModel.setProperty(idxNow, "marker", newOrdMarker);
                                        itemsModel.setProperty(idxNow, "isTask", false);
                                        itemsModel.setProperty(idxNow, "checked", false);
                                        itemsModel.setProperty(idxNow, "text", itOrd.text);
                                    }

                                    _syncingLocal = true;
                                    lineEdit.text = itemRow.liveDisplayText(itOrd.text);
                                    lineEdit.cursorPosition = 0;
                                    _syncingLocal = false;
                                    lineEdit.forceActiveFocus();

                                    root._notifyRawChanged();
                                    return;
                                }
                            }

                            var newRaw = itemRow.displayToRaw(cleanText);
                            if (root._itemsRawArray[itemRow.index].text !== newRaw) {
                                root._itemsRawArray[itemRow.index].text = newRaw;
                                root._notifyRawChanged();
                            }
                            liveFormatTimer.restart();

                            if (!lineEdit.inputMethodComposing) {
                                var wTrigger = ReferenceLogic.detectWikilinkTrigger(cleanText, lineEdit.cursorPosition);
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
                                                lsm.open(lineEdit, wTrigger, "anchors", filteredH, wTrigger.noteTitle);
                                            }
                                        } else {
                                            var notesList = (typeof NotesService !== "undefined" && NotesService.notes) ? NotesService.notes : [];
                                            var filteredN = ReferenceLogic.filterNotes(notesList, wTrigger.query);
                                            if (lsm.isOpen) {
                                                lsm.update(wTrigger, "notes", filteredN, "");
                                            } else {
                                                lsm.open(lineEdit, wTrigger, "notes", filteredN, "");
                                            }
                                        }
                                    }
                                } else if (lsm && lsm.isOpen && lsm.targetInput === lineEdit) {
                                    lsm.close();
                                }
                            }
                        }
                    }

                    function _updateLiveFormatting() {
                        if (!root.isEditing || lineEdit._syncingLocal || root._loadingModel || root.activeItemIndex !== itemRow.index) return;
                        if (root.editor && (root.editor.readOnly || root.editor._syncingSelection || root.editor.isDraggingSelection || root.editor.hasBlockSelection)) return;
                        if (root.hasMultiItemSelection) return;
                        if (lineEdit.inputMethodComposing) return;
                        var dispRaw = Inline.plainText(lineEdit);
                        if (!dispRaw || !/[#*_~=`<\[]/.test(dispRaw)) return;
                        var newFormatted = itemRow.liveDisplayText(itemRow.displayToRaw(dispRaw));
                        if (lineEdit._lastAppliedHtml !== newFormatted) {
                            lineEdit._lastAppliedHtml = newFormatted;
                            var s = lineEdit.selectionStart;
                            var e = lineEdit.selectionEnd;
                            var curPos = lineEdit.cursorPosition;
                            lineEdit._syncingLocal = true;
                            lineEdit.text = newFormatted;
                            if (s !== e) {
                                lineEdit.select(Math.min(lineEdit.length, s), Math.min(lineEdit.length, e));
                            } else {
                                lineEdit.cursorPosition = Math.min(lineEdit.length, curPos);
                            }
                            lineEdit._syncingLocal = false;
                        }
                    }

                    // Re-aplica el formato en vivo sobre el CONTENIDO (display), manteniendo
                    // el tamaño de encabezado sin mostrar `##` (F21).
                    Timer {
                        id: liveFormatTimer
                        interval: 250
                        repeat: false
                        onTriggered: lineEdit._updateLiveFormatting()
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
                        if (event.modifiers & Qt.ControlModifier) {
                            if (model.isTask) {
                                itemsModel.setProperty(itemRow.index, "checked", !model.checked);
                                root._notifyRawChanged();
                                event.accepted = true;
                                return;
                            }
                        }
                        var pos = lineEdit.cursorPosition;
                        var fullTxt = Inline.plainText(lineEdit);
                        event.accepted = true;
                        root.handleItemReturn(itemRow.index, pos, fullTxt);
                    }

                    Keys.onEnterPressed: (event) => {
                        Keys.onReturnPressed(event);
                    }

                    Keys.onEscapePressed: (event) => {
                        var lsm = root.editor ? root.editor.linkSuggestionMenu : null;
                        if (lsm && lsm.isOpen) {
                            lsm.close();
                            event.accepted = true;
                            return;
                        }
                        if (root.editor) {
                            root.editor.confirmActiveBlock();
                            event.accepted = true;
                        }
                    }

                    Keys.onDeletePressed: (event) => {
                        if (root.editor && root.editor.readOnly) {
                            event.accepted = true;
                            return;
                        }
                        if (lineEdit.selectionStart !== lineEdit.selectionEnd) {
                            lineEdit.remove(lineEdit.selectionStart, lineEdit.selectionEnd);
                            event.accepted = true;
                            return;
                        }
                        if (lineEdit.cursorPosition === lineEdit.length) {
                            if (itemRow.index < itemsModel.count - 1) {
                                var nextItem = root._itemsRawArray[itemRow.index + 1];
                                var curItem = root._itemsRawArray[itemRow.index];
                                curItem.text = (curItem.text || "") + (nextItem.text || "");
                                itemsModel.setProperty(itemRow.index, "text", curItem.text);
                                root._removeItem(itemRow.index + 1);
                                root._notifyRawChanged();
                                event.accepted = true;
                                return;
                            } else if (itemRow.index === itemsModel.count - 1 && root.editor) {
                                if (typeof root.editor.handleBlockDeleteAtEnd === "function") {
                                    root.editor.handleBlockDeleteAtEnd(root.blockData.bid);
                                    event.accepted = true;
                                    return;
                                }
                            }
                        }
                        event.accepted = false;
                    }

                    Keys.onTabPressed: (event) => {
                        if (root.editor && root.editor.readOnly) {
                            event.accepted = true;
                            return;
                        }
                        root.handleItemTab(itemRow.index, lineEdit);
                        event.accepted = true;
                    }

                    Keys.onBacktabPressed: (event) => {
                        if (root.editor && root.editor.readOnly) {
                            event.accepted = true;
                            return;
                        }
                        root.handleItemBacktab(itemRow.index, lineEdit);
                        event.accepted = true;
                    }

                    Keys.onLeftPressed: (event) => {
                        var rEditor = itemRow.rootBlock ? itemRow.rootBlock.editor : (root.editor || null);
                        if (rEditor && typeof rEditor.resetPreferredCursorX === "function") {
                            rEditor.resetPreferredCursorX();
                        }
                        if (event.modifiers & Qt.ShiftModifier) {
                            event.accepted = false;
                            return;
                        }
                        if (lineEdit.cursorPosition === 0 && lineEdit.selectionStart === lineEdit.selectionEnd) {
                            if (itemRow.index > 0) {
                                root._focusItem(itemRow.index - 1, -1);
                                event.accepted = true;
                            } else if (itemRow.index === 0) {
                                if (root.editor && root.blockData) root.editor.focusPreviousBlock(root.blockData.bid);
                                event.accepted = true;
                            } else {
                                event.accepted = false;
                            }
                        } else {
                            event.accepted = false;
                        }
                    }

                    Keys.onRightPressed: (event) => {
                        var rEditor = itemRow.rootBlock ? itemRow.rootBlock.editor : (root.editor || null);
                        if (rEditor && typeof rEditor.resetPreferredCursorX === "function") {
                            rEditor.resetPreferredCursorX();
                        }
                        if (event.modifiers & Qt.ShiftModifier) {
                            event.accepted = false;
                            return;
                        }
                        if (lineEdit.cursorPosition === lineEdit.length && lineEdit.selectionStart === lineEdit.selectionEnd) {
                            if (itemRow.index < root._itemsRawArray.length - 1) {
                                root._focusItem(itemRow.index + 1, 0);
                                event.accepted = true;
                            } else if (itemRow.index === root._itemsRawArray.length - 1) {
                                if (root.editor && root.blockData) root.editor.focusNextBlock(root.blockData.bid);
                                event.accepted = true;
                            } else {
                                event.accepted = false;
                            }
                        } else {
                            event.accepted = false;
                        }
                    }

                    Keys.onPressed: (event) => {
                        var lsm = (itemRow.rootBlock && itemRow.rootBlock.editor) ? itemRow.rootBlock.editor.linkSuggestionMenu : (root.editor ? root.editor.linkSuggestionMenu : null);
                        if (lsm && lsm.isOpen) {
                            if (event.key === Qt.Key_Up) {
                                lsm.selectPreviousItem();
                                event.accepted = true;
                                return;
                            }
                            if (event.key === Qt.Key_Down) {
                                lsm.selectNextItem();
                                event.accepted = true;
                                return;
                            }
                            if (event.key === Qt.Key_Escape) {
                                lsm.close();
                                event.accepted = true;
                                return;
                            }
                        }
                        var cm = (itemRow.rootBlock && itemRow.rootBlock.editor) ? itemRow.rootBlock.editor.contextMenu : (root.editor ? root.editor.contextMenu : null);
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
                            itemRow._openContextMenuAt(lineEdit, lineEdit.cursorPosition, true);
                            event.accepted = true;
                            return;
                        }

                        var rEditor = itemRow.rootBlock ? itemRow.rootBlock.editor : (root.editor || null);
                        var isCtrlKey = !!(event.modifiers & Qt.ControlModifier);
                        var isShiftKey = !!(event.modifiers & Qt.ShiftModifier);
                        var isAltKey = !!(event.modifiers & Qt.AltModifier);

                        if (isCtrlKey && !isShiftKey && !isAltKey && event.key === Qt.Key_Home) {
                            if (rEditor && typeof rEditor.goToDocumentStart === "function") {
                                rEditor.goToDocumentStart();
                                event.accepted = true;
                                return;
                            }
                        }
                        if (isCtrlKey && !isShiftKey && !isAltKey && event.key === Qt.Key_End) {
                            if (rEditor && typeof rEditor.goToDocumentEnd === "function") {
                                rEditor.goToDocumentEnd();
                                event.accepted = true;
                                return;
                            }
                        }
                        if (event.key === Qt.Key_PageUp) {
                            if (rEditor && typeof rEditor.pageUp === "function") {
                                rEditor.pageUp();
                                event.accepted = true;
                                return;
                            }
                        }
                        if (event.key === Qt.Key_PageDown) {
                            if (rEditor && typeof rEditor.pageDown === "function") {
                                rEditor.pageDown();
                                event.accepted = true;
                                return;
                            }
                        }
                        if (isCtrlKey && !isShiftKey && !isAltKey && event.key === Qt.Key_Delete) {
                            if (root.editor && root.editor.readOnly) {
                                event.accepted = true;
                                return;
                            }
                            if (lineEdit.selectionStart !== lineEdit.selectionEnd) {
                                lineEdit.remove(lineEdit.selectionStart, lineEdit.selectionEnd);
                            } else if (lineEdit.cursorPosition < lineEdit.length) {
                                var pTextD = Inline.plainText(lineEdit);
                                var nextWD = Inline.findNextWordEnd(pTextD, lineEdit.cursorPosition);
                                lineEdit.remove(lineEdit.cursorPosition, nextWD);
                            } else if (lineEdit.cursorPosition === lineEdit.length) {
                                if (itemRow.index < itemsModel.count - 1) {
                                    var nextItem = root._itemsRawArray[itemRow.index + 1];
                                    var curItem = root._itemsRawArray[itemRow.index];
                                    curItem.text = (curItem.text || "") + (nextItem.text || "");
                                    itemsModel.setProperty(itemRow.index, "text", curItem.text);
                                    root._removeItem(itemRow.index + 1);
                                    root._notifyRawChanged();
                                } else if (itemRow.index === itemsModel.count - 1 && rEditor) {
                                    rEditor.handleBlockDeleteAtEnd(root.blockData.bid);
                                }
                            }
                            event.accepted = true;
                            return;
                        }

                        if (!isCtrlKey && !isShiftKey && !isAltKey && event.key === Qt.Key_Insert) {
                            if (rEditor && typeof rEditor.toggleOverwriteMode === "function") {
                                rEditor.toggleOverwriteMode();
                            } else {
                                lineEdit.overwriteMode = !lineEdit.overwriteMode;
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
                            if (rEditor && typeof rEditor.resetPreferredCursorX === "function") {
                                rEditor.resetPreferredCursorX();
                            }
                        }
                        if (root.editor && root.editor.hasBlockSelection) {
                            var isCtrlB = !!(event.modifiers & Qt.ControlModifier);
                            var isShiftB = !!(event.modifiers & Qt.ShiftModifier);
                            var isAltB = !!(event.modifiers & Qt.AltModifier);

                            if ((isCtrlB && !isShiftB && !isAltB && event.key === Qt.Key_C) ||
                                (isCtrlB && !isShiftB && !isAltB && event.key === Qt.Key_Insert)) {
                                root.editor.copySelectedText();
                                event.accepted = true;
                                return;
                            }
                            if ((isCtrlB && !isShiftB && !isAltB && event.key === Qt.Key_X) ||
                                (isShiftB && !isCtrlB && !isAltB && event.key === Qt.Key_Delete)) {
                                root.editor.copySelectedText();
                                if (!root.editor.readOnly && typeof root.editor.replaceSelectedRange === "function") {
                                    root.editor.replaceSelectedRange("");
                                }
                                event.accepted = true;
                                return;
                            }
                            if ((isCtrlB && !isShiftB && !isAltB && event.key === Qt.Key_V) ||
                                (isShiftB && !isCtrlB && !isAltB && event.key === Qt.Key_Insert)) {
                                if (!root.editor.readOnly && typeof root.editor.replaceSelectedRange === "function") {
                                    var pasteTxtB = (typeof Quickshell.clipboardText === "string") ? Quickshell.clipboardText : "";
                                    root.editor.replaceSelectedRange(pasteTxtB);
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
                            if (!isCtrlB && !isAltB && event.text && event.text.length > 0 && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) {
                                if (!root.editor.readOnly && typeof root.editor.replaceSelectedRange === "function") {
                                    root.editor.replaceSelectedRange(event.text);
                                }
                                event.accepted = true;
                                return;
                            }
                        }

                        var isMulti = root.hasMultipleItemsSelected() || root.hasMultiItemSelection;
                        if (isMulti) {
                            var isCtrlM = !!(event.modifiers & Qt.ControlModifier);
                            var isShiftM = !!(event.modifiers & Qt.ShiftModifier);
                            var isAltM = !!(event.modifiers & Qt.AltModifier);

                            if ((isCtrlM && !isShiftM && !isAltM && event.key === Qt.Key_C) ||
                                (isCtrlM && !isShiftM && !isAltM && event.key === Qt.Key_Insert)) {
                                var fullSelTxtC = root.getSelectedText();
                                if (rEditor && typeof rEditor.copyText === "function") {
                                    rEditor.copyText(fullSelTxtC);
                                } else if (typeof Quickshell.clipboardText !== "undefined") {
                                    Quickshell.clipboardText = fullSelTxtC;
                                }
                                event.accepted = true;
                                return;
                            }
                            if ((isCtrlM && !isShiftM && !isAltM && event.key === Qt.Key_X) ||
                                (isShiftM && !isCtrlM && !isAltM && event.key === Qt.Key_Delete)) {
                                var fullSelTxtX = root.getSelectedText();
                                if (rEditor && typeof rEditor.copyText === "function") {
                                    rEditor.copyText(fullSelTxtX);
                                } else if (typeof Quickshell.clipboardText !== "undefined") {
                                    Quickshell.clipboardText = fullSelTxtX;
                                }
                                root.deleteMultiItemSelection("");
                                event.accepted = true;
                                return;
                            }
                            if ((isCtrlM && !isShiftM && !isAltM && event.key === Qt.Key_V) ||
                                (isShiftM && !isCtrlM && !isAltM && event.key === Qt.Key_Insert)) {
                                var pasteTxtM = (typeof Quickshell.clipboardText === "string") ? Quickshell.clipboardText : "";
                                root.deleteMultiItemSelection(pasteTxtM);
                                event.accepted = true;
                                return;
                            }
                            if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
                                root.deleteMultiItemSelection("");
                                event.accepted = true;
                                return;
                            }
                            if (event.key === Qt.Key_Escape) {
                                root.clearTextSelection();
                                if (rEditor) rEditor.clearBlockSelection();
                                event.accepted = true;
                                return;
                            }
                            if (!isCtrlM && !isAltM && event.text && event.text.length > 0 && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) {
                                root.deleteMultiItemSelection(event.text);
                                event.accepted = true;
                                return;
                            }
                        }

                        if (rEditor && typeof rEditor.handleAutoPair === "function") {
                            if (rEditor.handleAutoPair(lineEdit, event)) {
                                return;
                            }
                        }

                        if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_V) {
                            if (rEditor && rEditor.editorModal && typeof rEditor.editorModal.pasteClipboardImage === "function") {
                                rEditor.editorModal.pasteClipboardImage();
                                event.accepted = true;
                                return;
                            }
                        }

                        if (((event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_V) ||
                            ((event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_Insert)) {
                            if (rEditor && typeof rEditor.handlePaste === "function") {
                                if (rEditor.handlePaste(lineEdit)) {
                                    event.accepted = true;
                                    return;
                                }
                            }
                        }

                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            var pos = lineEdit.cursorPosition;
                            var fullTxt = Inline.plainText(lineEdit);
                            event.accepted = true;
                            root.handleItemReturn(itemRow.index, pos, fullTxt);
                            return;
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
                            // F21: con TODO el ítem seleccionado, copiar/cortar el Markdown
                            // CON el prefijo `## ` (el TextEdit solo tiene el contenido).
                            if ((event.key === Qt.Key_C || event.key === Qt.Key_X)
                                && lineEdit.selectionStart === 0 && lineEdit.selectionEnd === lineEdit.length
                                && lineEdit.length > 0 && (itemRow.headingLevel || 0) > 0) {
                                var lvC = itemRow.headingLevel;
                                var withPfx = new Array(lvC + 1).join("#") + " " + lineEdit.selectedText;
                                if (rEditor && typeof rEditor.copyText === "function") {
                                    rEditor.copyText(withPfx);
                                } else if (typeof Quickshell.clipboardText !== "undefined") {
                                    Quickshell.clipboardText = withPfx;
                                }
                                if (event.key === Qt.Key_X) {
                                    lineEdit.remove(0, lineEdit.length);
                                }
                                event.accepted = true;
                                return;
                            }
                        }

                        if (event.key === Qt.Key_Backspace) {
                            if (lineEdit.cursorPosition === 0 && lineEdit.selectionStart === lineEdit.selectionEnd) {
                                var fullTxt = Inline.plainText(lineEdit);
                                if (root.handleItemBackspace(itemRow.index, lineEdit.cursorPosition, fullTxt)) {
                                    event.accepted = true;
                                    return;
                                }
                            }
                        } else if (event.key === Qt.Key_Tab) {
                            root.handleItemTab(itemRow.index, lineEdit);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Backtab) {
                            root.handleItemBacktab(itemRow.index, lineEdit);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up) {
                            var curX = lineEdit.positionToRectangle(lineEdit.cursorPosition).x;
                            var targetX = (rEditor && typeof rEditor.getPreferredCursorX === "function") ? rEditor.getPreferredCursorX(curX) : curX;
                            if (event.modifiers & Qt.ShiftModifier) {
                                var curUpYShift = lineEdit.positionToRectangle(lineEdit.cursorPosition).y;
                                var topYShift = lineEdit.positionToRectangle(0).y;
                                if (curUpYShift <= topYShift + 4) {
                                    if (itemRow.index === 0) {
                                        if (lineEdit.cursorPosition === 0) {
                                            if (root.editor && root.blockData && typeof root.editor.extendKeyboardSelectionUp === "function") {
                                                root.editor.extendKeyboardSelectionUp(root.blockData.bid, 0);
                                                event.accepted = true;
                                                return;
                                            }
                                        } else {
                                            var aUp = (lineEdit.selectionStart === lineEdit.cursorPosition) ? lineEdit.selectionEnd : lineEdit.selectionStart;
                                            lineEdit.select(aUp, 0);
                                            event.accepted = true;
                                            return;
                                        }
                                    } else {
                                        root.extendItemSelectionUp(itemRow.index);
                                        event.accepted = true;
                                        return;
                                    }
                                }
                                return;
                            }
                            var curUpY = lineEdit.positionToRectangle(lineEdit.cursorPosition).y;
                            var topY = lineEdit.positionToRectangle(0).y;
                            if (curUpY <= topY + 4) {
                                if (itemRow.index > 0) {
                                    root._focusItem(itemRow.index - 1, { x: targetX, fromBottom: true });
                                    event.accepted = true;
                                } else if (itemRow.index === 0) {
                                    if (root.editor && root.blockData) {
                                        root.editor.focusPreviousBlock(root.blockData.bid, { x: targetX, fromBottom: true });
                                        event.accepted = true;
                                    } else if (lineEdit.cursorPosition > 0) {
                                        lineEdit.cursorPosition = 0;
                                        event.accepted = true;
                                    }
                                }
                            }
                        } else if (event.key === Qt.Key_Down) {
                            var curXDown = lineEdit.positionToRectangle(lineEdit.cursorPosition).x;
                            var targetXDown = (rEditor && typeof rEditor.getPreferredCursorX === "function") ? rEditor.getPreferredCursorX(curXDown) : curXDown;
                            if (event.modifiers & Qt.ShiftModifier) {
                                var curDownYShift = lineEdit.positionToRectangle(lineEdit.cursorPosition).y;
                                var botYShift = lineEdit.positionToRectangle(lineEdit.length).y;
                                if (curDownYShift >= botYShift - 4) {
                                    if (itemRow.index === root._itemsRawArray.length - 1) {
                                        if (lineEdit.cursorPosition === lineEdit.length) {
                                            if (root.editor && root.blockData && typeof root.editor.extendKeyboardSelectionDown === "function") {
                                                root.editor.extendKeyboardSelectionDown(root.blockData.bid, root.getTextLength());
                                                event.accepted = true;
                                                return;
                                            }
                                        } else {
                                            var aDown = (lineEdit.selectionStart === lineEdit.cursorPosition) ? lineEdit.selectionEnd : lineEdit.selectionStart;
                                            lineEdit.select(aDown, lineEdit.length);
                                            event.accepted = true;
                                            return;
                                        }
                                    } else {
                                        root.extendItemSelectionDown(itemRow.index);
                                        event.accepted = true;
                                        return;
                                    }
                                }
                                return;
                            }
                            var curDownY = lineEdit.positionToRectangle(lineEdit.cursorPosition).y;
                            var botY = lineEdit.positionToRectangle(lineEdit.length).y;
                            if (curDownY >= botY - 4) {
                                if (itemRow.index < root._itemsRawArray.length - 1) {
                                    root._focusItem(itemRow.index + 1, { x: targetXDown, fromTop: true });
                                    event.accepted = true;
                                } else if (itemRow.index === root._itemsRawArray.length - 1) {
                                    if (root.editor && root.blockData) {
                                        root.editor.focusNextBlock(root.blockData.bid, { x: targetXDown, fromTop: true });
                                        event.accepted = true;
                                    } else if (lineEdit.cursorPosition < lineEdit.length) {
                                        lineEdit.cursorPosition = lineEdit.length;
                                        event.accepted = true;
                                    }
                                }
                            }
                        } else if (event.key === Qt.Key_Left) {
                            if (event.modifiers & Qt.ShiftModifier) {
                                if (lineEdit.cursorPosition === 0) {
                                    if (itemRow.index === 0) {
                                        if (root.editor && root.blockData && typeof root.editor.extendKeyboardSelectionUp === "function") {
                                            root.editor.extendKeyboardSelectionUp(root.blockData.bid, 0);
                                            event.accepted = true;
                                            return;
                                        }
                                    } else {
                                        root.extendItemSelectionUp(itemRow.index);
                                        event.accepted = true;
                                        return;
                                    }
                                }
                            }
                        } else if (event.key === Qt.Key_Right) {
                            if (event.modifiers & Qt.ShiftModifier) {
                                if (lineEdit.cursorPosition === lineEdit.length) {
                                    if (itemRow.index === root._itemsRawArray.length - 1) {
                                        if (root.editor && root.blockData && typeof root.editor.extendKeyboardSelectionDown === "function") {
                                            root.editor.extendKeyboardSelectionDown(root.blockData.bid, root.getTextLength());
                                            event.accepted = true;
                                            return;
                                        }
                                    } else {
                                        root.extendItemSelectionDown(itemRow.index);
                                        event.accepted = true;
                                        return;
                                    }
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
                                lineEdit.forceActiveFocus();
                                var pos = lineEdit.positionAt(mouse.x, mouse.y);
                                itemRow._openContextMenuAt(lineEdit, pos);
                            }
                        }
                    }

                    SpellOverlay {
                        id: spellOverlay
                        textItem: lineEdit
                        ranges: itemRow.spellRanges
                        active: root.spellActive
                        waveColor: Theme.color3
                    }
                }

                    // Imágenes del ítem como Image reales: tamaño natural
                    // acotado al ancho disponible (sin tope de alto, sin marco),
                    // alineadas a la izquierda con el mismo sangrado del texto.
                    // Solo lectura. El alt sale del texto y va solo al placeholder.
                    Repeater {
                        model: itemRow.itemImages
                        delegate: Item {
                            id: imgWrap
                            readonly property real availW: textCol.width
                            // Tamaño natural capturado una sola vez al cargar (no reactivo a
                            // imgItem.implicit*, que dependía de nuestro propio alto -> binding loop)
                            property real natW: 0
                            property real natH: 0
                            readonly property real dispW: (natW > 0 && !failed)
                                ? Math.min(natW * (typeof EditorMetrics !== "undefined" && EditorMetrics.zoom ? EditorMetrics.zoom : 1.0), availW)
                                : availW
                            width: dispW
                            visible: !root.isEditing && !itemRow.isSelected

                            readonly property var imgRef: modelData
                            readonly property string rawSrc: (imgRef.src || "")
                            readonly property string fileUrl: {
                                var s = rawSrc;
                                if (s.startsWith("http://") || s.startsWith("https://") || s.startsWith("file://")) return s;
                                var abs = ImageProbe.resolveLocal(itemRow.itemImgBase, s);
                                return abs ? ("file://" + encodeURI(abs)) : "";
                            }
                            // Se pide salvo faltante conocido; en duda (probe
                            // pendiente) se muestra placeholder, nunca warning.
                            readonly property bool attempt: {
                                var t = rawSrc.trim();
                                if (t === "") return false;
                                if (t.startsWith("http://") || t.startsWith("https://")) return true;
                                var st = NotesService.imageStateFor(t, itemRow.itemImgBase);
                                return st === "yes" || st === "remote";
                            }
                            readonly property bool failed: !attempt || imgItem.status === Image.Error

                            height: {
                                if (failed) return errCol.implicitHeight + 8;
                                if (natW > 0 && natH > 0) {
                                    return Math.round(dispW * natH / Math.max(1, natW));
                                }
                                return 200;
                            }

                            AnimatedImage {
                                id: imgItem
                                anchors.fill: parent
                                visible: !parent.failed
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: true
                                playing: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                paused: GamemodeService.gamemodeActive
                                sourceSize.width: Math.max(1, Math.ceil(parent.availW * (Screen.devicePixelRatio || 1)))
                                source: parent.attempt ? parent.fileUrl : ""

                                onStatusChanged: {
                                    if (status === Image.Ready && implicitWidth > 0 && implicitHeight > 0) {
                                        if (imgWrap.natW !== implicitWidth) imgWrap.natW = implicitWidth;
                                        if (imgWrap.natH !== implicitHeight) imgWrap.natH = implicitHeight;
                                    }
                                }
                            }

                            ColumnLayout {
                                id: errCol
                                width: parent.width
                                anchors.centerIn: parent
                                spacing: 4
                                visible: parent.failed

                                Image {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: 24
                                    Layout.preferredHeight: 24
                                    source: Theme.iconsPath + "broken-image.svg"
                                    sourceSize: Qt.size(24, 24)
                                    smooth: true
                                    mipmap: true
                                    layer.enabled: visible && !GamemodeService.gamemodeActive
                                    layer.effect: MultiEffect {
                                        colorization: 1.0
                                        colorizationColor: Theme.danger
                                    }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: Math.min(errCol.width, 420)
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.Wrap
                                    text: (imgRef.alt && imgRef.alt.trim() !== "") ? imgRef.alt : I18n.t("notes.image_load_error", "No se pudo cargar la imagen")
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: EditorMetrics.caption
                                }
                            }
                        }
                    }
                }
                MouseArea {
                    id: listMa
                    anchors.fill: parent
                    z: 5
                    enabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: (!root.isEditing && listViewText.hoveredLink !== "") ? Qt.PointingHandCursor : Qt.IBeamCursor
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
                        var rEditorMa = itemRow.rootBlock ? itemRow.rootBlock.editor : (root.editor || null);
                        if (rEditorMa && typeof rEditorMa.resetPreferredCursorX === "function") {
                            rEditorMa.resetPreferredCursorX();
                        }
                        if (mouse.button === Qt.RightButton) {
                            if (!lineEdit) return;
                            var ptEditR = mapToItem(lineEdit, mouse.x, mouse.y);
                            var posR = lineEdit.positionAt(ptEditR.x, ptEditR.y);
                            itemRow._openContextMenuAt(lineEdit, posR);
                            return;
                        }
                        var r = itemRow.rootBlock || (typeof root !== "undefined" ? root : null);
                        if (!r) return;
                        if (!r.isEditing) {
                            var link = listViewText.linkAt(mouse.x, mouse.y);
                            pressedOnLink = (link && link !== "");
                            if (pressedOnLink) return;
                        }
                        r.clearOtherItemsSelection(itemRow.index);
                        if (r.editor && r.blockData && typeof r.editor.clearSelectionExcept === "function") {
                            r.editor.clearSelectionExcept(r.blockData.bid, itemRow.index);
                        }
                        dragging = true;
                        isCrossDragging = false;
                        startX = mouse.x;
                        startY = mouse.y;
                        var ptEdit = mapToItem(lineEdit, mouse.x, mouse.y);
                        if (lineEdit) anchorPos = lineEdit.positionAt(ptEdit.x, ptEdit.y);
                        if (r.editor && r.blockData && r.editor.activeBlockBid !== r.blockData.bid) {
                            r.editor.requestEditBlock(r.blockData.bid, { x: ptEdit.x, y: ptEdit.y });
                        }
                        itemRow.focusInput({ x: ptEdit.x, y: ptEdit.y });
                        var globalAnchor = r.getItemStartOffset(itemRow.index) + itemRow.rawPrefixLen() + (anchorPos >= 0 ? anchorPos : 0);
                        if (r.editor && r.blockData && typeof r.editor.startCrossBlockDrag === "function") {
                            r.editor.startCrossBlockDrag(r.blockData.bid, globalAnchor);
                        }
                    }

                    onPositionChanged: (mouse) => {
                        var r = itemRow.rootBlock || (typeof root !== "undefined" ? root : null);
                        if (!r || !dragging || anchorPos < 0) return;
                        if (!isCrossDragging && Math.abs(mouse.x - startX) < 3 && Math.abs(mouse.y - startY) < 3) return;

                        if (mouse.y < -2 || mouse.y > height + 2 || isCrossDragging) {
                            if (!isCrossDragging) {
                                isCrossDragging = true;
                            }
                            if (r.editor && typeof r.editor.handleCrossBlockDrag === "function") {
                                var ptInContent = mapToItem(r.editor.contentItem, mouse.x, mouse.y);
                                r.editor.handleCrossBlockDrag(r.blockData ? r.blockData.bid : -1, ptInContent.y, ptInContent.x);
                                return;
                            }
                        }

                        var ptEdit = mapToItem(lineEdit, mouse.x, mouse.y);
                        if (lineEdit) lineEdit.select(anchorPos, lineEdit.positionAt(ptEdit.x, ptEdit.y));
                    }

                    onReleased: (mouse) => {
                        var r = itemRow.rootBlock || (typeof root !== "undefined" ? root : null);
                        if (_doubleClickedRecently || (lineEdit && lineEdit.selectionStart !== lineEdit.selectionEnd)) {
                            _doubleClickedRecently = false;
                        } else if (!isCrossDragging && Math.abs(mouse.x - startX) < 4 && Math.abs(mouse.y - startY) < 4 && lineEdit) {
                            var ptEditRel = mapToItem(lineEdit, mouse.x, mouse.y);
                            var posRel = lineEdit.positionAt(ptEditRel.x, ptEditRel.y);
                            if (posRel >= 0 && posRel <= lineEdit.length) {
                                lineEdit.cursorPosition = posRel;
                            }
                        }
                        dragging = false;
                        anchorPos = -1;
                        if (isCrossDragging || (r && r.editor && r.editor.isDraggingSelection)) {
                            isCrossDragging = false;
                            if (r && r.editor && typeof r.editor.endCrossBlockDrag === "function") {
                                r.editor.endCrossBlockDrag();
                            }
                        }
                    }

                    onCanceled: {
                        dragging = false;
                        anchorPos = -1;
                        isCrossDragging = false;
                        var r = itemRow.rootBlock || (typeof root !== "undefined" ? root : null);
                        if (r && r.editor && typeof r.editor.endCrossBlockDrag === "function") {
                            r.editor.endCrossBlockDrag();
                        }
                    }

                    onDoubleClicked: (mouse) => {
                        _doubleClickedRecently = true;
                        var r = itemRow.rootBlock || (typeof root !== "undefined" ? root : null);
                        if (r) {
                            r.clearOtherItemsSelection(itemRow.index);
                            if (r.editor && r.blockData && typeof r.editor.clearSelectionExcept === "function") {
                                r.editor.clearSelectionExcept(r.blockData.bid, itemRow.index);
                            }
                        }
                        if (!lineEdit) return;
                        var ptEdit = mapToItem(lineEdit, mouse.x, mouse.y);
                        var pos = lineEdit.positionAt(ptEdit.x, ptEdit.y);
                        if (pos >= 0 && pos <= lineEdit.length) {
                            lineEdit.forceActiveFocus();
                            lineEdit.cursorPosition = pos;
                            lineEdit.selectWord();
                        }
                    }

                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) return;
                        var r = itemRow.rootBlock || (typeof root !== "undefined" ? root : null);
                        if (!r) return;
                        if (!r.isEditing && pressedOnLink) {
                            var link = listViewText.linkAt(mouse.x, mouse.y);
                            if (link && link !== "") {
                                if (r.editor && typeof r.editor.handleLink === "function") {
                                    r.editor.handleLink(link);
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
