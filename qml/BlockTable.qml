import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Controls
import Notas
import "."
import "TableParser.js" as TP
import "Inline.js" as Inline
import "SpellLogic.js" as SpellLogic

Item {
    id: root

    property var blockData: null
    property bool isEditing: false
    property var editor: null
    property bool isSelected: false
    property bool inViewportChunk: true

    readonly property bool isReadOnly: Boolean(
        (root.editor && root.editor.readOnly) ||
        (NotesService.activeNote && NotesService.activeNote.readOnly) ||
        (root.editor && root.editor.editorModal && root.editor.editorModal.isPreviewMode)
    )

    readonly property bool spellActive: (typeof SpellConfig !== "undefined" && SpellConfig.enabled) && (typeof SpellService !== "undefined" && SpellService.available)
    property bool _isDestroyed: false

    Component.onDestruction: {
        _isDestroyed = true;
        if (typeof SpellService !== "undefined") {
            SpellService.cancelOwner(root);
        }
    }

    Connections {
        target: (typeof SpellService !== "undefined") ? SpellService : null
        function onCacheRevisionChanged() {
            if (root.spellActive && root.isEditing) {
                root.triggerActiveCellSpellCheck();
            }
        }
        function onAvailableChanged() {
            if (root.spellActive && SpellService.available && root.isEditing) {
                root.triggerActiveCellSpellCheck();
            }
        }
    }

    function triggerActiveCellSpellCheck() {
        if (!root.isEditing || root._isDestroyed) return;
        var r = root.focusedRow;
        var c = root.focusedCol;
        if (r === -1) {
            if (headerRepeater) {
                var hDel = headerRepeater.itemAt(c);
                if (hDel && typeof hDel.runSpellCheck === "function") hDel.runSpellCheck();
            }
        } else if (r >= 0) {
            if (rowsRepeater) {
                var rDel = rowsRepeater.itemAt(r);
                if (rDel && typeof rDel.getCellDelegate === "function") {
                    var cDel = rDel.getCellDelegate(c);
                    if (cDel && typeof cDel.runSpellCheck === "function") cDel.runSpellCheck();
                }
            }
        }
    }

    function selectRange(start, end) {}
    function selectAllText() {}
    function clearTextSelection() {}
    function getCharPosAt(lx, ly) { return 0; }
    function getTextLength() { return root.blockData ? (root.blockData.raw || "").length : 0; }
    function getSelectedText() { return root.blockData ? (root.blockData.raw || "") : ""; }
    function getTextContent() { return root.blockData ? (root.blockData.raw || "") : ""; }
    function deleteSelectedText() {}

    property var parsedTable: _activeTable

    property var _activeTable: null
    property string _lastSyncedRaw: ""
    property int focusedRow: -1 // -1 = header, 0..N-1 = data rows
    property int focusedCol: 0

    // ── Dimensiones dinámicas de columnas y tabla ─────────────────────────
    readonly property real minColWidth: Math.max(96, Math.round(96 * (EditorMetrics.zoom || 1.0)))
    readonly property int colCount: (root.parsedTable && root.parsedTable.headers) ? Math.max(1, root.parsedTable.headers.length) : 1
    readonly property real availableTableWidth: Math.max(100, (tableFlickable ? tableFlickable.width : 400) - ((addColDot && addColDot.visible) ? (addColDot.width + 12) : 0))
    readonly property real colWidth: Math.max(minColWidth, Math.floor(availableTableWidth / colCount))
    readonly property real tableColWidth: colCount * colWidth

    function ensureCellVisible(colIndex) {
        if (colIndex < 0 || !tableFlickable) return;
        var cellLeft = colIndex * root.colWidth;
        var cellRight = cellLeft + root.colWidth;
        var viewLeft = tableFlickable.contentX;
        var viewRight = viewLeft + tableFlickable.width;

        if (cellLeft < viewLeft) {
            tableFlickable.contentX = Math.max(0, cellLeft);
        } else if (cellRight > viewRight) {
            var targetX = cellRight - tableFlickable.width + ((addColDot && addColDot.visible) ? (addColDot.width + 16) : 0);
            tableFlickable.contentX = Math.max(0, Math.min(tableFlickable.contentWidth - tableFlickable.width, targetX));
        }
    }

    implicitWidth: parent ? parent.width : 400
    implicitHeight: (root.parsedTable !== null)
        ? (tableContainer.implicitHeight + 8)
        : (rawEditor.paintedHeight + 16)

    function _syncFromRaw() {
        var raw = root.blockData ? (root.blockData.raw || "") : "";
        if (raw === _lastSyncedRaw && _activeTable !== null) return;
        _lastSyncedRaw = raw;
        _activeTable = TP.parseTable(raw);
    }

    onBlockDataChanged: _syncFromRaw()
    Component.onCompleted: _syncFromRaw()

    onIsEditingChanged: {
        if (!isEditing && _activeTable) {
            var r = TP.serializeTable(_activeTable);
            _lastSyncedRaw = r;
            _activeTable = TP.parseTable(r);
        }
    }

    function getRaw() {
        if (root._activeTable) {
            return TP.serializeTable(root._activeTable);
        }
        if (rawEditor) {
            return Inline.plainText(rawEditor);
        }
        return root.blockData ? (root.blockData.raw || "") : "";
    }

    function getTextEdit() {
        if (root._activeTable && root.isEditing) {
            var cellInput = root._getCellInput(root.focusedRow, root.focusedCol);
            if (cellInput) return cellInput;
        }
        return rawEditor;
    }

    function commitInlineSubEdit(textEdit, newPlain, selStart, selEnd) {
        root._notifyCellChange(root.focusedRow, root.focusedCol, newPlain);
        if (textEdit && typeof selStart === "number" && typeof selEnd === "number") {
            textEdit.select(selStart, selEnd);
        }
    }

    function focusInput(cursorPos) {
        if (!_activeTable) {
            _syncFromRaw();
        }
        if (!_activeTable) {
            if (rawEditor) {
                rawEditor.forceActiveFocus();
                if (cursorPos !== undefined && cursorPos >= 0) {
                    rawEditor.cursorPosition = Math.min(rawEditor.text.length, cursorPos);
                } else {
                    rawEditor.cursorPosition = rawEditor.text.length;
                }
            }
            return;
        }
        var numCols = _activeTable.headers ? _activeTable.headers.length : 0;
        var numRows = _activeTable.rows ? _activeTable.rows.length : 0;
        if (numCols === 0) return;

        if (typeof cursorPos === "object" && cursorPos !== null && cursorPos.x !== undefined) {
            var col = Math.max(0, Math.min(numCols - 1, Math.floor(cursorPos.x / root.colWidth)));
            if (cursorPos.fromBottom === true || cursorPos.y > 1000) {
                focusCell(numRows > 0 ? numRows - 1 : -1, col, -1);
            } else {
                focusCell(-1, col, 0);
            }
            return;
        }

        if (cursorPos === "data" || cursorPos === "cell_0_0") {
            if (numRows > 0) {
                focusCell(0, 0, 0);
            } else {
                focusCell(-1, 0, 0);
            }
        } else if (cursorPos === -1 || (typeof cursorPos === "object" && cursorPos !== null && (cursorPos.fromBottom === true || cursorPos.y > 1000))) {
            // Navegación desde abajo: enfocar última celda
            if (numRows > 0) {
                focusCell(numRows - 1, numCols - 1, -1);
            } else {
                focusCell(-1, numCols - 1, -1);
            }
        } else {
            // Navegación desde arriba: enfocar primera celda de encabezado
            focusCell(-1, 0, 0);
        }
    }

    function focusCell(r, c, pos) {
        if (!_activeTable) return;
        var numCols = _activeTable.headers ? _activeTable.headers.length : 0;
        var numRows = _activeTable.rows ? _activeTable.rows.length : 0;
        if (numCols === 0) return;

        r = Math.max(-1, Math.min(numRows - 1, r));
        c = Math.max(0, Math.min(numCols - 1, c));
        if ((r !== root.focusedRow || c !== root.focusedCol) && _activeTable) {
            var rsync = TP.serializeTable(_activeTable);
            _lastSyncedRaw = rsync;
            _activeTable = TP.parseTable(rsync);
        }
        root.focusedRow = r;
        root.focusedCol = c;
        root.ensureCellVisible(c);
        Qt.callLater(() => {
            var input = _getCellInput(r, c);
            if (input) {
                input.forceActiveFocus();
                if (pos === -1) {
                    input.cursorPosition = input.length;
                } else if (typeof pos === "number" && pos >= 0) {
                    input.cursorPosition = Math.min(input.length, pos);
                }
            }
        });
    }

    function _getCellInput(r, c) {
        if (r === -1) {
            if (!headerRepeater) return null;
            var hDel = headerRepeater.itemAt(c);
            return hDel ? hDel.textInput : null;
        } else {
            if (!rowsRepeater) return null;
            var rDel = rowsRepeater.itemAt(r);
            if (!rDel) return null;
            var cDel = rDel.getCellDelegate(c);
            return cDel ? cDel.textInput : null;
        }
    }

    function _notifyCellChange(r, c, val) {
        if (!_activeTable || (root.editor && root.editor.readOnly)) return;
        if (r === -1) {
            if (_activeTable.headers && c >= 0 && c < _activeTable.headers.length) {
                _activeTable.headers[c] = val;
            }
        } else {
            if (_activeTable.rows && r >= 0 && r < _activeTable.rows.length) {
                if (_activeTable.rows[r] && c >= 0 && c < _activeTable.rows[r].length) {
                    _activeTable.rows[r][c] = val;
                }
            }
        }
        var newRaw = TP.serializeTable(_activeTable);
        _lastSyncedRaw = newRaw;
        if (root.blockData) {
            root.blockData.raw = newRaw;
        }
        if (root.editor && root.blockData) {
            root.editor.onBlockRawChanged(root.blockData.bid, newRaw);
        }
    }

    function addNewRow(index) {
        if (!_activeTable || (root.editor && root.editor.readOnly)) return;
        TP.addRow(_activeTable, index);
        var newRaw = TP.serializeTable(_activeTable);
        _lastSyncedRaw = newRaw;
        _activeTable = TP.parseTable(newRaw);
        if (root.blockData) root.blockData.raw = newRaw;
        if (root.editor && root.blockData) {
            root.editor.onBlockRawChanged(root.blockData.bid, newRaw);
        }
    }

    function removeRowAt(index) {
        if (!_activeTable || _activeTable.rows.length <= 1 || (root.editor && root.editor.readOnly)) return;
        TP.removeRow(_activeTable, index);
        var newRaw = TP.serializeTable(_activeTable);
        _lastSyncedRaw = newRaw;
        _activeTable = TP.parseTable(newRaw);
        if (root.blockData) root.blockData.raw = newRaw;
        if (root.editor && root.blockData) {
            root.editor.onBlockRawChanged(root.blockData.bid, newRaw);
        }
    }

    function addNewCol(index) {
        if (!_activeTable || (root.editor && root.editor.readOnly)) return;
        var defaultHeader = I18n.t("notes.table_column", "Columna");
        TP.addCol(_activeTable, index, defaultHeader);
        var newRaw = TP.serializeTable(_activeTable);
        _lastSyncedRaw = newRaw;
        _activeTable = TP.parseTable(newRaw);
        if (root.blockData) root.blockData.raw = newRaw;
        if (root.editor && root.blockData) {
            root.editor.onBlockRawChanged(root.blockData.bid, newRaw);
        }
        Qt.callLater(() => {
            if (tableFlickable) {
                tableFlickable.contentX = Math.max(0, tableFlickable.contentWidth - tableFlickable.width);
            }
            var newColIdx = (root._activeTable && root._activeTable.headers) ? (root._activeTable.headers.length - 1) : 0;
            root.focusCell(root.focusedRow >= 0 ? root.focusedRow : -1, newColIdx);
        });
    }

    function removeColAt(index) {
        if (!_activeTable || _activeTable.headers.length <= 1 || (root.editor && root.editor.readOnly)) return;
        TP.removeCol(_activeTable, index);
        var newRaw = TP.serializeTable(_activeTable);
        _lastSyncedRaw = newRaw;
        _activeTable = TP.parseTable(newRaw);
        if (root.blockData) root.blockData.raw = newRaw;
        if (root.editor && root.blockData) {
            root.editor.onBlockRawChanged(root.blockData.bid, newRaw);
        }
        Qt.callLater(() => {
            if (tableFlickable) {
                tableFlickable.contentX = Math.max(0, Math.min(tableFlickable.contentWidth - tableFlickable.width, tableFlickable.contentX));
            }
        });
    }

    function toggleAlignment(c) {
        if (!_activeTable || (root.editor && root.editor.readOnly)) return;
        TP.toggleColAlign(_activeTable, c);
        var newRaw = TP.serializeTable(_activeTable);
        _lastSyncedRaw = newRaw;
        _activeTable = TP.parseTable(newRaw);
        if (root.blockData) root.blockData.raw = newRaw;
        if (root.editor && root.blockData) {
            root.editor.onBlockRawChanged(root.blockData.bid, newRaw);
        }
    }

    function _getAlignment(colIndex) {
        if (!_activeTable || !_activeTable.aligns || colIndex >= _activeTable.aligns.length) return Text.AlignLeft;
        var a = _activeTable.aligns[colIndex];
        if (a === "center") return Text.AlignHCenter;
        if (a === "right") return Text.AlignRight;
        return Text.AlignLeft;
    }

    function _getAlign(colIndex) {
        if (!_activeTable || !_activeTable.aligns || colIndex >= _activeTable.aligns.length) return "none";
        return _activeTable.aligns[colIndex] || "none";
    }

    function _getAlignIcon(colIndex) {
        var a = _getAlign(colIndex);
        if (a === "center") return Theme.iconsPath + "align-horizontal-center.svg";
        if (a === "right") return Theme.iconsPath + "align-horizontal-right.svg";
        return Theme.iconsPath + "align-horizontal-left.svg";
    }

    function _handleCellTab(r, c, event) {
        event.accepted = true;
        if (event.modifiers & Qt.ShiftModifier) {
            _handleCellBacktab(r, c, event);
            return;
        }
        if (!_activeTable) return;
        var numCols = _activeTable.headers.length;
        var numRows = _activeTable.rows.length;

        if (c < numCols - 1) {
            focusCell(r, c + 1);
        } else if (r === -1) {
            if (numRows > 0) {
                focusCell(0, 0);
            } else {
                addNewRow();
                focusCell(0, 0);
            }
        } else if (r < numRows - 1) {
            focusCell(r + 1, 0);
        } else {
            addNewRow();
            focusCell(numRows, 0);
        }
    }

    function _handleCellBacktab(r, c, event) {
        event.accepted = true;
        if (!_activeTable) return;
        var numCols = _activeTable.headers.length;

        if (c > 0) {
            focusCell(r, c - 1);
        } else if (r > 0) {
            focusCell(r - 1, numCols - 1);
        } else if (r === 0) {
            focusCell(-1, numCols - 1);
        } else if (r === -1) {
            if (root.editor && typeof root.editor.focusPreviousBlock === "function") {
                root.editor.focusPreviousBlock(root.blockData.bid);
            }
        }
    }

    function _handleCellReturn(r, c, event) {
        if (event.modifiers & Qt.ControlModifier) {
            if (root.editor && root.blockData && typeof root.editor.insertParagraphAfter === "function") {
                root.editor.insertParagraphAfter(root.blockData.bid);
            } else if (root.editor) {
                root.editor.confirmActiveBlock();
            }
            event.accepted = true;
            return;
        }
        event.accepted = true;
        if (!_activeTable) return;
        var numRows = _activeTable.rows.length;

        if (r === -1) {
            if (numRows > 0) {
                focusCell(0, c);
            } else {
                addNewRow();
                focusCell(0, c);
            }
        } else if (r < numRows - 1) {
            focusCell(r + 1, c);
        } else {
            // Si la última fila está completamente vacía, eliminarla y salir de la tabla a un párrafo debajo
            var rowCells = _activeTable.rows[r];
            var allEmpty = true;
            if (rowCells) {
                for (var k = 0; k < rowCells.length; k++) {
                    if ((rowCells[k] || "").trim() !== "") { allEmpty = false; break; }
                }
            }
            if (allEmpty && numRows > 1) {
                removeRowAt(r);
                if (root.editor && root.blockData && typeof root.editor.insertParagraphAfter === "function") {
                    root.editor.insertParagraphAfter(root.blockData.bid);
                }
                return;
            }
            addNewRow();
            focusCell(numRows, c);
        }
    }

    function _handleCellUp(r, c, event) {
        if (r > 0) {
            focusCell(r - 1, c);
            event.accepted = true;
        } else if (r === 0) {
            focusCell(-1, c);
            event.accepted = true;
        } else if (r === -1) {
            if (root.editor && typeof root.editor.focusPreviousBlock === "function") {
                root.editor.focusPreviousBlock(root.blockData.bid);
                event.accepted = true;
            }
        }
    }

    function _handleCellDown(r, c, event) {
        if (!_activeTable) return;
        var numRows = _activeTable.rows.length;
        if (r === -1) {
            if (numRows > 0) {
                focusCell(0, c);
                event.accepted = true;
            }
        } else if (r < numRows - 1) {
            focusCell(r + 1, c);
            event.accepted = true;
        } else {
            if (root.editor && typeof root.editor.focusNextBlock === "function") {
                root.editor.focusNextBlock(root.blockData.bid);
                event.accepted = true;
            }
        }
    }

    function _handleCellLeft(r, c, input, event) {
        if (event.modifiers & Qt.ShiftModifier) {
            event.accepted = false;
            return;
        }
        if (input.cursorPosition === 0 && input.selectionStart === input.selectionEnd) {
            if (!_activeTable) {
                event.accepted = false;
                return;
            }
            var numCols = _activeTable.headers ? _activeTable.headers.length : 0;
            if (c > 0) {
                focusCell(r, c - 1, -1);
                event.accepted = true;
            } else if (r > 0) {
                focusCell(r - 1, numCols - 1, -1);
                event.accepted = true;
            } else if (r === 0) {
                focusCell(-1, numCols - 1, -1);
                event.accepted = true;
            } else if (r === -1) {
                if (root.editor && typeof root.editor.focusPreviousBlock === "function") {
                    root.editor.focusPreviousBlock(root.blockData.bid);
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            } else {
                event.accepted = false;
            }
        } else {
            event.accepted = false;
        }
    }

    function _handleCellRight(r, c, input, event) {
        if (event.modifiers & Qt.ShiftModifier) {
            event.accepted = false;
            return;
        }
        if (input.cursorPosition === input.length && input.selectionStart === input.selectionEnd) {
            if (!_activeTable) {
                event.accepted = false;
                return;
            }
            var numCols = _activeTable.headers ? _activeTable.headers.length : 0;
            var numRows = _activeTable.rows ? _activeTable.rows.length : 0;
            if (c < numCols - 1) {
                focusCell(r, c + 1, 0);
                event.accepted = true;
            } else if (r === -1) {
                if (numRows > 0) {
                    focusCell(0, 0, 0);
                    event.accepted = true;
                } else {
                    if (root.editor && typeof root.editor.focusNextBlock === "function") {
                        root.editor.focusNextBlock(root.blockData.bid);
                        event.accepted = true;
                    } else {
                        event.accepted = false;
                    }
                }
            } else if (r < numRows - 1) {
                focusCell(r + 1, 0, 0);
                event.accepted = true;
            } else {
                if (root.editor && typeof root.editor.focusNextBlock === "function") {
                    root.editor.focusNextBlock(root.blockData.bid);
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            }
        } else {
            event.accepted = false;
        }
    }

    function _handleCellEscape(event) {
        if (root.editor) {
            root.editor.confirmActiveBlock();
            event.accepted = true;
        }
    }

    function _handleCellSpecialKeys(event) {
        // F23: Ctrl+Shift+V fuerza imagen; Ctrl+V decide por MIME real.
        // En celdas no se pega la imagen dentro de la celda: se inserta como bloque (vía modal).
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
                var cellInput = root._getCellInput(root.focusedRow, root.focusedCol);
                if (cellInput) {
                    if (root.editor.handlePaste(cellInput)) {
                        event.accepted = true;
                        return;
                    }
                } else if (root.editor.editorModal && typeof root.editor.editorModal.pasteClipboardImage === "function") {
                    var clipText = (typeof Quickshell.clipboardText === "string") ? Quickshell.clipboardText : "";
                    if (!clipText || clipText.trim() === "") {
                        root.editor.editorModal.pasteClipboardImage();
                        event.accepted = true;
                        return;
                    }
                }
            }
        }
        if (event.modifiers & Qt.ControlModifier) {
            if (event.key === Qt.Key_Z) {
                if (event.modifiers & Qt.ShiftModifier) {
                    if (root.editor) root.editor.redo();
                } else {
                    if (root.editor) root.editor.undo();
                }
                event.accepted = true;
                return;
            } else if (event.key === Qt.Key_Y) {
                if (root.editor) root.editor.redo();
                event.accepted = true;
                return;
            }
        }
    }

    // Contenedor visual de la tabla (usado tanto en modo lectura como en modo edición interactiva)
    Item {
        id: tableContainer
        visible: root.parsedTable !== null
        width: parent.width
        implicitHeight: tableFlickable.height + 28 + ((addRowDot && addRowDot.visible) ? 26 : 0)

        // Botón para borrar la tabla (por fuera arriba a la derecha)
        Rectangle {
            id: deleteTableBtn
            visible: !root.isReadOnly
            anchors.right: tableFlickable.right
            anchors.bottom: tableFlickable.top
            anchors.bottomMargin: 4
            width: 22
            height: 22
            radius: 11
            color: delTableMa.containsMouse ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.18) : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
            opacity: (delTableMa.containsMouse || root.isEditing) ? 1.0 : 0.65

            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on opacity { NumberAnimation { duration: 120 } }

            Image {
                anchors.centerIn: parent
                width: 14; height: 14
                source: Theme.iconsPath + "delete.svg"
                sourceSize: Qt.size(14, 14)
                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: delTableMa.containsMouse ? Theme.danger : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.6)
                }
            }

            MouseArea {
                id: delTableMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                    if (root.editor && root.editor.tooltipLayer) {
                        root.editor.tooltipLayer.showTooltip(deleteTableBtn, I18n.t("notes.delete_table", "Eliminar tabla"), "");
                    }
                }
                onExited: {
                    if (root.editor && root.editor.tooltipLayer) {
                        root.editor.tooltipLayer.hideTooltip();
                    }
                }
                onClicked: {
                    if (root.editor && root.editor.tooltipLayer) {
                        root.editor.tooltipLayer.hideTooltip();
                    }
                    if (root.editor && root.blockData && typeof root.editor.deleteBlock === "function") {
                        root.editor.deleteBlock(root.blockData.bid);
                    }
                }
            }

            EditorToolTip {
                label: I18n.t("notes.delete_table", "Eliminar tabla")
                show: delTableMa.containsMouse && (!root.editor || !root.editor.tooltipLayer)
            }
        }

        // ── Flickable horizontal para columnas dinámicas sin compresión visual ──
        Flickable {
            id: tableFlickable
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.rightMargin: 12
            y: 26
            height: tableContentItem.implicitHeight + (hScrollBar.isShowing ? hScrollBar.reservedSpace : 0)
            contentWidth: tableContentItem.width
            contentHeight: height
            clip: true
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.horizontal: CustomScrollBar {
                id: hScrollBar
                orientation: Qt.Horizontal
            }

            // 1. Desplazamiento horizontal con Shift + Rueda
            WheelHandler {
                id: shiftWheelHandler
                target: null
                acceptedModifiers: Qt.ShiftModifier
                acceptedDevices: PointerDevice.AllDevices
                onWheel: (event) => {
                    var delta = event.angleDelta ? (event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x) : 0;
                    tableFlickable.contentX = Math.max(0, Math.min(tableFlickable.contentWidth - tableFlickable.width, tableFlickable.contentX - delta * 0.6));
                    event.accepted = true;
                }
            }

            // 2. Desplazamiento horizontal directo (trackpad o rueda horizontal)
            WheelHandler {
                id: horizWheelHandler
                target: null
                orientation: Qt.Horizontal
                acceptedModifiers: Qt.NoModifier
                acceptedDevices: PointerDevice.AllDevices
                onWheel: (event) => {
                    var deltaX = event.angleDelta ? event.angleDelta.x : 0;
                    if (deltaX !== 0) {
                        tableFlickable.contentX = Math.max(0, Math.min(tableFlickable.contentWidth - tableFlickable.width, tableFlickable.contentX - deltaX * 0.6));
                        event.accepted = true;
                    }
                }
            }

            Item {
                id: tableContentItem
                width: tableCol.width + ((addColDot && addColDot.visible) ? (addColDot.width + 12) : 0)
                implicitHeight: tableCol.implicitHeight

                Column {
                    id: tableCol
                    width: root.tableColWidth
                    spacing: 0

                    // Encabezados
                    Rectangle {
                        id: headerContainer
                        width: root.tableColWidth
                        readonly property real minHeaderHeight: Math.max(38, Math.round(38 * (EditorMetrics.zoom || 1.0)))
                        property real maxHeaderHeight: minHeaderHeight
                        height: Math.max(minHeaderHeight, maxHeaderHeight)
                        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
                        radius: 6

                        function updateHeaderHeight() {
                            var maxH = minHeaderHeight;
                            for (var c = 0; c < headerRepeater.count; c++) {
                                var it = headerRepeater.itemAt(c);
                                if (it && typeof it.cellHeight === "number") {
                                    if (it.cellHeight > maxH) maxH = it.cellHeight;
                                }
                            }
                            if (headerContainer.maxHeaderHeight !== maxH) {
                                headerContainer.maxHeaderHeight = maxH;
                            }
                        }

                        Row {
                            anchors.fill: parent

                            Repeater {
                                id: headerRepeater
                                model: root.parsedTable ? root.parsedTable.headers : []

                                delegate: Rectangle {
                                    id: headerCell
                                    property int colIndex: index
                                    property alias textInput: hInput
                                    readonly property bool isCurrentCell: root.isEditing && root.focusedRow === -1 && root.focusedCol === colIndex
                                    property var spellRanges: []
                                    width: root.colWidth
                                    height: headerContainer.height
                                    color: "transparent"
                                    border.color: isCurrentCell ? Theme.accent : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
                                    border.width: isCurrentCell ? 1.5 : 1

                                    readonly property real cellHeight: Math.max(headerContainer.minHeaderHeight, (isCurrentCell ? hInput.paintedHeight : hViewText.paintedHeight) + 14)
                                    onCellHeightChanged: headerContainer.updateHeaderHeight()
                                    Component.onCompleted: headerContainer.updateHeaderHeight()

                                    Timer {
                                        id: hSpellTimer
                                        interval: 300
                                        repeat: false
                                        onTriggered: headerCell.runSpellCheck()
                                    }

                                    onIsCurrentCellChanged: {
                                        if (isCurrentCell && root.spellActive) {
                                            hSpellTimer.restart();
                                        } else {
                                            headerCell.spellRanges = [];
                                        }
                                    }

                                    function runSpellCheck() {
                                        if (!root.spellActive || root._isDestroyed || typeof SpellService === "undefined" || !SpellService.available) {
                                            headerCell.spellRanges = [];
                                            return;
                                        }
                                        var plain = hInput ? hInput.text : "";
                                        if (!plain || plain.trim() === "") {
                                            headerCell.spellRanges = [];
                                            return;
                                        }
                                        var tokens = SpellLogic.tokenize(plain, {
                                            ignoreUppercase: (typeof SpellConfig !== "undefined") ? SpellConfig.ignoreUppercase : true,
                                            ignoreWithDigits: (typeof SpellConfig !== "undefined") ? SpellConfig.ignoreWithDigits : true,
                                            ignoreCamelCase: (typeof SpellConfig !== "undefined") ? SpellConfig.ignoreCamelCase : true,
                                            ignoreSnakeCase: (typeof SpellConfig !== "undefined") ? SpellConfig.ignoreSnakeCase : true
                                        });
                                        if (tokens.length === 0) {
                                            headerCell.spellRanges = [];
                                            return;
                                        }
                                        var words = tokens.map(function(t) { return t.word; });
                                        SpellService.checkWordsBatch(words, function(results) {
                                            if (root._isDestroyed || !headerCell) return;
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
                                            headerCell.spellRanges = badRanges;
                                            if (hSpellOverlay) hSpellOverlay.requestUpdate();
                                        }, root);
                                    }

                                    function _openContextMenuAt(targetItem, clickPos, fromKeyboard) {
                                        if (!root.editor || !root.editor.contextMenu) return;
                                        var pos = (clickPos !== undefined && clickPos >= 0) ? clickPos : (hInput ? hInput.cursorPosition : -1);
                                        var err = (root.spellActive && (!root.editor || !root.editor.readOnly)) ? SpellLogic.findRangeAt(headerCell.spellRanges, pos) : null;
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
                                                                headerCell._replaceWordAtRange(targetItem, err, formattedSug);
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

                                    function _replaceWordAtRange(targetItem, range, replacement) {
                                        if (!range || !replacement || !hInput) return;
                                        var maxLen = hInput.length;
                                        var s = Math.max(0, Math.min(range.start, maxLen));
                                        var e = Math.max(s, Math.min(range.end, maxLen));
                                        hInput.forceActiveFocus();
                                        hInput.select(s, e);
                                        hInput.remove(s, e);
                                        hInput.insert(s, replacement);
                                        root._notifyCellChange(-1, colIndex, hInput.text);
                                        var endPos = s + replacement.length;
                                        hInput.cursorPosition = Math.min(hInput.length, endPos);
                                        headerCell.runSpellCheck();
                                    }

                                    // Modo lectura: Text con RichText y clic en enlaces
                                    Text {
                                        id: hViewText
                                        visible: !headerCell.isCurrentCell
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Inline.inlineToHtml(modelData, {
                                            linkColor: "" + Theme.accent, highlightBg: EditorMetrics.highlightBg,
                                            baseFolder: root.editor ? root.editor.imgBaseFolder : "",
                                            imageSkipMissing: true,
                                            imageExists: root.editor ? root.editor.imageExistsFn : null,
                                            probeTick: NotesService.imageProbeSeq,
                                            searchQuery: root.editor ? root.editor.searchQuery : "",
                                            searchHighlightBg: root.editor ? ("" + root.editor.searchHighlightColor) : "",
                                            searchHighlightActiveBg: (root.editor && root.blockData) ? root.editor.searchActiveBg(root.blockData.bid, colIndex) : "",
                                            searchActiveOrdinal: (root.editor && root.blockData) ? root.editor.searchActiveOrdinal(root.blockData.bid, colIndex) : -1,
                                            searchHighlightActiveFg: (root.editor && root.blockData) ? root.editor.searchActiveFg(root.blockData.bid, colIndex) : ""
                                        })
                                        textFormat: Text.RichText
                                        font.family: Theme.fontFamily
                                        font.pixelSize: EditorMetrics.fs(Theme.fontSizeCaption + 1)
                                        font.bold: true
                                        color: Theme.text
                                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                        horizontalAlignment: root._getAlignment(colIndex)

                                        HoverHandler {
                                            enabled: parent.hoveredLink !== ""
                                            cursorShape: Qt.PointingHandCursor
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            cursorShape: hViewText.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
                                            onClicked: (mouse) => {
                                                if (mouse.button === Qt.RightButton) {
                                                    if (root.editor) {
                                                        root.editor.requestEditBlock(root.blockData.bid);
                                                        root.focusCell(-1, colIndex);
                                                        Qt.callLater(() => {
                                                            var input = root._getCellInput(-1, colIndex);
                                                            if (input) {
                                                                var p = input.positionAt ? input.positionAt(mouse.x, mouse.y) : -1;
                                                                headerCell._openContextMenuAt(input, p, false);
                                                            }
                                                        });
                                                    }
                                                    return;
                                                }
                                                var link = hViewText.linkAt(mouse.x, mouse.y);
                                                if (link && link !== "") {
                                                    if (root.editor && typeof root.editor.handleLink === "function") {
                                                        root.editor.handleLink(link);
                                                    }
                                                    return;
                                                }
                                                if (root.editor) {
                                                    root.editor.requestEditBlock(root.blockData.bid);
                                                    root.focusCell(-1, colIndex);
                                                }
                                            }
                                        }
                                    }

                                    // Modo edición: TextEdit y botón de alternar alineación
                                    RowLayout {
                                        visible: headerCell.isCurrentCell
                                        anchors.fill: parent
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 6
                                        spacing: 4

                                        TextEdit {
                                            id: hInput
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                                            textFormat: TextEdit.PlainText
                                            horizontalAlignment: root._getAlignment(colIndex)
                                            text: (typeof modelData === "string") ? modelData : ""
                                            readOnly: Boolean(root.editor && root.editor.readOnly)
                                            cursorVisible: activeFocus && (!root.editor || !root.editor.readOnly)
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: EditorMetrics.fs(Theme.fontSizeCaption + 1)
                                            font.bold: true
                                            selectByMouse: true
                                            activeFocusOnTab: false
                                            CustomTextCursor {}

                                            SpellOverlay {
                                                id: hSpellOverlay
                                                visible: headerCell.isCurrentCell && root.spellActive && headerCell.spellRanges && headerCell.spellRanges.length > 0
                                                textItem: hInput
                                                ranges: headerCell.spellRanges
                                                active: root.spellActive
                                                waveColor: Theme.color3
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                acceptedButtons: Qt.RightButton
                                                propagateComposedEvents: true
                                                onClicked: (mouse) => {
                                                    if (mouse.button === Qt.RightButton && root.editor && root.editor.contextMenu) {
                                                        hInput.forceActiveFocus();
                                                        var pos = hInput.positionAt(mouse.x, mouse.y);
                                                        headerCell._openContextMenuAt(hInput, pos, false);
                                                    }
                                                }
                                            }

                                            onActiveFocusChanged: {
                                                if (activeFocus) {
                                                    root.focusedRow = -1;
                                                    root.focusedCol = colIndex;
                                                    if (root.spellActive) hSpellTimer.restart();
                                                }
                                            }

                                            onTextEdited: {
                                                root._notifyCellChange(-1, colIndex, hInput.text);
                                                hSpellTimer.restart();
                                            }

                                            Keys.onTabPressed: (event) => root._handleCellTab(-1, colIndex, event)
                                            Keys.onBacktabPressed: (event) => root._handleCellBacktab(-1, colIndex, event)
                                            Keys.onReturnPressed: (event) => {
                                                if (event.modifiers & Qt.ShiftModifier) {
                                                    hInput.insert(hInput.cursorPosition, "<br>");
                                                    event.accepted = true;
                                                } else {
                                                    root._handleCellReturn(-1, colIndex, event);
                                                }
                                            }
                                            Keys.onEnterPressed: (event) => {
                                                if (event.modifiers & Qt.ShiftModifier) {
                                                    hInput.insert(hInput.cursorPosition, "<br>");
                                                    event.accepted = true;
                                                } else {
                                                    root._handleCellReturn(-1, colIndex, event);
                                                }
                                            }
                                            Keys.onUpPressed: (event) => {
                                                var curRect = hInput.positionToRectangle(hInput.cursorPosition);
                                                if (curRect.y <= 2) {
                                                    root._handleCellUp(-1, colIndex, event);
                                                } else {
                                                    event.accepted = false;
                                                }
                                            }
                                            Keys.onDownPressed: (event) => {
                                                var curRect = hInput.positionToRectangle(hInput.cursorPosition);
                                                if (curRect.y + curRect.height >= hInput.paintedHeight - 3) {
                                                    root._handleCellDown(-1, colIndex, event);
                                                } else {
                                                    event.accepted = false;
                                                }
                                            }
                                            Keys.onLeftPressed: (event) => root._handleCellLeft(-1, colIndex, hInput, event)
                                            Keys.onRightPressed: (event) => root._handleCellRight(-1, colIndex, hInput, event)
                                            Keys.onEscapePressed: (event) => root._handleCellEscape(event)
                                            Keys.onPressed: (event) => {
                                                if (event.key === Qt.Key_Menu || ((event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_F10)) {
                                                    headerCell._openContextMenuAt(hInput, hInput.cursorPosition, true);
                                                    event.accepted = true;
                                                    return;
                                                }
                                                root._handleCellSpecialKeys(event);
                                            }
                                        }

                                Rectangle {
                                    visible: !root.isReadOnly
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: 4
                                    color: alignMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12) : "transparent"

                                    Image {
                                        anchors.centerIn: parent
                                        width: 14; height: 14
                                        source: root._getAlignIcon(colIndex)
                                        sourceSize: Qt.size(14, 14)
                                        opacity: root._getAlign(colIndex) === "none" ? 0.4 : 0.9
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            colorization: 1.0
                                            colorizationColor: Theme.accent
                                        }
                                    }

                                    MouseArea {
                                        id: alignMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.toggleAlignment(colIndex);
                                            hInput.forceActiveFocus();
                                        }
                                    }

                                    EditorToolTip {
                                        label: {
                                            var a = root._getAlign(colIndex);
                                            if (a === "center") return I18n.t("notes.align_center", "Alineación: centro");
                                            if (a === "right") return I18n.t("notes.align_right", "Alineación: derecha");
                                            if (a === "left") return I18n.t("notes.align_left", "Alineación: izquierda");
                                            return I18n.t("notes.align_none", "Alineación: predeterminada");
                                        }
                                        show: alignMa.containsMouse
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Filas de datos
            Repeater {
                id: rowsRepeater
                model: root.parsedTable ? root.parsedTable.rows : []

                delegate: Rectangle {
                    id: rowRect
                    readonly property int rowIndex: index
                    width: root.tableColWidth
                    readonly property real minRowHeight: Math.max(34, Math.round(34 * (EditorMetrics.zoom || 1.0)))
                    property real maxContentHeight: minRowHeight
                    height: Math.max(minRowHeight, maxContentHeight)
                    color: rowIndex % 2 === 1 ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.03) : "transparent"

                    function updateRowHeight() {
                        var maxH = minRowHeight;
                        for (var c = 0; c < cellRepeater.count; c++) {
                            var it = cellRepeater.itemAt(c);
                            if (it && typeof it.cellHeight === "number") {
                                if (it.cellHeight > maxH) maxH = it.cellHeight;
                            }
                        }
                        if (rowRect.maxContentHeight !== maxH) {
                            rowRect.maxContentHeight = maxH;
                        }
                    }

                    function getCellDelegate(c) {
                        return cellRepeater.itemAt(c);
                    }

                    Row {
                        anchors.fill: parent

                        Repeater {
                            id: cellRepeater
                            model: modelData

                            delegate: Rectangle {
                                id: dataCell
                                property int colIndex: index
                                property alias textInput: cellInput
                                readonly property bool isCurrentCell: root.isEditing && root.focusedRow === rowRect.rowIndex && root.focusedCol === colIndex
                                property var spellRanges: []
                                width: root.colWidth
                                height: rowRect.height
                                color: "transparent"
                                border.color: isCurrentCell ? Theme.accent : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)
                                border.width: isCurrentCell ? 1.5 : 1

                                readonly property real cellHeight: Math.max(rowRect.minRowHeight, (isCurrentCell ? cellInput.paintedHeight : cellViewText.paintedHeight) + 14)
                                onCellHeightChanged: rowRect.updateRowHeight()
                                Component.onCompleted: rowRect.updateRowHeight()

                                Timer {
                                    id: cellSpellTimer
                                    interval: 300
                                    repeat: false
                                    onTriggered: dataCell.runSpellCheck()
                                }

                                onIsCurrentCellChanged: {
                                    if (isCurrentCell && root.spellActive) {
                                        cellSpellTimer.restart();
                                    } else {
                                        dataCell.spellRanges = [];
                                    }
                                }

                                function runSpellCheck() {
                                    if (!root.spellActive || root._isDestroyed || typeof SpellService === "undefined" || !SpellService.available) {
                                        dataCell.spellRanges = [];
                                        return;
                                    }
                                    var plain = cellInput ? cellInput.text : "";
                                    if (!plain || plain.trim() === "") {
                                        dataCell.spellRanges = [];
                                        return;
                                    }
                                    var tokens = SpellLogic.tokenize(plain, {
                                        ignoreUppercase: (typeof SpellConfig !== "undefined") ? SpellConfig.ignoreUppercase : true,
                                        ignoreWithDigits: (typeof SpellConfig !== "undefined") ? SpellConfig.ignoreWithDigits : true,
                                        ignoreCamelCase: (typeof SpellConfig !== "undefined") ? SpellConfig.ignoreCamelCase : true,
                                        ignoreSnakeCase: (typeof SpellConfig !== "undefined") ? SpellConfig.ignoreSnakeCase : true
                                    });
                                    if (tokens.length === 0) {
                                        dataCell.spellRanges = [];
                                        return;
                                    }
                                    var words = tokens.map(function(t) { return t.word; });
                                    SpellService.checkWordsBatch(words, function(results) {
                                        if (root._isDestroyed || !dataCell) return;
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
                                        dataCell.spellRanges = badRanges;
                                        if (cellSpellOverlay) cellSpellOverlay.requestUpdate();
                                    }, root);
                                }

                                function _openContextMenuAt(targetItem, clickPos, fromKeyboard) {
                                    if (!root.editor || !root.editor.contextMenu) return;
                                    var pos = (clickPos !== undefined && clickPos >= 0) ? clickPos : (cellInput ? cellInput.cursorPosition : -1);
                                    var err = (root.spellActive && (!root.editor || !root.editor.readOnly)) ? SpellLogic.findRangeAt(dataCell.spellRanges, pos) : null;
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
                                                            dataCell._replaceWordAtRange(targetItem, err, formattedSug);
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

                                function _replaceWordAtRange(targetItem, range, replacement) {
                                    if (!range || !replacement || !cellInput) return;
                                    var maxLen = cellInput.length;
                                    var s = Math.max(0, Math.min(range.start, maxLen));
                                    var e = Math.max(s, Math.min(range.end, maxLen));
                                    cellInput.forceActiveFocus();
                                    cellInput.select(s, e);
                                    cellInput.remove(s, e);
                                    cellInput.insert(s, replacement);
                                    root._notifyCellChange(rowRect.rowIndex, colIndex, cellInput.text);
                                    var endPos = s + replacement.length;
                                    cellInput.cursorPosition = Math.min(cellInput.length, endPos);
                                    dataCell.runSpellCheck();
                                }

                                // Modo lectura: RichText con detección de enlaces y wrap multilínea
                                Text {
                                    id: cellViewText
                                    visible: !dataCell.isCurrentCell
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Inline.inlineToHtml(modelData, {
                                        linkColor: "" + Theme.accent, highlightBg: EditorMetrics.highlightBg,
                                        baseFolder: root.editor ? root.editor.imgBaseFolder : "",
                                        imageSkipMissing: true,
                                        imageExists: root.editor ? root.editor.imageExistsFn : null,
                                        probeTick: NotesService.imageProbeSeq,
                                        searchQuery: root.editor ? root.editor.searchQuery : "",
                                        searchHighlightBg: root.editor ? ("" + root.editor.searchHighlightColor) : "",
                                        searchHighlightActiveBg: (root.editor && root.blockData && root.parsedTable) ? root.editor.searchActiveBg(root.blockData.bid, root.parsedTable.headers.length + rowRect.rowIndex * root.parsedTable.headers.length + colIndex) : "",
                                        searchActiveOrdinal: (root.editor && root.blockData && root.parsedTable) ? root.editor.searchActiveOrdinal(root.blockData.bid, root.parsedTable.headers.length + rowRect.rowIndex * root.parsedTable.headers.length + colIndex) : -1,
                                        searchHighlightActiveFg: (root.editor && root.blockData && root.parsedTable) ? root.editor.searchActiveFg(root.blockData.bid, root.parsedTable.headers.length + rowRect.rowIndex * root.parsedTable.headers.length + colIndex) : ""
                                    })
                                    textFormat: Text.RichText
                                    font.family: Theme.fontFamily
                                    font.pixelSize: EditorMetrics.caption
                                    color: Theme.text
                                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                    horizontalAlignment: root._getAlignment(colIndex)

                                    HoverHandler {
                                        enabled: parent.hoveredLink !== ""
                                        cursorShape: Qt.PointingHandCursor
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        cursorShape: cellViewText.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
                                        onClicked: (mouse) => {
                                            if (mouse.button === Qt.RightButton) {
                                                if (root.editor) {
                                                    root.editor.requestEditBlock(root.blockData.bid);
                                                    root.focusCell(rowRect.rowIndex, colIndex);
                                                    Qt.callLater(() => {
                                                        var input = root._getCellInput(rowRect.rowIndex, colIndex);
                                                        if (input) {
                                                            var p = input.positionAt ? input.positionAt(mouse.x, mouse.y) : -1;
                                                            dataCell._openContextMenuAt(input, p, false);
                                                        }
                                                    });
                                                }
                                                return;
                                            }
                                            var link = cellViewText.linkAt(mouse.x, mouse.y);
                                            if (link && link !== "") {
                                                if (root.editor && typeof root.editor.handleLink === "function") {
                                                    root.editor.handleLink(link);
                                                }
                                                return;
                                            }
                                            if (root.editor) {
                                                root.editor.requestEditBlock(root.blockData.bid);
                                                root.focusCell(rowRect.rowIndex, colIndex);
                                            }
                                        }
                                    }
                                }

                                // Modo edición: TextEdit interactivo con wrap multilínea
                                TextEdit {
                                    id: cellInput
                                    visible: dataCell.isCurrentCell
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    horizontalAlignment: root._getAlignment(colIndex)
                                    wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                                    textFormat: TextEdit.PlainText
                                    text: (typeof modelData === "string") ? modelData : ""
                                    readOnly: Boolean(root.editor && root.editor.readOnly)
                                    cursorVisible: activeFocus && (!root.editor || !root.editor.readOnly)
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: EditorMetrics.caption
                                    selectByMouse: true
                                    activeFocusOnTab: false
                                    CustomTextCursor {}

                                    SpellOverlay {
                                        id: cellSpellOverlay
                                        visible: dataCell.isCurrentCell && root.spellActive && dataCell.spellRanges && dataCell.spellRanges.length > 0
                                        textItem: cellInput
                                        ranges: dataCell.spellRanges
                                        active: root.spellActive
                                        waveColor: Theme.color3
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.RightButton
                                        propagateComposedEvents: true
                                        onClicked: (mouse) => {
                                            if (mouse.button === Qt.RightButton && root.editor && root.editor.contextMenu) {
                                                cellInput.forceActiveFocus();
                                                var pos = cellInput.positionAt(mouse.x, mouse.y);
                                                dataCell._openContextMenuAt(cellInput, pos, false);
                                            }
                                        }
                                    }

                                    onActiveFocusChanged: {
                                        if (activeFocus) {
                                            root.focusedRow = rowRect.rowIndex;
                                            root.focusedCol = colIndex;
                                            if (root.spellActive) cellSpellTimer.restart();
                                        }
                                    }

                                    onTextEdited: {
                                        root._notifyCellChange(rowRect.rowIndex, colIndex, cellInput.text);
                                        cellSpellTimer.restart();
                                    }

                                    Keys.onTabPressed: (event) => root._handleCellTab(rowRect.rowIndex, colIndex, event)
                                    Keys.onBacktabPressed: (event) => root._handleCellBacktab(rowRect.rowIndex, colIndex, event)
                                    Keys.onReturnPressed: (event) => {
                                        if (event.modifiers & Qt.ShiftModifier) {
                                            cellInput.insert(cellInput.cursorPosition, "<br>");
                                            event.accepted = true;
                                        } else {
                                            root._handleCellReturn(rowRect.rowIndex, colIndex, event);
                                        }
                                    }
                                    Keys.onEnterPressed: (event) => {
                                        if (event.modifiers & Qt.ShiftModifier) {
                                            cellInput.insert(cellInput.cursorPosition, "<br>");
                                            event.accepted = true;
                                        } else {
                                            root._handleCellReturn(rowRect.rowIndex, colIndex, event);
                                        }
                                    }
                                    Keys.onUpPressed: (event) => {
                                        var curRect = cellInput.positionToRectangle(cellInput.cursorPosition);
                                        if (curRect.y <= 2) {
                                            root._handleCellUp(rowRect.rowIndex, colIndex, event);
                                        } else {
                                            event.accepted = false;
                                        }
                                    }
                                    Keys.onDownPressed: (event) => {
                                        var curRect = cellInput.positionToRectangle(cellInput.cursorPosition);
                                        if (curRect.y + curRect.height >= cellInput.paintedHeight - 3) {
                                            root._handleCellDown(rowRect.rowIndex, colIndex, event);
                                        } else {
                                            event.accepted = false;
                                        }
                                    }
                                    Keys.onLeftPressed: (event) => root._handleCellLeft(rowRect.rowIndex, colIndex, cellInput, event)
                                    Keys.onRightPressed: (event) => root._handleCellRight(rowRect.rowIndex, colIndex, cellInput, event)
                                    Keys.onEscapePressed: (event) => root._handleCellEscape(event)
                                    Keys.onPressed: (event) => {
                                        if (event.key === Qt.Key_Menu || ((event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_F10)) {
                                            dataCell._openContextMenuAt(cellInput, cellInput.cursorPosition, true);
                                            event.accepted = true;
                                            return;
                                        }
                                        root._handleCellSpecialKeys(event);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Puntito lateral derecho para agregar/quitar columna (dentro del flickable al extremo derecho de la tabla)
        Rectangle {
            id: addColDot
            visible: !root.isReadOnly
            anchors.left: tableCol.right
            anchors.leftMargin: 6
            anchors.verticalCenter: tableCol.verticalCenter
            width: 22
            height: 22
            radius: 11
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)

            Rectangle {
                anchors.centerIn: parent
                width: 6; height: 6; radius: 3
                color: Theme.accent
            }

            MouseArea {
                id: addColMa
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                    if (root.editor && root.editor.tooltipLayer) {
                        root.editor.tooltipLayer.showTooltip(addColDot, I18n.t("notes.table_dots_hint", "Click: agregar · Click derecho: quitar"), "");
                    }
                }
                onExited: {
                    if (root.editor && root.editor.tooltipLayer) {
                        root.editor.tooltipLayer.hideTooltip();
                    }
                }
                onClicked: (mouse) => {
                    if (root.editor && root.editor.tooltipLayer) {
                        root.editor.tooltipLayer.hideTooltip();
                    }
                    if (root.isReadOnly || !root._activeTable) return;
                    if (mouse.button === Qt.LeftButton) {
                        root.addNewCol();
                    } else if (mouse.button === Qt.RightButton) {
                        root.removeColAt(root._activeTable.headers.length - 1);
                    }
                }
            }

            EditorToolTip {
                label: I18n.t("notes.table_dots_hint", "Click: agregar · Click derecho: quitar")
                show: addColMa.containsMouse && (!root.editor || !root.editor.tooltipLayer)
            }
        }
    } // tableContentItem
} // tableFlickable

        // ── Puntito interactivo inferior para agregar/quitar fila ──
        Rectangle {
            id: addRowDot
            visible: !root.isReadOnly
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: tableFlickable.bottom
            anchors.topMargin: 4
            width: 22
            height: 22
            radius: 11
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)

            Rectangle {
                anchors.centerIn: parent
                width: 6; height: 6; radius: 3
                color: Theme.accent
            }

            MouseArea {
                id: addRowMa
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                    if (root.editor && root.editor.tooltipLayer) {
                        root.editor.tooltipLayer.showTooltip(addRowDot, I18n.t("notes.table_dots_hint", "Click: agregar · Click derecho: quitar"), "");
                    }
                }
                onExited: {
                    if (root.editor && root.editor.tooltipLayer) {
                        root.editor.tooltipLayer.hideTooltip();
                    }
                }
                onClicked: (mouse) => {
                    if (root.editor && root.editor.tooltipLayer) {
                        root.editor.tooltipLayer.hideTooltip();
                    }
                    if (root.isReadOnly || !root._activeTable) return;
                    if (mouse.button === Qt.LeftButton) {
                        root.addNewRow();
                    } else if (mouse.button === Qt.RightButton) {
                        root.removeRowAt(root._activeTable.rows.length - 1);
                    }
                }
            }

            EditorToolTip {
                label: I18n.t("notes.table_dots_hint", "Click: agregar · Click derecho: quitar")
                show: addRowMa.containsMouse && (!root.editor || !root.editor.tooltipLayer)
            }
        }
    }

    // Modo de edición cruda como respaldo si la tabla no se puede parsear
    TextEdit {
        id: rawEditor
        visible: root.parsedTable === null
        width: parent.width
        textFormat: TextEdit.PlainText
        text: (root.blockData && typeof root.blockData.raw === "string") ? root.blockData.raw : ""
        readOnly: Boolean(root.editor && root.editor.readOnly)
        cursorVisible: activeFocus && (!root.editor || !root.editor.readOnly)
        color: Theme.text
        font.family: Theme.fontFamilyMonospace || "monospace"
        font.pixelSize: EditorMetrics.fs(Theme.fontSizeCaption + 1)
        wrapMode: TextEdit.NoWrap
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

        Keys.onLeftPressed: (event) => {
            if (event.modifiers & Qt.ShiftModifier) {
                event.accepted = false;
                return;
            }
            if (rawEditor.cursorPosition === 0 && rawEditor.selectionStart === rawEditor.selectionEnd) {
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
                    rawEditor.forceActiveFocus();
                    root.editor.contextMenu.open(rawEditor);
                }
            }
        }
    }
}
