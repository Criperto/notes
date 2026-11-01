pragma Singleton
import QtQuick

QtObject {
    id: root

    // ── Paleta nativa del sistema (Qt Quick) ─────────────────────────────
    readonly property SystemPalette systemPalette: SystemPalette {
        id: sysPal
        colorGroup: SystemPalette.Active
    }

    // ── Soporte reactivo opcional para Pywal / Matugen ───────────────────
    // Se poblará vía Notas.Native.Sys o lectura directa de archivo si está disponible
    property var pywal: null

    // ── Ruta base de iconos vectoriales ──────────────────────────────────
    readonly property string iconsPath: "qrc:/qt/qml/Notas/assets/icons/"

    // ── Colores base y especiales ────────────────────────────────────────
    readonly property color background: pywal ? pywal.special.background : sysPal.window
    readonly property color foreground: pywal ? pywal.special.foreground : sysPal.windowText
    readonly property color cursor:     pywal ? pywal.special.cursor     : (isDark ? "#ffffff" : "#000000")

    // ── Paleta completa de 16 colores ANSI ───────────────────────────────
    readonly property color color0:  pywal ? pywal.colors.color0  : (isDark ? "#1e1e2e" : "#e6e9ef")
    readonly property color color1:  pywal ? pywal.colors.color1  : "#f38ba8"
    readonly property color color2:  pywal ? pywal.colors.color2  : "#a6e3a1"
    readonly property color color3:  pywal ? pywal.colors.color3  : "#f9e2af"
    readonly property color color4:  pywal ? pywal.colors.color4  : "#89b4fa"
    readonly property color color5:  pywal ? pywal.colors.color5  : "#f5c2e7"
    readonly property color color6:  pywal ? pywal.colors.color6  : "#94e2d5"
    readonly property color color7:  pywal ? pywal.colors.color7  : (isDark ? "#cdd6f4" : "#4c4f69")
    readonly property color color8:  pywal ? pywal.colors.color8  : (isDark ? "#585b70" : "#9ca0b0")
    readonly property color color9:  pywal ? pywal.colors.color9  : "#eba0ac"
    readonly property color color10: pywal ? pywal.colors.color10 : "#a6e3a1"
    readonly property color color11: pywal ? pywal.colors.color11 : "#f9e2af"
    readonly property color color12: pywal ? pywal.colors.color12 : "#89b4fa"
    readonly property color color13: pywal ? pywal.colors.color13 : "#f5c2e7"
    readonly property color color14: pywal ? pywal.colors.color14 : "#94e2d5"
    readonly property color color15: pywal ? pywal.colors.color15 : (isDark ? "#ffffff" : "#11111b")

    // Detecta si el tema es oscuro o claro según luminancia WCAG
    readonly property bool isDark: relLuminance(background) < 0.5

    // ── Aliases semánticos ───────────────────────────────────────────────
    readonly property color accent:  color1
    readonly property color primary: accent
    readonly property color success: color2
    readonly property color warning: color3
    readonly property color danger:  color1
    readonly property color muted:   Qt.rgba(text.r, text.g, text.b, 0.6)
    readonly property color text:          color15
    readonly property color surface:       color0
    readonly property color border:        Qt.rgba(text.r, text.g, text.b, 0.12)
    readonly property color surfaceHover:  Qt.rgba(text.r, text.g, text.b, 0.08)
    readonly property color surfaceActive: Qt.rgba(primary.r, primary.g, primary.b, 0.16)

    // ── Tipografía y Tokens de tamaño ────────────────────────────────────
    readonly property string fontFamily:          "Google Sans, sans-serif"
    readonly property string fontFamilyDisplay:   "Google Sans, sans-serif"
    readonly property string fontFamilyRounded:   "Google Sans, sans-serif"
    readonly property string fontFamilyMonospace: "monospace"

    property real fontSizeScale: 1.0

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
    property bool animationsEnabled: true
    property real panelOpacity: 1.0
    property bool hideScrollbars: false
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
