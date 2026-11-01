.pragma library

// SearchLogic.js — Lógica pura de búsqueda dentro de la nota.
// Se usa desde NoteEditorModal.qml (construcción de la lista de coincidencias,
// mapeo de offsets) y desde los delegates Block*.qml solo vía los parámetros
// que ya calcula el modal. Todo es testeable con node (tests/run.js).
// Convención de ordinales: los matches se ordenan por (bloque, unidad, pos) y
// el ordinal global es el índice en ese orden. Dentro de una unidad pintada
// (párrafo, heading limpio, cita limpia, ítem de lista, celda, código puro,
// bloque raw) el ordinal LOCAL es el índice del match dentro de esa unidad, en
// el mismo orden en que Inline.highlightInHtml los pinta (chunks HTML en orden,
// pos ascendente, sin solapamiento).

// Normaliza para búsqueda: minúsculas + tildes a forma base sin cambiar longitud
// (idéntico a Inline._stripAccentsSameLen + toLowerCase y al del modal).
function normalize(str) {
    if (!str || typeof str !== "string") return "";
    var out = "";
    for (var i = 0; i < str.length; i++) {
        var c = str[i];
        var n = (typeof c.normalize === "function") ? c.normalize("NFD") : c;
        out += (n.length > 0 ? n[0] : c);
    }
    return out.toLowerCase();
}

// Todas las ocurrencias no solapadas de query en text (coordenadas de text).
// Igual avance que highlightInHtml (salta qLen tras cada match).
function findAll(text, query) {
    var res = [];
    if (!text || !query || typeof text !== "string" || typeof query !== "string") return res;
    var q = normalize(query.trim());
    if (q.length === 0) return res;
    var norm = normalize(text);
    var qLen = q.length;
    var pos = norm.indexOf(q, 0);
    while (pos !== -1) {
        res.push({ pos: pos, len: qLen });
        pos = norm.indexOf(q, pos + Math.max(1, qLen));
    }
    return res;
}

// Texto "visible" aproximado de un fragmento markdown ya limpio de prefijos de
// bloque (párrafo, heading sin #, cita sin >, ítem de lista, celda, código puro).
// Quita lo que Inline.inlineToHtml NO pinta como texto (URLs de links, imágenes
// completas) y marcadores de formato pareados. Devuelve {text, map} donde
// map[i] = índice en el markdown original del carácter visible i.
function stripForSearch(md) {
    var text = "";
    var map = [];
    var s = (typeof md === "string") ? md : "";
    var i = 0;
    var n = s.length;

    function pushChars(chunk, startIdx) {
        for (var k = 0; k < chunk.length; k++) {
            text += chunk[k];
            map.push(startIdx + k);
        }
    }

    while (i < n) {
        // Imagen ![alt](url): no se pinta como texto → se descarta entera
        if (s[i] === "!" && s[i + 1] === "[") {
            var imgEnd = _scanLink(s, i + 1);
            if (imgEnd !== -1) { i = imgEnd; continue; }
        }
        // Link [texto](url): se conserva el texto con sus offsets originales
        if (s[i] === "[") {
            var linkParsed = _parseLink(s, i);
            if (linkParsed) {
                var inner = stripForSearch(linkParsed.inner);
                for (var m = 0; m < inner.text.length; m++) {
                    text += inner.text[m];
                    map.push(linkParsed.innerStart + inner.map[m]);
                }
                i = linkParsed.end;
                continue;
            }
            // Wikilink [[dest|alias]]: se conserva alias o destino
            var wiki = s.substring(i).match(/^\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/);
            if (wiki) {
                var label = (wiki[2] !== undefined) ? wiki[2] : wiki[1];
                var labelStart = i + wiki[0].indexOf(label);
                pushChars(label, labelStart);
                i += wiki[0].length;
                continue;
            }
        }
        // Autolink <https://...> : se conserva la URL (se pinta como texto)
        if (s[i] === "<") {
            var auto = s.substring(i).match(/^<(https?:\/\/[^\s>]+|mailto:[^\s>]+)>/);
            if (auto) {
                pushChars(auto[1], i + 1);
                i += auto[0].length;
                continue;
            }
        }
        // Código inline `code`: se conserva el interior
        if (s[i] === "`") {
            var closeTick = s.indexOf("`", i + 1);
            if (closeTick !== -1) {
                pushChars(s.substring(i + 1, closeTick), i + 1);
                i = closeTick + 1;
                continue;
            }
        }
        // Marcadores pareados ** ~~ == : se descartan, se conserva el interior
        if ((s[i] === "*" && s[i + 1] === "*") || (s[i] === "~" && s[i + 1] === "~") || (s[i] === "=" && s[i + 1] === "=")) {
            i += 2;
            continue;
        }
        text += s[i];
        map.push(i);
        i++;
    }
    return { text: text, map: map };
}

// Escanea "[...](...)" empezando en el '[' (idx). Devuelve índice posterior al
// ')' final o -1. Soporta un nivel de paréntesis en la URL (como Inline.js).
function _scanLink(s, idx) {
    var closeBracket = s.indexOf("]", idx + 1);
    if (closeBracket === -1 || s[closeBracket + 1] !== "(") return -1;
    var j = closeBracket + 2;
    var depth = 1;
    while (j < s.length) {
        if (s[j] === "(") depth++;
        else if (s[j] === ")") {
            depth--;
            if (depth === 0) return j + 1;
        } else if (/\s/.test(s[j]) && depth === 1) {
            // Título opcional "titulo" tras la URL: saltarlo hasta el ')'
            var titleMatch = s.substring(j).match(/^\s+"[^"]*"\)/);
            if (titleMatch) return j + titleMatch[0].length;
            return -1;
        }
        j++;
    }
    return -1;
}

function _parseLink(s, idx) {
    var closeBracket = s.indexOf("]", idx + 1);
    if (closeBracket === -1 || s[closeBracket + 1] !== "(") return null;
    var end = _scanLink(s, idx);
    if (end === -1) return null;
    return { inner: s.substring(idx + 1, closeBracket), innerStart: idx + 1, end: end };
}

// Longitud del prefijo de encabezado "## " (mismo criterio que
// BlockHeading.cleanHeadingText: /^[ \t]*#{1,6}[ \t]*(.*)$/).
function headingPrefixLen(raw) {
    if (!raw || typeof raw !== "string") return 0;
    var m = raw.match(/^[ \t]*#{1,6}[ \t]*/);
    // Solo hay prefijo si queda texto después (si no, es solo "##" suelto)
    if (m && m[0].length < raw.length) return m[0].length;
    return 0;
}

// Texto limpio de cita + mapa a offsets raw (mismo regex que
// BlockQuote.cleanQuoteText: /^[ \t]*>[ \t]?/gm).
function quoteCleanMap(raw) {
    var s = (typeof raw === "string") ? raw : "";
    var clean = "";
    var map = [];
    var lines = s.split("\n");
    for (var li = 0; li < lines.length; li++) {
        var line = lines[li];
        var m = line.match(/^[ \t]*>[ \t]?/);
        var pre = m ? m[0].length : 0;
        var lineStart = 0;
        for (var k = 0; k < li; k++) lineStart += lines[k].length + 1;
        for (var c = pre; c < line.length; c++) {
            clean += line[c];
            map.push(lineStart + c);
        }
        if (li < lines.length - 1) {
            clean += "\n";
            map.push(lineStart + line.length);
        }
    }
    return { clean: clean, map: map };
}

// Rango del código puro dentro del raw de un bloque code (espejo exacto de
// BlockCode.pureCodeText: quita primera línea si es fence y última si cierra).
function codePureRange(raw) {
    var s = (typeof raw === "string") ? raw : "";
    var lines = s.split("\n");
    var start = 0;
    var end = s.length;
    if (lines.length >= 2 && /^[ \t]*(`{3,}|~{3,})/.test(lines[0])) {
        start = lines[0].length + 1;
        if (/^[ \t]*(`{3,}|~{3,})[ \t]*$/.test(lines[lines.length - 1])) {
            end = s.length - lines[lines.length - 1].length - 1;
            if (end < start) end = start;
        }
    }
    return { start: start, length: Math.max(0, end - start) };
}

// Cuenta ocurrencias visibles en un HTML ya renderizado, con el MISMO recorrido
// que Inline.highlightInHtml (chunks fuera de tags/entidades, normalizado, sin
// solapar). N del contador = cantidad de spans que se van a pintar.
function countInHtml(html, query) {
    if (!html || !query || typeof html !== "string" || typeof query !== "string") return 0;
    var q = normalize(query.trim());
    if (q.length === 0) return 0;
    var parts = html.split(/(<[^>]+>|&[#A-Za-z0-9]+;)/g);
    var total = 0;
    for (var i = 0; i < parts.length; i++) {
        if (i % 2 === 0 && parts[i]) {
            var normChunk = normalize(parts[i]);
            var idx = normChunk.indexOf(q, 0);
            while (idx !== -1) {
                total++;
                idx = normChunk.indexOf(q, idx + Math.max(1, q.length));
            }
        }
    }
    return total;
}
