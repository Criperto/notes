import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Controls
import Notas
import "Inline.js" as Inline
import "MermaidParser.js" as MermaidParser
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

    readonly property bool isReadOnly: Boolean(
        (root.editor && root.editor.readOnly) ||
        (NotesService.activeNote && NotesService.activeNote.readOnly) ||
        (root.editor && root.editor.editorModal && root.editor.editorModal.isPreviewMode)
    )

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

    readonly property string diagramType: {
        var d = MermaidParser.detect(pureCodeText);
        return d.type || "mermaid";
    }

    implicitWidth: parent ? parent.width : 400
    implicitHeight: {
        var base = headerRow.height + 24;
        if (root.isEditing) {
            return base + mermaidView.implicitHeight + editInput.paintedHeight + 40;
        }
        return base + mermaidView.implicitHeight;
    }

    radius: 10
    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04)
    border.color: (root.isEditing || root.isSelected) ? Theme.accent : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
    border.width: (root.isEditing || root.isSelected) ? 1.5 : 1

    property bool _syncingModel: false

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
        if (!editInput) return;
        _syncTextFromModel();
        var s = Math.max(0, Math.min(editInput.length, Math.min(start, end)));
        var e = Math.max(0, Math.min(editInput.length, Math.max(start, end)));
        editInput.select(s, e);
    }

    function selectAllText() {
        if (!editInput) return;
        _syncTextFromModel();
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

    onBlockDataChanged: {
        if (!root.isEditing) _syncTextFromModel();
    }

    onIsEditingChanged: {
        if (root.isEditing) {
            _syncTextFromModel();
        }
    }

    Component.onCompleted: {
        if (root.isEditing) _syncTextFromModel();
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
        if (!root.isEditing && root.editor && root.blockData) {
            root.editor.requestEditBlock(root.blockData.bid, cursorPos);
            return;
        }
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

    Column {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        // Cabecera superior con insignia de tipo y botones de acción
        RowLayout {
            id: headerRow
            width: parent.width
            height: 24

            RowLayout {
                spacing: 6
                Layout.fillWidth: true

                Image {
                    width: 14; height: 14
                    source: Theme.iconsPath + "diagram.svg"
                    sourceSize: Qt.size(14, 14)
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: Theme.accent
                    }
                }

                Text {
                    text: "mermaid · " + root.diagramType
                    color: Theme.muted
                    font.family: "monospace"
                    font.pixelSize: EditorMetrics.caption
                }
            }

            // Botones alineados a la derecha: sólo "Listo" muestra texto
            RowLayout {
                spacing: 6
                Layout.alignment: Qt.AlignRight

                // Botón Listo (sólo en modo edición: icono + texto "Listo")
                Rectangle {
                    id: doneBtn
                    visible: root.isEditing && !root.isReadOnly
                    Layout.preferredWidth: doneBtnRow.implicitWidth + 14
                    Layout.preferredHeight: 24
                    radius: 6
                    color: doneMa.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                                                : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, doneMa.containsMouse ? 0.45 : 0.25)
                    border.width: 1

                    RowLayout {
                        id: doneBtnRow
                        anchors.centerIn: parent
                        spacing: 5

                        Image {
                            Layout.preferredWidth: 12
                            Layout.preferredHeight: 12
                            source: Theme.iconsPath + "check.svg"
                            sourceSize: Qt.size(12, 12)
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: Theme.accent
                            }
                        }

                        Text {
                            text: I18n.t("notes.mermaid.done", "Listo")
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.bold: true
                            font.pixelSize: EditorMetrics.fs(Theme.fontSizeCaption - 1)
                        }
                    }

                    MouseArea {
                        id: doneMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.editor) root.editor.confirmActiveBlock();
                        }
                    }
                }

                // Botón Editar (sólo en reposo: sólo icono)
                Rectangle {
                    id: editBtn
                    visible: !root.isEditing && !root.isReadOnly
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 24
                    radius: 6
                    color: editMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12)
                                                : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)

                    Image {
                        anchors.centerIn: parent
                        width: 13; height: 13
                        source: Theme.iconsPath + "edit.svg"
                        sourceSize: Qt.size(13, 13)
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: editMa.containsMouse ? Theme.accent : Theme.muted
                        }
                    }

                    MouseArea {
                        id: editMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            if (root.editor && root.editor.tooltipLayer) {
                                root.editor.tooltipLayer.showTooltip(editBtn, I18n.t("notes.mermaid.edit", "Editar"), "");
                            }
                        }
                        onExited: {
                            if (root.editor && root.editor.tooltipLayer) root.editor.tooltipLayer.hideTooltip();
                        }
                        onClicked: {
                            if (root.editor && root.editor.tooltipLayer) root.editor.tooltipLayer.hideTooltip();
                            if (root.editor && root.blockData) {
                                root.editor.requestEditBlock(root.blockData.bid);
                            }
                        }
                    }
                }

                // Botón Copiar código (sólo icono)
                Rectangle {
                    id: copyBtn
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 24
                    radius: 6
                    color: copyMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12)
                                                : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)

                    Image {
                        anchors.centerIn: parent
                        width: 13; height: 13
                        source: Theme.iconsPath + (root.copiedRecently ? "check.svg" : "content-copy.svg")
                        sourceSize: Qt.size(13, 13)
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: root.copiedRecently ? Theme.success : (copyMa.containsMouse ? Theme.accent : Theme.muted)
                        }
                    }

                    MouseArea {
                        id: copyMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            if (root.editor && root.editor.tooltipLayer) {
                                root.editor.tooltipLayer.showTooltip(copyBtn,
                                    root.copiedRecently ? I18n.t("notes.editor.copied", "Copiado")
                                                        : I18n.t("notes.mermaid.copy_code", "Copiar código"), "");
                            }
                        }
                        onExited: {
                            if (root.editor && root.editor.tooltipLayer) root.editor.tooltipLayer.hideTooltip();
                        }
                        onClicked: {
                            if (root.editor && typeof root.editor.copyText === "function") {
                                root.editor.copyText(root.pureCodeText);
                            } else {
                                if (typeof Quickshell !== "undefined" && typeof Quickshell.clipboardText !== "undefined") {
                                    Quickshell.clipboardText = root.pureCodeText;
                                }
                                if (typeof Sys === "undefined" || typeof Sys.hasCommand !== "function" || Sys.hasCommand("wl-copy")) {
                                    Quickshell.execDetached(["wl-copy", "--", root.pureCodeText]);
                                }
                            }
                            root.copiedRecently = true;
                            copiedTimer.restart();
                            if (root.editor && root.editor.tooltipLayer) {
                                root.editor.tooltipLayer.showTooltip(copyBtn, I18n.t("notes.editor.copied", "Copiado"), "");
                            }
                        }
                    }
                }

                // Botón Eliminar diagrama (sólo icono)
                Rectangle {
                    id: delBtn
                    visible: !root.isEditing && !root.isReadOnly
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 24
                    radius: 6
                    color: delMa.containsMouse ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.2)
                                               : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)

                    Image {
                        anchors.centerIn: parent
                        width: 13; height: 13
                        source: Theme.iconsPath + "delete.svg"
                        sourceSize: Qt.size(13, 13)
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: delMa.containsMouse ? Theme.danger : Theme.muted
                        }
                    }

                    MouseArea {
                        id: delMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            if (root.editor && root.editor.tooltipLayer) {
                                root.editor.tooltipLayer.showTooltip(delBtn, I18n.t("notes.mermaid.delete", "Eliminar diagrama"), "");
                            }
                        }
                        onExited: {
                            if (root.editor && root.editor.tooltipLayer) root.editor.tooltipLayer.hideTooltip();
                        }
                        onClicked: {
                            if (root.editor && root.editor.tooltipLayer) root.editor.tooltipLayer.hideTooltip();
                            if (root.editor && root.blockData && typeof root.editor.deleteBlock === "function") {
                                root.editor.deleteBlock(root.blockData.bid);
                            }
                        }
                    }
                }
            }
        }

        // Vista vectorial del diagrama Mermaid (Interactiva)
        Item {
            width: parent.width
            height: mermaidView.implicitHeight

            MermaidView {
                id: mermaidView
                anchors.fill: parent
                source: root.pureCodeText
                availableWidth: parent.width
                liveEditMode: root.isEditing
            }

            // Interacción sobre el diagrama en reposo (clic izquierdo: editar; clic derecho: menú contextual)
            MouseArea {
                anchors.fill: parent
                visible: !root.isEditing && !root.isReadOnly
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        if (root.editor && root.editor.contextMenu) {
                            root._syncTextFromModel();
                            var extras = [
                                {
                                    text: I18n.t("notes.mermaid.edit", "Editar"),
                                    onTriggered: function() {
                                        if (root.editor && root.blockData) {
                                            root.editor.requestEditBlock(root.blockData.bid);
                                        }
                                    }
                                },
                                {
                                    text: I18n.t("notes.mermaid.copy_code", "Copiar código"),
                                    onTriggered: function() {
                                        if (root.editor && typeof root.editor.copyText === "function") {
                                            root.editor.copyText(root.pureCodeText);
                                        } else {
                                            if (typeof Quickshell !== "undefined" && typeof Quickshell.clipboardText !== "undefined") {
                                                Quickshell.clipboardText = root.pureCodeText;
                                            }
                                            if (typeof Sys === "undefined" || typeof Sys.hasCommand !== "function" || Sys.hasCommand("wl-copy")) {
                                                Quickshell.execDetached(["wl-copy", "--", root.pureCodeText]);
                                            }
                                        }
                                        root.copiedRecently = true;
                                        copiedTimer.restart();
                                    }
                                },
                                {
                                    text: I18n.t("notes.mermaid.delete", "Eliminar diagrama"),
                                    onTriggered: function() {
                                        if (root.editor && root.blockData && typeof root.editor.deleteBlock === "function") {
                                            root.editor.deleteBlock(root.blockData.bid);
                                        }
                                    }
                                }
                            ];
                            root.editor.contextMenu.open(editInput, extras);
                        }
                    } else {
                        if (root.editor && root.blockData) {
                            root.editor.requestEditBlock(root.blockData.bid);
                        }
                    }
                }
            }
        }

        // Vista de edición de código crudo (visible en modo edición)
        TextEdit {
            id: editInput
            visible: root.isEditing
            readOnly: !root.isEditing || (root.editor && root.editor.readOnly)
            cursorVisible: activeFocus && root.isEditing && (!root.editor || !root.editor.readOnly)
            width: parent.width
            textFormat: TextEdit.PlainText
            text: ""
            color: Theme.text
            font.family: Theme.fontFamilyMonospace || "monospace"
            font.pixelSize: EditorMetrics.fs(Theme.fontSizeCaption + 1)
            wrapMode: TextEdit.NoWrap
            selectByMouse: true
            activeFocusOnTab: false
            CustomTextCursor {}

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
                var ex = BlockModel.fenceExit(editInput.text, editInput.cursorPosition);
                if (ex.exit && root.editor && root.blockData && typeof root.editor.exitFenceBlock === "function") {
                    root._syncingModel = true;
                    editInput.text = ex.raw;
                    root._syncingModel = false;
                    root.editor.exitFenceBlock(root.blockData.bid);
                    event.accepted = true;
                    return;
                }
                editInput.insert(editInput.cursorPosition, "\n");
                event.accepted = true;
            }
            Keys.onEnterPressed: (event) => Keys.onReturnPressed(event)

            Keys.onTabPressed: (event) => {
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
                    editInput.insert(editInput.cursorPosition, "    ");
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

            Keys.onEscapePressed: (event) => {
                var cm = root.editor ? root.editor.contextMenu : null;
                if (cm && cm.visible && !cm.isClosing) {
                    cm.close();
                    event.accepted = true;
                    return;
                }
                if (root.editor) {
                    root.editor.confirmActiveBlock();
                    event.accepted = true;
                }
            }

            Keys.onPressed: (event) => {
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

                // Pegado
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

                // Deshacer / Rehacer
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

                // Backspace al inicio
                if (event.key === Qt.Key_Backspace) {
                    if (editInput.cursorPosition === 0 && editInput.selectionStart === editInput.selectionEnd) {
                        if (root.editor && typeof root.editor.handleBlockBackspaceAtStart === "function" && root.blockData) {
                            root.editor.handleBlockBackspaceAtStart(root.blockData.bid);
                            event.accepted = true;
                        }
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
