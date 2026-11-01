import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Controls
import Notas
import "."
import "MermaidParser.js" as MermaidParser
import "MermaidShapes.js" as MermaidShapes
import "MermaidLayout.js" as MermaidLayout

Item {
    id: root

    property string source: ""
    property real availableWidth: parent ? parent.width : 500
    property bool liveEditMode: false

    readonly property bool parseOk: !!(layoutResult && layoutResult.ok)
    readonly property string errorMessage: (layoutResult && layoutResult.error) ? layoutResult.error.msg : ""
    readonly property bool isUnsupported: !!(layoutResult && layoutResult.unsupported)

    property var layoutResult: null

    readonly property real zoomK: (typeof EditorMetrics !== "undefined" && EditorMetrics.zoom) ? EditorMetrics.zoom : 1.0
    readonly property real naturalW: (layoutResult && typeof layoutResult.width === "number") ? layoutResult.width : 200
    readonly property real naturalH: (layoutResult && typeof layoutResult.height === "number") ? layoutResult.height : 80
    readonly property real renderScale: {
        var avail = availableWidth - 28;
        if (avail > 0 && naturalW * zoomK > avail) {
            return Math.max(avail / naturalW, zoomK * 0.65);
        }
        return zoomK;
    }

    implicitWidth: availableWidth
    implicitHeight: {
        if (!layoutResult) return 80;
        if (!layoutResult.ok) return Math.max(80, errorBanner.implicitHeight + 20);
        return Math.max(90, Math.round(naturalH * renderScale) + 24);
    }

    // TextMetrics para medición exacta de texto en espacio de diseño (base 1.0)
    TextMetrics {
        id: nodeTextMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody - 1
    }

    TextMetrics {
        id: edgeTextMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeCaption
    }

    function measureText(text, fontPx) {
        if (fontPx <= 12) {
            edgeTextMetrics.text = text || "";
            return {
                width: Math.max(16, Math.ceil(edgeTextMetrics.advanceWidth)),
                height: Math.max(14, Math.ceil(edgeTextMetrics.height * 1.25))
            };
        } else {
            nodeTextMetrics.text = text || "";
            return {
                width: Math.max(24, Math.ceil(nodeTextMetrics.advanceWidth)),
                height: Math.max(18, Math.ceil(nodeTextMetrics.height * 1.3))
            };
        }
    }

    function pieSliceColor(idx) {
        var palette = [
            Theme.color4,
            Theme.color2,
            Theme.color3,
            Theme.color5,
            Theme.color6,
            Theme.color1,
            Theme.color12,
            Theme.color10,
            Theme.color11,
            Theme.color13,
            Theme.color14
        ];
        return palette[Math.abs(idx || 0) % palette.length];
    }

    function journeyScoreColor(score) {
        if (score >= 5) return "#22c55e";
        if (score === 4) return Theme.accent;
        if (score === 3) return Theme.warning;
        return Theme.danger;
    }

    function xyPlotColor(plotItem, idx) {
        if (plotItem.type === "line") {
            var linePalette = [Theme.color11, Theme.color14, Theme.accent, Theme.color12];
            return linePalette[Math.abs(idx || 0) % linePalette.length] || Theme.accent;
        }
        return root.pieSliceColor(idx);
    }

    function visColor(vis) {
        if (vis === "+") return Theme.success;
        if (vis === "-") return Theme.danger;
        if (vis === "#") return Theme.warning;
        return Theme.muted;
    }

    Timer {
        id: updateDebounce
        interval: 160
        repeat: false
        onTriggered: root._recomputeLayout()
    }

    onSourceChanged: {
        if (root.liveEditMode) {
            updateDebounce.restart();
        } else {
            root._recomputeLayout();
        }
    }

    Component.onCompleted: root._recomputeLayout()

    function _recomputeLayout() {
        if (!source || source.trim() === "") {
            layoutResult = { ok: true, empty: true, width: 200, height: 60 };
            return;
        }

        var parsed = MermaidParser.parse(source);
        if (!parsed.ok) {
            layoutResult = parsed;
            return;
        }

        var res = MermaidLayout.layout(parsed, root.measureText, {
            maxWidth: 800,
            fontSize: Theme.fontSizeBody - 1
        });
        layoutResult = res;
    }

    // ── VISTA DE ERROR O NO SOPORTADO ────────────────────────────────────────
    Rectangle {
        id: errorBanner
        implicitWidth: Math.min(parent.width - 24, 460)
        implicitHeight: errCol.implicitHeight + 24
        width: implicitWidth
        height: implicitHeight
        anchors.centerIn: parent
        visible: !root.parseOk && !(root.layoutResult && root.layoutResult.empty)
        radius: 8
        color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.12)
        border.color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.35)
        border.width: 1

        ColumnLayout {
            id: errCol
            anchors.centerIn: parent
            width: parent.width - 24
            spacing: 6

            RowLayout {
                spacing: 8
                Image {
                    width: 16; height: 16
                    source: Theme.iconsPath + (root.isUnsupported ? "info.svg" : "alert.svg")
                    sourceSize: Qt.size(16, 16)
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: root.isUnsupported ? Theme.accent : Theme.danger
                    }
                }
                Text {
                    text: root.isUnsupported
                        ? I18n.t("notes.mermaid.unsupported", "Diagrama en desarrollo para próximas fases")
                        : I18n.t("notes.mermaid.syntax_error", "Error de sintaxis en diagrama Mermaid")
                    color: root.isUnsupported ? Theme.accent : Theme.danger
                    font.family: Theme.fontFamily
                    font.pixelSize: EditorMetrics.fs(Theme.fontSizeBody - 1)
                    font.bold: true
                }
            }

            Text {
                text: root.errorMessage
                color: Theme.text
                font.family: Theme.fontFamilyMonospace || "monospace"
                font.pixelSize: EditorMetrics.fs(Theme.fontSizeCaption)
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }
    }

    // ── VISTA PRINCIPAL DEL DIAGRAMA CON SCROLL HORIZONTAL SI DESBORDA ───────
    Flickable {
        id: diagramFlickable
        anchors.fill: parent
        anchors.margins: 6
        visible: root.parseOk && !(root.layoutResult && root.layoutResult.empty)
        clip: true
        flickableDirection: Flickable.HorizontalFlick
        contentWidth: Math.max(width, Math.round(root.naturalW * root.renderScale) + 24)
        contentHeight: Math.max(height, Math.round(root.naturalH * root.renderScale) + 12)

        ScrollBar.horizontal: CustomScrollBar {}

        Item {
            id: diagramContent
            width: Math.round(root.naturalW * root.renderScale)
            height: Math.round(root.naturalH * root.renderScale)
            x: Math.max(12, Math.round((diagramFlickable.width - width) / 2))
            y: (root.layoutResult && root.layoutResult.title) ? 2 : 6

            Item {
                id: scaledCanvas
                width: root.naturalW
                height: root.naturalH
                scale: root.renderScale
                transformOrigin: Item.TopLeft

                // ── Título del diagrama ──
                Text {
                    id: diagramTitle
                    visible: !!(root.layoutResult && root.layoutResult.title)
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (root.layoutResult && root.layoutResult.title) ? root.layoutResult.title : ""
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody + 1
                    font.bold: true
                }

                // ── 1. RENDERIZADO DE FLOWCHART Y STATE DIAGRAM ─────────────────
                Item {
                    id: flowchartGroup
                    visible: root.layoutResult && (root.layoutResult.type === "flowchart" || root.layoutResult.type === "stateDiagram")
                    anchors.fill: parent

                    // A. Subgrafos (Clusters de fondo)
                    Repeater {
                        model: (flowchartGroup.visible && root.layoutResult && root.layoutResult.subgraphs) ? root.layoutResult.subgraphs : []
                        delegate: Rectangle {
                            x: modelData.x
                            y: modelData.y
                            width: modelData.w
                            height: modelData.h
                            radius: 8
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.04)
                            border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                            border.width: 1

                            Rectangle {
                                anchors.top: parent.top
                                anchors.topMargin: 4
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(parent.width - 12, subTitleText.implicitWidth + 16)
                                height: 20
                                radius: 4
                                color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.85)
                                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2)
                                border.width: 1

                                Text {
                                    id: subTitleText
                                    anchors.centerIn: parent
                                    text: modelData.title || modelData.id
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }
                    }

                    // B. Aristas (Líneas y Curvas Bézier detrás de los nodos)
                    Repeater {
                        model: (flowchartGroup.visible && root.layoutResult && root.layoutResult.edges) ? root.layoutResult.edges : []
                        delegate: Item {
                            anchors.fill: parent
                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                antialiasing: true

                                // Curva Bézier de la arista
                                ShapePath {
                                    strokeColor: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.45)
                                    strokeWidth: modelData.thick ? 2.8 : 1.6
                                    fillColor: "transparent"
                                    strokeStyle: modelData.strokeDash ? ShapePath.DashLine : ShapePath.SolidLine
                                    dashPattern: [4, 4]
                                    capStyle: ShapePath.RoundCap

                                    PathSvg {
                                        path: modelData.path
                                    }
                                }
                            }
                        }
                    }

                    // C. Nodos del grafo
                    Repeater {
                        model: {
                            if (!flowchartGroup.visible || !root.layoutResult || !root.layoutResult.nodes) return [];
                            var arr = [];
                            for (var k in root.layoutResult.nodes) arr.push(root.layoutResult.nodes[k]);
                            return arr;
                        }
                        delegate: Item {
                            x: modelData.x
                            y: modelData.y
                            width: modelData.w
                            height: modelData.h

                            // Para nodos start (estado inicial): círculo sólido
                            Rectangle {
                                visible: modelData.shape === "start"
                                anchors.fill: parent
                                radius: width / 2
                                color: Theme.accent
                            }

                            // Para nodos end (estado terminal): anillo exterior y punto interior
                            Rectangle {
                                visible: modelData.shape === "end"
                                anchors.fill: parent
                                radius: width / 2
                                color: "transparent"
                                border.color: Theme.accent
                                border.width: 1.5

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: Math.max(8, parent.width - 10)
                                    height: width
                                    radius: width / 2
                                    color: Theme.accent
                                }
                            }

                            // Para el resto de formas: Shape con PathSvg
                            Shape {
                                visible: modelData.shape !== "start" && modelData.shape !== "end"
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                antialiasing: true

                                ShapePath {
                                    strokeColor: Theme.accent
                                    strokeWidth: 1.5
                                    fillColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                                    capStyle: ShapePath.RoundCap
                                    joinStyle: ShapePath.RoundJoin

                                    PathSvg {
                                        path: MermaidShapes.getShapePath(modelData.shape, modelData.w, modelData.h, 6)
                                    }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                width: parent.width - 12
                                visible: modelData.shape !== "start" && modelData.shape !== "end"
                                text: modelData.label || ""
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody - 1
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                wrapMode: Text.Wrap
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // D. Marcadores de flecha en extremos (renderizados sobre el borde de los nodos)
                    Repeater {
                        model: (flowchartGroup.visible && root.layoutResult && root.layoutResult.edges) ? root.layoutResult.edges : []
                        delegate: Item {
                            anchors.fill: parent
                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                antialiasing: true

                                ShapePath {
                                    strokeColor: Theme.accent
                                    strokeWidth: 1.4
                                    fillColor: (modelData.type === "arrow" || modelData.type === "circle") ? Theme.accent : "transparent"

                                    PathSvg {
                                        path: MermaidShapes.getArrowPath(modelData.type, modelData.endX, modelData.endY, modelData.endAngle, 9)
                                    }
                                }
                            }
                        }
                    }

                    // E. Etiquetas de aristas
                    Repeater {
                        model: (flowchartGroup.visible && root.layoutResult && root.layoutResult.edges) ? root.layoutResult.edges : []
                        delegate: Rectangle {
                            visible: !!(modelData.label && modelData.label.trim() !== "")
                            x: modelData.labelX - width / 2
                            y: modelData.labelY - height / 2
                            width: edgeText.implicitWidth + 10
                            height: edgeText.implicitHeight + 4
                            radius: 4
                            color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.95)
                            border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3)
                            border.width: 1

                            Text {
                                id: edgeText
                                anchors.centerIn: parent
                                text: modelData.label || ""
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeCaption
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }

                // ── 2. RENDERIZADO DE SEQUENCE DIAGRAM ───────────────────────────
                Item {
                    id: sequenceGroup
                    visible: root.layoutResult && root.layoutResult.type === "sequenceDiagram"
                    anchors.fill: parent

                    // Líneas de vida verticales
                    Repeater {
                        model: {
                            if (!sequenceGroup.visible || !root.layoutResult || !root.layoutResult.participants) return [];
                            var arr = [];
                            for (var pId in root.layoutResult.participants) arr.push(root.layoutResult.participants[pId]);
                            return arr;
                        }
                        delegate: Item {
                            anchors.fill: parent
                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                antialiasing: true

                                ShapePath {
                                    strokeColor: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.2)
                                    strokeWidth: 1.2
                                    strokeStyle: ShapePath.DashLine
                                    dashPattern: [4, 4]
                                    fillColor: "transparent"

                                    PathSvg {
                                        path: "M " + modelData.centerX + " " + (modelData.y + modelData.h) +
                                              " L " + modelData.centerX + " " + (root.layoutResult.lifeLineEndY || (parent.height - 20))
                                    }
                                }
                            }
                        }
                    }

                    // Cajas de participantes superiores
                    Repeater {
                        model: {
                            if (!sequenceGroup.visible || !root.layoutResult || !root.layoutResult.participants) return [];
                            var arr2 = [];
                            for (var pk in root.layoutResult.participants) arr2.push(root.layoutResult.participants[pk]);
                            return arr2;
                        }
                        delegate: Rectangle {
                            x: modelData.x
                            y: modelData.y
                            width: modelData.w
                            height: modelData.h
                            radius: modelData.isActor ? 16 : 8
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                            border.color: Theme.accent
                            border.width: 1.4

                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody - 1
                                font.bold: true
                            }
                        }
                    }

                    // Cajas de participantes inferiores (pie de línea de vida)
                    Repeater {
                        model: {
                            if (!sequenceGroup.visible || !root.layoutResult || !root.layoutResult.participants) return [];
                            var arrBottom = [];
                            for (var pb in root.layoutResult.participants) arrBottom.push(root.layoutResult.participants[pb]);
                            return arrBottom;
                        }
                        delegate: Rectangle {
                            x: modelData.x
                            y: root.layoutResult.lifeLineEndY || (parent.height - modelData.h - 10)
                            width: modelData.w
                            height: modelData.h
                            radius: modelData.isActor ? 16 : 8
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                            border.color: Theme.accent
                            border.width: 1.4

                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody - 1
                                font.bold: true
                            }
                        }
                    }

                    // Mensajes horizontales
                    Repeater {
                        model: (sequenceGroup.visible && root.layoutResult && root.layoutResult.messages) ? root.layoutResult.messages : []
                        delegate: Item {
                            width: parent.width
                            height: 36
                            y: modelData.y - 18

                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                antialiasing: true

                                ShapePath {
                                    strokeColor: Theme.accent
                                    strokeWidth: 1.5
                                    fillColor: "transparent"
                                    strokeStyle: modelData.dotted ? ShapePath.DashLine : ShapePath.SolidLine
                                    dashPattern: [4, 4]

                                    PathSvg {
                                        path: "M " + modelData.startX + " 18 L " + modelData.endX + " 18"
                                    }
                                }

                                // Flecha de destino
                                ShapePath {
                                    strokeColor: Theme.accent
                                    strokeWidth: 1.5
                                    fillColor: modelData.arrow === "arrow" ? Theme.accent : "transparent"

                                    PathSvg {
                                        path: {
                                            var angle = modelData.endX > modelData.startX ? 0 : Math.PI;
                                            return MermaidShapes.getArrowPath("arrow", modelData.endX, 18, angle, 8);
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                anchors.centerIn: msgText
                                width: msgText.implicitWidth + 8
                                height: msgText.implicitHeight + 2
                                radius: 3
                                color: Theme.surface
                                opacity: 0.95
                            }

                            Text {
                                id: msgText
                                x: (modelData.startX + modelData.endX) / 2 - implicitWidth / 2
                                y: 0
                                text: modelData.text
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeCaption
                            }
                        }
                    }

                    // Notas
                    Repeater {
                        model: (sequenceGroup.visible && root.layoutResult && root.layoutResult.notes) ? root.layoutResult.notes : []
                        delegate: Rectangle {
                            x: modelData.x
                            y: modelData.y
                            width: modelData.w
                            height: modelData.h
                            radius: 4
                            color: Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.18)
                            border.color: Theme.warning
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: modelData.text
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeCaption
                            }
                        }
                    }
                }

                // ── 3. RENDERIZADO DE PIE CHART ──────────────────────────────────
                Item {
                    id: pieGroup
                    visible: root.layoutResult && root.layoutResult.type === "pie"
                    anchors.fill: parent

                    Repeater {
                        model: (pieGroup.visible && root.layoutResult && root.layoutResult.slices) ? root.layoutResult.slices : []
                        delegate: Item {
                            anchors.fill: parent
                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                antialiasing: true

                                ShapePath {
                                    strokeColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.8)
                                    strokeWidth: 2
                                    fillColor: root.pieSliceColor(index)

                                    PathSvg {
                                        path: modelData.path
                                    }
                                }
                            }
                        }
                    }

                    // Porcentajes dentro de cada porción
                    Repeater {
                        model: (pieGroup.visible && root.layoutResult && root.layoutResult.slices) ? root.layoutResult.slices : []
                        delegate: Text {
                            visible: modelData.percent >= 5 && typeof modelData.labelX === "number"
                            x: modelData.labelX - implicitWidth / 2
                            y: modelData.labelY - implicitHeight / 2
                            text: modelData.percent + "%"
                            color: Theme.textOn(root.pieSliceColor(index))
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }

                    // Leyenda de torta al costado
                    Column {
                        x: (root.layoutResult && typeof root.layoutResult.legendX === "number") ? root.layoutResult.legendX : 240
                        y: (root.layoutResult && typeof root.layoutResult.legendY === "number") ? root.layoutResult.legendY : 20
                        spacing: 8
                        visible: pieGroup.visible

                        Repeater {
                            model: (pieGroup.visible && root.layoutResult && root.layoutResult.slices) ? root.layoutResult.slices : []
                            delegate: RowLayout {
                                spacing: 8
                                Rectangle {
                                    width: 12; height: 12
                                    radius: 3
                                    color: root.pieSliceColor(index)
                                }
                                Text {
                                    text: modelData.label + " (" + modelData.percent + "%)"
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeCaption
                                }
                            }
                        }
                    }
                }

                // ── 4. RENDERIZADO DE CLASS DIAGRAM Y ER DIAGRAM (UML) ───────────
                Item {
                    id: classDiagramGroup
                    visible: root.layoutResult && (root.layoutResult.type === "classDiagram" || root.layoutResult.type === "erDiagram")
                    anchors.fill: parent

                    // A. Aristas (Líneas y Curvas Bézier detrás de las clases)
                    Repeater {
                        model: {
                            if (!classDiagramGroup.visible || !root.layoutResult) return [];
                            return (root.layoutResult.edges || root.layoutResult.relations || []);
                        }
                        delegate: Item {
                            anchors.fill: parent
                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                antialiasing: true

                                ShapePath {
                                    strokeColor: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.45)
                                    strokeWidth: 1.6
                                    fillColor: "transparent"
                                    strokeStyle: modelData.strokeDash ? ShapePath.DashLine : ShapePath.SolidLine
                                    dashPattern: [4, 4]
                                    capStyle: ShapePath.RoundCap

                                    PathSvg {
                                        path: modelData.path
                                    }
                                }
                            }
                        }
                    }

                    // B. Marcadores en extremos de aristas (Herencia, Composición, Crow's foot)
                    Repeater {
                        model: {
                            if (!classDiagramGroup.visible || !root.layoutResult) return [];
                            return (root.layoutResult.edges || root.layoutResult.relations || []);
                        }
                        delegate: Item {
                            anchors.fill: parent
                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                antialiasing: true

                                ShapePath {
                                    strokeColor: Theme.accent
                                    strokeWidth: 1.4
                                    fillColor: (modelData.toMarker === "diamond_filled" || modelData.toMarker === "arrow")
                                        ? Theme.accent
                                        : (modelData.toMarker === "triangle" || modelData.toMarker === "triangle_hollow" || modelData.toMarker === "diamond_hollow")
                                            ? Theme.surface
                                            : "transparent"

                                    PathSvg {
                                        path: MermaidShapes.getArrowPath(modelData.toMarker, modelData.endX, modelData.endY, modelData.endAngle, 9)
                                    }
                                }
                            }
                        }
                    }

                    // C. Etiquetas de aristas y cardinalidades
                    Repeater {
                        model: {
                            if (!classDiagramGroup.visible || !root.layoutResult) return [];
                            return (root.layoutResult.edges || root.layoutResult.relations || []);
                        }
                        delegate: Item {
                            anchors.fill: parent

                            // Multiplicidad de origen
                            Text {
                                visible: !!(modelData.fromCard && modelData.fromCard.trim() !== "")
                                x: modelData.fromCardX
                                y: modelData.fromCardY
                                text: modelData.fromCard || ""
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                            }

                            // Multiplicidad de destino
                            Text {
                                visible: !!(modelData.toCard && modelData.toCard.trim() !== "")
                                x: modelData.toCardX
                                y: modelData.toCardY
                                text: modelData.toCard || ""
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                            }

                            // Etiqueta central de relación
                            Rectangle {
                                visible: !!(modelData.label && modelData.label.trim() !== "")
                                x: modelData.labelX - width / 2
                                y: modelData.labelY - height / 2
                                width: relLabelText.implicitWidth + 8
                                height: relLabelText.implicitHeight + 4
                                radius: 4
                                color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.95)
                                border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.2)
                                border.width: 1

                                Text {
                                    id: relLabelText
                                    anchors.centerIn: parent
                                    text: modelData.label || ""
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeCaption
                                }
                            }
                        }
                    }

                    // D. Cajas de Clases UML
                    Repeater {
                        model: {
                            if (!classDiagramGroup.visible || !root.layoutResult || root.layoutResult.type !== "classDiagram" || !root.layoutResult.nodes) return [];
                            var arr = [];
                            for (var k in root.layoutResult.nodes) arr.push(root.layoutResult.nodes[k]);
                            return arr;
                        }
                        delegate: Rectangle {
                            x: modelData.x
                            y: modelData.y
                            width: modelData.w
                            height: modelData.h
                            radius: 6
                            color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.9)
                            border.color: Theme.accent
                            border.width: 1.5

                            Column {
                                anchors.fill: parent

                                // Encabezado de clase
                                Rectangle {
                                    width: parent.width
                                    height: modelData.headerH
                                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                                    radius: 6

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 1

                                        Text {
                                            visible: !!modelData.stereotype
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: "<<" + (modelData.stereotype || "") + ">>"
                                            color: Theme.muted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.italic: true
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.label
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeBody - 1
                                            font.bold: true
                                        }
                                    }
                                }

                                // Divisor 1
                                Rectangle {
                                    width: parent.width
                                    height: 1
                                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
                                }

                                // Compartimento de Atributos
                                Column {
                                    width: parent.width
                                    anchors.margins: 4
                                    topPadding: 4
                                    bottomPadding: 4
                                    leftPadding: 8
                                    rightPadding: 8
                                    spacing: 3

                                    Repeater {
                                        model: modelData.attributes || []
                                        delegate: RowLayout {
                                            spacing: 6
                                            Text {
                                                text: modelData.visibility || ""
                                                color: root.visColor(modelData.visibility)
                                                font.family: "monospace"
                                                font.pixelSize: 11
                                                font.bold: true
                                            }
                                            Text {
                                                text: modelData.text
                                                color: Theme.text
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.italic: modelData.isAbstract
                                                font.underline: modelData.isStatic
                                            }
                                        }
                                    }
                                }

                                // Divisor 2 (sólo si hay métodos)
                                Rectangle {
                                    visible: modelData.methods && modelData.methods.length > 0
                                    width: parent.width
                                    height: 1
                                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
                                }

                                // Compartimento de Métodos
                                Column {
                                    visible: modelData.methods && modelData.methods.length > 0
                                    width: parent.width
                                    anchors.margins: 4
                                    topPadding: 4
                                    bottomPadding: 4
                                    leftPadding: 8
                                    rightPadding: 8
                                    spacing: 3

                                    Repeater {
                                        model: modelData.methods || []
                                        delegate: RowLayout {
                                            spacing: 6
                                            Text {
                                                text: modelData.visibility || ""
                                                color: root.visColor(modelData.visibility)
                                                font.family: "monospace"
                                                font.pixelSize: 11
                                                font.bold: true
                                            }
                                            Text {
                                                text: modelData.text
                                                color: Theme.text
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.italic: modelData.isAbstract
                                                font.underline: modelData.isStatic
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // E. Cajas de Entidades ER
                    Repeater {
                        model: {
                            if (!classDiagramGroup.visible || !root.layoutResult || root.layoutResult.type !== "erDiagram" || !root.layoutResult.entities) return [];
                            var arrEr = [];
                            for (var ek in root.layoutResult.entities) arrEr.push(root.layoutResult.entities[ek]);
                            return arrEr;
                        }
                        delegate: Rectangle {
                            x: modelData.x
                            y: modelData.y
                            width: modelData.w
                            height: modelData.h
                            radius: 6
                            color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.9)
                            border.color: Theme.accent
                            border.width: 1.5

                            Column {
                                anchors.fill: parent

                                // Encabezado de entidad ER
                                Rectangle {
                                    width: parent.width
                                    height: modelData.headerH
                                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                                    radius: 6

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.id
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody - 1
                                        font.bold: true
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 1
                                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
                                }

                                // Atributos de entidad ER
                                Column {
                                    width: parent.width
                                    topPadding: 4
                                    bottomPadding: 4
                                    leftPadding: 8
                                    rightPadding: 8
                                    spacing: 3

                                    Repeater {
                                        model: modelData.attributes || []
                                        delegate: RowLayout {
                                            spacing: 6
                                            Text {
                                                text: modelData.type
                                                color: Theme.muted
                                                font.family: "monospace"
                                                font.pixelSize: 11
                                            }
                                            Text {
                                                text: modelData.name
                                                color: Theme.text
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.bold: !!modelData.key
                                            }
                                            Rectangle {
                                                visible: !!modelData.key
                                                Layout.preferredWidth: keyText.implicitWidth + 6
                                                Layout.preferredHeight: 14
                                                radius: 3
                                                color: modelData.key === "PK" ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
                                                                              : Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.2)
                                                border.color: modelData.key === "PK" ? Theme.accent : Theme.warning
                                                border.width: 1
                                                Text {
                                                    id: keyText
                                                    anchors.centerIn: parent
                                                    text: modelData.key
                                                    color: modelData.key === "PK" ? Theme.accent : Theme.warning
                                                    font.pixelSize: 9
                                                    font.bold: true
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── 5. RENDERIZADO DE GANTT CHART ────────────────────────────────
                Item {
                    id: ganttGroup
                    visible: root.layoutResult && root.layoutResult.type === "gantt"
                    anchors.fill: parent

                    // Líneas de cuadrícula temporal
                    Repeater {
                        model: (ganttGroup.visible && root.layoutResult && root.layoutResult.gridTicks) ? root.layoutResult.gridTicks : []
                        delegate: Item {
                            anchors.fill: parent
                            Rectangle {
                                x: modelData.x
                                y: (root.layoutResult && root.layoutResult.gridTopY) ? root.layoutResult.gridTopY : 30
                                width: 1
                                height: parent.height - y
                                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1)
                            }
                            Text {
                                x: modelData.x - implicitWidth / 2
                                y: (root.layoutResult && root.layoutResult.tickLabelY) ? root.layoutResult.tickLabelY : 12
                                text: modelData.label
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                            }
                        }
                    }

                    // Títulos de sección Gantt
                    Repeater {
                        model: (ganttGroup.visible && root.layoutResult && root.layoutResult.sections) ? root.layoutResult.sections : []
                        delegate: Rectangle {
                            x: 10
                            y: modelData.y
                            width: root.layoutResult.labelColW - 20
                            height: modelData.h
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.08)
                            radius: 4
                            Text {
                                anchors.centerIn: parent
                                text: modelData.name
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                    }

                    // Tareas y barras de duración Gantt
                    Repeater {
                        model: (ganttGroup.visible && root.layoutResult && root.layoutResult.tasks) ? root.layoutResult.tasks : []
                        delegate: Item {
                            anchors.fill: parent

                            // Etiqueta de la tarea en la columna izquierda
                            Text {
                                x: 14
                                y: modelData.y + (modelData.h - implicitHeight) / 2
                                width: root.layoutResult.labelColW - 24
                                text: modelData.name
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }

                            // Barra de progreso (cápsula)
                            Rectangle {
                                visible: !modelData.isMilestone
                                x: modelData.x
                                y: modelData.y
                                width: modelData.w
                                height: modelData.h
                                radius: 4
                                color: modelData.isDone
                                    ? Qt.rgba(Theme.success.r, Theme.success.g, Theme.success.b, 0.45)
                                    : modelData.isActive
                                        ? Theme.accent
                                        : modelData.isCrit
                                            ? Theme.danger
                                            : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
                                border.color: modelData.isCrit ? Theme.danger : Theme.accent
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    visible: parent.width > implicitWidth + 8
                                    text: modelData.name
                                    color: Theme.textOn(parent.color)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }

                            // Hito (Rombo rotado 45°)
                            Rectangle {
                                visible: modelData.isMilestone
                                x: modelData.x - 7
                                y: modelData.y + 2
                                width: 14
                                height: 14
                                rotation: 45
                                color: Theme.warning
                                border.color: Theme.text
                                border.width: 1
                            }
                        }
                    }
                }

                // ── 6. RENDERIZADO DE TIMELINE ───────────────────────────────────
                Item {
                    id: timelineGroup
                    visible: root.layoutResult && root.layoutResult.type === "timeline"
                    anchors.fill: parent

                    // Banners de sección cronológica (ej: 2024, 2025)
                    Repeater {
                        model: (timelineGroup.visible && root.layoutResult && root.layoutResult.sections) ? root.layoutResult.sections : []
                        delegate: Rectangle {
                            x: modelData.x
                            y: modelData.y - 12
                            width: modelData.w
                            height: 24
                            radius: 12
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                            border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: modelData.name
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                    }

                    // Eje horizontal central
                    Rectangle {
                        visible: timelineGroup.visible && root.layoutResult
                        x: root.layoutResult.axisStartX || 20
                        y: (root.layoutResult.axisY || 130) - 1.5
                        width: (root.layoutResult.axisEndX || 600) - x
                        height: 3
                        radius: 1.5
                        color: Theme.accent
                    }

                    // Marcadores de período sobre el eje
                    Repeater {
                        model: (timelineGroup.visible && root.layoutResult && root.layoutResult.periods) ? root.layoutResult.periods : []
                        delegate: Rectangle {
                            x: modelData.x - width / 2
                            y: modelData.y - height / 2
                            width: perText.implicitWidth + 16
                            height: 24
                            radius: 12
                            color: Theme.accent
                            border.color: Theme.surface
                            border.width: 2

                            Text {
                                id: perText
                                anchors.centerIn: parent
                                text: modelData.name
                                color: Theme.textOn(Theme.accent)
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                    }

                    // Tarjetas de eventos conectadas por vástago
                    Repeater {
                        model: (timelineGroup.visible && root.layoutResult && root.layoutResult.cards) ? root.layoutResult.cards : []
                        delegate: Item {
                            anchors.fill: parent

                            // Vástago conector vertical
                            Rectangle {
                                x: modelData.stemX - 1
                                y: Math.min(modelData.stemY1, modelData.stemY2)
                                width: 2
                                height: Math.abs(modelData.stemY2 - modelData.stemY1)
                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.4)
                            }

                            // Tarjeta de eventos
                            Rectangle {
                                x: modelData.x
                                y: modelData.y
                                width: modelData.w
                                height: modelData.h
                                radius: 6
                                color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.95)
                                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3)
                                border.width: 1

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 3
                                    Repeater {
                                        model: modelData.events || []
                                        delegate: RowLayout {
                                            spacing: 6
                                            Rectangle {
                                                width: 5; height: 5; radius: 2.5
                                                color: Theme.accent
                                            }
                                            Text {
                                                text: modelData
                                                color: Theme.text
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── 7. RENDERIZADO DE MINDMAP ────────────────────────────────────
                Item {
                    id: mindmapGroup
                    visible: root.layoutResult && root.layoutResult.type === "mindmap"
                    anchors.fill: parent

                    // Ramas Bézier orgánicas
                    Repeater {
                        model: (mindmapGroup.visible && root.layoutResult && root.layoutResult.edges) ? root.layoutResult.edges : []
                        delegate: Item {
                            anchors.fill: parent
                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                antialiasing: true

                                ShapePath {
                                    strokeColor: root.pieSliceColor(modelData.colorIdx || 0)
                                    strokeWidth: 2.2
                                    fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap

                                    PathSvg {
                                        path: modelData.path
                                    }
                                }
                            }
                        }
                    }

                    // Nodos con formas
                    Repeater {
                        model: (mindmapGroup.visible && root.layoutResult && root.layoutResult.nodes) ? root.layoutResult.nodes : []
                        delegate: Item {
                            x: modelData.x
                            y: modelData.y
                            width: modelData.w
                            height: modelData.h

                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                antialiasing: true

                                ShapePath {
                                    strokeColor: root.pieSliceColor(modelData.colorIdx || 0)
                                    strokeWidth: 1.8
                                    fillColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.95)
                                    joinStyle: ShapePath.RoundJoin

                                    PathSvg {
                                        path: MermaidShapes.getShapePath(modelData.shape || "rect", modelData.w, modelData.h, 6)
                                    }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                width: parent.width - 12
                                text: modelData.label || ""
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody - 1
                                font.bold: modelData.id === "root"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                // ── 8. RENDERIZADO DE GIT GRAPH (FASE 3) ─────────────────────────
                Item {
                    id: gitGraphGroup
                    visible: root.layoutResult && root.layoutResult.type === "gitGraph"
                    anchors.fill: parent

                    // Carriles de ramas
                    Repeater {
                        model: (gitGraphGroup.visible && root.layoutResult && root.layoutResult.branches) ? root.layoutResult.branches : []
                        delegate: Item {
                            anchors.fill: parent

                            // Píldora de rama a la izquierda
                            Rectangle {
                                x: 16
                                y: modelData.y - 12
                                width: branchLabel.implicitWidth + 14
                                height: 24
                                radius: 12
                                color: Qt.rgba(root.pieSliceColor(modelData.colorIdx).r, root.pieSliceColor(modelData.colorIdx).g, root.pieSliceColor(modelData.colorIdx).b, 0.16)
                                border.color: root.pieSliceColor(modelData.colorIdx)
                                border.width: 1

                                Text {
                                    id: branchLabel
                                    anchors.centerIn: parent
                                    text: modelData.name
                                    color: root.pieSliceColor(modelData.colorIdx)
                                    font.family: Theme.fontFamilyMonospace || "monospace"
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }

                            // Línea guía del carril
                            Rectangle {
                                x: modelData.startX
                                y: modelData.y - 1
                                width: Math.max(10, modelData.endX - modelData.startX)
                                height: 2
                                color: Qt.rgba(root.pieSliceColor(modelData.colorIdx).r, root.pieSliceColor(modelData.colorIdx).g, root.pieSliceColor(modelData.colorIdx).b, 0.28)
                            }
                        }
                    }

                    // Conectores Bézier entre commits
                    Repeater {
                        model: (gitGraphGroup.visible && root.layoutResult && root.layoutResult.connectors) ? root.layoutResult.connectors : []
                        delegate: Item {
                            anchors.fill: parent
                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                antialiasing: true

                                ShapePath {
                                    strokeColor: root.pieSliceColor(modelData.colorIdx || 0)
                                    strokeWidth: 2.4
                                    fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap

                                    PathSvg {
                                        path: modelData.path
                                    }
                                }
                            }
                        }
                    }

                    // Nodos de commits
                    Repeater {
                        model: (gitGraphGroup.visible && root.layoutResult && root.layoutResult.commits) ? root.layoutResult.commits : []
                        delegate: Item {
                            x: modelData.x - 10
                            y: modelData.y - 10
                            width: 20
                            height: 20

                            // Tag badge si existe (sobre el commit)
                            Rectangle {
                                visible: !!(modelData.tag && modelData.tag.length > 0)
                                z: 2
                                anchors.bottom: parent.top
                                anchors.bottomMargin: 4
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: tagText.implicitWidth + 10
                                height: 18
                                radius: 4
                                color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.95)
                                border.color: root.pieSliceColor(modelData.colorIdx)
                                border.width: 1

                                Text {
                                    id: tagText
                                    anchors.centerIn: parent
                                    text: modelData.tag
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                            }

                            // Círculo exterior del nodo
                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                color: modelData.type === "HIGHLIGHT" ? Theme.warning : root.pieSliceColor(modelData.colorIdx)
                                border.color: Theme.surface
                                border.width: 2
                            }

                            // Círculo interior para tipo REVERSE
                            Rectangle {
                                visible: modelData.type === "REVERSE"
                                anchors.centerIn: parent
                                width: 8; height: 8
                                radius: 4
                                color: Theme.surface
                            }

                            // Mensaje/ID del commit debajo del nodo
                            Text {
                                anchors.top: parent.bottom
                                anchors.topMargin: 4
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.id
                                color: Theme.muted
                                font.family: Theme.fontFamilyMonospace || "monospace"
                                font.pixelSize: 10
                            }
                        }
                    }
                }

                // ── 9. RENDERIZADO DE QUADRANT CHART (FASE 3) ────────────────────
                Item {
                    id: quadrantGroup
                    visible: root.layoutResult && root.layoutResult.type === "quadrantChart"
                    anchors.fill: parent

                    // Marco y 4 cuadrantes
                    Item {
                        x: root.layoutResult ? root.layoutResult.left : 0
                        y: root.layoutResult ? root.layoutResult.top : 0
                        width: root.layoutResult ? root.layoutResult.chartSize : 0
                        height: root.layoutResult ? root.layoutResult.chartSize : 0

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.55)
                            border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.20)
                            border.width: 1
                        }

                        // Resalte sutil en Q1
                        Rectangle {
                            x: parent.width / 2; y: 0
                            width: parent.width / 2; height: parent.height / 2
                            radius: 8
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                        }

                        // Ejes centrales en cruz
                        Rectangle {
                            x: 0; y: parent.height / 2
                            width: parent.width; height: 1
                            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.22)
                        }
                        Rectangle {
                            x: parent.width / 2; y: 0
                            width: 1; height: parent.height
                            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.22)
                        }

                        // Textos de nombres de cuadrantes
                        Text {
                            x: 12; y: 10
                            text: (root.layoutResult && root.layoutResult.quadrants && root.layoutResult.quadrants.q2) ? root.layoutResult.quadrants.q2.text : ""
                            color: Theme.muted
                            font.family: Theme.fontFamily; font.pixelSize: 11; font.bold: true
                        }
                        Text {
                            x: parent.width / 2 + 12; y: 10
                            text: (root.layoutResult && root.layoutResult.quadrants && root.layoutResult.quadrants.q1) ? root.layoutResult.quadrants.q1.text : ""
                            color: Theme.muted
                            font.family: Theme.fontFamily; font.pixelSize: 11; font.bold: true
                        }
                        Text {
                            x: 12; y: parent.height / 2 + 10
                            text: (root.layoutResult && root.layoutResult.quadrants && root.layoutResult.quadrants.q3) ? root.layoutResult.quadrants.q3.text : ""
                            color: Theme.muted
                            font.family: Theme.fontFamily; font.pixelSize: 11; font.bold: true
                        }
                        Text {
                            x: parent.width / 2 + 12; y: parent.height / 2 + 10
                            text: (root.layoutResult && root.layoutResult.quadrants && root.layoutResult.quadrants.q4) ? root.layoutResult.quadrants.q4.text : ""
                            color: Theme.muted
                            font.family: Theme.fontFamily; font.pixelSize: 11; font.bold: true
                        }

                        // Extremos de ejes rotulados
                        Text {
                            anchors.bottom: parent.top; anchors.bottomMargin: 4; anchors.horizontalCenter: parent.horizontalCenter
                            text: (root.layoutResult && root.layoutResult.yAxis) ? root.layoutResult.yAxis.top : ""
                            color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 10
                        }
                        Text {
                            anchors.top: parent.bottom; anchors.topMargin: 4; anchors.horizontalCenter: parent.horizontalCenter
                            text: (root.layoutResult && root.layoutResult.yAxis) ? root.layoutResult.yAxis.bottom : ""
                            color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 10
                        }
                        Text {
                            anchors.right: parent.left; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                            text: (root.layoutResult && root.layoutResult.xAxis) ? root.layoutResult.xAxis.left : ""
                            color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 10
                        }
                        Text {
                            anchors.left: parent.right; anchors.leftMargin: 6; anchors.verticalCenter: parent.verticalCenter
                            text: (root.layoutResult && root.layoutResult.xAxis) ? root.layoutResult.xAxis.right : ""
                            color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 10
                        }
                    }

                    // Puntos dispersos
                    Repeater {
                        model: (quadrantGroup.visible && root.layoutResult && root.layoutResult.points) ? root.layoutResult.points : []
                        delegate: Item {
                            x: modelData.x
                            y: modelData.y

                            Rectangle {
                                x: -5; y: -5
                                width: 10; height: 10
                                radius: 5
                                color: Theme.accent
                                border.color: Theme.surface
                                border.width: 1.5
                            }

                            Text {
                                x: modelData.alignLeft ? (-implicitWidth - 8) : 8
                                y: -7
                                text: modelData.label
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.bold: true
                            }
                        }
                    }
                }

                // ── 10. RENDERIZADO DE USER JOURNEY (FASE 3) ─────────────────────
                Item {
                    id: journeyGroup
                    visible: root.layoutResult && root.layoutResult.type === "journey"
                    anchors.fill: parent

                    // Líneas guía sutiles de benchmark
                    Repeater {
                        model: (journeyGroup.visible && root.layoutResult && root.layoutResult.curveGuides) ? root.layoutResult.curveGuides : []
                        delegate: Item {
                            anchors.fill: parent
                            Rectangle {
                                x: 20
                                y: modelData.y
                                width: root.layoutResult ? (root.layoutResult.width - 40) : 0
                                height: 1
                                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.10)
                            }
                            Text {
                                x: 6
                                y: modelData.y - implicitHeight / 2
                                text: modelData.label
                                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.35)
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                            }
                        }
                    }

                    // Secciones
                    Repeater {
                        model: (journeyGroup.visible && root.layoutResult && root.layoutResult.sections) ? root.layoutResult.sections : []
                        delegate: Rectangle {
                            x: modelData.x
                            y: modelData.y
                            width: modelData.w
                            height: 26
                            radius: 6
                            color: Qt.rgba(root.pieSliceColor(modelData.colorIdx).r, root.pieSliceColor(modelData.colorIdx).g, root.pieSliceColor(modelData.colorIdx).b, 0.18)
                            border.color: root.pieSliceColor(modelData.colorIdx)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: modelData.name
                                color: root.pieSliceColor(modelData.colorIdx)
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                    }

                    // Curva continua de satisfacción
                    Item {
                        anchors.fill: parent
                        Shape {
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            antialiasing: true

                            ShapePath {
                                strokeColor: Theme.accent
                                strokeWidth: 2.5
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap

                                PathSvg {
                                    path: (journeyGroup.visible && root.layoutResult && root.layoutResult.trajectoryPath) ? root.layoutResult.trajectoryPath : ""
                                }
                            }
                        }
                    }

                    // Puntos de puntuación sobre la curva
                    Repeater {
                        model: (journeyGroup.visible && root.layoutResult && root.layoutResult.points) ? root.layoutResult.points : []
                        delegate: Rectangle {
                            x: modelData.x - 5
                            y: modelData.y - 5
                            width: 10; height: 10
                            radius: 5
                            color: root.journeyScoreColor(modelData.score)
                            border.color: Theme.surface
                            border.width: 1.5
                        }
                    }

                    // Tarjetas de tareas
                    Repeater {
                        model: (journeyGroup.visible && root.layoutResult && root.layoutResult.tasks) ? root.layoutResult.tasks : []
                        delegate: Rectangle {
                            x: modelData.x
                            y: modelData.y
                            width: modelData.w
                            height: modelData.h
                            radius: 8
                            color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.95)
                            border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.20)
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 4

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        text: modelData.name
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.bold: true
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        Layout.fillWidth: true
                                    }
                                    Rectangle {
                                        width: 20; height: 20
                                        radius: 10
                                        color: Qt.rgba(root.journeyScoreColor(modelData.score).r, root.journeyScoreColor(modelData.score).g, root.journeyScoreColor(modelData.score).b, 0.2)
                                        border.color: root.journeyScoreColor(modelData.score)
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.score
                                            color: root.journeyScoreColor(modelData.score)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                    }
                                }

                                // Chips de actores
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Repeater {
                                        model: modelData.actors || []
                                        delegate: Rectangle {
                                            height: 16
                                            width: actorText.implicitWidth + 8
                                            radius: 4
                                            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.10)

                                            Text {
                                                id: actorText
                                                anchors.centerIn: parent
                                                text: modelData
                                                color: Theme.text
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 9
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── 11. RENDERIZADO DE XY CHART (FASE 3) ─────────────────────────
                Item {
                    id: xychartGroup
                    visible: root.layoutResult && root.layoutResult.type === "xychart"
                    anchors.fill: parent

                    // Líneas de rejilla y valores del eje Y
                    Repeater {
                        model: (xychartGroup.visible && root.layoutResult && root.layoutResult.ticks) ? root.layoutResult.ticks : []
                        delegate: Item {
                            anchors.fill: parent
                            Rectangle {
                                x: root.layoutResult.plotLeft
                                y: modelData.y
                                width: root.layoutResult.plotW
                                height: 1
                                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.15)
                            }
                            Text {
                                x: root.layoutResult.plotLeft - implicitWidth - 8
                                y: modelData.y - implicitHeight / 2
                                text: modelData.value
                                color: Theme.muted
                                font.family: Theme.fontFamilyMonospace || "monospace"
                                font.pixelSize: 10
                            }
                        }
                    }

                    // Eje vertical Y
                    Rectangle {
                        visible: !!root.layoutResult
                        x: root.layoutResult ? root.layoutResult.plotLeft : 0
                        y: root.layoutResult ? (root.layoutResult.plotTop - 4) : 0
                        width: 1
                        height: root.layoutResult ? (root.layoutResult.plotH + 4) : 0
                        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.45)
                    }

                    // Eje horizontal base X
                    Rectangle {
                        visible: !!root.layoutResult
                        x: root.layoutResult ? root.layoutResult.plotLeft : 0
                        y: root.layoutResult ? (root.layoutResult.plotTop + root.layoutResult.plotH) : 0
                        width: root.layoutResult ? root.layoutResult.plotW : 0
                        height: 1
                        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.45)
                    }

                    // Título del eje Y
                    Text {
                        visible: !!(root.layoutResult && root.layoutResult.yAxisTitle)
                        x: root.layoutResult ? (root.layoutResult.plotLeft - 10) : 0
                        y: root.layoutResult ? (root.layoutResult.yAxisTitleY !== undefined ? root.layoutResult.yAxisTitleY : (root.layoutResult.plotTop - 26)) : 0
                        text: (root.layoutResult && root.layoutResult.yAxisTitle) ? root.layoutResult.yAxisTitle : ""
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                    }

                    // Series de barras y líneas
                    Repeater {
                        model: (xychartGroup.visible && root.layoutResult && root.layoutResult.plots) ? root.layoutResult.plots : []
                        delegate: Item {
                            id: plotDelegate
                            anchors.fill: parent
                            property var plotItem: modelData

                            // Barras
                            Repeater {
                                model: plotItem.type === "bar" ? plotItem.data : []
                                delegate: Rectangle {
                                    x: modelData.x
                                    y: modelData.y
                                    width: modelData.w
                                    height: modelData.h
                                    radius: 3
                                    color: Qt.rgba(root.xyPlotColor(plotItem, plotItem.colorIdx).r, root.xyPlotColor(plotItem, plotItem.colorIdx).g, root.xyPlotColor(plotItem, plotItem.colorIdx).b, 0.60)
                                    border.color: root.xyPlotColor(plotItem, plotItem.colorIdx)
                                    border.width: 1
                                }
                            }

                            // Líneas
                            Shape {
                                visible: plotItem.type === "line"
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                antialiasing: true

                                ShapePath {
                                    strokeColor: root.xyPlotColor(plotItem, plotItem.colorIdx)
                                    strokeWidth: 2.5
                                    fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap

                                    PathSvg {
                                        path: plotItem.path || ""
                                    }
                                }
                            }

                            // Puntos en vértices de líneas
                            Repeater {
                                model: plotItem.type === "line" ? plotItem.data : []
                                delegate: Rectangle {
                                    x: modelData.x - 4
                                    y: modelData.y - 4
                                    width: 8; height: 8
                                    radius: 4
                                    color: root.xyPlotColor(plotItem, plotItem.colorIdx)
                                    border.color: Theme.surface
                                    border.width: 1.5
                                }
                            }
                        }
                    }

                    // Categorías del eje X
                    Repeater {
                        model: (xychartGroup.visible && root.layoutResult && root.layoutResult.categories) ? root.layoutResult.categories : []
                        delegate: Text {
                            x: modelData.x - implicitWidth / 2
                            y: modelData.y
                            text: modelData.label
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }
                    }
                }
            }
        }
    }
}
