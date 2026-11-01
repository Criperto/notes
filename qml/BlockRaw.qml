import QtQuick
import Notas
import "Inline.js" as Inline
import "."

Item {
    id: root

    property var blockData: null
    property bool isEditing: false
    property var editor: null
    property bool isSelected: false
    property bool inViewportChunk: true

    implicitWidth: parent ? parent.width : 400
    // F24: misma altura en vista y edición.
    implicitHeight: (isEditing || isSelected) ? (editInput.paintedHeight + 10) : (viewText.paintedHeight + 10)

    function selectRange(start, end) {
        if (!editInput) return;
        var s = Math.max(0, Math.min(editInput.length, Math.min(start, end)));
        var e = Math.max(0, Math.min(editInput.length, Math.max(start, end)));
        editInput.select(s, e);
    }

    function selectAllText() {
        if (!editInput) return;
        editInput.selectAll();
    }

    function clearTextSelection() {
        if (!editInput) return;
        editInput.deselect();
    }

    function getCharPosAt(lx, ly) {
        if (!editInput) return 0;
        return editInput.positionAt(lx, ly);
    }

    function getTextLength() {
        if (!editInput) return 0;
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
            return Inline.plainText(editInput);
        }
        return root.blockData ? (root.blockData.raw || "") : "";
    }

    function commitInlineSubEdit(textEdit, newPlain, selStart, selEnd) {
        if (root.editor && root.blockData) {
            root.editor.onBlockRawChanged(root.blockData.bid, newPlain);
        }
        if (textEdit && typeof selStart === "number" && typeof selEnd === "number") {
            textEdit.select(selStart, selEnd);
        }
    }

    function getTextEdit() {
        return editInput;
    }

    function focusInput(cursorPos) {
        if (editInput) {
            editInput.forceActiveFocus();
            if (editInput.selectionStart !== editInput.selectionEnd) return;
            if (typeof cursorPos === "object" && cursorPos !== null) {
                if (cursorPos.fromBottom) {
                    var lastRect = editInput.positionToRectangle(editInput.length);
                    var targetY = Math.max(0, lastRect.y + (lastRect.height / 2));
                    editInput.cursorPosition = editInput.positionAt(cursorPos.x !== undefined ? cursorPos.x : 0, targetY);
                } else {
                    var firstRect = editInput.positionToRectangle(0);
                    var targetY0 = Math.max(0, firstRect.y + (firstRect.height / 2));
                    editInput.cursorPosition = editInput.positionAt(cursorPos.x !== undefined ? cursorPos.x : 0, targetY0);
                }
            } else if (cursorPos !== undefined && cursorPos >= 0) {
                editInput.cursorPosition = Math.min(editInput.text.length, cursorPos);
            } else {
                editInput.cursorPosition = editInput.text.length;
            }
        }
    }

    Text {
        id: viewText
        visible: !root.isEditing && !root.isSelected
        width: parent.width
        textFormat: Text.RichText
        // El raw también pinta resaltado (escape + highlight, como BlockCode) para
        // que el contador N de búsqueda incluya lo que realmente se ve
        text: (root.blockData && root.editor && root.editor.searchQuery)
            ? Inline.highlightInHtml(Inline.escapeHtml(root.blockData.raw || ""), root.editor.searchQuery, "" + root.editor.searchHighlightColor,
                root.editor.searchActiveBg(root.blockData.bid, 0),
                root.editor.searchActiveOrdinal(root.blockData.bid, 0),
                root.editor.searchActiveFg(root.blockData.bid, 0))
            : (root.blockData ? Inline.escapeHtml(root.blockData.raw || "") : "")
        color: Theme.text
        font.family: Theme.fontFamilyMonospace || "monospace"
        font.pixelSize: EditorMetrics.body
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        lineHeight: EditorMetrics.lineHeight

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor
            onClicked: {
                if (root.editor) {
                    root.editor.requestEditBlock(root.blockData.bid);
                }
            }
        }
    }

    TextEdit {
        id: editInput
        visible: root.isEditing || root.isSelected
        readOnly: !root.isEditing || (root.editor && root.editor.readOnly)
        cursorVisible: activeFocus && root.isEditing && (!root.editor || !root.editor.readOnly)
        width: parent.width
        textFormat: TextEdit.PlainText
        text: (root.blockData && typeof root.blockData.raw === "string") ? root.blockData.raw : ""
        color: Theme.text
        font.family: Theme.fontFamilyMonospace || "monospace"
        font.pixelSize: EditorMetrics.body
        wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
        selectByMouse: true
        activeFocusOnTab: false
        CustomTextCursor {}

        onTextChanged: {
            if (root.editor && root.editor.readOnly) return;
            if (root.isEditing && root.editor && root.blockData) {
                root.editor.onBlockRawChanged(root.blockData.bid, editInput.text);
            }
        }

        Keys.onUpPressed: (event) => {
            if (event.modifiers & Qt.ShiftModifier) {
                event.accepted = false;
                return;
            }
            var curY = editInput.positionToRectangle(editInput.cursorPosition).y;
            var topY = editInput.positionToRectangle(0).y;
            if (curY <= topY + 2) {
                if (root.editor && root.blockData) {
                    var curX = editInput.positionToRectangle(editInput.cursorPosition).x;
                    root.editor.preferredCursorX = curX;
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
            var curYDown = editInput.positionToRectangle(editInput.cursorPosition).y;
            var botYDown = editInput.positionToRectangle(editInput.length).y;
            if (curYDown >= botYDown - 2) {
                if (root.editor && root.blockData) {
                    var curXDown = editInput.positionToRectangle(editInput.cursorPosition).x;
                    root.editor.preferredCursorX = curXDown;
                    root.editor.focusNextBlock(root.blockData.bid);
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            } else {
                event.accepted = false;
            }
        }

        Keys.onReturnPressed: (event) => {
            if (event.modifiers & Qt.ControlModifier) {
                if (root.editor) {
                    root.editor.confirmActiveBlock();
                    event.accepted = true;
                }
            } else {
                editInput.insert(editInput.cursorPosition, "\n");
                event.accepted = true;
            }
        }

        Keys.onEnterPressed: (event) => {
            Keys.onReturnPressed(event);
        }

        Keys.onPressed: (event) => {
            if ((event.modifiers & Qt.ControlModifier) && !event.isAutoRepeat) {
                if (event.key === Qt.Key_Z && !(event.modifiers & Qt.ShiftModifier)) {
                    if (root.editor && typeof root.editor.undo === "function") { root.editor.undo(); event.accepted = true; return; }
                } else if (event.key === Qt.Key_Y || (event.key === Qt.Key_Z && (event.modifiers & Qt.ShiftModifier))) {
                    if (root.editor && typeof root.editor.redo === "function") { root.editor.redo(); event.accepted = true; return; }
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
            if (editInput.cursorPosition === editInput.text.length && editInput.selectionStart === editInput.selectionEnd) {
                if (root.editor && typeof root.editor.handleBlockDeleteAtEnd === "function") {
                    root.editor.handleBlockDeleteAtEnd(root.blockData.bid);
                    event.accepted = true;
                }
            }
        }

        Keys.onLeftPressed: (event) => {
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
            if (event.modifiers & Qt.ShiftModifier) {
                event.accepted = false;
                return;
            }
            if (editInput.cursorPosition === editInput.text.length && editInput.selectionStart === editInput.selectionEnd) {
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
