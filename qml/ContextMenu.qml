import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Effects
import Notas

Window {
    id: menuWindow
    visible: false
    flags: Qt.Popup | Qt.FramelessWindowHint
    color: "transparent"
    transientParent: (target && target.Window && target.Window.window) ? target.Window.window : null

    property var target: null
    property var extraItems: []
    property var editor: null
    property bool showStandardItems: true
    function _isDescendantOf(item, anc) {
        if (!item || !anc) return false;
        var p = item;
        for (var hop = 0; hop < 32 && p; hop++) {
            if (p === anc) return true;
            p = p.parent;
        }
        return false;
    }

    readonly property bool isTextInputTarget: !!(target && (typeof target.cursorPosition === "number" || typeof target.selectedText === "string" || typeof target.canUndo !== "undefined" || (editor && typeof editor.hasBlockSelection !== "undefined" && editor.hasBlockSelection)))
    readonly property bool _useBlockEditor: !!(editor && target && _isDescendantOf(target, editor))
    readonly property bool _useDocHistory: !!(editor && typeof editor.undo === "function" && typeof editor.redo === "function" && (!target || _useBlockEditor))
    readonly property bool _canEditMenuTarget: !!(_useBlockEditor ? (!editor.readOnly && !(target && target.menuPreviewOnly === true)) : (target && !target.readOnly))
    readonly property bool _canPasteMenuTarget: !!(_canEditMenuTarget && ((target && Boolean(target.canPaste)) || (_useBlockEditor && typeof Quickshell !== "undefined" && typeof Quickshell.clipboardText === "string" && Quickshell.clipboardText !== "")))
    readonly property bool _canUndoEffective: _useDocHistory ? Boolean(editor.canUndo) : Boolean(target && target.canUndo)
    readonly property bool _canRedoEffective: _useDocHistory ? Boolean(editor.canRedo) : Boolean(target && target.canRedo)
    function _performUndo() {
        if (_useDocHistory) {
            editor.undo();
        } else if (target && typeof target.undo === "function") {
            target.undo();
        }
    }
    function _performRedo() {
        if (_useDocHistory) {
            editor.redo();
        } else if (target && typeof target.redo === "function") {
            target.redo();
        }
    }
    function _performPaste() {
        if (_useBlockEditor && _hasMultiSelection()) {
            var clipTxt = (typeof Quickshell !== "undefined" && typeof Quickshell.clipboardText === "string") ? Quickshell.clipboardText : "";
            if (typeof editor.replaceSelectedRange === "function") {
                editor.replaceSelectedRange(clipTxt);
            }
            return;
        }
        if (_useBlockEditor && target && target.readOnly && typeof editor.activateTargetForEdit === "function") {
            editor.activateTargetForEdit(target);
        }
        if (_useBlockEditor && typeof editor.handlePaste === "function" && target) {
            editor.handlePaste(target);
        } else if (target && typeof target.paste === "function") {
            target.paste();
        }
    }
    signal extraItemTriggered(var item)

    function _hasMultiSelection() {
        if (!_useBlockEditor) return false;
        return !!(editor && (
            (typeof editor.hasBlockSelection !== "undefined" && editor.hasBlockSelection) ||
            (typeof editor.hasMultiItemSelectionActive === "function" && editor.hasMultiItemSelectionActive())
        ));
    }

    function _hasAnySelection() {
        if (_hasMultiSelection()) return true;
        if (target && typeof target.selectedText === "string" && target.selectedText !== "") return true;
        return false;
    }

    function _performCopy() {
        if (_hasMultiSelection()) {
            var txt = (typeof editor.getSelectedText === "function") ? editor.getSelectedText() : "";
            if (txt !== "") {
                if (typeof editor.copyText === "function") {
                    editor.copyText(txt);
                } else if (typeof Quickshell.clipboardText !== "undefined") {
                    Quickshell.clipboardText = txt;
                }
                return;
            }
        }
        if (target && typeof target.copy === "function") {
            target.copy();
        }
    }

    function _performCut() {
        if (_hasMultiSelection()) {
            var txt = (typeof editor.getSelectedText === "function") ? editor.getSelectedText() : "";
            if (txt !== "") {
                if (typeof editor.copyText === "function") {
                    editor.copyText(txt);
                } else if (typeof Quickshell.clipboardText !== "undefined") {
                    Quickshell.clipboardText = txt;
                }
                if (typeof editor.replaceSelectedRange === "function") {
                    editor.replaceSelectedRange("");
                }
                return;
            }
        }
        if (_useBlockEditor && target && target.readOnly && typeof editor.commitTargetSelectionEdit === "function") {
            if (editor.commitTargetSelectionEdit(target, true)) return;
        }
        if (target && !target.readOnly && typeof target.cut === "function") {
            target.cut();
        }
    }

    function _performDelete() {
        if (_hasMultiSelection()) {
            if (typeof editor.replaceSelectedRange === "function") {
                editor.replaceSelectedRange("");
                return;
            }
        }
        if (_useBlockEditor && target && target.readOnly && typeof editor.commitTargetSelectionEdit === "function") {
            if (editor.commitTargetSelectionEdit(target, false)) return;
        }
        if (target && !target.readOnly && typeof target.remove === "function") {
            target.remove(target.selectionStart, target.selectionEnd);
        }
    }

    readonly property real shadowPadding: 14
    readonly property real cornerGap: 3
    readonly property real maxMenuHeight: Math.min(520, (Screen.desktopAvailableHeight > 0) ? (Screen.desktopAvailableHeight - 80) : 520)
    property real _dynamicMaxMenuHeight: maxMenuHeight
    readonly property real targetMenuWidth: 272
    readonly property real targetMenuHeight: Math.min(Math.min(maxMenuHeight, _dynamicMaxMenuHeight), menuLayout.implicitHeight + 16)

    property bool _flipX: false
    property bool _flipY: false
    property real _anchorX: 120
    property real _anchorY: 120
    property real _anchorWinW: 1080
    property real _anchorWinH: 760

    width: targetMenuWidth + shadowPadding * 2
    height: targetMenuHeight + shadowPadding * 2

    property bool isExpanded: false
    property bool isClosing: false
    readonly property int windowRadius: (typeof HyprlandConfig !== "undefined" && HyprlandConfig.rounding >= 0) ? HyprlandConfig.rounding : 12

    property int highlightedNavIndex: -1

    function open(targetInput, customItems, showStandard) {
        if (!targetInput) return;
        closeTimer.stop();
        isClosing = false;
        highlightedNavIndex = -1;
        target = targetInput;
        extraItems = (customItems && Array.isArray(customItems)) ? customItems : [];
        showStandardItems = (typeof showStandard === "boolean") ? showStandard : true;
        if (targetInput.Window && targetInput.Window.window) {
            transientParent = targetInput.Window.window;
        }

        var gx = (typeof Sys !== "undefined") ? Sys.lastMouseX : 120;
        var gy = (typeof Sys !== "undefined") ? Sys.lastMouseY : 120;
        _applyCoordinates(targetInput, gx, gy);
    }

    function openAt(targetInput, xPos, yPos, customItems, showStandard) {
        if (!targetInput) return;
        closeTimer.stop();
        isClosing = false;
        highlightedNavIndex = -1;
        target = targetInput;
        extraItems = (customItems && Array.isArray(customItems)) ? customItems : [];
        showStandardItems = (typeof showStandard === "boolean") ? showStandard : true;
        if (targetInput.Window && targetInput.Window.window) {
            transientParent = targetInput.Window.window;
        }

        var cx = (typeof Sys !== "undefined") ? Sys.lastMouseX : 120;
        var cy = (typeof Sys !== "undefined") ? Sys.lastMouseY : 120;
        if (typeof xPos === "number" && typeof yPos === "number") {
            var pt = targetInput.mapToItem(null, xPos, yPos);
            cx = pt.x;
            cy = pt.y;
        }
        _applyCoordinates(targetInput, cx, cy);
    }

    function getActionableItems() {
        var list = [];
        if (extraItems && Array.isArray(extraItems)) {
            for (var i = 0; i < extraItems.length; i++) {
                var it = extraItems[i];
                if (!it || it.kind === "separator" || it.kind === "header") continue;
                if (it.enabled === false) continue;
                (function(itemObj, itemIndex) {
                    list.push({
                        type: "extra",
                        index: itemIndex,
                        trigger: function() {
                            if (typeof itemObj.onTriggered === "function") {
                                itemObj.onTriggered();
                            } else if (typeof itemObj.triggered === "function") {
                                itemObj.triggered();
                            }
                            menuWindow.extraItemTriggered(itemObj);
                            menuWindow.close();
                        }
                    });
                })(it, i);
            }
        }
        if (showStandardItems && isTextInputTarget) {
            if (_canEditMenuTarget && _canUndoEffective) {
                list.push({ type: "standard", id: "undo", trigger: function() { menuWindow._performUndo(); menuWindow.close(); } });
            }
            if (_canEditMenuTarget && _canRedoEffective) {
                list.push({ type: "standard", id: "redo", trigger: function() { menuWindow._performRedo(); menuWindow.close(); } });
            }
            if (_canEditMenuTarget && _hasAnySelection()) {
                list.push({ type: "standard", id: "cut", trigger: function() { _performCut(); menuWindow.close(); } });
            }
            if (target && _hasAnySelection()) {
                list.push({ type: "standard", id: "copy", trigger: function() { _performCopy(); menuWindow.close(); } });
            }
            if (_canPasteMenuTarget) {
                list.push({ type: "standard", id: "paste", trigger: function() { menuWindow._performPaste(); menuWindow.close(); } });
            }
            if (_canEditMenuTarget && _hasAnySelection()) {
                list.push({ type: "standard", id: "delete", trigger: function() { _performDelete(); menuWindow.close(); } });
            }
            if (target && target.text !== "") {
                list.push({ type: "standard", id: "selectAll", trigger: function() { if (target) target.selectAll(); menuWindow.close(); } });
            }
        }
        return list;
    }

    function isItemHighlighted(type, idOrIndex) {
        if (highlightedNavIndex < 0) return false;
        var items = getActionableItems();
        if (highlightedNavIndex >= items.length) return false;
        var cur = items[highlightedNavIndex];
        if (!cur) return false;
        if (cur.type !== type) return false;
        if (type === "extra") return cur.index === idOrIndex;
        return cur.id === idOrIndex;
    }

    function selectNextItem() {
        var items = getActionableItems();
        if (items.length === 0) {
            highlightedNavIndex = -1;
            return;
        }
        if (highlightedNavIndex < 0) {
            highlightedNavIndex = 0;
        } else {
            highlightedNavIndex = (highlightedNavIndex + 1) % items.length;
        }
    }

    function selectPreviousItem() {
        var items = getActionableItems();
        if (items.length === 0) {
            highlightedNavIndex = -1;
            return;
        }
        if (highlightedNavIndex <= 0) {
            highlightedNavIndex = items.length - 1;
        } else {
            highlightedNavIndex = (highlightedNavIndex - 1) % items.length;
        }
    }

    function triggerSelectedItem() {
        var items = getActionableItems();
        if (highlightedNavIndex >= 0 && highlightedNavIndex < items.length) {
            items[highlightedNavIndex].trigger();
            return true;
        }
        return false;
    }

    function toggleAtTextCursor(targetInput, customItems, showStandard) {
        if (visible && !isClosing) {
            close();
        } else {
            openAtTextCursor(targetInput, customItems, showStandard);
            highlightedNavIndex = 0;
        }
    }

    function openAtTextCursor(targetInput, customItems, showStandard) {
        if (!targetInput) return;
        closeTimer.stop();
        isClosing = false;
        highlightedNavIndex = -1;
        target = targetInput;
        extraItems = (customItems && Array.isArray(customItems)) ? customItems : [];
        showStandardItems = (typeof showStandard === "boolean") ? showStandard : true;
        if (targetInput.Window && targetInput.Window.window) {
            transientParent = targetInput.Window.window;
        }

        var curPos = (typeof targetInput.cursorPosition === "number") ? targetInput.cursorPosition : 0;
        var maxPos = (typeof targetInput.length === "number") ? targetInput.length : (targetInput.text ? targetInput.text.length : 0);
        curPos = Math.max(0, Math.min(curPos, maxPos));
        var rect = (typeof targetInput.positionToRectangle === "function") ? targetInput.positionToRectangle(curPos) : Qt.rect(0, 0, 0, 20);
        var pt = targetInput.mapToItem(null, rect.x, rect.y + rect.height);
        _applyCoordinates(targetInput, pt.x, pt.y);
    }

    function closeMenu() {
        close();
    }

    function close() {
        if (!visible || isClosing) return;
        highlightedNavIndex = -1;
        if (!Theme.animationsEnabled || GamemodeService.gamemodeActive) {
            forceClose();
            return;
        }
        isClosing = true;
        isExpanded = false;
        closeTimer.restart();
    }

    function forceClose() {
        closeTimer.stop();
        isClosing = false;
        isExpanded = false;
        visible = false;
        target = null;
        extraItems = [];
        highlightedNavIndex = -1;
    }

    Timer {
        id: closeTimer
        interval: 280
        repeat: false
        onTriggered: {
            menuWindow.visible = false;
            menuWindow.target = null;
            menuWindow.isClosing = false;
            menuWindow.extraItems = [];
            menuWindow.highlightedNavIndex = -1;
        }
    }

    onActiveChanged: {
        if (!active && visible && isExpanded && !isClosing) {
            close();
        }
    }

    Connections {
        target: menuWindow.transientParent
        function onActiveChanged() {
            if (menuWindow.transientParent && !menuWindow.transientParent.active && menuWindow.visible && !menuWindow.isClosing) {
                menuWindow.close();
            }
        }
    }

    Shortcut {
        enabled: menuWindow.visible && !menuWindow.isClosing
        sequence: "Escape"
        onActivated: menuWindow.close()
    }

    Connections {
        target: menuWindow.target && menuWindow.target.Window && menuWindow.target.Window.window ? menuWindow.target.Window.window : null
        enabled: menuWindow.target !== null && menuWindow.target.Window !== undefined && menuWindow.target.Window.window !== null
        ignoreUnknownSignals: true

        function onActiveChanged() {
            if (menuWindow.target && menuWindow.target.Window.window && !menuWindow.target.Window.window.active) {
                menuWindow.forceClose();
            }
        }
        function onVisibleChanged() {
            if (menuWindow.target && menuWindow.target.Window.window && !menuWindow.target.Window.window.visible) {
                menuWindow.forceClose();
            }
        }
    }

    Connections {
        target: menuWindow.target
        enabled: menuWindow.target !== null
        ignoreUnknownSignals: true

        function onVisibleChanged() {
            if (menuWindow.target && !menuWindow.target.visible) {
                menuWindow.forceClose();
            }
        }
    }

    onTargetMenuHeightChanged: {
        if (menuWindow.visible && !menuWindow.isClosing && menuWindow.target) {
            menuWindow._repositionFromAnchor();
        }
    }

    function _repositionFromAnchor() {
        var winW = menuWindow._anchorWinW > 0 ? menuWindow._anchorWinW : 1080;
        var winH = menuWindow._anchorWinH > 0 ? menuWindow._anchorWinH : 760;
        var cx = menuWindow._anchorX;
        var cy = menuWindow._anchorY;
        var gap = menuWindow.cornerGap;

        var menuW = menuWindow.targetMenuWidth;
        var availRight = winW - (cx + gap);
        var availLeft = cx - gap;
        var flipX = (availRight < menuW) && (availLeft >= menuW || availLeft > availRight);

        var naturalH = Math.min(menuWindow.maxMenuHeight, menuLayout.implicitHeight + 16);
        var availDown = winH - (cy + gap);
        var availUp = cy - gap;
        var flipY = (availDown < naturalH) && (availUp >= naturalH || availUp > availDown);

        var chosenVertSpace = flipY ? availUp : availDown;
        menuWindow._dynamicMaxMenuHeight = Math.max(120, Math.min(menuWindow.maxMenuHeight, chosenVertSpace - 4));
        var menuH = menuWindow.targetMenuHeight;

        menuWindow._flipX = flipX;
        menuWindow._flipY = flipY;

        var posX = flipX ? (cx - gap - menuW) : (cx + gap);
        var posY = flipY ? (cy - gap - menuH) : (cy + gap);

        menuWindow.x = Math.round(posX - menuWindow.shadowPadding);
        menuWindow.y = Math.round(posY - menuWindow.shadowPadding);
    }

    function _applyCoordinates(targetInput, cx, cy) {
        var win = (targetInput && targetInput.Window && targetInput.Window.window) ? targetInput.Window.window : null;
        menuWindow._anchorWinW = (win && win.width > 0) ? win.width : 1080;
        menuWindow._anchorWinH = (win && win.height > 0) ? win.height : 760;
        menuWindow._anchorX = cx;
        menuWindow._anchorY = cy;
        menuWindow._dynamicMaxMenuHeight = menuWindow.maxMenuHeight;

        menuWindow._repositionFromAnchor();

        if (!Theme.animationsEnabled || GamemodeService.gamemodeActive) {
            menuWindow.isExpanded = true;
            menuWindow.visible = true;
        } else {
            menuWindow.isExpanded = false;
            menuWindow.visible = true;
            Qt.callLater(function() {
                if (!menuWindow || menuWindow.isClosing || !menuWindow.visible) return;
                menuWindow._repositionFromAnchor();
                menuWindow.isExpanded = true;
            });
        }
    }

    // Dismiss al hacer clic en el margen/sombra exterior de la ventana emergente
    MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.AllButtons
        onPressed: menuWindow.close()
    }

    Rectangle {
        id: menuBox
        x: menuWindow.shadowPadding
        y: menuWindow.shadowPadding
        width: menuWindow.targetMenuWidth
        height: menuWindow.targetMenuHeight
        radius: menuWindow.windowRadius
        opacity: menuWindow.isExpanded ? 1.0 : 0.0
        scale: menuWindow.isExpanded ? 1.0 : 0.88
        transformOrigin: {
            if (menuWindow._flipX && menuWindow._flipY) return Item.BottomRight;
            if (menuWindow._flipX && !menuWindow._flipY) return Item.TopRight;
            if (!menuWindow._flipX && menuWindow._flipY) return Item.BottomLeft;
            return Item.TopLeft;
        }

        Behavior on scale {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        color: {
            var opacityVal = 0.96;
            if (GamemodeService.gamemodeActive) {
                opacityVal = 1.0;
            }
            var hue = Theme.surface ? (Theme.surface.hsvHue < 0 ? 0 : Theme.surface.hsvHue) : 0;
            var sat = Theme.surface ? Theme.surface.hsvSaturation : 0;
            var val = Theme.surface ? Math.min(1, Theme.surface.hsvValue + 0.05) : 0.2;
            return Qt.hsva(hue, sat, val, opacityVal);
        }
        border.color: Qt.hsva(Theme.text.hsvHue < 0 ? 0 : Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.12)
        border.width: 1

        layer.enabled: !GamemodeService.gamemodeActive
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#80000000"
            shadowBlur: 0.65
            shadowVerticalOffset: 6
        }

        Flickable {
            id: menuFlickable
            anchors.fill: parent
            anchors.margins: 6
            contentWidth: width
            contentHeight: menuLayout.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            ColumnLayout {
                id: menuLayout
                width: parent.width
                spacing: 0
// Elementos adicionales dinámicos (sin iconos, sugerencias, etc.)
                    Repeater {
                        model: menuWindow.extraItems
                        delegate: Item {
                            id: extraDelegate
                            required property var modelData
                            required property int index
                            readonly property var itemData: modelData
                            readonly property bool isSeparator: !!(itemData && itemData.kind === "separator")
                            readonly property bool isHeader: !!(itemData && itemData.kind === "header")
                            readonly property bool isAction: !isSeparator && !isHeader
                            readonly property bool isEnabled: !!(itemData && itemData.enabled !== false)
                            readonly property bool isItemActive: (extraMA.containsMouse || menuWindow.isItemHighlighted("extra", index)) && isEnabled

                            Layout.fillWidth: true
                            Layout.preferredHeight: isSeparator ? 9 : (isHeader ? 26 : 34)
                            visible: true

                            // Separador
                            Rectangle {
                                anchors.fill: parent
                                anchors.topMargin: 4
                                anchors.bottomMargin: 4
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                color: Qt.hsva(Theme.text.hsvHue < 0 ? 0 : Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.08)
                                visible: extraDelegate.isSeparator
                            }

                            // Encabezado
                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                verticalAlignment: Text.AlignVCenter
                                text: itemData ? (itemData.text || itemData.label || "") : ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                color: Theme.muted
                                elide: Text.ElideRight
                                visible: extraDelegate.isHeader
                            }

                            // Ítem de acción
                            Rectangle {
                                radius: 6
                                color: extraDelegate.isItemActive ? ((itemData && itemData.danger) ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.15) : Qt.hsva(Theme.accent.hsvHue < 0 ? 0 : Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.14)) : "transparent"
                                border.width: 0
                                visible: extraDelegate.isAction

                                anchors {
                                    fill: parent
                                    leftMargin: 4
                                    rightMargin: 4
                                    topMargin: 2
                                    bottomMargin: 2
                                }

                                Behavior on color {
                                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                    ColorAnimation { duration: 80 }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 10
                                visible: extraDelegate.isAction

                                Image {
                                    source: (itemData && itemData.icon) ? itemData.icon : ""
                                    sourceSize: Qt.size(16, 16)
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    fillMode: Image.PreserveAspectFit
                                    visible: !!(itemData && itemData.icon)
                                    layer.enabled: menuWindow.visible && !GamemodeService.gamemodeActive
                                    layer.effect: MultiEffect {
                                        colorization: 1.0
                                        colorizationColor: (itemData && itemData.danger)
                                            ? (Theme.danger || Theme.red)
                                            : (extraDelegate.isItemActive ? Theme.accent : Theme.text)
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: (itemData && (itemData.text || itemData.label)) ? (itemData.text || itemData.label) : (typeof itemData === "string" ? itemData : "")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.bold: !!(itemData && (itemData.bold || itemData.kind === "suggestion" || itemData.isSuggestion))
                                    color: (itemData && itemData.danger)
                                        ? (Theme.danger || Theme.red)
                                        : (extraDelegate.isItemActive ? Theme.accent : Theme.text)
                                    elide: Text.ElideRight
                                    opacity: extraDelegate.isEnabled ? 1.0 : 0.4
                                }

                                Text {
                                    text: (itemData && (itemData.shortcut || itemData.lang)) ? (itemData.shortcut || itemData.lang) : ""
                                    color: extraDelegate.isItemActive ? Theme.accent : Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    visible: text !== ""
                                }
                            }

                            MouseArea {
                                id: extraMA
                                anchors.fill: parent
                                hoverEnabled: extraDelegate.isAction && extraDelegate.isEnabled
                                cursorShape: (extraDelegate.isAction && extraDelegate.isEnabled) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                enabled: extraDelegate.isAction && extraDelegate.isEnabled
                                onClicked: {
                                    if (typeof itemData.onTriggered === "function") {
                                        itemData.onTriggered();
                                    } else if (typeof itemData.triggered === "function") {
                                        itemData.triggered();
                                    }
                                    menuWindow.extraItemTriggered(itemData);
                                    menuWindow.close();
                                }
                            }
                        }
                    }

                    // Separador divisorio entre extras y opciones estándar
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.hsva(Theme.text.hsvHue < 0 ? 0 : Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.08)
                        visible: (menuWindow.extraItems && menuWindow.extraItems.length > 0) &&
                                 (undoItem.visible || redoItem.visible || cutItem.visible || copyItem.visible || pasteItem.visible || deleteItem.visible || selectAllItem.visible)
                        Layout.topMargin: 4
                        Layout.bottomMargin: 4
                        Layout.leftMargin: 12
                        Layout.rightMargin: 12
                    }

                    // Deshacer
                    Item {
                        id: undoItem
                        visible: showStandardItems && isTextInputTarget && menuWindow._canEditMenuTarget
                        enabled: menuWindow._canUndoEffective
                        readonly property bool isItemActive: (undoMA.containsMouse || menuWindow.isItemHighlighted("standard", "undo")) && undoItem.enabled
                        opacity: enabled ? 1.0 : 0.4
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34

                        Rectangle {
                            radius: 6
                            color: undoItem.isItemActive ? Qt.hsva(Theme.accent.hsvHue < 0 ? 0 : Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.14) : "transparent"
                            border.width: 0

                            anchors {
                                fill: parent
                                leftMargin: 4
                                rightMargin: 4
                                topMargin: 2
                                bottomMargin: 2
                            }

                            Behavior on color { enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive; ColorAnimation { duration: 80 } }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12

                            Image {
                                source: Theme.iconsPath + "undo.svg"
                                sourceSize: Qt.size(16, 16)
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                fillMode: Image.PreserveAspectFit
                                layer.enabled: menuWindow.visible && !GamemodeService.gamemodeActive
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: undoItem.isItemActive ? Theme.accent : Theme.text
                                }
                            }

                            Item {
                                id: undoTextClip
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true

                                readonly property bool overflows: undoTextA.implicitWidth > undoTextClip.width
                                readonly property real gap: 24
                                readonly property real stride: undoTextA.implicitWidth + gap
                                property real offset: 0

                                SequentialAnimation on offset {
                                    running: undoTextClip.overflows && undoItem.isItemActive && Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                    loops: GamemodeService.gamemodeActive ? 0 : Animation.Infinite
                                    PauseAnimation { duration: 1000 }
                                    NumberAnimation {
                                        from: 0; to: -undoTextClip.stride
                                        duration: undoTextClip.stride * 18
                                        easing.type: Easing.Linear
                                    }
                                }

                                Text {
                                    id: undoTextA
                                    x: undoTextClip.offset
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.t("common.actions.undo", "Deshacer")
                                    color: undoItem.isItemActive ? Theme.accent : Theme.text
                                    font { family: Theme.fontFamily; pixelSize: 13 }
                                }

                                Text {
                                    x: undoTextClip.offset + undoTextClip.stride
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: undoTextClip.overflows
                                    text: undoTextA.text
                                    color: undoTextA.color
                                    font: undoTextA.font
                                }
                            }

                            Text {
                                text: "Ctrl+Z"
                                color: undoItem.isItemActive ? Theme.accent : Theme.muted
                                font { family: Theme.fontFamily; pixelSize: 11 }
                            }
                        }

                        MouseArea {
                            id: undoMA
                            anchors.fill: parent
                            hoverEnabled: parent.enabled
                            cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onContainsMouseChanged: {
                                if (!containsMouse) undoTextClip.offset = 0;
                            }
                            onClicked: {
                                menuWindow._performUndo();
                                menuWindow.close();
                            }
                        }
                    }

                    // Rehacer
                    Item {
                        id: redoItem
                        visible: showStandardItems && isTextInputTarget && menuWindow._canEditMenuTarget
                        enabled: menuWindow._canRedoEffective
                        readonly property bool isItemActive: (redoMA.containsMouse || menuWindow.isItemHighlighted("standard", "redo")) && redoItem.enabled
                        opacity: enabled ? 1.0 : 0.4
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34

                        Rectangle {
                            radius: 6
                            color: redoItem.isItemActive ? Qt.hsva(Theme.accent.hsvHue < 0 ? 0 : Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.14) : "transparent"
                            border.width: 0

                            anchors {
                                fill: parent
                                leftMargin: 4
                                rightMargin: 4
                                topMargin: 2
                                bottomMargin: 2
                            }

                            Behavior on color { enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive; ColorAnimation { duration: 80 } }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12

                            Image {
                                source: Theme.iconsPath + "redo.svg"
                                sourceSize: Qt.size(16, 16)
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                fillMode: Image.PreserveAspectFit
                                layer.enabled: menuWindow.visible && !GamemodeService.gamemodeActive
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: redoItem.isItemActive ? Theme.accent : Theme.text
                                }
                            }

                            Item {
                                id: redoTextClip
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true

                                readonly property bool overflows: redoTextA.implicitWidth > redoTextClip.width
                                readonly property real gap: 24
                                readonly property real stride: redoTextA.implicitWidth + gap
                                property real offset: 0

                                SequentialAnimation on offset {
                                    running: redoTextClip.overflows && redoItem.isItemActive && Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                    loops: GamemodeService.gamemodeActive ? 0 : Animation.Infinite
                                    PauseAnimation { duration: 1000 }
                                    NumberAnimation {
                                        from: 0; to: -redoTextClip.stride
                                        duration: redoTextClip.stride * 18
                                        easing.type: Easing.Linear
                                    }
                                }

                                Text {
                                    id: redoTextA
                                    x: redoTextClip.offset
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.t("common.actions.redo", "Rehacer")
                                    color: redoItem.isItemActive ? Theme.accent : Theme.text
                                    font { family: Theme.fontFamily; pixelSize: 13 }
                                }

                                Text {
                                    x: redoTextClip.offset + redoTextClip.stride
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: redoTextClip.overflows
                                    text: redoTextA.text
                                    color: redoTextA.color
                                    font: redoTextA.font
                                }
                            }

                            Text {
                                text: "Ctrl+Shift+Z"
                                color: redoItem.isItemActive ? Theme.accent : Theme.muted
                                font { family: Theme.fontFamily; pixelSize: 11 }
                            }
                        }

                        MouseArea {
                            id: redoMA
                            anchors.fill: parent
                            hoverEnabled: parent.enabled
                            cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onContainsMouseChanged: {
                                if (!containsMouse) redoTextClip.offset = 0;
                            }
                            onClicked: {
                                menuWindow._performRedo();
                                menuWindow.close();
                            }
                        }
                    }

                    // Separador 1
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.hsva(Theme.text.hsvHue < 0 ? 0 : Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.08)
                        visible: showStandardItems && isTextInputTarget && (undoItem.visible || redoItem.visible)
                        Layout.topMargin: 4
                        Layout.bottomMargin: 4
                        Layout.leftMargin: 12
                        Layout.rightMargin: 12
                    }

                    // Cortar
                    Item {
                        id: cutItem
                        visible: showStandardItems && isTextInputTarget && menuWindow._canEditMenuTarget
                        enabled: target ? menuWindow._hasAnySelection() : false
                        readonly property bool isItemActive: (cutMA.containsMouse || menuWindow.isItemHighlighted("standard", "cut")) && cutItem.enabled
                        opacity: enabled ? 1.0 : 0.4
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34

                        Rectangle {
                            radius: 6
                            color: cutItem.isItemActive ? Qt.hsva(Theme.accent.hsvHue < 0 ? 0 : Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.14) : "transparent"
                            border.width: 0

                            anchors {
                                fill: parent
                                leftMargin: 4
                                rightMargin: 4
                                topMargin: 2
                                bottomMargin: 2
                            }

                            Behavior on color { enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive; ColorAnimation { duration: 80 } }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12

                            Image {
                                source: Theme.iconsPath + "content-cut.svg"
                                sourceSize: Qt.size(16, 16)
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                fillMode: Image.PreserveAspectFit
                                layer.enabled: menuWindow.visible && !GamemodeService.gamemodeActive
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: cutItem.isItemActive ? Theme.accent : Theme.text
                                }
                            }

                            Item {
                                id: cutTextClip
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true

                                readonly property bool overflows: cutTextA.implicitWidth > cutTextClip.width
                                readonly property real gap: 24
                                readonly property real stride: cutTextA.implicitWidth + gap
                                property real offset: 0

                                SequentialAnimation on offset {
                                    running: cutTextClip.overflows && cutItem.isItemActive && Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                    loops: GamemodeService.gamemodeActive ? 0 : Animation.Infinite
                                    PauseAnimation { duration: 1000 }
                                    NumberAnimation {
                                        from: 0; to: -cutTextClip.stride
                                        duration: cutTextClip.stride * 18
                                        easing.type: Easing.Linear
                                    }
                                }

                                Text {
                                    id: cutTextA
                                    x: cutTextClip.offset
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.t("common.actions.cut", "Cortar")
                                    color: cutItem.isItemActive ? Theme.accent : Theme.text
                                    font { family: Theme.fontFamily; pixelSize: 13 }
                                }

                                Text {
                                    x: cutTextClip.offset + cutTextClip.stride
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: cutTextClip.overflows
                                    text: cutTextA.text
                                    color: cutTextA.color
                                    font: cutTextA.font
                                }
                            }

                            Text {
                                text: "Ctrl+X"
                                color: cutItem.isItemActive ? Theme.accent : Theme.muted
                                font { family: Theme.fontFamily; pixelSize: 11 }
                            }
                        }

                        MouseArea {
                            id: cutMA
                            anchors.fill: parent
                            hoverEnabled: parent.enabled
                            cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onContainsMouseChanged: {
                                if (!containsMouse) cutTextClip.offset = 0;
                            }
                            onClicked: {
                                menuWindow._performCut();
                                menuWindow.close();
                            }
                        }
                    }

                    // Copiar
                    Item {
                        id: copyItem
                        visible: showStandardItems && isTextInputTarget && !!target
                        enabled: target ? menuWindow._hasAnySelection() : false
                        readonly property bool isItemActive: (copyMA.containsMouse || menuWindow.isItemHighlighted("standard", "copy")) && copyItem.enabled
                        opacity: enabled ? 1.0 : 0.4
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34

                        Rectangle {
                            radius: 6
                            color: copyItem.isItemActive ? Qt.hsva(Theme.accent.hsvHue < 0 ? 0 : Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.14) : "transparent"
                            border.width: 0

                            anchors {
                                fill: parent
                                leftMargin: 4
                                rightMargin: 4
                                topMargin: 2
                                bottomMargin: 2
                            }

                            Behavior on color { enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive; ColorAnimation { duration: 80 } }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12

                            Image {
                                source: Theme.iconsPath + "content-copy.svg"
                                sourceSize: Qt.size(16, 16)
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                fillMode: Image.PreserveAspectFit
                                layer.enabled: menuWindow.visible && !GamemodeService.gamemodeActive
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: copyItem.isItemActive ? Theme.accent : Theme.text
                                }
                            }

                            Item {
                                id: copyTextClip
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true

                                readonly property bool overflows: copyTextA.implicitWidth > copyTextClip.width
                                readonly property real gap: 24
                                readonly property real stride: copyTextA.implicitWidth + gap
                                property real offset: 0

                                SequentialAnimation on offset {
                                    running: copyTextClip.overflows && copyItem.isItemActive && Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                    loops: GamemodeService.gamemodeActive ? 0 : Animation.Infinite
                                    PauseAnimation { duration: 1000 }
                                    NumberAnimation {
                                        from: 0; to: -copyTextClip.stride
                                        duration: copyTextClip.stride * 18
                                        easing.type: Easing.Linear
                                    }
                                }

                                Text {
                                    id: copyTextA
                                    x: copyTextClip.offset
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.t("common.actions.copy", "Copiar")
                                    color: copyItem.isItemActive ? Theme.accent : Theme.text
                                    font { family: Theme.fontFamily; pixelSize: 13 }
                                }

                                Text {
                                    x: copyTextClip.offset + copyTextClip.stride
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: copyTextClip.overflows
                                    text: copyTextA.text
                                    color: copyTextA.color
                                    font: copyTextA.font
                                }
                            }

                            Text {
                                text: "Ctrl+C"
                                color: copyItem.isItemActive ? Theme.accent : Theme.muted
                                font { family: Theme.fontFamily; pixelSize: 11 }
                            }
                        }

                        MouseArea {
                            id: copyMA
                            anchors.fill: parent
                            hoverEnabled: parent.enabled
                            cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onContainsMouseChanged: {
                                if (!containsMouse) copyTextClip.offset = 0;
                            }
                            onClicked: {
                                menuWindow._performCopy();
                                menuWindow.close();
                            }
                        }
                    }

                    // Pegar
                    Item {
                        id: pasteItem
                        visible: showStandardItems && isTextInputTarget && menuWindow._canEditMenuTarget
                        enabled: menuWindow._canPasteMenuTarget
                        readonly property bool isItemActive: (pasteMA.containsMouse || menuWindow.isItemHighlighted("standard", "paste")) && pasteItem.enabled
                        opacity: enabled ? 1.0 : 0.4
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34

                        Rectangle {
                            radius: 6
                            color: pasteItem.isItemActive ? Qt.hsva(Theme.accent.hsvHue < 0 ? 0 : Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.14) : "transparent"
                            border.width: 0

                            anchors {
                                fill: parent
                                leftMargin: 4
                                rightMargin: 4
                                topMargin: 2
                                bottomMargin: 2
                            }

                            Behavior on color { enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive; ColorAnimation { duration: 80 } }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12

                            Image {
                                source: Theme.iconsPath + "content-paste.svg"
                                sourceSize: Qt.size(16, 16)
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                fillMode: Image.PreserveAspectFit
                                layer.enabled: menuWindow.visible && !GamemodeService.gamemodeActive
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: pasteItem.isItemActive ? Theme.accent : Theme.text
                                }
                            }

                            Item {
                                id: pasteTextClip
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true

                                readonly property bool overflows: pasteTextA.implicitWidth > pasteTextClip.width
                                readonly property real gap: 24
                                readonly property real stride: pasteTextA.implicitWidth + gap
                                property real offset: 0

                                SequentialAnimation on offset {
                                    running: pasteTextClip.overflows && pasteItem.isItemActive && Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                    loops: GamemodeService.gamemodeActive ? 0 : Animation.Infinite
                                    PauseAnimation { duration: 1000 }
                                    NumberAnimation {
                                        from: 0; to: -pasteTextClip.stride
                                        duration: pasteTextClip.stride * 18
                                        easing.type: Easing.Linear
                                    }
                                }

                                Text {
                                    id: pasteTextA
                                    x: pasteTextClip.offset
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.t("common.actions.paste", "Pegar")
                                    color: pasteItem.isItemActive ? Theme.accent : Theme.text
                                    font { family: Theme.fontFamily; pixelSize: 13 }
                                }

                                Text {
                                    x: pasteTextClip.offset + pasteTextClip.stride
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: pasteTextClip.overflows
                                    text: pasteTextA.text
                                    color: pasteTextA.color
                                    font: pasteTextA.font
                                }
                            }

                            Text {
                                text: "Ctrl+V"
                                color: pasteItem.isItemActive ? Theme.accent : Theme.muted
                                font { family: Theme.fontFamily; pixelSize: 11 }
                            }
                        }

                        MouseArea {
                            id: pasteMA
                            anchors.fill: parent
                            hoverEnabled: parent.enabled
                            cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onContainsMouseChanged: {
                                if (!containsMouse) pasteTextClip.offset = 0;
                            }
                            onClicked: {
                                menuWindow._performPaste();
                                menuWindow.close();
                            }
                        }
                    }

                    // Borrar (Delete)
                    Item {
                        id: deleteItem
                        visible: showStandardItems && isTextInputTarget && menuWindow._canEditMenuTarget
                        enabled: menuWindow._canEditMenuTarget && menuWindow._hasAnySelection()
                        readonly property bool isItemActive: (deleteMA.containsMouse || menuWindow.isItemHighlighted("standard", "delete")) && deleteItem.enabled
                        opacity: enabled ? 1.0 : 0.4
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34

                        Rectangle {
                            radius: 6
                            color: deleteItem.isItemActive ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.15) : "transparent"
                            border.width: 0

                            anchors {
                                fill: parent
                                leftMargin: 4
                                rightMargin: 4
                                topMargin: 2
                                bottomMargin: 2
                            }

                            Behavior on color { enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive; ColorAnimation { duration: 80 } }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12

                            Image {
                                source: Theme.iconsPath + "delete-red.svg"
                                sourceSize: Qt.size(16, 16)
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                fillMode: Image.PreserveAspectFit
                                layer.enabled: menuWindow.visible && !GamemodeService.gamemodeActive
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: deleteItem.isItemActive ? (Theme.danger || Theme.red) : Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.8)
                                }
                            }

                            Item {
                                id: deleteTextClip
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true

                                readonly property bool overflows: deleteTextA.implicitWidth > deleteTextClip.width
                                readonly property real gap: 24
                                readonly property real stride: deleteTextA.implicitWidth + gap
                                property real offset: 0

                                SequentialAnimation on offset {
                                    running: deleteTextClip.overflows && deleteItem.isItemActive && Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                    loops: GamemodeService.gamemodeActive ? 0 : Animation.Infinite
                                    PauseAnimation { duration: 1000 }
                                    NumberAnimation {
                                        from: 0; to: -deleteTextClip.stride
                                        duration: deleteTextClip.stride * 18
                                        easing.type: Easing.Linear
                                    }
                                }

                                Text {
                                    id: deleteTextA
                                    x: deleteTextClip.offset
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.t("common.actions.delete", "Borrar")
                                    color: deleteItem.isItemActive ? (Theme.danger || Theme.red) : Theme.text
                                    font { family: Theme.fontFamily; pixelSize: 13 }
                                }

                                Text {
                                    x: deleteTextClip.offset + deleteTextClip.stride
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: deleteTextClip.overflows
                                    text: deleteTextA.text
                                    color: deleteTextA.color
                                    font: deleteTextA.font
                                }
                            }

                            Text {
                                text: "Supr"
                                color: deleteItem.isItemActive ? (Theme.danger || Theme.red) : Theme.muted
                                font { family: Theme.fontFamily; pixelSize: 11 }
                            }
                        }

                        MouseArea {
                            id: deleteMA
                            anchors.fill: parent
                            hoverEnabled: parent.enabled
                            cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onContainsMouseChanged: {
                                if (!containsMouse) deleteTextClip.offset = 0;
                            }
                            onClicked: {
                                menuWindow._performDelete();
                                menuWindow.close();
                            }
                        }
                    }

                    // Separador 2
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.hsva(Theme.text.hsvHue < 0 ? 0 : Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.08)
                        visible: showStandardItems && isTextInputTarget && selectAllItem.visible && (undoItem.visible || redoItem.visible || cutItem.visible || copyItem.visible || pasteItem.visible || deleteItem.visible)
                        Layout.topMargin: 4
                        Layout.bottomMargin: 4
                        Layout.leftMargin: 12
                        Layout.rightMargin: 12
                    }

                    // Seleccionar todo
                    Item {
                        id: selectAllItem
                        visible: showStandardItems && isTextInputTarget && !!target
                        enabled: target ? target.text !== "" : false
                        readonly property bool isItemActive: (selectAllMA.containsMouse || menuWindow.isItemHighlighted("standard", "selectAll")) && selectAllItem.enabled
                        opacity: enabled ? 1.0 : 0.4
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34

                        Rectangle {
                            radius: 6
                            color: selectAllItem.isItemActive ? Qt.hsva(Theme.accent.hsvHue < 0 ? 0 : Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.14) : "transparent"
                            border.width: 0

                            anchors {
                                fill: parent
                                leftMargin: 4
                                rightMargin: 4
                                topMargin: 2
                                bottomMargin: 2
                            }

                            Behavior on color { enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive; ColorAnimation { duration: 80 } }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12

                            Image {
                                source: Theme.iconsPath + "select-all.svg"
                                sourceSize: Qt.size(16, 16)
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                fillMode: Image.PreserveAspectFit
                                layer.enabled: menuWindow.visible && !GamemodeService.gamemodeActive
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: selectAllItem.isItemActive ? Theme.accent : Theme.text
                                }
                            }

                            Item {
                                id: selectAllTextClip
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true

                                readonly property bool overflows: selectAllTextA.implicitWidth > selectAllTextClip.width
                                readonly property real gap: 24
                                readonly property real stride: selectAllTextA.implicitWidth + gap
                                property real offset: 0

                                SequentialAnimation on offset {
                                    running: selectAllTextClip.overflows && selectAllItem.isItemActive && Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                    loops: GamemodeService.gamemodeActive ? 0 : Animation.Infinite
                                    PauseAnimation { duration: 1000 }
                                    NumberAnimation {
                                        from: 0; to: -selectAllTextClip.stride
                                        duration: selectAllTextClip.stride * 18
                                        easing.type: Easing.Linear
                                    }
                                }

                                Text {
                                    id: selectAllTextA
                                    x: selectAllTextClip.offset
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.t("common.actions.select_all", "Seleccionar todo")
                                    color: selectAllItem.isItemActive ? Theme.accent : Theme.text
                                    font { family: Theme.fontFamily; pixelSize: 13 }
                                }

                                Text {
                                    x: selectAllTextClip.offset + selectAllTextClip.stride
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: selectAllTextClip.overflows
                                    text: selectAllTextA.text
                                    color: selectAllTextA.color
                                    font: selectAllTextA.font
                                }
                            }

                            Text {
                                text: "Ctrl+A"
                                color: selectAllItem.isItemActive ? Theme.accent : Theme.muted
                                font { family: Theme.fontFamily; pixelSize: 11 }
                            }
                        }

                        MouseArea {
                            id: selectAllMA
                            anchors.fill: parent
                            hoverEnabled: parent.enabled
                            cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onContainsMouseChanged: {
                                if (!containsMouse) selectAllTextClip.offset = 0;
                            }
                            onClicked: {
                                if (target) target.selectAll();
                                menuWindow.close();
                            }
                        }
                    }
                }
            }
        }
    }