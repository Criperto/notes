import QtQuick
import Notas
import "."
import "SpellLogic.js" as SpellLogic

Item {
    id: root

    property var textItem: null
    property var ranges: []
    property bool active: true
    property color waveColor: Theme.color3

    anchors.fill: textItem ? textItem : parent
    visible: active && ranges && ranges.length > 0
    z: 2

    // Evitar interceptar eventos de ratón
    enabled: false

    function requestUpdate() {
        if (waveCanvas && waveCanvas.available) {
            waveCanvas.requestPaint();
        }
    }

    Timer {
        id: repaintDelayTimer
        interval: 60
        repeat: false
        onTriggered: root.requestUpdate()
    }

    Connections {
        target: root.textItem
        ignoreUnknownSignals: true
        function onPaintedWidthChanged() {
            root.requestUpdate();
            repaintDelayTimer.restart();
        }
        function onPaintedHeightChanged() {
            root.requestUpdate();
            repaintDelayTimer.restart();
        }
        function onTextChanged() {
            root.requestUpdate();
            repaintDelayTimer.restart();
        }
    }

    onVisibleChanged: {
        if (visible) {
            requestUpdate();
            repaintDelayTimer.restart();
        }
    }

    onRangesChanged: {
        requestUpdate();
        if (visible) repaintDelayTimer.restart();
    }
    onActiveChanged: requestUpdate()
    onWaveColorChanged: requestUpdate()
    onWidthChanged: {
        requestUpdate();
        if (visible) repaintDelayTimer.restart();
    }
    onHeightChanged: {
        requestUpdate();
        if (visible) repaintDelayTimer.restart();
    }

    Canvas {
        id: waveCanvas
        anchors.fill: parent
        renderTarget: Canvas.Image
        antialiasing: true

        onAvailableChanged: {
            if (available && root.visible) {
                root.requestUpdate();
                repaintDelayTimer.restart();
            }
        }

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            if (!root.active || !root.ranges || root.ranges.length === 0 || !root.textItem) {
                return;
            }

            var posToRect = function(pos) {
                if (root.textItem && typeof root.textItem.positionToRectangle === "function") {
                    return root.textItem.positionToRectangle(pos);
                }
                return null;
            };

            ctx.save();
            ctx.strokeStyle = root.waveColor;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";

            for (var i = 0; i < root.ranges.length; i++) {
                var r = root.ranges[i];
                if (!r || r.start === undefined || r.end === undefined || r.start >= r.end) continue;

                var segments = SpellLogic.calculateWaveSegments(posToRect, r.start, r.end);
                for (var s = 0; s < segments.length; s++) {
                    var seg = segments[s];
                    if (!seg || seg.width <= 0) continue;

                    var segH = seg.height || 18;
                    // Adaptación multi-escala proporcional a la altura de línea (H1..H6 y zoom)
                    var scale = Math.max(0.85, Math.min(2.5, segH / 18.0));
                    var lineWidth = 1.35 * Math.min(scale, 1.8);
                    var step = 3.6 * scale;
                    var amp = 1.35 * scale;
                    var baseLineY = seg.y - Math.max(1, Math.round(1.5 * scale));

                    ctx.lineWidth = lineWidth;
                    ctx.beginPath();
                    ctx.moveTo(seg.x, baseLineY);

                    var startX = seg.x;
                    var endX = seg.x + seg.width;
                    var curX = startX;
                    var up = true;

                    // Curva sinusoidal suave con bezier cuadrática sin picos verticales al final
                    while (curX < endX) {
                        var nextX = Math.min(endX, curX + step);
                        var midX = (curX + nextX) * 0.5;
                        var ratio = (nextX - curX) / step;
                        var ctrlY = baseLineY + (up ? -amp : amp) * ratio;
                        ctx.quadraticCurveTo(midX, ctrlY, nextX, baseLineY);
                        up = !up;
                        curX = nextX;
                    }
                    ctx.stroke();
                }
            }
            ctx.restore();
        }
    }
}
