pragma Singleton
import QtQuick
import Notas

QtObject {
    id: root

    // ── Paleta nativa del sistema (Qt Quick) ─────────────────────────────
    readonly property SystemPalette systemPalette: SystemPalette {
        id: sysPal
        colorGroup: SystemPalette.Active
    }

    // ── Modo de tema configurado ─────────────────────────────────────────
    readonly property string themeMode: (typeof ConfigBackend !== "undefined" && ConfigBackend.themeMode) ? ConfigBackend.themeMode : "system"

    // ── Soporte reactivo opcional para Pywal / Matugen ───────────────────
    property var pywal: null

    property var _pywalWatcher: FileView {
        id: pywalWatcher
        path: (typeof Sys !== "undefined" && Sys.homePath ? Sys.homePath : "") + "/.cache/wal/colors.json"
        printErrors: false
        onLoadedChanged: {
            var raw = (typeof text === "function") ? text() : text;
            if (loaded && raw) {
                try {
                    root.pywal = JSON.parse(raw);
                } catch (e) {
                    root.pywal = null;
                }
            }
        }
        onFileChanged: {
            var raw = (typeof text === "function") ? text() : text;
            if (raw) {
                try {
                    root.pywal = JSON.parse(raw);
                } catch (e) {
                    root.pywal = null;
                }
            }
        }
    }

    // ── Ruta base de iconos vectoriales ──────────────────────────────────
    readonly property string iconsPath: "qrc:/qt/qml/Notas/assets/icons/"

    // ── Detecta si el tema es oscuro o claro según luminancia WCAG ────────
    readonly property bool isDark: {
        if (themeMode === "dark") return true;
        if (themeMode === "light") return false;
        if (themeMode === "pywal" && pywal && pywal.special) {
            return relLuminance(Qt.color(pywal.special.background)) < 0.5;
        }
        return relLuminance(sysPal.window) < 0.5;
    }

    // ── Colores base y especiales ────────────────────────────────────────
    readonly property color background: {
        if (themeMode === "dark") return "#1e1e2e";
        if (themeMode === "light") return "#eff1f5";
        if (themeMode === "pywal" && pywal && pywal.special) return Qt.color(pywal.special.background);
        return sysPal.window;
    }

    readonly property color foreground: {
        if (themeMode === "dark") return "#cdd6f4";
        if (themeMode === "light") return "#4c4f69";
        if (themeMode === "pywal" && pywal && pywal.special) return Qt.color(pywal.special.foreground);
        return sysPal.windowText;
    }

    readonly property color cursor: {
        if (themeMode === "pywal" && pywal && pywal.special && pywal.special.cursor) return Qt.color(pywal.special.cursor);
        return isDark ? "#ffffff" : "#000000";
    }

    // ── Paleta completa de 16 colores ANSI ───────────────────────────────
    readonly property color color0:  (themeMode === "pywal" && pywal) ? Qt.color(pywal.colors.color0)  : (isDark ? "#1e1e2e" : "#e6e9ef")
    readonly property color color1:  (themeMode === "pywal" && pywal) ? Qt.color(pywal.colors.color1)  : (isDark ? "#f38ba8" : "#d20f39")
    readonly property color color2:  (themeMode === "pywal" && pywal) ? Qt.color(pywal.colors.color2)  : (isDark ? "#a6e3a1" : "#40a02b")
    readonly property color color3:  (themeMode === "pywal" && pywal) ? Qt.color(pywal.colors.color3)  : (isDark ? "#f9e2af" : "#df8e1d")
    readonly property color color4:  (themeMode === "pywal" && pywal) ? Qt.color(pywal.colors.color4)  : (isDark ? "#89b4fa" : "#1e66f5")
    readonly property color color5:  (themeMode === "pywal" && pywal) ? Qt.color(pywal.colors.color5)  : (isDark ? "#f5c2e7" : "#ea76cb")
    readonly property color color6:  (themeMode === "pywal" && pywal) ? Qt.color(pywal.colors.color6)  : (isDark ? "#94e2d5" : "#179299")
    readonly property color color7:  (themeMode === "pywal" && pywal) ? Qt.color(pywal.colors.color7)  : (isDark ? "#cdd6f4" : "#4c4f69")
    readonly property color color8:  (themeMode === "pywal" && pywal) ? Qt.color(pywal.colors.color8)  : (isDark ? "#585b70" : "#9ca0b0")
    readonly property color color9:  (themeMode === "pywal" && pywal) ? Qt.color(pywal.colors.color9)  : (isDark ? "#eba0ac" : "#e64553")
    readonly property color color10: (themeMode === "pywal" && pywal) ? Qt.color(pywal.colors.color10) : (isDark ? "#a6e3a1" : "#40a02b")
    readonly property color color11: (themeMode === "pywal" && pywal) ? Qt.color(pywal.colors.color11) : (isDark ? "#f9e2af" : "#df8e1d")
    readonly property color color12: (themeMode === "pywal" && pywal) ? Qt.color(pywal.colors.color12) : (isDark ? "#89b4fa" : "#1e66f5")
    readonly property color color13: (themeMode === "pywal" && pywal) ? Qt.color(pywal.colors.color13) : (isDark ? "#f5c2e7" : "#ea76cb")
    readonly property color color14: (themeMode === "pywal" && pywal) ? Qt.color(pywal.colors.color14) : (isDark ? "#94e2d5" : "#179299")
    readonly property color color15: (themeMode === "pywal" && pywal) ? Qt.color(pywal.colors.color15) : (isDark ? "#ffffff" : "#11111b")

    // ── Aliases semánticos ───────────────────────────────────────────────
    readonly property color accent:  color1
    readonly property color primary: accent
    readonly property color success: color2
    readonly property color warning: color3
    readonly property color danger:  color1
    readonly property color muted:   Qt.rgba(text.r, text.g, text.b, 0.6)
    readonly property color text:    (themeMode === "system") ? sysPal.windowText : color15
    readonly property color surface: (themeMode === "system") ? (isDark ? "#181825" : "#e6e9ef") : (isDark ? "#181825" : "#e6e9ef")
    readonly property color border:  Qt.rgba(text.r, text.g, text.b, 0.12)
    readonly property color surfaceHover:  Qt.rgba(text.r, text.g, text.b, 0.08)
    readonly property color surfaceActive: Qt.rgba(primary.r, primary.g, primary.b, 0.16)

    // ── Tipografía y Tokens de tamaño ────────────────────────────────────
    readonly property string fontFamily:          "Google Sans, sans-serif"
    readonly property string fontFamilyDisplay:   "Google Sans, sans-serif"
    readonly property string fontFamilyRounded:   "Google Sans, sans-serif"
    readonly property string fontFamilyMonospace: "monospace"

    property real fontSizeScale: (typeof ConfigBackend !== "undefined" && ConfigBackend.fontSizeScale > 0) ? ConfigBackend.fontSizeScale : 1.0

    readonly property real fontSizeBadge:         Math.round(8  * fontSizeScale)
    readonly property real fontSizeCaption:       Math.round(9  * fontSizeScale)
    readonly property real fontSizeSmall:         Math.round(10 * fontSizeScale)
    readonly property real fontSizeBodySecondary: Math.round(11 * fontSizeScale)
    readonly property real fontSizeBody:          Math.round(12 * fontSizeScale)
    readonly property real fontSizeSubheading:    Math.round(13 * fontSizeScale)
    readonly property real fontSizeTitle:         Math.round(14 * fontSizeScale)
    readonly property real fontSizeTitleLarge:    Math.round(16 * fontSizeScale)
    readonly property real fontSizeHeader:        Math.round(18 * fontSizeScale)
    readonly property real fontSizeDisplay:       Math.round(22 * fontSizeScale)

    // ── Ajustes generales ────────────────────────────────────────────────
    property bool animationsEnabled: (typeof ConfigBackend !== "undefined") ? ConfigBackend.animationsEnabled : true
    property real panelOpacity: (typeof ConfigBackend !== "undefined" && ConfigBackend.panelOpacity > 0) ? ConfigBackend.panelOpacity : 1.0
    property bool hideScrollbars: (typeof ConfigBackend !== "undefined") ? ConfigBackend.hideScrollbars : false
    property bool blurEnabled: (typeof ConfigBackend !== "undefined") ? ConfigBackend.blurEnabled : true
    property bool hasTouchscreen: false

    // ── Helpers WCAG de luminancia y contraste ───────────────────────────
    function _toLinear(c) {
        return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    }

    function relLuminance(c) {
        return 0.2126 * _toLinear(c.r)
             + 0.7152 * _toLinear(c.g)
             + 0.0722 * _toLinear(c.b);
    }

    function contrastRatio(c1, c2) {
        var l1 = relLuminance(c1);
        var l2 = relLuminance(c2);
        return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
    }

    function textOn(bg) {
        return contrastRatio(bg, color15) > contrastRatio(bg, color0) ? color15 : color0;
    }
}
