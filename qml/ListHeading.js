.pragma library

// ListHeading.js — Encabezado dentro de ítems de lista (F21)
// El marcador `##` forma parte del texto crudo del ítem (se serializa tal cual),
// pero en edición solo lo ve el ítem activo y únicamente con el cursor al inicio
// o con el contenido vacío. El TextEdit edita SOLO el contenido (sin `## `) y el
// marcador revelado es un Text separado (el cursor/selección nunca lo incluyen).
//
// Reglas de detección (iguales que ListParser.headingLevelOf):
// - `## texto` → level 2, content `texto`; `##` solo → level 2, content ``;
// - `#hashtag` (sin espacio) → NO es encabezado (level 0);
// - `#` adentro del texto no cuenta (solo al inicio).

function splitHeading(raw) {
    if (typeof raw !== "string" || raw === "") return { level: 0, content: raw || "" };
    var m = raw.match(/^(#{1,6})(?=\s|$)/);
    if (!m) return { level: 0, content: raw };
    var level = m[1].length;
    if (raw.length > m[1].length) {
        var nx = raw.charAt(m[1].length);
        if (nx !== " " && nx !== "\t" && nx !== "\n") return { level: 0, content: raw };
        return { level: level, content: raw.replace(/^#{1,6}[ \t]+/, "") };
    }
    return { level: level, content: "" };
}

function composeHeading(level, content) {
    var c = (typeof content === "string") ? content : "";
    if (typeof level !== "number" || level < 1 || level > 6) return c;
    if (c === "") return new Array(level + 1).join("#");
    return new Array(level + 1).join("#") + " " + c;
}

// Longitud del prefijo crudo (`## ` con un espacio canónico; `##` solo → 2).
// Para espaciados no canónicos se normaliza al editar (el raw intacto se conserva
// mientras el usuario no toque el ítem).
function prefixLenOf(level, raw) {
    if (typeof level !== "number" || level < 1 || level > 6) return 0;
    if (typeof raw === "string") {
        var m = raw.match(/^(#{1,6})[ \t]*/);
        if (m && m[1].length === level) return m[0].length;
    }
    return level + 1;
}

// rawPos (coords. crudo, con `## `) → displayPos (coords. contenido sin prefijo).
// Posiciones dentro del prefijo colapsan a 0 (el marcador no es editable).
function toDisplayPos(level, rawPos) {
    if (typeof level !== "number" || level < 1 || level > 6) return rawPos;
    var pLen = level + 1;
    if (typeof rawPos !== "number" || rawPos <= pLen) return 0;
    return rawPos - pLen;
}

// displayPos (contenido) → rawPos (crudo con prefijo canónico).
function toRawPos(level, displayPos) {
    if (typeof level !== "number" || level < 1 || level > 6) return displayPos;
    if (typeof displayPos !== "number" || displayPos < 0) return level + 1;
    return displayPos + level + 1;
}
