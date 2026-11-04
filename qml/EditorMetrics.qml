pragma Singleton
import QtQuick
import Notas
import "Inline.js" as Inline

Item {
    id: root
    visible: false

    property real zoom: (typeof NotesConfig !== "undefined" && NotesConfig.editorZoom) ? (NotesConfig.editorZoom / 100) : 1.0
    readonly property real minZoom: 0.5
    readonly property real maxZoom: 3.0
    readonly property real zoomStep: 0.1

    readonly property real pageWidthBase: 794                       // A4 @96dpi (ver T3)
    readonly property real pageWidth: Math.round(pageWidthBase * zoom)

    // Resaltado (==texto==): Theme.color3 con transparencia para mantener legible el texto.
    readonly property string highlightBg: "rgba(" + Math.round(Theme.color3.r * 255) + ", "
        + Math.round(Theme.color3.g * 255) + ", " + Math.round(Theme.color3.b * 255) + ", 0.35)"
    onHighlightBgChanged: Inline.setHighlightBg(highlightBg)

    function syncThemeToInline() {
        if (typeof Theme !== "undefined" && Theme) {
            Inline.setThemeConfig({
                accent: "" + Theme.accent,
                lightMode: Boolean(Theme.lightMode),
                surface: "" + Theme.surface,
                color15: "" + Theme.color15,
                fontFamilyMonospace: Theme.fontFamilyMonospace || "Google Sans Code"
            });
        }
    }

    Component.onCompleted: {
        Inline.setHighlightBg(highlightBg);
        Inline.setZoom(root.zoom);
        root.syncThemeToInline();
        if (typeof Sys !== "undefined" && Sys && typeof Sys.renderLatexSvg === "function") {
            Inline.setLatexRenderer(function(latex, display, color, ptSize) {
                return Sys.renderLatexSvg(latex, display, color, ptSize);
            });
        }
    }

    Connections {
        target: (typeof Theme !== "undefined") ? Theme : null
        function onAccentChanged() { root.syncThemeToInline(); }
        function onLightModeChanged() { root.syncThemeToInline(); }
        function onSurfaceChanged() { root.syncThemeToInline(); }
        function onFontFamilyMonospaceChanged() { root.syncThemeToInline(); }
    }

    function fs(px) { return Math.max(6, Math.round(px * root.zoom)); }

    readonly property int body:    fs(Theme.fontSizeBody)
    readonly property int caption: fs(Theme.fontSizeCaption)
    readonly property int title:   fs(Theme.fontSizeTitle)

    // F24: interlineado único. TextEdit no tiene lineHeight en Qt, así que
    // vista (Text) y edición (TextEdit) coinciden usando el natural 1.0 en Text.
    readonly property real lineHeight: 1.0

    // F25: tamaño de encabezado único (antes duplicado en BlockHeading y BlockList).
    // Los bloques nuevos (citas con ##) lo reutilizan en vez de copiar la tabla.
    function headingSize(level) {
        switch (level) {
            case 1: return fs(Theme.fontSizeTitle + 8);
            case 2: return fs(Theme.fontSizeTitle + 4);
            case 3: return title;
            case 4: return fs(Theme.fontSizeBody + 2);
            case 5: return body;
            case 6: return fs(Theme.fontSizeCaption + 1);
            default: return title;
        }
    }

    function setZoom(z) {
        var target = Math.max(minZoom, Math.min(maxZoom, Math.round(z * 100) / 100));
        if (Math.abs(root.zoom - target) > 0.001) {
            root.zoom = target;
        }
    }
    function zoomIn()    { setZoom(root.zoom + zoomStep); }
    function zoomOut()   { setZoom(root.zoom - zoomStep); }
    function zoomReset() { setZoom(1.0); }

    Timer {
        id: saveZoomTimer
        interval: 350
        repeat: false
        onTriggered: root.flushZoom()
    }

    onZoomChanged: {
        Inline.setZoom(root.zoom);
        saveZoomTimer.restart();
    }

    function flushZoom() {
        saveZoomTimer.stop();
        if (typeof NotesConfig === "undefined") return;
        var pct = Math.round(root.zoom * 100);
        if (NotesConfig.editorZoom !== pct) {
            NotesConfig.editorZoom = pct;
        }
    }

    Connections {
        target: (typeof NotesConfig !== "undefined") ? NotesConfig : null
        function onEditorZoomChanged() {
            var targetZoom = Math.max(root.minZoom, Math.min(root.maxZoom, NotesConfig.editorZoom / 100));
            if (Math.abs(root.zoom - targetZoom) > 0.001) {
                root.setZoom(targetZoom);
            }
        }
    }

    Component.onDestruction: {
        root.flushZoom();
    }
}
