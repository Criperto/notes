pragma Singleton
import QtQuick
import Notas

QtObject {
    id: root

    // ── Home del usuario actual (sin slash final) ────────────────────────
    readonly property string homeDir: (typeof Sys !== "undefined" && Sys.homeDir) ? Sys.homeDir : ""

    // ── Modo de tema configurado ("pywal" | "qt" | "custom") ─────────────
    readonly property string themeMode: (typeof ConfigBackend !== "undefined" && ConfigBackend.themeMode) ? ConfigBackend.themeMode : "pywal"
    readonly property string customThemeName: (typeof ConfigBackend !== "undefined" && ConfigBackend.customThemeName) ? ConfigBackend.customThemeName : "amarillo"
    readonly property bool lightMode: (typeof ConfigBackend !== "undefined") ? ConfigBackend.lightMode : false

    // ── Soporte reactivo para Pywal / Matugen (~/.cache/wal/colors.json) ─
    property var pywal: null

    property var _pywalFile: FileView {
        id: pywalFile
        path: root.homeDir + "/.cache/wal/colors.json"
        preload: true
        watchChanges: true
        printErrors: false
        onLoaded: root._parsePywal(pywalFile.text())
        onFileChanged: pywalDebounceTimer.restart()
    }

    property var _pywalDebounceTimer: Timer {
        id: pywalDebounceTimer
        interval: 150
        repeat: false
        onTriggered: {
            pywalFile.reload();
            root._parsePywal(pywalFile.text());
        }
    }

    Component.onCompleted: {
        if (pywalFile.loaded) {
            root._parsePywal(pywalFile.text());
        }
    }

    function _parsePywal(rawText) {
        if (!rawText || rawText.trim() === "") {
            root.pywal = null;
            return;
        }
        try {
            var parsed = JSON.parse(rawText);
            if (parsed && parsed.special && parsed.colors) {
                root.pywal = parsed;
            } else {
                root.pywal = null;
            }
        } catch (e) {
            root.pywal = null;
        }
    }

    readonly property bool pywalAvailable: root.pywal !== null

    // ── Catálogo de los 14 temas predefinidos (idénticos a ThemeManager.qml / ThemeConfig.qml) ──
    readonly property var predefinedThemes: [
        { id: "rojo",       labelKey: "settings.theme.color_red",        fallback: "Rojo" },
        { id: "naranja",    labelKey: "settings.theme.color_orange",     fallback: "Naranja" },
        { id: "amarillo",   labelKey: "settings.theme.color_yellow",     fallback: "Amarillo" },
        { id: "lima",       labelKey: "settings.theme.color_lime",       fallback: "Lima" },
        { id: "verde",      labelKey: "settings.theme.color_green",      fallback: "Verde" },
        { id: "cian",       labelKey: "settings.theme.color_cyan",       fallback: "Cian" },
        { id: "azul_claro", labelKey: "settings.theme.color_light_blue", fallback: "Azul Claro" },
        { id: "azul",       labelKey: "settings.theme.color_blue",       fallback: "Azul" },
        { id: "morado",     labelKey: "settings.theme.color_purple",     fallback: "Morado" },
        { id: "magenta",    labelKey: "settings.theme.color_magenta",    fallback: "Magenta" },
        { id: "rosa",       labelKey: "settings.theme.color_pink",       fallback: "Rosa" },
        { id: "blanco",     labelKey: "settings.theme.color_white",      fallback: "Blanco" },
        { id: "gris_claro", labelKey: "settings.theme.color_light_gray", fallback: "Gris Claro" },
        { id: "gris",       labelKey: "settings.theme.color_gray",       fallback: "Gris" }
    ]

    function getPredefinedThemeColors(themeName, isLight) {
        var hue = 0.14; // Default Amarillo
        var isMonochrome = false;

        if (themeName === "rojo") {
            hue = 0.0;
        } else if (themeName === "naranja") {
            hue = 0.08;
        } else if (themeName === "amarillo") {
            hue = 0.14;
        } else if (themeName === "lima") {
            hue = 0.24;
        } else if (themeName === "verde") {
            hue = 0.33;
        } else if (themeName === "cian") {
            hue = 0.50;
        } else if (themeName === "azul_claro") {
            hue = 0.56;
        } else if (themeName === "azul") {
            hue = 0.63;
        } else if (themeName === "morado") {
            hue = 0.76;
        } else if (themeName === "magenta") {
            hue = 0.83;
        } else if (themeName === "rosa") {
            hue = 0.92;
        } else if (themeName === "blanco") {
            isMonochrome = true;
            hue = 0.0;
        } else if (themeName === "gris_claro") {
            isMonochrome = true;
            hue = 0.0;
        } else if (themeName === "gris") {
            isMonochrome = true;
            hue = 0.0;
        }

        function hsvaToHex(h, s, v) {
            var ch = ((h % 1.0) + 1.0) % 1.0;
            var cs = Math.max(0.0, Math.min(1.0, s));
            var cv = Math.max(0.0, Math.min(1.0, v));
            var c = Qt.hsva(ch, cs, cv, 1.0);
            var hex = c.toString();
            if (hex.length === 9) {
                return "#" + hex.substring(3);
            }
            return hex;
        }

        var obj = {
            "special": {},
            "colors": {}
        };

        var i;
        var hues, sats, vals, satsB, valsB, h, baseV, bgH, bgS, bgV, fgH, fgS, fgV, c0, c7, c15;

        if (isLight) {
            bgH = hue;
            bgS = isMonochrome ? 0.0 : 0.10;
            bgV = themeName === "gris" ? 0.82 : (themeName === "gris_claro" ? 0.90 : 0.98);

            fgH = hue;
            fgS = isMonochrome ? 0.0 : 0.15;
            fgV = 0.12;

            c0 = hsvaToHex(bgH, bgS, bgV);
            c7 = hsvaToHex(fgH, fgS, fgV);
            c15 = hsvaToHex(fgH, isMonochrome ? 0.0 : (fgS + 0.05), 0.05);

            obj.special.background = c0;
            obj.special.foreground = c7;
            obj.special.cursor = c7;

            obj.colors.color0 = c0;
            obj.colors.color7 = c7;
            obj.colors.color8 = hsvaToHex(bgH, isMonochrome ? 0.0 : (bgS + 0.05), bgV - 0.10);
            obj.colors.color15 = c15;

            if (isMonochrome) {
                baseV = (themeName === "blanco") ? 0.45 : (themeName === "gris_claro" ? 0.35 : 0.25);
                for (i = 1; i <= 6; i++) {
                    obj.colors["color" + i] = hsvaToHex(0, 0, baseV + (i - 1) * 0.04);
                    obj.colors["color" + (i + 8)] = hsvaToHex(0, 0, baseV + (i - 1) * 0.04 - 0.10);
                }
            } else {
                hues = [hue, hue + 0.03, hue - 0.03, hue + 0.06, hue - 0.06, hue + 0.09];
                sats = [0.80, 0.70, 0.60, 0.50, 0.40, 0.30];
                vals = [0.60, 0.65, 0.70, 0.75, 0.80, 0.85];
                satsB = [0.90, 0.80, 0.70, 0.60, 0.50, 0.40];
                valsB = [0.50, 0.55, 0.60, 0.65, 0.70, 0.75];
                for (i = 1; i <= 6; i++) {
                    h = (hues[i - 1] + 1.0) % 1.0;
                    obj.colors["color" + i] = hsvaToHex(h, sats[i - 1], vals[i - 1]);
                    obj.colors["color" + (i + 8)] = hsvaToHex(h, satsB[i - 1], valsB[i - 1]);
                }
            }
        } else {
            bgH = hue;
            bgS = isMonochrome ? 0.0 : 0.16;
            bgV = themeName === "blanco" ? 0.10 : (themeName === "gris_claro" ? 0.07 : 0.05);

            fgH = hue;
            fgS = isMonochrome ? 0.0 : 0.08;
            fgV = 0.90;

            c0 = hsvaToHex(bgH, bgS, bgV);
            c7 = hsvaToHex(fgH, fgS, fgV);
            c15 = hsvaToHex(fgH, isMonochrome ? 0.0 : (fgS - 0.04), 0.98);

            obj.special.background = c0;
            obj.special.foreground = c7;
            obj.special.cursor = c7;

            obj.colors.color0 = c0;
            obj.colors.color7 = c7;
            obj.colors.color8 = hsvaToHex(bgH, isMonochrome ? 0.0 : (bgS + 0.04), bgV + 0.08);
            obj.colors.color15 = c15;

            if (isMonochrome) {
                baseV = (themeName === "blanco") ? 0.80 : (themeName === "gris_claro" ? 0.65 : 0.50);
                for (i = 1; i <= 6; i++) {
                    obj.colors["color" + i] = hsvaToHex(0, 0, baseV - (i - 1) * 0.05);
                    obj.colors["color" + (i + 8)] = hsvaToHex(0, 0, baseV - (i - 1) * 0.05 + 0.10);
                }
            } else {
                hues = [hue, hue + 0.03, hue - 0.03, hue + 0.06, hue - 0.06, hue + 0.09];
                sats = [0.75, 0.65, 0.55, 0.45, 0.35, 0.25];
                vals = [0.80, 0.85, 0.90, 0.95, 1.00, 1.00];
                satsB = [0.85, 0.75, 0.65, 0.55, 0.45, 0.35];
                valsB = [0.90, 0.95, 1.00, 1.00, 1.00, 1.00];
                for (i = 1; i <= 6; i++) {
                    h = (hues[i - 1] + 1.0) % 1.0;
                    obj.colors["color" + i] = hsvaToHex(h, sats[i - 1], vals[i - 1]);
                    obj.colors["color" + (i + 8)] = hsvaToHex(h, satsB[i - 1], valsB[i - 1]);
                }
            }
        }

        return obj;
    }

    // ── Resolución unificada de paleta activa ────────────────────────────
    readonly property var _qtPalette: (typeof Sys !== "undefined" && Sys.qtColors && Sys.qtColors.special && Sys.qtColors.colors)
        ? Sys.qtColors
        : null

    readonly property var _activePalette: {
        if (root.themeMode === "custom") {
            return root.getPredefinedThemeColors(root.customThemeName, root.lightMode);
        }
        if (root.themeMode === "qt" || root.themeMode === "system") {
            if (root._qtPalette) return root._qtPalette;
            if (root.pywal) return root.pywal;
            return root.getPredefinedThemeColors(root.customThemeName, root.lightMode);
        }
        // Default: "pywal"
        if (root.pywal) return root.pywal;
        if (root._qtPalette) return root._qtPalette;
        return root.getPredefinedThemeColors(root.customThemeName, root.lightMode);
    }

    // ── Ruta base de iconos vectoriales ──────────────────────────────────
    readonly property string iconsPath: "qrc:/qt/qml/Notas/assets/icons/"

    // ── Colores especiales (idéntico a Theme.qml de Quickshell) ──────────
    readonly property color background: (_activePalette && _activePalette.special && _activePalette.special.background) ? Qt.color(_activePalette.special.background) : "#000000"
    readonly property color foreground: (_activePalette && _activePalette.special && _activePalette.special.foreground) ? Qt.color(_activePalette.special.foreground) : "#ffffff"
    readonly property color cursor:     (_activePalette && _activePalette.special && _activePalette.special.cursor)     ? Qt.color(_activePalette.special.cursor)     : "#ffffff"

    // ── Paleta completa de 16 colores ────────────────────────────────────
    readonly property color color0:  (_activePalette && _activePalette.colors && _activePalette.colors.color0)  ? Qt.color(_activePalette.colors.color0)  : "#000000"
    readonly property color color1:  (_activePalette && _activePalette.colors && _activePalette.colors.color1)  ? Qt.color(_activePalette.colors.color1)  : "#ff0000"
    readonly property color color2:  (_activePalette && _activePalette.colors && _activePalette.colors.color2)  ? Qt.color(_activePalette.colors.color2)  : "#00ff00"
    readonly property color color3:  (_activePalette && _activePalette.colors && _activePalette.colors.color3)  ? Qt.color(_activePalette.colors.color3)  : "#ffff00"
    readonly property color color4:  (_activePalette && _activePalette.colors && _activePalette.colors.color4)  ? Qt.color(_activePalette.colors.color4)  : "#0000ff"
    readonly property color color5:  (_activePalette && _activePalette.colors && _activePalette.colors.color5)  ? Qt.color(_activePalette.colors.color5)  : "#ff00ff"
    readonly property color color6:  (_activePalette && _activePalette.colors && _activePalette.colors.color6)  ? Qt.color(_activePalette.colors.color6)  : "#00ffff"
    readonly property color color7:  (_activePalette && _activePalette.colors && _activePalette.colors.color7)  ? Qt.color(_activePalette.colors.color7)  : "#ffffff"
    readonly property color color8:  (_activePalette && _activePalette.colors && _activePalette.colors.color8)  ? Qt.color(_activePalette.colors.color8)  : "#808080"
    readonly property color color9:  (_activePalette && _activePalette.colors && _activePalette.colors.color9)  ? Qt.color(_activePalette.colors.color9)  : "#ff8080"
    readonly property color color10: (_activePalette && _activePalette.colors && _activePalette.colors.color10) ? Qt.color(_activePalette.colors.color10) : "#80ff80"
    readonly property color color11: (_activePalette && _activePalette.colors && _activePalette.colors.color11) ? Qt.color(_activePalette.colors.color11) : "#ffff80"
    readonly property color color12: (_activePalette && _activePalette.colors && _activePalette.colors.color12) ? Qt.color(_activePalette.colors.color12) : "#8080ff"
    readonly property color color13: (_activePalette && _activePalette.colors && _activePalette.colors.color13) ? Qt.color(_activePalette.colors.color13) : "#ff80ff"
    readonly property color color14: (_activePalette && _activePalette.colors && _activePalette.colors.color14) ? Qt.color(_activePalette.colors.color14) : "#80ffff"
    readonly property color color15: (_activePalette && _activePalette.colors && _activePalette.colors.color15) ? Qt.color(_activePalette.colors.color15) : "#ffffff"

    // Detecta si el tema cargado es oscuro o claro según luminancia WCAG
    readonly property bool isDark: relLuminance(background) < 0.5

    // ── Aliases semánticos (idénticos a Theme.qml de Quickshell) ─────────
    readonly property color accent:  color1
    readonly property color primary: accent
    readonly property color success: color2
    readonly property color warning: color3
    readonly property color danger:  color1
    readonly property color red:     "#ff4444"
    readonly property color text:    color15
    readonly property color surface: color0
    readonly property color muted:   Qt.rgba(text.r, text.g, text.b, 0.6)
    readonly property color border:  Qt.rgba(text.r, text.g, text.b, 0.12)
    readonly property color surfaceHover:  Qt.rgba(text.r, text.g, text.b, 0.08)
    readonly property color surfaceActive: Qt.rgba(primary.r, primary.g, primary.b, 0.16)
    readonly property color accentText:    textOn(accent)

    // ── Tipografía y Tokens de tamaño ────────────────────────────────────
    readonly property string systemFont: (typeof Sys !== "undefined" && Sys.systemFontFamily) ? Sys.systemFontFamily : ""
    readonly property string systemMonospace: (typeof Sys !== "undefined" && Sys.systemMonospaceFontFamily) ? Sys.systemMonospaceFontFamily : ""

    readonly property string fontFamily:          systemFont ? systemFont : "Google Sans"
    readonly property string fontFamilyDisplay:   (typeof Sys !== "undefined" && Sys.systemFontFamilyDisplay) ? Sys.systemFontFamilyDisplay : (systemFont ? systemFont : "Google Sans Display")
    readonly property string fontFamilyRounded:   (typeof Sys !== "undefined" && Sys.systemFontFamilyRounded) ? Sys.systemFontFamilyRounded : (systemFont ? systemFont : "Google Sans")
    readonly property string fontFamilyMonospace: systemMonospace ? systemMonospace : "Google Sans Code"

    readonly property real fontSizeScale: (typeof ConfigBackend !== "undefined" && ConfigBackend.fontSizeScale > 0) ? ConfigBackend.fontSizeScale : 1.0

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
    readonly property bool animationsEnabled: (typeof ConfigBackend !== "undefined") ? (ConfigBackend.animationsEnabled && !GamemodeService.gamemodeActive) : true
    readonly property real panelOpacity: (typeof ConfigBackend !== "undefined" && ConfigBackend.panelOpacity > 0)
        ? Math.max(0.5, Math.min(1.0, ConfigBackend.panelOpacity / 100.0))
        : 0.94
    readonly property bool hideScrollbars: (typeof ConfigBackend !== "undefined") ? ConfigBackend.hideScrollbars : false
    readonly property bool blurEnabled: (typeof ConfigBackend !== "undefined") ? ConfigBackend.blurEnabled : true
    readonly property bool hasTouchscreen: (typeof Sys !== "undefined") ? Sys.hasTouchscreen : false

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
