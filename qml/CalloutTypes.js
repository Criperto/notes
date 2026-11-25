.pragma library

// CalloutTypes.js — Definición y metadatos de callouts estilo GitHub (F77)
var TYPES = {
    "NOTE": {
        id: "note",
        nameKey: "notes.callout.note",
        fallbackName: "Note",
        icon: "info.svg",
        colorToken: "color4",
        defaultHex: "#58a6ff"
    },
    "TIP": {
        id: "tip",
        nameKey: "notes.callout.tip",
        fallbackName: "Tip",
        icon: "lightbulb.svg",
        colorToken: "color2",
        defaultHex: "#3fb950"
    },
    "IMPORTANT": {
        id: "important",
        nameKey: "notes.callout.important",
        fallbackName: "Important",
        icon: "report.svg",
        colorToken: "color5",
        defaultHex: "#bc8cff"
    },
    "WARNING": {
        id: "warning",
        nameKey: "notes.callout.warning",
        fallbackName: "Warning",
        icon: "warning.svg",
        colorToken: "color3",
        defaultHex: "#d29922"
    },
    "CAUTION": {
        id: "caution",
        nameKey: "notes.callout.caution",
        fallbackName: "Caution",
        icon: "error.svg",
        colorToken: "red",
        defaultHex: "#f85149"
    }
};

function getType(typeKey) {
    if (!typeKey || typeof typeKey !== "string") return null;
    var k = typeKey.toUpperCase();
    return TYPES[k] || null;
}

function _parseHexRgb(hexStr) {
    if (!hexStr || typeof hexStr !== "string") return null;
    var s = hexStr.trim();
    if (s.charAt(0) === "#") s = s.slice(1);
    if (s.length === 8) s = s.slice(2); // ignorar alfa (#AARRGGBB -> #RRGGBB)
    if (s.length !== 6) return null;
    var n = parseInt(s, 16);
    if (isNaN(n)) return null;
    return {
        r: ((n >> 16) & 255) / 255.0,
        g: ((n >> 8) & 255) / 255.0,
        b: (n & 255) / 255.0
    };
}

function _toHexRgb(rgb) {
    function comp(v) {
        var n = Math.max(0, Math.min(255, Math.round(v * 255)));
        return (n < 16 ? "0" : "") + n.toString(16);
    }
    return "#" + comp(rgb.r) + comp(rgb.g) + comp(rgb.b);
}

function _relLuminance(rgb) {
    function toLin(c) {
        return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    }
    return 0.2126 * toLin(rgb.r) + 0.7152 * toLin(rgb.g) + 0.0722 * toLin(rgb.b);
}

function _contrastRatio(a, b) {
    var l1 = _relLuminance(a);
    var l2 = _relLuminance(b);
    return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
}

function _ensureReadableColor(hexStr, Theme) {
    if (!Theme || (!Theme.surface && !Theme.text)) return hexStr;
    var fg = _parseHexRgb(hexStr);
    var bg = Theme.surface ? _parseHexRgb("" + Theme.surface) : _parseHexRgb(Theme.lightMode ? "#f5f5f5" : "#181818");
    var target = Theme.text ? _parseHexRgb("" + Theme.text) : _parseHexRgb(Theme.lightMode ? "#1c1c1c" : "#f0f0f0");
    if (!fg || !bg || !target) return hexStr;

    var minRatio = 4.5;
    if (_contrastRatio(fg, bg) >= minRatio) return _toHexRgb(fg);

    // Mezclar progresivamente hacia Theme.text preservando el matiz hasta alcanzar contraste legible.
    var best = fg;
    for (var step = 1; step <= 12; step++) {
        var t = step / 12.0;
        var mixed = {
            r: fg.r + (target.r - fg.r) * t,
            g: fg.g + (target.g - fg.g) * t,
            b: fg.b + (target.b - fg.b) * t
        };
        best = mixed;
        if (_contrastRatio(mixed, bg) >= minRatio) break;
    }
    return _toHexRgb(best);
}

function getColor(typeKey, Theme) {
    var def = getType(typeKey);
    if (!def) return (Theme && Theme.accent) ? ("" + Theme.accent) : "#e3e3e3";
    if (!Theme) return def.defaultHex;
    var rawHex;
    switch (def.colorToken) {
        case "color4": rawHex = "" + (Theme.color4 || def.defaultHex); break;
        case "color2": rawHex = "" + (Theme.color2 || def.defaultHex); break;
        case "color5": rawHex = "" + (Theme.color5 || def.defaultHex); break;
        case "color3": rawHex = "" + (Theme.color3 || def.defaultHex); break;
        case "red":    rawHex = "" + (Theme.red || def.defaultHex); break;
        default:       rawHex = "" + (Theme[def.colorToken] || def.defaultHex); break;
    }
    return _ensureReadableColor(rawHex, Theme);
}
