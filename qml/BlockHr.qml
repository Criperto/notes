import QtQuick
import Notas
import "."

Item {
    id: root

    property var blockData: null
    property bool isEditing: false
    property var editor: null
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

    implicitWidth: parent ? parent.width : 400
    implicitHeight: (isEditing && (!root.editor || !root.editor.readOnly)) ? (editInput.paintedHeight + 16) : 24

    function getTextEdit() {
        return editInput;
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
        if (root.editor && root.editor.readOnly) return;
        if (editInput) {
            editInput.forceActiveFocus();
            if (typeof cursorPos === "object" && cursorPos !== null) {
                if (cursorPos.x !== undefined) {
                    editInput.cursorPosition = editInput.positionAt(cursorPos.x, 0);
                } else {
                    editInput.cursorPosition = editInput.length;
                }
            } else if (typeof cursorPos === "number") {
                editInput.cursorPosition = Math.max(0, Math.min(editInput.text.length, cursorPos));
            } else {
                editInput.cursorPosition = editInput.text.length;
            }
        }
    }

    // Línea horizontal visible cuando no está en edición (o en modo solo lectura)
    Rectangle {
        id: line
        visible: !root.isEditing || (root.editor && root.editor.readOnly)
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 1
        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.15)

        MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            enabled: !root.editor || !root.editor.readOnly
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (root.editor && !root.editor.readOnly) {
                    root.editor.requestEditBlock(root.blockData.bid);
                }
            }
        }
    }

    // Vista de edición cruda (---)
    TextEdit {
        id: editInput
        visible: root.isEditing && (!root.editor || !root.editor.readOnly)
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        textFormat: TextEdit.PlainText
        text: (root.blockData && typeof root.blockData.raw === "string") ? root.blockData.raw : "---"
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: EditorMetrics.caption
        wrapMode: TextEdit.NoWrap
        selectByMouse: true
        CustomTextCursor {}

        onTextChanged: {
            if (root.isEditing && root.editor && root.blockData) {
                root.editor.onBlockRawChanged(root.blockData.bid, editInput.text);
            }
        }

        Keys.onUpPressed: (event) => {
            if (root.editor && root.blockData) {
                var curX = editInput.positionToRectangle(editInput.cursorPosition).x;
                root.editor.preferredCursorX = curX;
                root.editor.focusPreviousBlock(root.blockData.bid);
                event.accepted = true;
            }
        }

        Keys.onDownPressed: (event) => {
            if (root.editor && root.blockData) {
                var curXDown = editInput.positionToRectangle(editInput.cursorPosition).x;
                root.editor.preferredCursorX = curXDown;
                root.editor.focusNextBlock(root.blockData.bid);
                event.accepted = true;
            }
        }

        Keys.onReturnPressed: (event) => {
            if (root.editor) {
                root.editor.handleBlockEnter(root.blockData.bid, editInput.cursorPosition);
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
                if (editInput.cursorPosition === 0) {
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
    }
}
