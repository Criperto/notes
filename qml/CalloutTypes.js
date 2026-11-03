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

function getColor(typeKey, Theme) {
    var def = getType(typeKey);
    if (!def) return (Theme && Theme.accent) ? ("" + Theme.accent) : "#e3e3e3";
    if (!Theme) return def.defaultHex;
    switch (def.colorToken) {
        case "color4": return "" + (Theme.color4 || def.defaultHex);
        case "color2": return "" + (Theme.color2 || def.defaultHex);
        case "color5": return "" + (Theme.color5 || def.defaultHex);
        case "color3": return "" + (Theme.color3 || def.defaultHex);
        case "red":    return "" + (Theme.red || def.defaultHex);
        default:       return "" + (Theme[def.colorToken] || def.defaultHex);
    }
}
