.pragma library

// ListParser.js — Parser y serializador de listas y tareas Markdown
// Soporta viñetas (- * +), numeradas (1. 1)), casillas de tareas (- [ ] - [x]), y sangría anidada.

function parseList(raw) {
    if (!raw || typeof raw !== "string") return [];
    var lines = raw.split("\n");
    var items = [];

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        // Línea con marcador de lista de tareas o viñeta estándar
        var taskMatch = line.match(/^([ \t]*)([-*+]|\d+[.)])[ \t]*\[([ xX]?)\][ \t]*(.*)$/);
        if (taskMatch) {
            var isChecked = (taskMatch[3].toLowerCase() === "x");
            items.push({
                indent: taskMatch[1],
                marker: taskMatch[2],
                spacing: " ",
                isTask: true,
                checked: isChecked,
                text: taskMatch[4] || "",
                lineIndex: i
            });
        } else {
            var m = line.match(/^([ \t]*)([-*+]|\d+[.)])([ \t]+)(.*)$/);
            if (m) {
                items.push({
                    indent: m[1],
                    marker: m[2],
                    spacing: m[3],
                    isTask: false,
                    checked: false,
                    text: m[4] || "",
                    lineIndex: i
                });
            } else if (items.length > 0) {
                // Línea de continuación sangrada
                items[items.length - 1].text += "\n" + line;
            } else {
                // Línea sin marcador inicial (fallback)
                items.push({
                    indent: "",
                    marker: "-",
                    spacing: " ",
                    isTask: false,
                    checked: false,
                    text: line,
                    lineIndex: i
                });
            }
        }
    }

    return items;
}

function serializeList(items) {
    if (!items || !Array.isArray(items)) return "";
    var lines = [];
    for (var i = 0; i < items.length; i++) {
        var it = items[i];
        var taskStr = it.isTask ? ("[" + (it.checked ? "x" : " ") + "] ") : "";
        var sp = it.spacing || " ";
        var line = (it.indent || "") + (it.marker || "-") + sp + taskStr + (it.text || "");
        lines.push(line);
    }
    return lines.join("\n");
}

// Alterna la casilla de tarea del ítem N en el texto crudo sin alterar nada más
// Atajo de tarea al escribir dentro de un ítem de lista: "[]", "[ ]", "[x]" al inicio del texto del ítem.
// Convierte apenas se cierra el corchete (no exige espacio después), igual que el viejo "- []" en un párrafo.
// Devuelve { checked, rest } o null. 'rest' es el texto que siguió al atajo (sin el espacio opcional).
function detectTaskShorthand(text) {
    if (typeof text !== "string") return null;
    var m = text.match(/^\s*\[( |x|X)?\] ?([\s\S]*)$/);
    if (!m) return null;
    if (m[2].charAt(0) === "(") return null;          // [x](url) pegado: es un enlace, no una tarea
    return { checked: (m[1] || "").toLowerCase() === "x", rest: m[2] };
}

// ── F22: nivel de encabezado dentro de texto de ítem ─────────────────────
// headingLevelOf("## texto") → 2; ("##") → 2 (encabezado vacío); ("#hashtag") → 0;
// ("texto ## adentro") → 0. Solo cuenta al inicio, con espacio o fin después.
function headingLevelOf(text) {
    if (typeof text !== "string" || text === "") return 0;
    var m = text.match(/^(#{1,6})(?=\s|$)/);
    if (!m) return 0;
    // "#hashtag": hashes seguidos de texto sin espacio → no es encabezado
    if (text.length > m[1].length) {
        var next = text.charAt(m[1].length);
        if (next !== " " && next !== "\t" && next !== "\n") return 0;
    }
    return m[1].length;
}

// Quita el prefijo de encabezado ("## " o "##" vacío) dejando el contenido.
function stripHeadingPrefix(text) {
    if (typeof text !== "string") return "";
    return text.replace(/^#{1,6}(?:\s+|\s*$)/, "");
}

// Nivel común de un rango de ítems [from..to] (0 si mezclado o sin encabezado).
// items: salida de parseList (usa .text). from/to inclusivos; se clampan.
function headingLevelOfItems(items, from, to) {
    if (!items || !Array.isArray(items) || items.length === 0) return 0;
    var s = (typeof from === "number") ? from : 0;
    var e = (typeof to === "number") ? to : items.length - 1;
    if (s > e) { var t = s; s = e; e = t; }
    s = Math.max(0, s);
    e = Math.min(items.length - 1, e);
    var lvl = -1;
    for (var i = s; i <= e; i++) {
        var cur = headingLevelOf(items[i] ? (items[i].text || "") : "");
        if (lvl === -1) lvl = cur;
        else if (cur !== lvl) return 0;
    }
    if (lvl === -1) return 0;
    return lvl;
}

// true si TODOS los ítems del rango tienen exactamente `level` (level 1..6).
function allItemsMatchHeading(items, from, to, level) {
    if (typeof level !== "number" || level < 1 || level > 6) return false;
    if (!items || !Array.isArray(items) || items.length === 0) return false;
    var s = (typeof from === "number") ? from : 0;
    var e = (typeof to === "number") ? to : items.length - 1;
    if (s > e) { var t = s; s = e; e = t; }
    s = Math.max(0, s);
    e = Math.min(items.length - 1, e);
    for (var i = s; i <= e; i++) {
        if (headingLevelOf(items[i] ? (items[i].text || "") : "") !== level) return false;
    }
    return true;
}
