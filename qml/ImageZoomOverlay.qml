import QtQuick
import QtQuick.Window
import QtQuick.Effects
import Notas
import "."

// Visor ampliado (lightbox) de imágenes en ventana completa con morphing SpringAnimation,
// zoom suave con rueda hasta ~1x1 cm por píxel real, paneo con botón central y cierre por X/ESC.
Item {
    id: root

    anchors.fill: parent
    z: 9500
    visible: isOpen || isClosing

    signal closed()

    property bool isOpen: false
    property bool isExpanded: false
    property bool isClosing: false
    property bool _springActive: false
    property bool _isDestroyed: false

    property string imageSource: ""
    property real natW: 0
    property real natH: 0
    property Item sourceItem: null
    property rect originRect: Qt.rect(0, 0, 100, 100)

    property real currentScale: 1.0
    property real panX: 0.0
    property real panY: 0.0
    property bool isPanning: false

    readonly property real pxPerCm: {
        var dpr = Math.max(1.0, Screen.devicePixelRatio || 1.0);
        var densityMm = (Screen.pixelDensity > 0) ? Screen.pixelDensity : (96.0 / 25.4);
        return Math.max(24.0, Math.min(120.0, (densityMm * 10.0) / dpr));
    }

    readonly property real effectiveNatW: (natW > 0) ? natW : (zoomImg.implicitWidth > 0 ? zoomImg.implicitWidth : 600)
    readonly property real effectiveNatH: (natH > 0) ? natH : (zoomImg.implicitHeight > 0 ? zoomImg.implicitHeight : 400)

    readonly property real fitScale: {
        var maxW = Math.max(120, root.width - 96);
        var maxH = Math.max(120, root.height - 96);
        return Math.max(0.05, Math.min(maxW / effectiveNatW, maxH / effectiveNatH));
    }
    readonly property real minScale: Math.min(0.25, fitScale * 0.5)
    readonly property real maxScale: Math.max(fitScale, pxPerCm)

    readonly property real dispW: Math.max(24, effectiveNatW * currentScale)
    readonly property real dispH: Math.max(24, effectiveNatH * currentScale)
    readonly property bool canPan: isExpanded && !isClosing && (dispW > root.width || dispH > root.height || currentScale > fitScale * 1.02)

    readonly property real targetX: Math.round((root.width - dispW) / 2 + panX)
    readonly property real targetY: Math.round((root.height - dispH) / 2 + panY)

    Component.onDestruction: {
        _isDestroyed = true;
    }

    function _captureOriginRect(item) {
        if (item && item.width > 0 && item.height > 0 && typeof item.mapToItem === "function") {
            var pt = item.mapToItem(root, 0, 0);
            return Qt.rect(pt.x, pt.y, item.width, item.height);
        }
        return Qt.rect(Math.round(root.width / 2 - 48), Math.round(root.height / 2 - 48), 96, 96);
    }

    function _clampPan(px, py, customW, customH) {
        var w = (customW !== undefined) ? customW : root.dispW;
        var h = (customH !== undefined) ? customH : root.dispH;
        var slackX = Math.min(120, root.width * 0.2);
        var slackY = Math.min(120, root.height * 0.2);
        var maxPx = (w > root.width - 64) ? Math.max(0, (w - root.width) / 2 + slackX) : 0;
        var maxPy = (h > root.height - 64) ? Math.max(0, (h - root.height) / 2 + slackY) : 0;
        return {
            x: Math.max(-maxPx, Math.min(maxPx, px)),
            y: Math.max(-maxPy, Math.min(maxPy, py))
        };
    }

    function open(srcUrl, srcItem, naturalW, naturalH) {
        if (!srcUrl || root._isDestroyed) return;
        closeSettleTimer.stop();
        root.isClosing = false;
        root.isPanning = false;
        root._springActive = false;
        root.isExpanded = false;

        root.sourceItem = srcItem || null;
        root.originRect = root._captureOriginRect(srcItem);
        root.natW = (typeof naturalW === "number" && naturalW > 0) ? naturalW : 0;
        root.natH = (typeof naturalH === "number" && naturalH > 0) ? naturalH : 0;
        root.imageSource = srcUrl;
        root.panX = 0.0;
        root.panY = 0.0;
        root.currentScale = root.fitScale;
        root.isOpen = true;

        if (!Theme.animationsEnabled || GamemodeService.gamemodeActive) {
            root.isExpanded = true;
            return;
        }

        Qt.callLater(function() {
            if (!root || root._isDestroyed || !root.isOpen || root.isClosing) return;
            root._springActive = true;
            root.isExpanded = true;
        });
    }

    function _finishClose() {
        if (root._isDestroyed) return;
        closeSettleTimer.stop();
        root._springActive = false;
        root.isOpen = false;
        root.isClosing = false;
        root.isExpanded = false;
        root.isPanning = false;
        root.imageSource = "";
        root.sourceItem = null;
        root.closed();
    }

    function close() {
        if ((!root.isOpen && !root.isExpanded) || root.isClosing) return;
        root.isPanning = false;

        if (root.sourceItem) {
            root.originRect = root._captureOriginRect(root.sourceItem);
        }

        if (!Theme.animationsEnabled || GamemodeService.gamemodeActive) {
            root._finishClose();
            return;
        }

        root._springActive = true;
        root.isClosing = true;
        root.isExpanded = false;
        closeSettleTimer.restart();
    }

    onWidthChanged: {
        if (isExpanded && !isClosing && Math.abs(currentScale - fitScale) < 0.02) {
            currentScale = fitScale;
            panX = 0;
            panY = 0;
        }
    }
    onHeightChanged: {
        if (isExpanded && !isClosing && Math.abs(currentScale - fitScale) < 0.02) {
            currentScale = fitScale;
            panX = 0;
            panY = 0;
        }
    }

    Timer {
        id: closeSettleTimer
        interval: 460
        repeat: false
        onTriggered: root._finishClose()
    }

    // Fondo oscurecido en toda la ventana
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: "#000000"
        opacity: (root.isExpanded && !root.isClosing) ? 0.84 : 0.0

        Behavior on opacity {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
    }

    // Contenedor de imagen con la misma física SpringAnimation de apertura/cierre de notas y ajustes
    Rectangle {
        id: imgFrame
        z: 5
        x: root.isExpanded ? root.targetX : root.originRect.x
        y: root.isExpanded ? root.targetY : root.originRect.y
        width: root.isExpanded ? root.dispW : Math.max(24, root.originRect.width)
        height: root.isExpanded ? root.dispH : Math.max(24, root.originRect.height)
        radius: root.isExpanded ? (root.canPan ? 2 : 10) : 8
        color: "transparent"
        clip: true

        Behavior on x {
            enabled: root._springActive && Theme.animationsEnabled && !GamemodeService.gamemodeActive
            SpringAnimation { id: springX; spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25 }
        }
        Behavior on y {
            enabled: root._springActive && Theme.animationsEnabled && !GamemodeService.gamemodeActive
            SpringAnimation { id: springY; spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25 }
        }
        Behavior on width {
            enabled: root._springActive && Theme.animationsEnabled && !GamemodeService.gamemodeActive
            SpringAnimation {
                id: springW
                spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25
                onRunningChanged: {
                    if (!running && root.isClosing && !springH.running) {
                        root._finishClose();
                    }
                }
            }
        }
        Behavior on height {
            enabled: root._springActive && Theme.animationsEnabled && !GamemodeService.gamemodeActive
            SpringAnimation {
                id: springH
                spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25
                onRunningChanged: {
                    if (!running && root.isClosing && !springW.running) {
                        root._finishClose();
                    }
                }
            }
        }
        Behavior on radius {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        AnimatedImage {
            id: zoomImg
            anchors.fill: parent
            asynchronous: true
            cache: true
            smooth: root.currentScale < 3.5
            fillMode: Image.PreserveAspectFit
            playing: !root._isDestroyed && root.isOpen && Theme.animationsEnabled && !GamemodeService.gamemodeActive && Qt.application.active
            paused: GamemodeService.gamemodeActive || !playing
            source: root.imageSource

            onStatusChanged: {
                if (status === Image.Ready && implicitWidth > 0 && implicitHeight > 0) {
                    var wasDefault = (root.natW <= 0 || root.natH <= 0);
                    root.natW = implicitWidth;
                    root.natH = implicitHeight;
                    if (wasDefault) {
                        root.currentScale = root.fitScale;
                    }
                }
            }
        }
    }

    // Interacción: paneo con botón del medio (+ cursor) y cierre al clickear fuera de la imagen
    MouseArea {
        id: overlayMa
        anchors.fill: parent
        z: 10
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        property real startMouseX: 0
        property real startMouseY: 0
        property real startPanX: 0
        property real startPanY: 0

        readonly property bool pointerOverImage: {
            return mouseX >= imgFrame.x && mouseX <= (imgFrame.x + imgFrame.width)
                && mouseY >= imgFrame.y && mouseY <= (imgFrame.y + imgFrame.height);
        }

        cursorShape: {
            if (root.isPanning) return Qt.ClosedHandCursor;
            if (root.canPan && pointerOverImage) return Qt.OpenHandCursor;
            return Qt.ArrowCursor;
        }

        onPressed: (mouse) => {
            if (mouse.button === Qt.MiddleButton) {
                if (root.canPan) {
                    root._springActive = false;
                    root.isPanning = true;
                    startMouseX = mouse.x;
                    startMouseY = mouse.y;
                    startPanX = root.panX;
                    startPanY = root.panY;
                }
                mouse.accepted = true;
                return;
            }
            if (mouse.button === Qt.LeftButton) {
                var insideImg = (mouse.x >= imgFrame.x && mouse.x <= (imgFrame.x + imgFrame.width)
                              && mouse.y >= imgFrame.y && mouse.y <= (imgFrame.y + imgFrame.height));
                if (!insideImg) {
                    root.close();
                }
                mouse.accepted = true;
            }
        }

        onPositionChanged: (mouse) => {
            if (!root.isPanning) return;
            var clamped = root._clampPan(startPanX + (mouse.x - startMouseX), startPanY + (mouse.y - startMouseY));
            root.panX = clamped.x;
            root.panY = clamped.y;
        }

        onReleased: (mouse) => {
            if (mouse.button === Qt.MiddleButton) {
                root.isPanning = false;
            }
        }

        onCanceled: {
            root.isPanning = false;
        }
    }

    // Zoom continuo con rueda del ratón centrado en la posición del cursor (límite máximo ~1x1 cm/píxel)
    WheelHandler {
        id: zoomWheelHandler
        enabled: root.isOpen && !root.isClosing
        target: null
        acceptedDevices: PointerDevice.AllDevices
        onWheel: (event) => {
            event.accepted = true;
            if (!root.isExpanded || root.isClosing) return;

            var dy = event.angleDelta ? event.angleDelta.y : 0;
            if (dy === 0 && event.pixelDelta) dy = event.pixelDelta.y;
            if (dy === 0) return;

            root._springActive = false;

            var steps = Math.max(-3.0, Math.min(3.0, dy / 120.0));
            var factor = Math.pow(1.18, steps);
            var oldScale = root.currentScale;
            var newScale = Math.max(root.minScale, Math.min(root.maxScale, oldScale * factor));
            if (Math.abs(newScale - oldScale) < 0.0001) return;

            var pt = zoomWheelHandler.point.position;
            var mx = pt ? pt.x : (root.width / 2);
            var my = pt ? pt.y : (root.height / 2);

            var oldCenterX = root.width / 2 + root.panX;
            var oldCenterY = root.height / 2 + root.panY;
            var ratio = newScale / oldScale;
            var rawPanX = mx - (mx - oldCenterX) * ratio - root.width / 2;
            var rawPanY = my - (my - oldCenterY) * ratio - root.height / 2;

            var newW = Math.max(24, root.effectiveNatW * newScale);
            var newH = Math.max(24, root.effectiveNatH * newScale);
            var clamped = root._clampPan(rawPanX, rawPanY, newW, newH);

            root.currentScale = newScale;
            root.panX = clamped.x;
            root.panY = clamped.y;
        }
    }

    // Botón X superior derecho por fuera de la imagen (blanco -> Theme.color1 al hacer hover)
    Rectangle {
        id: closeBtn
        z: 20
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 24
        width: 38
        height: 38
        radius: 19
        color: closeMa.containsMouse
            ? Qt.rgba(Theme.color1.r, Theme.color1.g, Theme.color1.b, 0.18)
            : Qt.rgba(0, 0, 0, 0.48)
        border.width: 1
        border.color: closeMa.containsMouse
            ? Qt.rgba(Theme.color1.r, Theme.color1.g, Theme.color1.b, 0.55)
            : Qt.rgba(1, 1, 1, 0.18)
        opacity: (root.isExpanded && !root.isClosing) ? 1.0 : 0.0
        visible: opacity > 0.0

        Behavior on opacity {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        Behavior on color {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            ColorAnimation { duration: 150 }
        }
        Behavior on border.color {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            ColorAnimation { duration: 150 }
        }

        Image {
            anchors.centerIn: parent
            width: 20
            height: 20
            source: Theme.iconsPath + "x.svg"
            sourceSize: Qt.size(20, 20)
            layer.enabled: closeBtn.visible
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: closeMa.containsMouse ? Theme.color1 : "#ffffff"
                Behavior on colorizationColor {
                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                    ColorAnimation { duration: 150 }
                }
            }
        }

        MouseArea {
            id: closeMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: (mouse) => {
                mouse.accepted = true;
                root.close();
            }
        }
    }
}
