import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Controls
import Notas
import "Inline.js" as Inline
import "HtmlStyleParser.js" as HtmlStyleParser
import "HtmlTemplates.js" as HtmlTemplates
import "ImageProbe.js" as ImageProbe
import "PreviewLogic.js" as PreviewLogic
import "."

// BlockHtml.qml — Renderizador y editor nativo Qt Quick para bloques HTML y CSS básico (sin QtWebEngine).
// Sigue la estética BlockMath / BlockCode en edición y se integra sin marcos invasivos en reposo/preview.
Rectangle {
    id: root

    property var blockData: null
    property bool isEditing: false
    property var editor: null
    property bool copiedRecently: false
    property bool isSelected: false
    property bool inViewportChunk: true
    property bool _isDestroyed: false

    readonly property bool isReadOnly: Boolean(
        (root.editor && root.editor.readOnly) ||
        (NotesService.activeNote && NotesService.activeNote.readOnly) ||
        (root.editor && root.editor.editorModal && root.editor.editorModal.isPreviewMode)
    )

    readonly property string rawSource: blockData ? (blockData.raw || "") : ""
    readonly property string baseFolder: root.editor ? root.editor.imgBaseFolder : ""

    property var _detailsOpenState: ({})
    property var _activePreviewTextEdit: null
    property string _activePreviewUnitId: ""
    property bool _syncingModel: false

    readonly property var _parserOpts: ({
        lightMode: Boolean(Theme.lightMode),
        baseFontPx: EditorMetrics.body,
        themeColors: {
            accent: "" + Theme.accent,
            text: "" + Theme.text,
            surface: "" + Theme.surface,
            muted: "" + Theme.muted,
            danger: "" + Theme.danger,
            success: "" + Theme.success,
            warning: "" + Theme.warning
        }
    })

    readonly property var parsedNodes: HtmlStyleParser.parseHtmlFragment(rawSource, _parserOpts)

    function _inlineOpts(st, searchUnit) {
        var colorStr = (st && st.color) ? st.color : ("" + Theme.text);
        var u = (typeof searchUnit === "number") ? searchUnit : 0;
        return {
            zoom: EditorMetrics.zoom,
            textColor: colorStr,
            mathColor: colorStr,
            mathPtSize: Math.max(8.0, EditorMetrics.body * 0.75),
            linkColor: "" + Theme.accent,
            highlightBg: EditorMetrics.highlightBg,
            codeBg: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08),
            codeColor: colorStr,
            surface: "" + Theme.surface,
            dimColor: "" + Theme.muted,
            kbdBezel: Theme.lightMode ? "#dcdcdc" : ("" + Theme.accent),
            kbdShadow1: Theme.lightMode ? "#9f9f9f" : ("" + Qt.darker(Theme.accent, 1.55)),
            kbdShadow2: Theme.lightMode ? "#b0b0b0" : ("" + Qt.darker(Theme.accent, 1.25)),
            kbdPlate: Theme.lightMode ? "#ffffff" : ("" + Theme.surface),
            kbdText: Theme.lightMode ? "#1c1c1c" : ("" + Theme.color15),
            fontFamilyMonospace: Theme.fontFamilyMonospace || "JetBrains Mono",
            lightMode: Theme.lightMode,
            baseFolder: root.baseFolder,
            imageSkipMissing: true,
            imageExists: root.editor ? root.editor.imageExistsFn : null,
            probeTick: NotesService.imageProbeSeq,
            themeColors: root._parserOpts.themeColors,
            baseFontPx: (st && st.fontSizePx > 0) ? st.fontSizePx : EditorMetrics.body,
            searchQuery: root.editor ? root.editor.searchQuery : "",
            searchHighlightBg: root.editor ? ("" + root.editor.searchHighlightColor) : "",
            searchHighlightActiveBg: (root.editor && root.blockData) ? root.editor.searchActiveBg(root.blockData.bid, u) : "",
            searchActiveOrdinal: (root.editor && root.blockData) ? root.editor.searchActiveOrdinal(root.blockData.bid, u) : -1,
            searchHighlightActiveFg: (root.editor && root.blockData) ? root.editor.searchActiveFg(root.blockData.bid, u) : ""
        };
    }

    function _qtAlign(al) {
        if (al === "center") return TextEdit.AlignHCenter;
        if (al === "right") return TextEdit.AlignRight;
        if (al === "justify") return TextEdit.AlignJustify;
        return TextEdit.AlignLeft;
    }

    function _qmlColor(c, fallback) {
        if (!c || c === "transparent") return fallback !== undefined ? fallback : "transparent";
        var s = String(c).trim();
        var m = s.match(/^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([0-9.]+))?\s*\)$/i);
        if (m) {
            var a = (m[4] !== undefined) ? parseFloat(m[4]) : 1.0;
            return Qt.rgba(parseInt(m[1], 10) / 255.0, parseInt(m[2], 10) / 255.0, parseInt(m[3], 10) / 255.0, isNaN(a) ? 1.0 : a);
        }
        return s;
    }

    function isDetailsOpen(nodePath, defaultOpen) {
        if (_detailsOpenState && _detailsOpenState[nodePath] !== undefined) {
            return !!_detailsOpenState[nodePath];
        }
        return !!defaultOpen;
    }

    function toggleDetails(nodePath, defaultOpen) {
        var next = Object.assign({}, _detailsOpenState || {});
        next[nodePath] = !isDetailsOpen(nodePath, defaultOpen);
        _detailsOpenState = next;
    }

    function _setPreviewTextSelection(unitId, editItem) {
        if (_activePreviewTextEdit && _activePreviewTextEdit !== editItem && typeof _activePreviewTextEdit.deselect === "function") {
            _activePreviewTextEdit.deselect();
        }
        _activePreviewTextEdit = editItem || null;
        _activePreviewUnitId = editItem ? String(unitId || "") : "";
        if (editItem && root.editor && root.blockData && typeof root.editor.notifySingleInputSelection === "function") {
            root.editor.notifySingleInputSelection(root.blockData.bid, 0);
        }
    }

    implicitWidth: parent ? parent.width : 400
    implicitHeight: root.isEditing
        ? (headerRow.height + Math.max(24, previewCol.implicitHeight) + editInput.paintedHeight + templatesScroll.height + 72)
        : Math.max(24, previewCol.implicitHeight + (root.isSelected ? 12 : 4))

    radius: 10
    color: root.isEditing
        ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04)
        : (root.isSelected ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.06) : "transparent")
    border.color: (root.isEditing || root.isSelected) ? Theme.accent : "transparent"
    border.width: (root.isEditing || root.isSelected) ? 1.5 : 0

    Component.onDestruction: {
        _isDestroyed = true;
        _activePreviewTextEdit = null;
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

    function clearOtherItemsSelection(exceptSubIdx) {
        // Mantener selección del texto preview activo dentro de BlockHtml si corresponde
    }

    function clearTextSelection() {
        if (_activePreviewTextEdit) {
            if (typeof _activePreviewTextEdit.deselect === "function") _activePreviewTextEdit.deselect();
            _activePreviewTextEdit = null;
            _activePreviewUnitId = "";
        }
        if (editInput) editInput.deselect();
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
        if (!root.isEditing && _activePreviewTextEdit && typeof _activePreviewTextEdit.selectedText === "string" && _activePreviewTextEdit.selectedText !== "") {
            return _activePreviewTextEdit.selectedText;
        }
        if (editInput && editInput.selectedText !== "") return editInput.selectedText;
        if (root.editor && root.editor.hasBlockSelection) {
            return HtmlStyleParser.extractVisibleText(root.rawSource, root._parserOpts);
        }
        return "";
    }

    function getTextContent() {
        if (root.isEditing && editInput) return Inline.plainText(editInput);
        return HtmlStyleParser.extractVisibleText(root.rawSource, root._parserOpts);
    }

    function deleteSelectedText() {
        if (!editInput || root.isReadOnly) return;
        var s = editInput.selectionStart;
        var e = editInput.selectionEnd;
        if (s !== e) editInput.remove(s, e);
    }

    function getRaw() {
        if (root.isEditing && editInput) return Inline.plainText(editInput);
        return root.rawSource;
    }

    function getTextEdit() {
        if (!root.isEditing && _activePreviewTextEdit) return _activePreviewTextEdit;
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
            if (typeof cursorPos === "number" && cursorPos >= 0) {
                editInput.cursorPosition = Math.min(editInput.text.length, cursorPos);
            } else {
                editInput.cursorPosition = editInput.text.length;
            }
        }
    }

    onBlockDataChanged: {
        if (!root.isEditing) _syncTextFromModel();
    }

    onIsEditingChanged: {
        if (root.isEditing) {
            clearTextSelection();
            _syncTextFromModel();
        }
    }

    Component.onCompleted: {
        if (root.isEditing) _syncTextFromModel();
    }

    Timer {
        id: copiedTimer
        interval: 1600
        onTriggered: {
            if (!root._isDestroyed) root.copiedRecently = false;
        }
    }

    HoverHandler {
        id: blockHover
        acceptedDevices: PointerDevice.Mouse
    }

    // ── Helper unificado para bloques de texto RichText seleccionables ───────
    Component {
        id: richTextComponent

        TextEdit {
            id: richTxt
            property var nodeStyle: null
            property string rawMd: ""
            property string unitId: ""
            property real explicitFontPx: 0
            property bool explicitBold: false
            property string prefixHtml: ""

            width: parent ? parent.width : root.width
            readOnly: true
            cursorVisible: false
            cursorDelegate: Item { width: 0; height: 0 }
            persistentSelection: true
            activeFocusOnTab: false
            selectByMouse: false
            textFormat: TextEdit.RichText
            wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
            horizontalAlignment: root._qtAlign(nodeStyle ? nodeStyle.textAlign : "")
            color: (nodeStyle && nodeStyle.color) ? nodeStyle.color : Theme.text
            selectionColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
            selectedTextColor: Theme.text
            font.family: (nodeStyle && nodeStyle.fontFamily === "monospace") ? (Theme.fontFamilyMonospace || "monospace") : Theme.fontFamily
            font.pixelSize: explicitFontPx > 0 ? explicitFontPx : ((nodeStyle && nodeStyle.fontSizePx > 0) ? Math.round(nodeStyle.fontSizePx * EditorMetrics.zoom) : EditorMetrics.body)
            font.bold: explicitBold || (nodeStyle && nodeStyle.fontWeight === "bold")
            font.italic: Boolean(nodeStyle && nodeStyle.fontStyle === "italic")
            text: richTxt.prefixHtml + Inline.inlineToHtml(richTxt.rawMd, root._inlineOpts(nodeStyle, 0))

            HoverHandler {
                enabled: richTxt.hoveredLink !== ""
                cursorShape: Qt.PointingHandCursor
            }

            MouseArea {
                id: richMa
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: richTxt.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
                preventStealing: dragging

                property bool dragging: false
                property bool didDrag: false
                property int anchorPos: -1
                property real startX: 0
                property real startY: 0
                property string pressedLink: ""

                onPressed: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        if (richTxt.selectionStart === richTxt.selectionEnd) {
                            var rPos = richTxt.positionAt(mouse.x, mouse.y);
                            if (rPos >= 0 && rPos <= richTxt.length) richTxt.cursorPosition = rPos;
                        }
                        root._setPreviewTextSelection(richTxt.unitId, richTxt);
                        if (root.editor && root.editor.contextMenu) {
                            root.editor.contextMenu.open(richTxt);
                        }
                        mouse.accepted = true;
                        return;
                    }
                    pressedLink = richTxt.linkAt(mouse.x, mouse.y) || "";
                    startX = mouse.x;
                    startY = mouse.y;
                    didDrag = false;
                    dragging = true;
                    anchorPos = Math.max(0, Math.min(richTxt.length, richTxt.positionAt(mouse.x, mouse.y)));
                    if (richTxt.selectionStart !== richTxt.selectionEnd) richTxt.deselect();
                    richTxt.cursorPosition = anchorPos;
                    root._setPreviewTextSelection(richTxt.unitId, richTxt);
                }

                onPositionChanged: (mouse) => {
                    if (!dragging || anchorPos < 0) return;
                    if (!didDrag && Math.abs(mouse.x - startX) < 3 && Math.abs(mouse.y - startY) < 3) return;
                    didDrag = true;
                    var pos = Math.max(0, Math.min(richTxt.length, richTxt.positionAt(mouse.x, mouse.y)));
                    richTxt.select(anchorPos, pos);
                    root._setPreviewTextSelection(richTxt.unitId, richTxt);
                }

                onReleased: (mouse) => {
                    if (mouse.button === Qt.RightButton) return;
                    var wasDrag = didDrag;
                    var pLink = pressedLink;
                    dragging = false;
                    didDrag = false;
                    anchorPos = -1;
                    pressedLink = "";
                    if (!wasDrag) {
                        if (pLink !== "" && root.editor && typeof root.editor.handleLink === "function") {
                            root.editor.handleLink(pLink);
                            return;
                        }
                        if (richTxt.selectionStart !== richTxt.selectionEnd) richTxt.deselect();
                        if (!root.isReadOnly && !root.isEditing && root.editor && root.blockData) {
                            root.editor.requestEditBlock(root.blockData.bid);
                        }
                    } else if (richTxt.selectionStart !== richTxt.selectionEnd) {
                        richTxt.forceActiveFocus();
                        root._setPreviewTextSelection(richTxt.unitId, richTxt);
                    }
                }

                onDoubleClicked: (mouse) => {
                    if (mouse.button !== Qt.LeftButton) return;
                    dragging = false;
                    didDrag = false;
                    richTxt.forceActiveFocus();
                    var pos = Math.max(0, Math.min(richTxt.length, richTxt.positionAt(mouse.x, mouse.y)));
                    richTxt.cursorPosition = pos;
                    richTxt.selectWord();
                    root._setPreviewTextSelection(richTxt.unitId, richTxt);
                }

                onCanceled: {
                    dragging = false;
                    didDrag = false;
                    anchorPos = -1;
                    pressedLink = "";
                }
            }
        }
    }

    // ── Delegado recursivo para cada nodo HTML / Markdown del AST ────────────
    Component {
        id: htmlNodeDelegate

        Item {
            id: nodeHost
            property var nodeData: null
            property string nodePath: "0"
            readonly property string kind: nodeData ? (nodeData.kind || "markdown") : "markdown"
            readonly property var st: nodeData ? (nodeData.style || ({})) : ({})
            width: parent ? parent.width : root.width
            implicitHeight: nodeLoader.item ? nodeLoader.item.implicitHeight : 0
            height: implicitHeight

            Loader {
                id: nodeLoader
                active: nodeHost.nodeData !== null
                width: parent.width
                sourceComponent: {
                    switch (nodeHost.kind) {
                        case "heading": return compHeading;
                        case "markdown": return compMarkdown;
                        case "hr": return compHr;
                        case "container": return compContainer;
                        case "details": return compDetails;
                        case "image_row": return compImageRow;
                        case "table": return compHtmlTable;
                        case "list": return compList;
                        case "code": return compCode;
                        case "blockquote": return compBlockquote;
                        default: return compMarkdown;
                    }
                }
            }

            Component {
                id: compHeading
                Loader {
                    id: headingRichLoader
                    width: nodeLoader.width
                    sourceComponent: richTextComponent
                    Binding {
                        target: headingRichLoader.item
                        property: "nodeStyle"
                        value: nodeHost.st
                        when: headingRichLoader.status === Loader.Ready && headingRichLoader.item !== null
                    }
                    Binding {
                        target: headingRichLoader.item
                        property: "rawMd"
                        value: (nodeHost.nodeData && nodeHost.nodeData.raw) ? nodeHost.nodeData.raw : ""
                        when: headingRichLoader.status === Loader.Ready && headingRichLoader.item !== null
                    }
                    Binding {
                        target: headingRichLoader.item
                        property: "unitId"
                        value: nodeHost.nodePath
                        when: headingRichLoader.status === Loader.Ready && headingRichLoader.item !== null
                    }
                    Binding {
                        target: headingRichLoader.item
                        property: "explicitFontPx"
                        value: EditorMetrics.headingSize((nodeHost.nodeData && nodeHost.nodeData.level) ? nodeHost.nodeData.level : 1)
                        when: headingRichLoader.status === Loader.Ready && headingRichLoader.item !== null
                    }
                    Binding {
                        target: headingRichLoader.item
                        property: "explicitBold"
                        value: true
                        when: headingRichLoader.status === Loader.Ready && headingRichLoader.item !== null
                    }
                }
            }

            Component {
                id: compMarkdown
                Loader {
                    id: mdRichLoader
                    width: nodeLoader.width
                    sourceComponent: richTextComponent
                    Binding {
                        target: mdRichLoader.item
                        property: "nodeStyle"
                        value: nodeHost.st
                        when: mdRichLoader.status === Loader.Ready && mdRichLoader.item !== null
                    }
                    Binding {
                        target: mdRichLoader.item
                        property: "rawMd"
                        value: (nodeHost.nodeData && nodeHost.nodeData.raw) ? nodeHost.nodeData.raw : ""
                        when: mdRichLoader.status === Loader.Ready && mdRichLoader.item !== null
                    }
                    Binding {
                        target: mdRichLoader.item
                        property: "unitId"
                        value: nodeHost.nodePath
                        when: mdRichLoader.status === Loader.Ready && mdRichLoader.item !== null
                    }
                }
            }

            Component {
                id: compHr
                Item {
                    width: nodeLoader.width
                    implicitHeight: Math.max(10, Math.round(12 * EditorMetrics.zoom))
                    height: implicitHeight
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: Math.max(1, Math.round(EditorMetrics.zoom))
                        color: root._qmlColor(nodeHost.st && nodeHost.st.color, Theme.border)
                    }
                }
            }

            Component {
                id: compContainer
                Item {
                    id: boxWrap
                    width: nodeLoader.width
                    implicitHeight: boxRect.implicitHeight + topM + botM
                    height: implicitHeight
                    readonly property real topM: nodeHost.st.marginTop > 0 ? Math.round(nodeHost.st.marginTop * EditorMetrics.zoom) : 0
                    readonly property real botM: nodeHost.st.marginBottom > 0 ? Math.round(nodeHost.st.marginBottom * EditorMetrics.zoom) : 0
                    readonly property real padT: Math.round((nodeHost.st.paddingTop || 0) * EditorMetrics.zoom)
                    readonly property real padR: Math.round((nodeHost.st.paddingRight || 0) * EditorMetrics.zoom)
                    readonly property real padB: Math.round((nodeHost.st.paddingBottom || 0) * EditorMetrics.zoom)
                    readonly property real padL: Math.round((nodeHost.st.paddingLeft || 0) * EditorMetrics.zoom)
                    readonly property real boxW: {
                        var w = nodeLoader.width;
                        if (nodeHost.st.widthPct > 0) w = Math.round(nodeLoader.width * nodeHost.st.widthPct);
                        else if (nodeHost.st.widthPx > 0) w = Math.min(nodeLoader.width, Math.round(nodeHost.st.widthPx * EditorMetrics.zoom));
                        if (nodeHost.st.maxWidthPx > 0) w = Math.min(w, Math.round(nodeHost.st.maxWidthPx * EditorMetrics.zoom));
                        return Math.max(40, w);
                    }

                    Rectangle {
                        id: boxRect
                        y: boxWrap.topM
                        width: boxWrap.boxW
                        x: (nodeHost.st.textAlign === "center")
                            ? Math.round((boxWrap.width - width) / 2)
                            : ((nodeHost.st.textAlign === "right") ? Math.max(0, boxWrap.width - width) : 0)
                        implicitHeight: boxCol.implicitHeight + boxWrap.padT + boxWrap.padB
                        height: implicitHeight
                        radius: Math.round((nodeHost.st.borderRadius || 0) * EditorMetrics.zoom)
                        color: root._qmlColor(nodeHost.st.backgroundColor, "transparent")
                        border.width: nodeHost.st.borderWidth || 0
                        border.color: root._qmlColor(nodeHost.st.borderColor, Theme.border)
                        opacity: nodeHost.st.opacity
                        clip: radius > 0

                        Rectangle {
                            visible: nodeHost.st.borderLeftWidth > 0
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: Math.max(2, Math.round((nodeHost.st.borderLeftWidth || 0) * EditorMetrics.zoom))
                            color: root._qmlColor(nodeHost.st.borderLeftColor, Theme.accent)
                        }

                        Column {
                            id: boxCol
                            x: boxWrap.padL + (nodeHost.st.borderLeftWidth > 0 ? Math.round(nodeHost.st.borderLeftWidth * EditorMetrics.zoom) : 0)
                            y: boxWrap.padT
                            width: Math.max(20, boxRect.width - boxWrap.padL - boxWrap.padR - (nodeHost.st.borderLeftWidth > 0 ? Math.round(nodeHost.st.borderLeftWidth * EditorMetrics.zoom) : 0))
                            spacing: Math.max(4, Math.round(6 * EditorMetrics.zoom))

                            Repeater {
                                model: (nodeHost.nodeData && nodeHost.nodeData.children) ? nodeHost.nodeData.children : []
                                delegate: Loader {
                                    id: boxChildLoader
                                    width: boxCol.width
                                    sourceComponent: htmlNodeDelegate
                                    Binding {
                                        target: boxChildLoader.item
                                        property: "nodeData"
                                        value: modelData
                                        when: boxChildLoader.status === Loader.Ready && boxChildLoader.item !== null
                                    }
                                    Binding {
                                        target: boxChildLoader.item
                                        property: "nodePath"
                                        value: nodeHost.nodePath + "." + index
                                        when: boxChildLoader.status === Loader.Ready && boxChildLoader.item !== null
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Component {
                id: compDetails
                Rectangle {
                    id: detailsCard
                    readonly property bool isOpen: root.isDetailsOpen(nodeHost.nodePath, (nodeHost.nodeData && nodeHost.nodeData.open) ? nodeHost.nodeData.open : false)
                    width: nodeLoader.width
                    implicitHeight: detailsCol.implicitHeight + 16
                    height: implicitHeight
                    radius: 8
                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.03)
                    border.color: Theme.border
                    border.width: 1

                    Column {
                        id: detailsCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        spacing: detailsCard.isOpen ? 8 : 0

                        Rectangle {
                            id: summaryBar
                            width: detailsCol.width
                            height: Math.max(26, summaryTxt.paintedHeight + 8)
                            radius: 6
                            color: summaryMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06) : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 6
                                spacing: 6

                                Image {
                                    Layout.preferredWidth: 14
                                    Layout.preferredHeight: 14
                                    source: Theme.iconsPath + "chevron-down.svg"
                                    sourceSize: Qt.size(14, 14)
                                    rotation: detailsCard.isOpen ? 0 : -90
                                    Behavior on rotation {
                                        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                                    }
                                    layer.enabled: visible && !GamemodeService.gamemodeActive
                                    layer.effect: MultiEffect {
                                        colorization: 1.0
                                        colorizationColor: Theme.accent
                                    }
                                }

                                Text {
                                    id: summaryTxt
                                    Layout.fillWidth: true
                                    textFormat: Text.RichText
                                    wrapMode: Text.WordWrap
                                    font.family: Theme.fontFamily
                                    font.pixelSize: EditorMetrics.body
                                    font.bold: true
                                    color: root._qmlColor(nodeHost.st && nodeHost.st.color, Theme.text)
                                    text: Inline.inlineToHtml((nodeHost.nodeData && nodeHost.nodeData.summaryRaw) ? nodeHost.nodeData.summaryRaw : "Detalles", root._inlineOpts(nodeHost.st, 0))
                                }
                            }

                            MouseArea {
                                id: summaryMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleDetails(nodeHost.nodePath, (nodeHost.nodeData && nodeHost.nodeData.open) ? nodeHost.nodeData.open : false)
                            }
                        }

                        Column {
                            id: detailsBodyCol
                            visible: detailsCard.isOpen
                            width: detailsCol.width - 14
                            x: 10
                            spacing: Math.max(4, Math.round(6 * EditorMetrics.zoom))

                            Repeater {
                                model: detailsCard.isOpen ? ((nodeHost.nodeData && nodeHost.nodeData.children) ? nodeHost.nodeData.children : []) : []
                                delegate: Loader {
                                    id: detailsChildLoader
                                    width: detailsBodyCol.width
                                    sourceComponent: htmlNodeDelegate
                                    Binding {
                                        target: detailsChildLoader.item
                                        property: "nodeData"
                                        value: modelData
                                        when: detailsChildLoader.status === Loader.Ready && detailsChildLoader.item !== null
                                    }
                                    Binding {
                                        target: detailsChildLoader.item
                                        property: "nodePath"
                                        value: nodeHost.nodePath + ".d" + index
                                        when: detailsChildLoader.status === Loader.Ready && detailsChildLoader.item !== null
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Component {
                id: compImageRow
                Item {
                    id: imgRowBox
                    readonly property string rowAlign: (nodeHost.nodeData && nodeHost.nodeData.align) ? nodeHost.nodeData.align : ((nodeHost.st && nodeHost.st.textAlign) ? nodeHost.st.textAlign : "left")
                    width: nodeLoader.width
                    implicitHeight: flowLayout.implicitHeight + 4
                    height: implicitHeight

                    Flow {
                        id: flowLayout
                        property real contentRowW: imgRowBox.width
                        function syncFlowWidth() {
                            var total = 0;
                            var count = hImgRep.count;
                            for (var i = 0; i < count; i++) {
                                var it = hImgRep.itemAt(i);
                                if (it) total += it.width;
                            }
                            if (count > 1) total += spacing * (count - 1);
                            contentRowW = Math.max(1, total);
                        }
                        width: (rowAlign === "center" || rowAlign === "right")
                            ? Math.min(imgRowBox.width, contentRowW)
                            : imgRowBox.width
                        x: (rowAlign === "center")
                            ? Math.max(0, Math.round((imgRowBox.width - width) / 2))
                            : ((rowAlign === "right") ? Math.max(0, imgRowBox.width - width) : 0)
                        spacing: Math.max(6, Math.round(8 * EditorMetrics.zoom))
                        onSpacingChanged: syncFlowWidth()
                        Component.onCompleted: syncFlowWidth()

                        Repeater {
                            id: hImgRep
                            model: (nodeHost.nodeData && nodeHost.nodeData.images) ? nodeHost.nodeData.images : []
                            onCountChanged: flowLayout.syncFlowWidth()
                            delegate: Item {
                                id: hImgItem
                                readonly property string imgSrc: modelData.src || ""
                                readonly property string imgAlt: modelData.alt || ""
                                readonly property string imgLink: modelData.link || ""
                                readonly property int reqW: modelData.width || 0
                                readonly property int reqH: modelData.height || 0
                                readonly property string imgState: {
                                    var _ = NotesService.imageProbeSeq;
                                    return NotesService.imageStateFor(imgSrc, root.baseFolder);
                                }
                                readonly property bool loadable: imgState === "yes" || imgState === "remote"
                                readonly property string localPath: ImageProbe.resolveLocal(root.baseFolder, imgSrc)
                                readonly property string fileUrl: ImageProbe.toFileUrl(root.baseFolder, imgSrc)
                                readonly property real natW: animImg.implicitWidth > 0 ? animImg.implicitWidth : (reqW > 0 ? reqW : 240)
                                readonly property real natH: animImg.implicitHeight > 0 ? animImg.implicitHeight : (reqH > 0 ? reqH : 40)
                                readonly property bool isBadge: PreviewLogic.isBadgeLike(imgSrc, imgAlt) || (natH > 0 && natH <= 38 && reqW === 0)
                                readonly property real targetW: {
                                    var z = EditorMetrics.zoom || 1.0;
                                    var maxW = Math.max(40, imgRowBox.width - 4);
                                    if (reqW > 0) return Math.min(maxW, Math.round(reqW * z));
                                    if (reqH > 0 && natH > 0) return Math.min(maxW, Math.round((natW * (reqH / natH)) * z));
                                    return Math.min(maxW, Math.round(natW * z));
                                }
                                readonly property real targetH: {
                                    var z = EditorMetrics.zoom || 1.0;
                                    if (reqH > 0 && reqW === 0) return Math.max(12, Math.round(reqH * z));
                                    if (natW > 0 && natH > 0) return Math.max(12, Math.round(targetW * (natH / natW)));
                                    return 32;
                                }

                                width: targetW
                                height: targetH
                                onWidthChanged: flowLayout.syncFlowWidth()
                                Component.onCompleted: flowLayout.syncFlowWidth()

                                AnimatedImage {
                                    id: animImg
                                    anchors.fill: parent
                                    asynchronous: true
                                    cache: true
                                    fillMode: Image.PreserveAspectFit
                                    playing: Theme.animationsEnabled && !GamemodeService.gamemodeActive && root.visible && Qt.application.active
                                    paused: GamemodeService.gamemodeActive || !playing
                                    source: hImgItem.loadable ? hImgItem.fileUrl : ""
                                    onStatusChanged: {
                                        if (status === Image.Ready && implicitWidth > 0 && implicitHeight > 0 && root.editor && typeof root.editor._storeImageDimension === "function") {
                                            root.editor._storeImageDimension(hImgItem.imgSrc, implicitWidth, implicitHeight);
                                        }
                                    }
                                }

                                HoverHandler {
                                    id: hImgHover
                                    enabled: hImgItem.loadable && animImg.status === Image.Ready && !hImgItem.isBadge
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton
                                    cursorShape: (hImgItem.imgLink !== "" || !hImgItem.isBadge) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (hImgItem.imgLink !== "" && root.editor && typeof root.editor.handleLink === "function") {
                                            root.editor.handleLink(hImgItem.imgLink);
                                            return;
                                        }
                                        if (animImg.status === Image.Ready && !hImgItem.isBadge && root.editor && typeof root.editor.openImageZoom === "function") {
                                            root.editor.openImageZoom(animImg.source.toString(), hImgItem, hImgItem.natW, hImgItem.natH);
                                        }
                                    }
                                }

                                ImageCopyButton {
                                    z: 10
                                    available: hImgItem.loadable && animImg.status === Image.Ready && !hImgItem.isBadge
                                    showZoomButton: true
                                    hoveredOutside: hImgHover.hovered
                                    localPath: hImgItem.localPath
                                    targetImageItem: animImg
                                    onZoomRequested: {
                                        if (root.editor && typeof root.editor.openImageZoom === "function") {
                                            root.editor.openImageZoom(animImg.source.toString(), hImgItem, hImgItem.natW, hImgItem.natH);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Component {
                id: compHtmlTable
                Rectangle {
                    id: tblRect
                    readonly property var headers: (nodeHost.nodeData && nodeHost.nodeData.headers) ? nodeHost.nodeData.headers : []
                    readonly property var rows: (nodeHost.nodeData && nodeHost.nodeData.rows) ? nodeHost.nodeData.rows : []
                    readonly property var aligns: (nodeHost.nodeData && nodeHost.nodeData.alignments) ? nodeHost.nodeData.alignments : []
                    readonly property var colWidths: (nodeHost.nodeData && nodeHost.nodeData.colWidths) ? nodeHost.nodeData.colWidths : []
                    readonly property int colsCount: Math.max(1, headers.length, (rows.length > 0 && rows[0]) ? rows[0].length : 0)
                    readonly property real availW: Math.max(80, tblCol.width)
                    function colWidthFor(c) {
                        var n = colsCount;
                        var totalW = availW;
                        if (n <= 1) return totalW;
                        var specSum = 0.0;
                        var unspecCount = 0;
                        for (var i = 0; i < n; i++) {
                            var v = (colWidths && i < colWidths.length) ? Number(colWidths[i] || 0) : 0;
                            if (v > 0) specSum += v;
                            else unspecCount += 1;
                        }
                        var used = 0;
                        for (var j = 0; j < n; j++) {
                            var w;
                            if (j === n - 1) {
                                w = Math.max(1, totalW - used);
                            } else if (specSum > 0) {
                                var rawV = (colWidths && j < colWidths.length) ? Number(colWidths[j] || 0) : 0;
                                var frac = 0;
                                if (specSum <= 1.0 && unspecCount > 0) {
                                    frac = rawV > 0 ? rawV : (1.0 - specSum) / unspecCount;
                                } else {
                                    var eff = rawV > 0 ? rawV : (specSum / Math.max(1, n - unspecCount));
                                    var denom = specSum + (unspecCount > 0 ? (specSum / Math.max(1, n - unspecCount)) * unspecCount : 0);
                                    frac = denom > 0 ? (eff / denom) : (1.0 / n);
                                }
                                w = Math.max(40, Math.floor(totalW * frac));
                            } else {
                                w = Math.floor(totalW / n);
                            }
                            if (j === c) return w;
                            used += w;
                        }
                        return Math.floor(totalW / n);
                    }

                    width: nodeLoader.width
                    implicitHeight: tblCol.implicitHeight + 2
                    height: implicitHeight
                    radius: 8
                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.02)
                    border.color: Theme.border
                    border.width: 1
                    clip: true

                    Column {
                        id: tblCol
                        width: parent.width - 2
                        x: 1; y: 1
                        spacing: 0

                        // Cabecera HTML <th>
                        Rectangle {
                            id: hWrap
                            visible: tblRect.headers.length > 0
                            width: parent.width
                            property real maxH: 30
                            function updateRowHeight() {
                                var m = 30;
                                for (var i = 0; i < hRep.count; i++) {
                                    var it = hRep.itemAt(i);
                                    if (it && it.cellH > m) m = it.cellH;
                                }
                                if (Math.abs(maxH - m) > 0.5) maxH = m;
                            }
                            implicitHeight: maxH
                            height: maxH
                            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)

                            Row {
                                id: hRow
                                width: parent.width
                                height: hWrap.maxH
                                Repeater {
                                    id: hRep
                                    model: tblRect.headers
                                    onCountChanged: hWrap.updateRowHeight()
                                    delegate: Item {
                                        readonly property real cellH: Math.max(30, hCellView.implicitHeight + 12)
                                        width: tblRect.colWidthFor(index)
                                        height: hWrap.maxH
                                        onCellHChanged: hWrap.updateRowHeight()
                                        Component.onCompleted: hWrap.updateRowHeight()
                                        TableCellView {
                                            id: hCellView
                                            anchors.left: parent.left; anchors.right: parent.right
                                            anchors.leftMargin: 8; anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            rawText: modelData || ""
                                            editor: root.editor
                                            blockData: root.blockData
                                            cellUnitIndex: index
                                            cellAlignment: root._qtAlign(tblRect.aligns[index] || "left")
                                            fontPixelSize: EditorMetrics.fs(Theme.fontSizeCaption + 1)
                                            fontBold: true
                                            isReadOnly: true
                                            onLinkClicked: (url) => { if (root.editor) root.editor.handleLink(url); }
                                            onCellSelectionActivated: (editItem) => root._setPreviewTextSelection(nodeHost.nodePath + ".th" + index, editItem)
                                            onPreviewContextMenuRequested: (editItem) => {
                                                root._setPreviewTextSelection(nodeHost.nodePath + ".th" + index, editItem);
                                                if (root.editor && root.editor.contextMenu) root.editor.contextMenu.open(editItem);
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Filas <tr>
                        Repeater {
                            model: tblRect.rows
                            delegate: Rectangle {
                                id: dRowWrap
                                readonly property int rIdx: index
                                readonly property var rowData: modelData || []
                                property real maxH: 28
                                function updateRowHeight() {
                                    var m = 28;
                                    for (var i = 0; i < dRep.count; i++) {
                                        var it = dRep.itemAt(i);
                                        if (it && it.cellH > m) m = it.cellH;
                                    }
                                    if (Math.abs(maxH - m) > 0.5) maxH = m;
                                }
                                width: tblCol.width
                                implicitHeight: maxH
                                height: maxH
                                color: (rIdx % 2 === 1) ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.02) : "transparent"

                                Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.border }

                                Row {
                                    id: dRow
                                    width: parent.width
                                    height: dRowWrap.maxH
                                    Repeater {
                                        id: dRep
                                        model: rowData
                                        onCountChanged: dRowWrap.updateRowHeight()
                                        delegate: Item {
                                            readonly property real cellH: Math.max(28, dCellView.implicitHeight + 10)
                                            width: tblRect.colWidthFor(index)
                                            height: dRowWrap.maxH
                                            onCellHChanged: dRowWrap.updateRowHeight()
                                            Component.onCompleted: dRowWrap.updateRowHeight()
                                            TableCellView {
                                                id: dCellView
                                                anchors.left: parent.left; anchors.right: parent.right
                                                anchors.leftMargin: 8; anchors.rightMargin: 8
                                                anchors.verticalCenter: parent.verticalCenter
                                                rawText: modelData || ""
                                                editor: root.editor
                                                blockData: root.blockData
                                                cellUnitIndex: (rIdx + 1) * tblRect.colsCount + index
                                                cellAlignment: root._qtAlign(tblRect.aligns[index] || "left")
                                                fontPixelSize: EditorMetrics.caption
                                                fontBold: false
                                                isReadOnly: true
                                                onLinkClicked: (url) => { if (root.editor) root.editor.handleLink(url); }
                                                onCellSelectionActivated: (editItem) => root._setPreviewTextSelection(nodeHost.nodePath + ".r" + rIdx + "c" + index, editItem)
                                                onPreviewContextMenuRequested: (editItem) => {
                                                    root._setPreviewTextSelection(nodeHost.nodePath + ".r" + rIdx + "c" + index, editItem);
                                                    if (root.editor && root.editor.contextMenu) root.editor.contextMenu.open(editItem);
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

            Component {
                id: compList
                Column {
                    width: nodeLoader.width
                    spacing: 4
                    Repeater {
                        model: (nodeHost.nodeData && nodeHost.nodeData.items) ? nodeHost.nodeData.items : []
                        delegate: Loader {
                            id: listRichLoader
                            width: parent.width
                            sourceComponent: richTextComponent
                            Binding {
                                target: listRichLoader.item
                                property: "nodeStyle"
                                value: nodeHost.st
                                when: listRichLoader.status === Loader.Ready && listRichLoader.item !== null
                            }
                            Binding {
                                target: listRichLoader.item
                                property: "prefixHtml"
                                value: (nodeHost.nodeData && nodeHost.nodeData.ordered) ? ("<b>" + (index + 1) + ".</b> ") : "• "
                                when: listRichLoader.status === Loader.Ready && listRichLoader.item !== null
                            }
                            Binding {
                                target: listRichLoader.item
                                property: "rawMd"
                                value: modelData || ""
                                when: listRichLoader.status === Loader.Ready && listRichLoader.item !== null
                            }
                            Binding {
                                target: listRichLoader.item
                                property: "unitId"
                                value: nodeHost.nodePath + ".li" + index
                                when: listRichLoader.status === Loader.Ready && listRichLoader.item !== null
                            }
                        }
                    }
                }
            }

            Component {
                id: compCode
                Rectangle {
                    id: htmlCodeRect
                    width: nodeLoader.width
                    implicitHeight: codeTxt.paintedHeight + 16
                    height: implicitHeight
                    radius: 8
                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)
                    border.color: Theme.border
                    border.width: 1

                    TextEdit {
                        id: codeTxt
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.top: parent.top; anchors.margins: 8
                        readOnly: true
                        cursorVisible: false
                        persistentSelection: true
                        selectByMouse: true
                        wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                        font.family: Theme.fontFamilyMonospace || "monospace"
                        font.pixelSize: EditorMetrics.caption
                        color: Theme.text
                        selectionColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
                        selectedTextColor: Theme.text
                        text: (nodeHost.nodeData && nodeHost.nodeData.text) ? nodeHost.nodeData.text : ""
                    }
                }
            }

            Component {
                id: compBlockquote
                Item {
                    width: nodeLoader.width
                    implicitHeight: bqCol.implicitHeight + 6
                    height: implicitHeight
                    Rectangle {
                        width: 3
                        height: parent.height - 4
                        y: 2
                        radius: 1.5
                        color: Theme.accent
                    }
                    Column {
                        id: bqCol
                        x: 12; y: 2
                        width: Math.max(40, parent.width - 12)
                        spacing: 4
                        Repeater {
                            model: (nodeHost.nodeData && nodeHost.nodeData.children && nodeHost.nodeData.children.length > 0)
                                ? nodeHost.nodeData.children
                                : [{ kind: "markdown", raw: (nodeHost.nodeData && nodeHost.nodeData.raw) ? nodeHost.nodeData.raw : "", style: nodeHost.st }]
                            delegate: Loader {
                                id: bqChildLoader
                                width: bqCol.width
                                sourceComponent: htmlNodeDelegate
                                Binding {
                                    target: bqChildLoader.item
                                    property: "nodeData"
                                    value: modelData
                                    when: bqChildLoader.status === Loader.Ready && bqChildLoader.item !== null
                                }
                                Binding {
                                    target: bqChildLoader.item
                                    property: "nodePath"
                                    value: nodeHost.nodePath + ".bq" + index
                                    when: bqChildLoader.status === Loader.Ready && bqChildLoader.item !== null
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Contenedor principal (Cabecera en edición + Preview + Editor HTML) ────
    Column {
        anchors.fill: parent
        anchors.margins: root.isEditing ? 12 : 2
        spacing: 10

        // Cabecera estilo BlockMath (visible solo cuando se edita)
        RowLayout {
            id: headerRow
            visible: root.isEditing
            width: parent.width
            height: 24

            RowLayout {
                spacing: 6
                Layout.fillWidth: true

                Image {
                    Layout.preferredWidth: 14; Layout.preferredHeight: 14
                    source: Theme.iconsPath + "html-block.svg"
                    sourceSize: Qt.size(14, 14)
                    layer.enabled: visible && !GamemodeService.gamemodeActive
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: Theme.accent
                    }
                }

                Text {
                    text: "HTML · CSS"
                    color: Theme.muted
                    font.family: "monospace"
                    font.pixelSize: EditorMetrics.caption
                }
            }

            RowLayout {
                spacing: 6
                Layout.alignment: Qt.AlignRight

                Rectangle {
                    visible: root.isEditing && !root.isReadOnly
                    Layout.preferredWidth: doneRow.implicitWidth + 14
                    Layout.preferredHeight: 24
                    radius: 6
                    color: doneMa.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                                                : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, doneMa.containsMouse ? 0.45 : 0.25)
                    border.width: 1

                    RowLayout {
                        id: doneRow
                        anchors.centerIn: parent
                        spacing: 5
                        Image {
                            Layout.preferredWidth: 12; Layout.preferredHeight: 12
                            source: Theme.iconsPath + "check.svg"
                            sourceSize: Qt.size(12, 12)
                            layer.enabled: visible && !GamemodeService.gamemodeActive
                            layer.effect: MultiEffect { colorization: 1.0; colorizationColor: Theme.accent }
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
                            if (root.editor) root.editor.confirmActiveBlock();
                            else root.isEditing = false;
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 24; Layout.preferredHeight: 24; radius: 6
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
                            if (typeof Quickshell !== "undefined" && typeof Quickshell.clipboardText !== "undefined") {
                                Quickshell.clipboardText = root.getRaw();
                            } else if (typeof Sys !== "undefined" && Sys) {
                                Sys.clipboardText = root.getRaw();
                            }
                            root.copiedRecently = true;
                            copiedTimer.restart();
                        }
                    }
                }

                Rectangle {
                    visible: !root.isReadOnly
                    Layout.preferredWidth: 24; Layout.preferredHeight: 24; radius: 6
                    color: delMa.containsMouse ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.15) : "transparent"
                    Image {
                        anchors.centerIn: parent
                        width: 14; height: 14
                        source: Theme.iconsPath + "delete.svg"
                        sourceSize: Qt.size(14, 14)
                        layer.enabled: visible && !GamemodeService.gamemodeActive
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
                        onClicked: {
                            if (root.editor && root.blockData) root.editor.deleteBlock(root.blockData.bid);
                        }
                    }
                }
            }
        }

        // Vista previa renderizada nativa (siempre visible en reposo/preview, y arriba al editar)
        Column {
            id: previewCol
            width: parent.width
            spacing: Math.max(6, Math.round(8 * EditorMetrics.zoom))

            Repeater {
                model: root.parsedNodes
                delegate: Loader {
                    id: topNodeLoader
                    width: previewCol.width
                    sourceComponent: htmlNodeDelegate
                    Binding {
                        target: topNodeLoader.item
                        property: "nodeData"
                        value: modelData
                        when: topNodeLoader.status === Loader.Ready && topNodeLoader.item !== null
                    }
                    Binding {
                        target: topNodeLoader.item
                        property: "nodePath"
                        value: String(index)
                        when: topNodeLoader.status === Loader.Ready && topNodeLoader.item !== null
                    }
                }
            }
        }

        // Editor de código HTML / CSS (solo al editar el bloque)
        Rectangle {
            id: editContainer
            visible: root.isEditing
            width: parent.width
            implicitHeight: Math.max(76, editInput.paintedHeight + 20)
            radius: 8
            color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.35)
            border.color: editInput.activeFocus ? Theme.accent : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12)
            border.width: 1

            TextEdit {
                id: editInput
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: parent.top; anchors.margins: 10
                persistentSelection: true
                overwriteMode: root.editor ? root.editor.overwriteMode : false
                readOnly: root.isReadOnly
                cursorVisible: activeFocus && root.isEditing && !root.isReadOnly
                textFormat: TextEdit.PlainText
                color: Theme.text
                selectionColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
                selectedTextColor: Theme.text
                font.family: Theme.fontFamilyMonospace || "monospace"
                font.pixelSize: EditorMetrics.fs(Theme.fontSizeCaption + 1)
                wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                selectByMouse: true
                activeFocusOnTab: false
                CustomTextCursor {}

                CodeSyntaxHighlighter {
                    textDocument: editInput.textDocument
                    language: "html"
                    enabled: root.isEditing
                    keywordColor: Theme.ensureSyntaxColor(Theme.color5)
                    stringColor: Theme.ensureSyntaxColor(Theme.color2)
                    commentColor: Theme.muted
                    numberColor: Theme.ensureSyntaxColor(Theme.color3)
                    typeColor: Theme.ensureSyntaxColor(Theme.color4)
                    functionColor: Theme.ensureSyntaxColor(Theme.color6)
                    operatorColor: Theme.ensureSyntaxColor(Theme.accent)
                }

                onTextChanged: {
                    if (root._syncingModel || root.isReadOnly) return;
                    if (root.isEditing && root.editor && root.blockData) {
                        root.editor.onBlockRawChanged(root.blockData.bid, Inline.plainText(editInput));
                    }
                }

                Keys.onTabPressed: (event) => {
                    if (root.isReadOnly) { event.accepted = true; return; }
                    if (editInput.selectionStart !== editInput.selectionEnd) {
                        editInput.remove(editInput.selectionStart, editInput.selectionEnd);
                    }
                    var p = editInput.cursorPosition;
                    editInput.insert(p, "  ");
                    editInput.cursorPosition = p + 2;
                    event.accepted = true;
                }

                Keys.onReturnPressed: (event) => {
                    if (event.modifiers & Qt.ControlModifier) {
                        if (root.editor) root.editor.confirmActiveBlock();
                        event.accepted = true;
                        return;
                    }
                    event.accepted = false;
                }

                Keys.onEscapePressed: (event) => {
                    if (root.editor) {
                        root.editor.confirmActiveBlock();
                        event.accepted = true;
                    }
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Backspace && editInput.cursorPosition === 0 && editInput.selectionStart === editInput.selectionEnd) {
                        if (root.editor && root.blockData) {
                            root.editor.handleBlockBackspaceAtStart(root.blockData.bid);
                            event.accepted = true;
                            return;
                        }
                    }
                    if ((event.modifiers & Qt.ControlModifier) && !event.isAutoRepeat) {
                        if (event.key === Qt.Key_Z && !(event.modifiers & Qt.ShiftModifier)) {
                            if (root.editor && typeof root.editor.undo === "function") { root.editor.undo(); event.accepted = true; return; }
                        } else if (event.key === Qt.Key_Y || (event.key === Qt.Key_Z && (event.modifiers & Qt.ShiftModifier))) {
                            if (root.editor && typeof root.editor.redo === "function") { root.editor.redo(); event.accepted = true; return; }
                        }
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

        // Chips de inserción rápida de plantillas HTML/CSS (estilo BlockMath)
        Flickable {
            id: templatesScroll
            visible: root.isEditing && !root.isReadOnly
            width: parent.width
            height: 28
            contentWidth: tplRow.implicitWidth
            clip: true
            flickableDirection: Flickable.HorizontalFlick

            Row {
                id: tplRow
                spacing: 6
                Repeater {
                    model: HtmlTemplates.getTemplateList()
                    delegate: Rectangle {
                        height: 26
                        width: chipRow.implicitWidth + 14
                        radius: 6
                        color: chipMa.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                                    : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)
                        border.color: chipMa.containsMouse ? Theme.accent : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.10)
                        border.width: 1

                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                text: I18n.t(modelData.labelKey, modelData.defaultLabel)
                                color: chipMa.containsMouse ? Theme.accent : Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: EditorMetrics.fs(Theme.fontSizeCaption - 1)
                            }
                        }

                        MouseArea {
                            id: chipMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var tpl = HtmlTemplates.getTemplate(modelData.id);
                                if (editInput) {
                                    editInput.forceActiveFocus();
                                    if (editInput.length === 0 || editInput.text.trim() === "") {
                                        editInput.text = tpl;
                                    } else {
                                        editInput.insert(editInput.cursorPosition, "\n" + tpl);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Pill flotante discreta para editar bloque HTML cuando se pasa el mouse en modo edición
    Rectangle {
        id: hoverEditPill
        visible: !root.isEditing && !root.isReadOnly && opacity > 0.01
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 4
        width: 24
        height: 24
        radius: 6
        z: 15
        opacity: (blockHover.hovered || hoverEditMa.containsMouse) ? 0.92 : 0.0
        color: hoverEditMa.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25) : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.85)
        border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.14)
        border.width: 1

        Behavior on opacity {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        Image {
            anchors.centerIn: parent
            width: 13; height: 13
            source: Theme.iconsPath + "edit.svg"
            sourceSize: Qt.size(13, 13)
            layer.enabled: visible && !GamemodeService.gamemodeActive
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: hoverEditMa.containsMouse ? Theme.accent : Theme.muted
            }
        }

        MouseArea {
            id: hoverEditMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.editor && root.blockData) root.editor.requestEditBlock(root.blockData.bid);
            }
        }
    }
}
