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

    readonly property bool isReadOnly: Boolean(
        (root.editor && root.editor.readOnly) ||
        (NotesService.activeNote && NotesService.activeNote.readOnly) ||
        (root.editor && root.editor.editorModal && root.editor.editorModal.isPreviewMode)
    )

    function extractLatexCode(raw) {
        if (!raw || typeof raw !== "string") return "";
        var str = raw.trim();

        // 1. ```math ... ``` o ```latex ... ```
        var fenceMatch = str.match(/^[ \t]*(`{3,}|~{3,})[ \t]*(?:math|latex)?[ \t]*\r?\n([\s\S]*?)\r?\n[ \t]*\1[ \t]*$/i);
        if (fenceMatch) {
            return fenceMatch[2].trim();
        }

        // 2. $$ ... $$
        if (str.startsWith("$$") && str.endsWith("$$") && str.length >= 4) {
            var inner = str.substring(2, str.length - 2).trim();
            return inner;
        }

        return str;
    }

    readonly property string pureCodeText: extractLatexCode(blockData ? blockData.raw : "")

    implicitWidth: parent ? parent.width : 400
    implicitHeight: {
        var base = headerRow.height + 28;
        if (root.isEditing) {
            return base + mathView.implicitHeight + editInput.paintedHeight + templatesScroll.height + 56;
        }
        return base + mathView.implicitHeight;
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
        anchors.margins: 12
        spacing: 10

        // ── Cabecera superior ────────────────────────────────────────────────
        RowLayout {
            id: headerRow
            width: parent.width
            height: 24

            RowLayout {
                spacing: 6
                Layout.fillWidth: true

                Image {
                    width: 14; height: 14
                    source: Theme.iconsPath + "math.svg"
                    sourceSize: Qt.size(14, 14)
                    layer.enabled: visible && !GamemodeService.gamemodeActive
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: Theme.accent
                    }
                }

                Text {
                    text: "LaTeX · Math"
                    color: Theme.muted
                    font.family: "monospace"
                    font.pixelSize: EditorMetrics.caption
                }
            }

            RowLayout {
                spacing: 6
                Layout.alignment: Qt.AlignRight

                // Botón Listo (en modo edición)
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
                            layer.enabled: visible && !GamemodeService.gamemodeActive
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: Theme.accent
                            }
                        }

                        Text {
                            text: I18n.t("notes.math.done", "Listo")
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
                            if (root.editor) {
                                root.editor.confirmActiveBlock();
                            } else {
                                root.isEditing = false;
                            }
                        }
                    }
                }

                // Botón Editar fórmula
                Rectangle {
                    id: editBtn
                    visible: !root.isEditing && !root.isReadOnly
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    radius: 6
                    color: editMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.10) : "transparent"

                    Image {
                        anchors.centerIn: parent
                        width: 14; height: 14
                        source: Theme.iconsPath + "edit.svg"
                        sourceSize: Qt.size(14, 14)
                        layer.enabled: visible && !GamemodeService.gamemodeActive
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: editMa.containsMouse ? Theme.text : Theme.muted
                        }
                    }

                    MouseArea {
                        id: editMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.editor && root.blockData) {
                                root.editor.requestEditBlock(root.blockData.bid);
                            } else {
                                root.isEditing = true;
                            }
                        }
                    }
                }

                // Botón Copiar LaTeX
                Rectangle {
                    id: copyBtn
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    radius: 6
                    color: copyMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.10) : "transparent"

                    Image {
                        anchors.centerIn: parent
                        width: 14; height: 14
                        source: Theme.iconsPath + (root.copiedRecently ? "check.svg" : "content-copy.svg")
                        sourceSize: Qt.size(14, 14)
                        layer.enabled: visible && !GamemodeService.gamemodeActive
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: root.copiedRecently ? Theme.accent : (copyMa.containsMouse ? Theme.text : Theme.muted)
                        }
                    }

                    MouseArea {
                        id: copyMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var textToCopy = root.pureCodeText;
                            if (typeof Sys !== "undefined" && Sys && typeof Sys.setClipboardText === "function") {
                                Sys.setClipboardText(textToCopy);
                            }
                            root.copiedRecently = true;
                            copiedTimer.restart();
                        }
                    }
                }

                // Botón Eliminar bloque
                Rectangle {
                    id: deleteBtn
                    visible: !root.isReadOnly
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    radius: 6
                    color: deleteMa.containsMouse ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.15) : "transparent"

                    Image {
                        anchors.centerIn: parent
                        width: 14; height: 14
                        source: Theme.iconsPath + "delete.svg"
                        sourceSize: Qt.size(14, 14)
                        layer.enabled: visible && !GamemodeService.gamemodeActive
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: deleteMa.containsMouse ? Theme.danger : Theme.muted
                        }
                    }

                    MouseArea {
                        id: deleteMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.editor && root.blockData && typeof root.editor.deleteBlock === "function") {
                                root.editor.deleteBlock(root.blockData.bid);
                            }
                        }
                    }
                }
            }
        }

        // ── Barra de plantillas matemáticas rápidas (modo edición) ───────────
        Flickable {
            id: templatesScroll
            visible: root.isEditing && !root.isReadOnly
            width: parent.width
            height: 28
            contentWidth: templatesRow.implicitWidth
            contentHeight: 28
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: templatesRow
                spacing: 6

                readonly property var mathTemplates: [
                    { label: "Fracción", snippet: "\\frac{a}{b}" },
                    { label: "Raíz", snippet: "\\sqrt{x}" },
                    { label: "Sumatoria", snippet: "\\sum_{i=1}^{n}" },
                    { label: "Integral", snippet: "\\int_{a}^{b} f(x) \\, dx" },
                    { label: "Límite", snippet: "\\lim_{x \\to \\infty}" },
                    { label: "Matriz", snippet: "\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}" },
                    { label: "Casos", snippet: "\\begin{cases} x & \\text{si } x \\ge 0 \\\\ -x & \\text{si } x < 0 \\end{cases}" },
                    { label: "Potencia", snippet: "x^{2}" },
                    { label: "Subíndice", snippet: "x_{i}" },
                    { label: "Griegas", snippet: "\\alpha, \\beta, \\gamma, \\pi, \\theta" }
                ]

                Repeater {
                    model: templatesRow.mathTemplates
                    delegate: Rectangle {
                        height: 24
                        width: tplText.implicitWidth + 14
                        radius: 6
                        color: tplMa.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                                                   : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)
                        border.color: tplMa.containsMouse ? Theme.accent : "transparent"
                        border.width: 1

                        Text {
                            id: tplText
                            anchors.centerIn: parent
                            text: modelData.label
                            color: tplMa.containsMouse ? Theme.accent : Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: EditorMetrics.caption
                        }

                        MouseArea {
                            id: tplMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!editInput) return;
                                var snip = modelData.snippet;
                                var pos = editInput.cursorPosition;
                                editInput.insert(pos, snip);
                                editInput.cursorPosition = pos + snip.length;
                                editInput.forceActiveFocus();
                            }
                        }
                    }
                }
            }
        }

        // ── Input de edición (modo edición) ──────────────────────────────────
        Rectangle {
            id: editContainer
            visible: root.isEditing
            width: parent.width
            implicitHeight: Math.max(70, editInput.paintedHeight + 20)
            radius: 8
            color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.5)
            border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.4)
            border.width: 1

            TextEdit {
                id: editInput
                anchors.fill: parent
                anchors.margins: 10
                font.family: "monospace"
                font.pixelSize: EditorMetrics.fs(Theme.fontSizeBody - 1)
                color: Theme.text
                selectionColor: Theme.accent
                selectedTextColor: Theme.surface
                wrapMode: TextEdit.Wrap
                activeFocusOnPress: true
                cursorDelegate: CustomTextCursor {}

                Keys.onPressed: event => {
                    // Ctrl+Enter o Shift+Enter confirma el bloque
                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier || event.modifiers & Qt.ShiftModifier)) {
                        event.accepted = true;
                        if (root.editor) root.editor.confirmActiveBlock();
                        return;
                    }
                    if (event.key === Qt.Key_Escape) {
                        event.accepted = true;
                        if (root.editor) {
                            root.editor.confirmActiveBlock();
                            if (root.editor.editorModal) {
                                root.editor.editorModal.requestClose();
                            }
                        }
                        return;
                    }
                }

                onTextChanged: {
                    if (root._syncingModel || (root.editor && root.editor.readOnly)) return;
                    if (root.isEditing && root.editor && root.blockData) {
                        var rawClean = Inline.plainText(editInput);
                        if (rawClean !== root.blockData.raw) {
                            root.editor.onBlockRawChanged(root.blockData.bid, rawClean);
                        }
                    }
                }
            }
        }

        // ── Divisor sutil en modo edición antes del preview ──────────────────
        Rectangle {
            visible: root.isEditing
            width: parent.width
            height: 1
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
        }

        // ── MathView (Visualización de la fórmula) ───────────────────────────
        MathView {
            id: mathView
            width: parent.width
            latex: root.isEditing ? root.extractLatexCode(editInput.text) : root.pureCodeText
            display: true
            textColor: Theme.text
            ptSize: EditorMetrics.body
            liveEditMode: root.isEditing

            MouseArea {
                anchors.fill: parent
                enabled: !root.isEditing && !root.isReadOnly
                cursorShape: Qt.PointingHandCursor
                onDoubleClicked: {
                    if (root.editor && root.blockData) {
                        root.editor.requestEditBlock(root.blockData.bid);
                    } else {
                        root.isEditing = true;
                    }
                }
            }
        }
    }
}
