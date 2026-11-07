import QtQuick
import Notas

Rectangle {
    id: root

    // ── Propiedades personalizables de estilo ────────────────────────────────
    property real cursorWidth: 2.5
    property real cursorRadius: cursorWidth / 2
    property color baseColor: Theme.accent
    property color cursorColor: baseColor

    property real selectionAlpha: 0.35
    property color selectionColor: Qt.hsva(baseColor.hsvHue, baseColor.hsvSaturation, baseColor.hsvValue, selectionAlpha)
    property color selectedTextColor: Theme.text

    // ── Doble cursor en selección y gotas táctiles estilo Android ────────────
    property bool dualSelectionCursor: true
    property bool _liveTouchDetected: false
    property bool touchHandlesEnabled: Theme.hasTouchscreen || _liveTouchDetected
    property real handleSize: 16
    property real hitboxSize: 38
    property real extraMargin: 38
    property real extraBottom: 48

    // ── Propiedades de selección coordinada multi-línea / multi-bloque ────────
    property bool multiSelectionMode: false
    property bool showStartBoundary: true
    property bool showEndBoundary: true
    property var externalHandleDragCallback: null

    // ── Indicador de teclas muertas (Dead Keys en español: ' ` ^ ¨ ~) ──────────
    property bool deadKeyIndicatorEnabled: true
    property color deadKeyColor: Theme.color2
    property bool isComposingDeadKey: false
    property string composingChar: ""
    property int composePosition: -1
    property int deadKeyDelayMs: 250
    property int deadKeyRolloverGuardMs: 150
    property double _lastTextChangeMs: 0
    property string _pendingDeadKeyGlyph: ""
    readonly property bool hasNativePlaceholder: root.targetInput !== null && ("placeholderText" in root.targetInput)
    readonly property bool isOverwrite: root.targetInput !== null && root.targetInput.overwriteMode === true

    Timer {
        id: deadKeyDelayTimer
        interval: root.deadKeyDelayMs
        repeat: false
        onTriggered: {
            if (root._pendingDeadKeyGlyph !== "" && (root.isInputFocused || (root.targetInput && root.targetInput.focus))) {
                if (!root.isComposingDeadKey) root.isComposingDeadKey = true;
                if (root.composingChar !== root._pendingDeadKeyGlyph) root.composingChar = root._pendingDeadKeyGlyph;
                var curPos = (root.targetInput && root.targetInput.cursorPosition !== undefined) ? root.targetInput.cursorPosition : -1;
                if (root.composePosition !== curPos) root.composePosition = curPos;
            }
        }
    }

    TextMetrics {
        id: slotMetrics
        font: (root.targetInput && root.targetInput.font) ? root.targetInput.font : undefined
        text: "o"
    }

    readonly property real deadKeySlotWidth: Math.max(8, Math.round(slotMetrics.width > 0 ? slotMetrics.width : ((targetInput && targetInput.cursorRectangle && targetInput.cursorRectangle.height > 0) ? targetInput.cursorRectangle.height * 0.55 : 10)))

    function isModifierKey(key) {
        return key === Qt.Key_Shift || key === Qt.Key_Control ||
               key === Qt.Key_Alt || key === Qt.Key_AltGr ||
               key === Qt.Key_Meta || key === Qt.Key_CapsLock;
    }

    function getDeadKeyGlyph(key) {
        switch (key) {
            case Qt.Key_Dead_Acute: return "´";
            case Qt.Key_Dead_Grave: return "`";
            case Qt.Key_Dead_Circumflex: return "^";
            case Qt.Key_Dead_Diaeresis: return "¨";
            case Qt.Key_Dead_Tilde: return "~";
            case Qt.Key_Dead_Caron: return "ˇ";
            case Qt.Key_Dead_Cedilla: return "¸";
            default: return "";
        }
    }

    function queueDeadKey(glyph) {
        if (!root.deadKeyIndicatorEnabled || glyph === "") return;
        root._pendingDeadKeyGlyph = glyph;
        deadKeyDelayTimer.restart();
    }

    function startDeadKeyCompose(glyph) {
        if (!root.deadKeyIndicatorEnabled || glyph === "") return;
        deadKeyDelayTimer.stop();
        if (root._pendingDeadKeyGlyph !== "") root._pendingDeadKeyGlyph = "";
        if (!root.isComposingDeadKey) root.isComposingDeadKey = true;
        if (root.composingChar !== glyph) root.composingChar = glyph;
        var curPos = (root.targetInput && root.targetInput.cursorPosition !== undefined) ? root.targetInput.cursorPosition : -1;
        if (root.composePosition !== curPos) root.composePosition = curPos;
    }

    function resetDeadKey() {
        deadKeyDelayTimer.stop();
        if (root._pendingDeadKeyGlyph !== "") root._pendingDeadKeyGlyph = "";
        if (root.isComposingDeadKey) root.isComposingDeadKey = false;
        if (root.composingChar !== "") root.composingChar = "";
        if (root.composePosition !== -1) root.composePosition = -1;
    }

    // Detecta si se usa como delegado directo (`cursorDelegate: CustomTextCursor {}`)
    // o como helper hijo (`CustomTextCursor {}`)
    readonly property bool actingAsCursor: parent !== null
        && parent.cursorDelegate !== undefined
        && parent.cursorDelegate !== null
        && parent.cursorDelegate !== cursorComp

    readonly property Item targetInput: parent

    readonly property bool hasSelection: targetInput !== null
        && targetInput.selectionStart !== undefined
        && targetInput.selectionEnd !== undefined
        && targetInput.selectionStart !== targetInput.selectionEnd

    readonly property bool isInputFocused: (targetInput !== null && targetInput.activeFocus === true)
        || (root.multiSelectionMode && root.hasSelection && targetInput !== null && targetInput.Window.window !== null && targetInput.Window.window.active)

    readonly property bool showTouchHandles: !root.actingAsCursor
        && root.touchHandlesEnabled
        && root.hasSelection
        && root.isInputFocused
        && root.targetInput !== null
        && root.targetInput.Window.window !== null
        && root.targetInput.Window.window.visible
        && ((root.startRect.height > 0 && (!root.multiSelectionMode || root.showStartBoundary))
            || (root.endRect.height > 0 && (!root.multiSelectionMode || root.showEndBoundary)))

    // Cálculo reactivo de rectángulos para selectionStart y selectionEnd
    readonly property rect startRect: {
        if (!hasSelection || !targetInput || typeof targetInput.positionToRectangle !== "function")
            return Qt.rect(0, 0, 0, 0)
        var _s = targetInput.selectionStart
        var _c = targetInput.cursorPosition
        var _cr = targetInput.cursorRectangle
        var rStart = targetInput.positionToRectangle(_s)
        var rCur = targetInput.positionToRectangle(_c)
        return Qt.rect(
            rStart.x + (_cr.x - rCur.x),
            rStart.y + (_cr.y - rCur.y),
            root.cursorWidth,
            rStart.height > 0 ? rStart.height : _cr.height
        )
    }

    readonly property rect endRect: {
        if (!hasSelection || !targetInput || typeof targetInput.positionToRectangle !== "function")
            return Qt.rect(0, 0, 0, 0)
        var _e = targetInput.selectionEnd
        var _c = targetInput.cursorPosition
        var _cr = targetInput.cursorRectangle
        var rEnd = targetInput.positionToRectangle(_e)
        var rCur = targetInput.positionToRectangle(_c)
        return Qt.rect(
            rEnd.x + (_cr.x - rCur.x),
            rEnd.y + (_cr.y - rCur.y),
            root.cursorWidth,
            rEnd.height > 0 ? rEnd.height : _cr.height
        )
    }

    // Rectángulo del extremo opuesto al cursorPosition activo
    readonly property rect anchorRect: (targetInput && targetInput.cursorPosition === targetInput.selectionStart)
        ? endRect
        : startRect

    readonly property bool anchorInBounds: targetInput !== null
        && anchorRect.height > 0
        && anchorRect.x >= -root.cursorWidth
        && anchorRect.x <= targetInput.width + root.cursorWidth
        && anchorRect.y >= -anchorRect.height
        && anchorRect.y <= targetInput.height

    x: 0
    y: 0
    z: 50
    width: actingAsCursor ? root.cursorWidth : 0
    height: actingAsCursor && targetInput ? targetInput.cursorRectangle.height : 0
    radius: root.cursorRadius
    color: root.cursorColor
    visible: actingAsCursor
        ? (isInputFocused && (hasSelection || (targetInput.cursorVisible !== undefined ? targetInput.cursorVisible : true)))
        : true
    transform: Translate {
        x: (root.actingAsCursor && root.deadKeyIndicatorEnabled && root.isComposingDeadKey && !root.hasSelection) ? root.deadKeySlotWidth : 0
        Behavior on x {
            NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
        }
    }

    // Detección en caliente de pantalla táctil por evento directo
    PointHandler {
        target: root.targetInput
        acceptedDevices: PointerDevice.TouchScreen
        onActiveChanged: {
            if (active && !root._liveTouchDetected) {
                root._liveTouchDetected = true
            }
        }
    }

    // ── 1. Cursor delegado principal en cursorPosition ───────────────────────
    Component {
        id: cursorComp
        Rectangle {
            width: (root.isOverwrite && !root.hasSelection) ? root.deadKeySlotWidth : root.cursorWidth
            radius: root.isOverwrite ? 2 : root.cursorRadius
            opacity: (root.isOverwrite && !root.hasSelection) ? 0.65 : 1.0
            color: root.cursorColor
            visible: parent
                ? (((parent.activeFocus || (root.multiSelectionMode && root.hasSelection))
                    && (root.hasSelection
                        ? (parent.cursorPosition === parent.selectionStart
                            ? (!root.multiSelectionMode || root.showStartBoundary)
                            : (!root.multiSelectionMode || root.showEndBoundary))
                        : (parent.cursorVisible !== undefined ? parent.cursorVisible : true))))
                : false
            transform: Translate {
                x: (!root.actingAsCursor && root.deadKeyIndicatorEnabled && root.isComposingDeadKey && !root.hasSelection) ? root.deadKeySlotWidth : 0
                Behavior on x {
                    NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
                }
            }
        }
    }

    // ── 2. Segundo cursor en el extremo inicial/opuesto de la selección ──────
    Rectangle {
        id: anchorCursor
        visible: !root.actingAsCursor
            && root.dualSelectionCursor
            && root.hasSelection
            && root.isInputFocused
            && root.anchorInBounds
            && (targetInput && targetInput.cursorPosition === targetInput.selectionStart
                ? (!root.multiSelectionMode || root.showEndBoundary)
                : (!root.multiSelectionMode || root.showStartBoundary))
        x: root.anchorRect.x
        y: root.anchorRect.y
        width: root.cursorWidth
        height: root.anchorRect.height
        radius: root.cursorRadius
        color: root.cursorColor
    }

    // ── 3. Indicador horizontal y glifo flotante de tecla muerta ──────────────
    Rectangle {
        id: deadKeyHorizontalBar
        visible: !root.actingAsCursor
            && root.deadKeyIndicatorEnabled
            && root.isComposingDeadKey
            && root.isInputFocused
            && !root.hasSelection
            && (root.targetInput ? (root.targetInput.cursorVisible !== undefined ? root.targetInput.cursorVisible : true) : false)
        x: (visible && root.targetInput && root.targetInput.cursorRectangle) ? root.targetInput.cursorRectangle.x : 0
        y: (visible && root.targetInput && root.targetInput.cursorRectangle) ? (root.targetInput.cursorRectangle.y + root.targetInput.cursorRectangle.height - root.cursorWidth) : 0
        width: root.deadKeySlotWidth
        height: root.cursorWidth
        radius: root.cursorRadius
        color: root.deadKeyColor
        z: 60

        opacity: (root.deadKeyIndicatorEnabled && root.isComposingDeadKey) ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: 90 }
        }
    }

    Text {
        id: deadKeyFloatingGlyph
        visible: !root.actingAsCursor
            && root.deadKeyIndicatorEnabled
            && root.isComposingDeadKey
            && root.isInputFocused
            && !root.hasSelection
            && (root.targetInput ? (root.targetInput.cursorVisible !== undefined ? root.targetInput.cursorVisible : true) : false)
        x: (visible && root.targetInput && root.targetInput.cursorRectangle) ? root.targetInput.cursorRectangle.x : 0
        y: (visible && root.targetInput && root.targetInput.cursorRectangle) ? root.targetInput.cursorRectangle.y : 0
        width: root.deadKeySlotWidth
        height: (visible && root.targetInput && root.targetInput.cursorRectangle) ? Math.max(1, root.targetInput.cursorRectangle.height - root.cursorWidth) : 16
        text: root.composingChar
        color: root.deadKeyColor
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.family: (root.targetInput && root.targetInput.font && root.targetInput.font.family) ? root.targetInput.font.family : "sans-serif"
        font.pixelSize: (root.targetInput && root.targetInput.font && root.targetInput.font.pixelSize) ? Math.max(11, Math.round(root.targetInput.font.pixelSize * 0.95)) : 13
        font.bold: true
        z: 60

        opacity: (root.deadKeyIndicatorEnabled && root.isComposingDeadKey) ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: 90 }
        }
    }

    // ── Conexión a eventos de teclado y cambios de estado en targetInput ─────
    Connections {
        target: root.targetInput ? root.targetInput.Keys : null
        function onPressed(event) {
            if (!root.deadKeyIndicatorEnabled || !root.targetInput) return;
            if (root.isModifierKey(event.key)) return;

            var glyph = root.getDeadKeyGlyph(event.key);
            if (glyph !== "") {
                root.queueDeadKey(glyph);
            } else {
                root.resetDeadKey();
            }
        }
        function onReleased(event) {
            if (!root.deadKeyIndicatorEnabled || !root.targetInput) return;
            if (root.isModifierKey(event.key)) return;

            var glyph = root.getDeadKeyGlyph(event.key);
            if (glyph !== "") {
                var elapsed = Date.now() - root._lastTextChangeMs;
                if (!root.isComposingDeadKey && !deadKeyDelayTimer.running && elapsed > root.deadKeyRolloverGuardMs) {
                    root.queueDeadKey(glyph);
                }
            }
        }
    }

    Connections {
        target: root.targetInput
        function onTextChanged() {
            root._lastTextChangeMs = Date.now();
            root.resetDeadKey();
        }
        function onActiveFocusChanged() {
            if (root.targetInput && !root.targetInput.activeFocus) {
                root.resetDeadKey();
            }
        }
        function onCursorPositionChanged() {
            if (root.isComposingDeadKey && root.targetInput && root.composePosition >= 0) {
                if (root.targetInput.cursorPosition !== root.composePosition) {
                    root.resetDeadKey();
                }
            }
        }
    }

    readonly property string _targetPreeditText: (root.targetInput !== null && typeof root.targetInput.preeditText === "string") ? root.targetInput.preeditText : ""
    on_TargetPreeditTextChanged: {
        if (!root.deadKeyIndicatorEnabled) return;
        if (_targetPreeditText.length > 0) {
            root.queueDeadKey(_targetPreeditText);
        } else if (root.isComposingDeadKey && root.targetInput && (root.targetInput.inputMethodComposing === false)) {
            root.resetDeadKey();
        }
    }

    // ── 3. Gotas táctiles Android en capa Wayland independiente (PopupWindow) ──
    // Renderizado en superficie Wayland separada para escapar 100% de cualquier clip:true
    Loader {
        id: touchHandlesLoader
        active: root.showTouchHandles
        sourceComponent: Component {
            Item {
                id: handlePopup
                parent: root.targetInput
                x: -root.extraMargin
                y: 0
                width: Math.max(1, (root.targetInput ? root.targetInput.width : 1) + (root.extraMargin * 2))
                height: Math.max(1, (root.targetInput ? root.targetInput.height : 1) + root.extraBottom)
                visible: true

                // ── Gota táctil Android inicial (debajo de selectionStart) ───────────
                Item {
                    id: startHitbox
                    visible: (!root.multiSelectionMode || root.showStartBoundary) && root.startRect.height > 0
                    x: root.extraMargin + root.startRect.x + (root.cursorWidth / 2) - root.handleSize - ((root.hitboxSize - root.handleSize) / 2)
                    y: root.startRect.y + root.startRect.height - ((root.hitboxSize - root.handleSize) / 2) + 1
                    width: root.hitboxSize
                    height: root.hitboxSize

                    Item {
                        id: startVisual
                        anchors.centerIn: parent
                        width: root.handleSize
                        height: root.handleSize

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: root.cursorColor
                        }
                        Rectangle {
                            width: Math.ceil(parent.width / 2)
                            height: Math.ceil(parent.height / 2)
                            anchors.top: parent.top
                            anchors.right: parent.right
                            radius: 1
                            color: root.cursorColor
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        preventStealing: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: function(mouse) {
                            if (!pressed || !root.targetInput || typeof root.targetInput.positionAt !== "function") return
                            if (typeof root.externalHandleDragCallback === "function") {
                                var globalPt = mapToItem(null, mouse.x, mouse.y)
                                root.externalHandleDragCallback(true, globalPt.x, globalPt.y)
                                return
                            }
                            var pt = mapToItem(null, mouse.x, mouse.y)
                            var rCur = root.targetInput.positionToRectangle(root.targetInput.cursorPosition)
                            var dx = root.targetInput.cursorRectangle.x - rCur.x
                            var dy = root.targetInput.cursorRectangle.y - rCur.y
                            var sampleX = (pt.x - root.extraMargin) - dx + (root.handleSize / 2)
                            var sampleY = pt.y - dy - (root.startRect.height / 2)
                            var newPos = root.targetInput.positionAt(sampleX, sampleY)
                            var endPos = root.targetInput.selectionEnd
                            if (newPos !== root.targetInput.selectionStart && newPos <= endPos) {
                                root.targetInput.select(newPos, endPos)
                            }
                        }
                    }
                }

                // ── Gota táctil Android final (debajo de selectionEnd) ─────────────
                Item {
                    id: endHitbox
                    visible: (!root.multiSelectionMode || root.showEndBoundary) && root.endRect.height > 0
                    x: root.extraMargin + root.endRect.x + (root.cursorWidth / 2) - ((root.hitboxSize - root.handleSize) / 2)
                    y: root.endRect.y + root.endRect.height - ((root.hitboxSize - root.handleSize) / 2) + 1
                    width: root.hitboxSize
                    height: root.hitboxSize

                    Item {
                        id: endVisual
                        anchors.centerIn: parent
                        width: root.handleSize
                        height: root.handleSize

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: root.cursorColor
                        }
                        Rectangle {
                            width: Math.ceil(parent.width / 2)
                            height: Math.ceil(parent.height / 2)
                            anchors.top: parent.top
                            anchors.left: parent.left
                            radius: 1
                            color: root.cursorColor
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        preventStealing: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: function(mouse) {
                            if (!pressed || !root.targetInput || typeof root.targetInput.positionAt !== "function") return
                            if (typeof root.externalHandleDragCallback === "function") {
                                var globalPt2 = mapToItem(null, mouse.x, mouse.y)
                                root.externalHandleDragCallback(false, globalPt2.x, globalPt2.y)
                                return
                            }
                            var pt = mapToItem(null, mouse.x, mouse.y)
                            var rCur = root.targetInput.positionToRectangle(root.targetInput.cursorPosition)
                            var dx = root.targetInput.cursorRectangle.x - rCur.x
                            var dy = root.targetInput.cursorRectangle.y - rCur.y
                            var sampleX = (pt.x - root.extraMargin) - dx - (root.handleSize / 2)
                            var sampleY = pt.y - dy - (root.endRect.height / 2)
                            var newPos = root.targetInput.positionAt(sampleX, sampleY)
                            var startPos = root.targetInput.selectionStart
                            if (newPos !== root.targetInput.selectionEnd && newPos >= startPos) {
                                root.targetInput.select(startPos, newPos)
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Bindings automáticos sobre el input padre ────────────────────────────
    Binding {
        target: root.targetInput
        property: "cursorDelegate"
        value: cursorComp
        when: !root.actingAsCursor && root.targetInput !== null && root.targetInput.cursorDelegate !== undefined
        restoreMode: Binding.RestoreBindingOrValue
    }

    Binding {
        target: root.targetInput
        property: "selectionColor"
        value: root.selectionColor
        when: root.targetInput !== null && root.targetInput.selectionColor !== undefined
        restoreMode: Binding.RestoreBindingOrValue
    }

    Binding {
        target: root.targetInput
        property: "selectedTextColor"
        value: root.selectedTextColor
        when: root.targetInput !== null && root.targetInput.selectedTextColor !== undefined
        restoreMode: Binding.RestoreBindingOrValue
    }

    Binding {
        target: root.hasNativePlaceholder ? root.targetInput : null
        property: "placeholderText"
        value: ""
        when: root.hasNativePlaceholder && (root.isComposingDeadKey || deadKeyDelayTimer.running)
        restoreMode: Binding.RestoreBindingOrValue
    }
}
