import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Controls
import Notas
import "."

Item {
    id: root

    property string latex: ""
    property bool display: true
    property color textColor: Theme.text
    property real ptSize: (typeof EditorMetrics !== "undefined" && EditorMetrics.body) ? EditorMetrics.body : 14.0
    property real availableWidth: parent ? parent.width : 500
    property bool liveEditMode: false

    readonly property real zoomK: (typeof EditorMetrics !== "undefined" && EditorMetrics.zoom) ? EditorMetrics.zoom : 1.0

    // Estado reactivo de renderizado
    property string _svgMarkup: ""
    property bool _hasError: false
    property string _errorMessage: ""
    property real _naturalWidth: 100
    property real _naturalHeight: 40

    readonly property bool hasError: _hasError
    readonly property string errorMessage: _errorMessage
    readonly property real naturalWidth: _naturalWidth
    readonly property real naturalHeight: _naturalHeight

    readonly property real renderedWidth: Math.round(_naturalWidth * zoomK)
    readonly property real renderedHeight: Math.round(_naturalHeight * zoomK)

    implicitWidth: availableWidth
    implicitHeight: {
        if (_hasError) return Math.max(64, errorBox.implicitHeight + 16);
        if (!_svgMarkup || _svgMarkup === "") return 40;
        return Math.max(36, renderedHeight + 20);
    }

    Timer {
        id: renderDebounce
        interval: 120
        repeat: false
        onTriggered: root._doRender()
    }

    onLatexChanged: {
        if (root.liveEditMode) {
            renderDebounce.restart();
        } else {
            root._doRender();
        }
    }

    onDisplayChanged: root._doRender()
    onTextColorChanged: root._doRender()
    onPtSizeChanged: root._doRender()

    Component.onCompleted: root._doRender()

    function _doRender() {
        var raw = (root.latex || "").trim();
        if (raw === "") {
            root._svgMarkup = "";
            root._hasError = false;
            root._errorMessage = "";
            root._naturalWidth = 60;
            root._naturalHeight = 28;
            return;
        }

        var colHex = root.textColor.toString();
        var effectivePt = root.ptSize * (root.display ? 1.25 : 1.0);

        var res = "";
        if (typeof Sys !== "undefined" && Sys && typeof Sys.renderLatexSvg === "function") {
            res = Sys.renderLatexSvg(raw, root.display, colHex, effectivePt);
        } else {
            res = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"120pt\" height=\"30pt\" viewBox=\"0 0 120 30\"><text x=\"10\" y=\"20\" fill=\"" + colHex + "\">" + raw + "</text></svg>";
        }

        if (!res || res.indexOf("ERROR:") === 0) {
            root._hasError = true;
            root._errorMessage = res ? res.substring(6) : "Error desconocido al procesar sintaxis LaTeX";
            root._svgMarkup = "";
            return;
        }

        root._hasError = false;
        root._errorMessage = "";
        root._svgMarkup = res;

        // Extraer dimensiones naturales del viewBox
        var vbMatch = res.match(/viewBox="0 0 ([0-9.]+) ([0-9.]+)"/);
        if (vbMatch) {
            var rawW = parseFloat(vbMatch[1]);
            var rawH = parseFloat(vbMatch[2]);
            // 1 pt = 1.3333 px en pantallas estándar (96 / 72)
            root._naturalWidth = Math.max(20, Math.ceil(rawW * 1.3333));
            root._naturalHeight = Math.max(16, Math.ceil(rawH * 1.3333));
        } else {
            root._naturalWidth = 120;
            root._naturalHeight = 36;
        }
    }

    readonly property string svgDataUri: (!root._hasError && root._svgMarkup.indexOf("<svg") !== -1)
        ? ("data:image/svg+xml;utf8," + encodeURIComponent(root._svgMarkup))
        : ""

    // ── VISTA PRINCIPAL (Contenedor interactivo con scroll si excede ancho) ──
    Flickable {
        id: mathFlickable
        visible: !root._hasError && root._svgMarkup !== ""
        anchors.fill: parent
        anchors.margins: 6
        contentWidth: Math.max(width, root.renderedWidth + 24)
        contentHeight: Math.max(height, root.renderedHeight + 10)
        clip: true
        interactive: contentWidth > width
        boundsBehavior: Flickable.StopAtBounds

        Image {
            id: mathImage
            x: root.renderedWidth < mathFlickable.width ? Math.round((mathFlickable.width - width) / 2) : 12
            y: Math.max(0, Math.round((mathFlickable.contentHeight - height) / 2))
            source: root.svgDataUri
            cache: false
            asynchronous: false
            smooth: true
            mipmap: true
            fillMode: Image.PreserveAspectFit

            // Forzar rasterización nítida a resolución real de display + zoom
            sourceSize.width: Math.max(1, Math.round(root._naturalWidth * (Screen.devicePixelRatio || 1.0) * root.zoomK))
            sourceSize.height: Math.max(1, Math.round(root._naturalHeight * (Screen.devicePixelRatio || 1.0) * root.zoomK))
            width: root.renderedWidth
            height: root.renderedHeight
        }

        WheelHandler {
            target: mathFlickable
            property: "contentX"
            orientation: Qt.Horizontal
            enabled: mathFlickable.interactive
        }
    }

    // ── CAJA DE ERROR RESILIENTE ─────────────────────────────────────────────
    Rectangle {
        id: errorBox
        visible: root._hasError
        anchors.centerIn: parent
        width: Math.min(parent.width - 24, Math.max(280, errorCol.implicitWidth + 32))
        implicitHeight: errorCol.implicitHeight + 20
        radius: 8
        color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.08)
        border.color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.35)
        border.width: 1

        ColumnLayout {
            id: errorCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6

            RowLayout {
                spacing: 8
                Image {
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                    source: Theme.iconsPath + "alert.svg"
                    sourceSize: Qt.size(16, 16)
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: Theme.danger
                    }
                }

                Text {
                    text: I18n.t("notes.math.syntax_error", "Error de sintaxis en fórmula LaTeX")
                    color: Theme.danger
                    font.family: Theme.fontFamily
                    font.bold: true
                    font.pixelSize: EditorMetrics.body - 1
                }
            }

            Text {
                Layout.fillWidth: true
                text: root._errorMessage
                color: Theme.text
                font.family: "monospace"
                font.pixelSize: EditorMetrics.caption
                wrapMode: Text.Wrap
                opacity: 0.85
            }
        }
    }
}
