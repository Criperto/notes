.pragma library

// BlockModel.js — Modelo y divisor de bloques Markdown con fidelidad byte a byte
// Regla fundamental: joinBlocks(splitBlocks(md)) === md sin pérdida alguna.

var _bidCounter = 1;

function getNextBid() {
    return _bidCounter++;
}

// Divide un texto markdown completo en bloques { bid, type, raw, sep }
function splitBlocks(md) {
    if (typeof md !== "string" || md.length === 0) {
        return { lead: "", blocks: [] };
    }

    // 1. Extraer saltos de línea / espacios iniciales (lead)
    var leadMatch = md.match(/^(?:[ \t]*\r?\n)+/);
    var lead = leadMatch ? leadMatch[0] : "";
    var rest = md.substring(lead.length);

    if (rest.length === 0) {
        return { lead: lead, blocks: [] };
    }

    // 2. Descomponer el resto en líneas con sus terminadores originales
    // Cada línea: { content: string, eol: string }
    var lines = [];
    var lineRegex = /([^\r\n]*?)(\r?\n|$)/g;
    var match;
    while ((match = lineRegex.exec(rest)) !== null) {
        if (match.index === rest.length) break;
        lines.push({ content: match[1], eol: match[2] });
        if (match[2] === "") break;
    }

    var blocks = [];
    var i = 0;
    var n = lines.length;

    while (i < n) {
        // Si encontramos líneas vacías inesperadas, las consumimos como sep del bloque anterior o lead
        if (lines[i].content.trim() === "" && blocks.length === 0) {
            lead += lines[i].content + lines[i].eol;
            i++;
            continue;
        }

        var block = _parseNextBlock(lines, i);
        if (block) {
            blocks.push(block.block);
            i = block.nextIndex;
        } else {
            // Fallback seguro: no perder jamás contenido
            var rawFallback = lines[i].content;
            var sepFallback = lines[i].eol;
            blocks.push({
                bid: getNextBid(),
                type: "raw",
                raw: rawFallback,
                sep: sepFallback
            });
            i++;
        }
    }

    return { lead: lead, blocks: blocks };
}

// Une los bloques reconstruyendo exactamente el markdown original
function joinBlocks(modelOrBlocks, lead) {
    var actualLead = "";
    var blocks = [];

    if (modelOrBlocks && Array.isArray(modelOrBlocks.blocks)) {
        actualLead = modelOrBlocks.lead || "";
        blocks = modelOrBlocks.blocks;
    } else if (Array.isArray(modelOrBlocks)) {
        actualLead = (typeof lead === "string") ? lead : "";
        blocks = modelOrBlocks;
    } else {
        return "";
    }

    var out = actualLead;
    for (var i = 0; i < blocks.length; i++) {
        var b = blocks[i];
        out += (b.raw || "") + (b.sep !== undefined ? b.sep : "");
    }
    return out;
}

// Reparsea un bloque editado. Puede dar 0, 1 o N bloques.
function reparseBlock(raw, baseBid) {
    if (typeof raw !== "string" || raw.trim() === "") {
        return [];
    }

    var result = splitBlocks(raw);
    var blocks = result.blocks;

    // Si había espacios o saltos al inicio en lead, se reintegran al primer bloque
    if (result.lead.length > 0 && blocks.length > 0) {
        blocks[0].raw = result.lead + blocks[0].raw;
    } else if (result.lead.length > 0 && blocks.length === 0) {
        return [{
            bid: baseBid || getNextBid(),
            type: "raw",
            raw: result.lead,
            sep: ""
        }];
    }

    // Reasignar baseBid al primer bloque para estabilidad de delegate en QML
    if (blocks.length > 0 && baseBid) {
        blocks[0].bid = baseBid;
    }

    return blocks;
}

// Detecta disparadores de autoformato al escribir al inicio o final de línea
function detectAutoformat(raw) {
    if (!raw || typeof raw !== "string") return { matched: false };

    // Encabezados (# a ###### seguido de espacio)
    var headingMatch = raw.match(/^(#{1,6}) (.*)$/);
    if (headingMatch) {
        return {
            matched: true,
            type: "heading",
            level: headingMatch[1].length,
            prefix: headingMatch[1] + " ",
            content: headingMatch[2]
        };
    }

    // Lista de tareas (- [ ], - [x], - [], * [ ], o atajo [] / [ ] sin guión)
    var taskMatch = raw.match(/^([ \t]*(?:[-*+][ \t]+)?)\[( |x|X)?\][ \t]*(.*)$/);
    if (taskMatch) {
        var rawPfx = (taskMatch[1] || "").trim();
        var bulletPfx = (rawPfx === "-" || rawPfx === "*" || rawPfx === "+") ? rawPfx : "-";
        var isChecked = (taskMatch[2] !== undefined && taskMatch[2].toLowerCase() === "x");
        return {
            matched: true,
            type: "list",
            subType: "task",
            checked: isChecked,
            prefix: bulletPfx + " [" + (isChecked ? "x" : " ") + "] ",
            content: taskMatch[3]
        };
    }

    // Lista viñeta (- , * , + ). '-' se incluye; el atajo '- [ ]' se resuelve dentro del ítem (ListParser.detectTaskShorthand).
    // Se excluyen líneas que son una regla horizontal ('- - -', '* * *').
    var bulletMatch = _isHrLine(raw) ? null : raw.match(/^([ \t]*[-*+]) (.*)$/);
    if (bulletMatch) {
        return {
            matched: true,
            type: "list",
            subType: "bullet",
            prefix: bulletMatch[1] + " ",
            content: bulletMatch[2]
        };
    }

    // Lista numerada (1. o 1) ), limitada a números <= 99 (evita años como "2024. fue...")
    var orderedMatch = raw.match(/^([ \t]*)(\d+)([.)]) (.*)$/);
    if (orderedMatch) {
        var num = parseInt(orderedMatch[2], 10);
        if (num <= 99) {
            return {
                matched: true,
                type: "list",
                subType: "ordered",
                number: num,
                prefix: orderedMatch[1] + orderedMatch[2] + orderedMatch[3] + " ",
                content: orderedMatch[4]
            };
        }
    }

    // Cita (> )
    var quoteMatch = raw.match(/^([ \t]*>) (.*)$/);
    if (quoteMatch) {
        return {
            matched: true,
            type: "quote",
            prefix: quoteMatch[1] + " ",
            content: quoteMatch[2]
        };
    }

    // Bloque de código con fence (``` o ~~~ con o sin lenguaje)
    var codeMatch = raw.match(/^[ \t]*(`{3,}|~{3,})([a-zA-Z0-9_-]*)[ \t]*$/);
    if (codeMatch) {
        return {
            matched: true,
            type: "code",
            fence: codeMatch[1],
            lang: codeMatch[2] || "",
            content: ""
        };
    }

    return { matched: false };
}

// ── Helpers internos de parsing ──────────────────────────────────────────────

function _parseNextBlock(lines, startIdx) {
    var lineObj = lines[startIdx];
    var line = lineObj.content;

    // 1. Bloque de código con fence (``` o ~~~)
    var fenceMatch = line.match(/^[ \t]*(`{3,}|~{3,})(.*)$/);
    if (fenceMatch) {
        return _consumeFenceBlock(lines, startIdx, fenceMatch[1]);
    }

    // 2. Encabezado (# a ######)
    var headingMatch = line.match(/^[ \t]*(#{1,6})(?:[ \t]+(.*))?$/);
    if (headingMatch) {
        return _consumeSingleLineBlock(lines, startIdx, "heading", {
            level: headingMatch[1].length,
            titleText: headingMatch[2] || ""
        });
    }

    // 3. Regla horizontal (---, ***, ___, - - -)
    if (_isHrLine(line)) {
        return _consumeSingleLineBlock(lines, startIdx, "hr", {});
    }

    // 4. Tabla (línea con | seguida de fila delimitadora)
    if (_isTableStart(lines, startIdx)) {
        return _consumeTableBlock(lines, startIdx);
    }

    // 5. Cita (> ...)
    if (_isQuoteLine(line)) {
        return _consumeQuoteBlock(lines, startIdx);
    }

    // 6. Lista (viñeta, numerada o tareas)
    if (_isListStart(line)) {
        return _consumeListBlock(lines, startIdx);
    }

    // 7. Línea de imágenes única o múltiple
    if (_isImageLine(line)) {
        return _consumeImageBlock(lines, startIdx);
    }

    // 8. Bloque HTML
    if (_isHtmlBlockStart(line)) {
        return _consumeHtmlBlock(lines, startIdx);
    }

    // 9. Párrafo estándar (o fallback)
    return _consumeParagraphBlock(lines, startIdx);
}

function _consumeFenceBlock(lines, startIdx, openFence) {
    var fenceChar = openFence[0];
    var fenceLen = openFence.length;
    var rawParts = [];
    var i = startIdx;

    // Agregar la línea de apertura
    rawParts.push(lines[i].content);
    var lastEol = lines[i].eol;
    i++;

    var hasClosingFence = false;
    for (var checkIdx = startIdx + 1; checkIdx < lines.length; checkIdx++) {
        var m = lines[checkIdx].content.match(/^[ \t]*(`{3,}|~{3,})[ \t]*$/);
        if (m && m[1][0] === fenceChar && m[1].length >= fenceLen) {
            hasClosingFence = true;
            break;
        }
    }

    var closed = false;
    while (i < lines.length) {
        var cur = lines[i];
        var closeMatch = cur.content.match(/^[ \t]*(`{3,}|~{3,})[ \t]*$/);
        if (closeMatch && closeMatch[1][0] === fenceChar && closeMatch[1].length >= fenceLen) {
            rawParts.push(cur.content);
            lastEol = cur.eol;
            closed = true;
            i++;
            break;
        }
        // Si el fence no está cerrado y encontramos una línea en blanco,
        // limitar el consumo al bloque contiguo para no tragar todo el documento
        if (!hasClosingFence && cur.content.trim() === "") {
            break;
        }
        rawParts.push(cur.content);
        lastEol = cur.eol;
        i++;
    }

    var sep = lastEol;
    // Consumir líneas en blanco siguientes como sep
    while (i < lines.length && lines[i].content.trim() === "") {
        sep += lines[i].content + lines[i].eol;
        i++;
    }

    var isMermaid = /^[ \t]*(`{3,}|~{3,})[ \t]*mermaid\b/i.test(lines[startIdx].content);

    return {
        nextIndex: i,
        block: {
            bid: getNextBid(),
            type: isMermaid ? "mermaid" : "code",
            raw: _joinLinesPreservingEols(lines, startIdx, (closed ? i - 1 : i - 1), rawParts),
            sep: sep
        }
    };
}

function _consumeSingleLineBlock(lines, startIdx, type, extra) {
    var raw = lines[startIdx].content;
    var sep = lines[startIdx].eol;
    var i = startIdx + 1;

    // Consumir líneas en blanco siguientes como sep
    while (i < lines.length && lines[i].content.trim() === "") {
        sep += lines[i].content + lines[i].eol;
        i++;
    }

    var block = {
        bid: getNextBid(),
        type: type,
        raw: raw,
        sep: sep
    };
    if (extra && extra.level) block.level = extra.level;
    return { nextIndex: i, block: block };
}

function _consumeImageBlock(lines, startIdx) {
    var rawLines = [];
    var i = startIdx;

    while (i < lines.length) {
        var cur = lines[i];
        if (cur.content.trim() === "") {
            break; // Una línea en blanco separa el bloque de imágenes
        }
        if (_isImageLine(cur.content)) {
            rawLines.push(cur.content);
            i++;
        } else {
            break;
        }
    }

    var sep = lines[i - 1].eol;
    while (i < lines.length && lines[i].content.trim() === "") {
        sep += lines[i].content + lines[i].eol;
        i++;
    }

    return {
        nextIndex: i,
        block: {
            bid: getNextBid(),
            type: "image",
            raw: _joinLinesPreservingEols(lines, startIdx, i - 1, rawLines),
            sep: sep
        }
    };
}

function _consumeTableBlock(lines, startIdx) {
    var rawLines = [];
    var i = startIdx;

    // Consumir filas de tabla mientras contengan '|'
    while (i < lines.length) {
        var cur = lines[i];
        if (cur.content.trim() === "" || cur.content.indexOf("|") === -1) {
            break;
        }
        rawLines.push(cur.content);
        i++;
    }

    var sep = "";
    if (i > startIdx) {
        sep = lines[i - 1].eol;
    }
    while (i < lines.length && lines[i].content.trim() === "") {
        sep += lines[i].content + lines[i].eol;
        i++;
    }

    return {
        nextIndex: i,
        block: {
            bid: getNextBid(),
            type: "table",
            raw: _joinLinesPreservingEols(lines, startIdx, i - 1, rawLines),
            sep: sep
        }
    };
}

function _consumeQuoteBlock(lines, startIdx) {
    var rawLines = [];
    var i = startIdx;

    while (i < lines.length) {
        var cur = lines[i];
        if (cur.content.trim() === "") {
            break; // Una línea en blanco separa el bloque de cita
        }
        if (_isQuoteLine(cur.content)) {
            rawLines.push(cur.content);
            i++;
        } else {
            // Si la línea no tiene '>', interrumpe la cita en nuestro modelo
            break;
        }
    }

    var sep = lines[i - 1].eol;
    while (i < lines.length && lines[i].content.trim() === "") {
        sep += lines[i].content + lines[i].eol;
        i++;
    }

    return {
        nextIndex: i,
        block: {
            bid: getNextBid(),
            type: "quote",
            raw: _joinLinesPreservingEols(lines, startIdx, i - 1, rawLines),
            sep: sep
        }
    };
}

function _consumeListBlock(lines, startIdx) {
    var rawLines = [];
    var i = startIdx;

    while (i < lines.length) {
        var cur = lines[i];
        if (cur.content.trim() === "") {
            break; // Línea en blanco separa bloques
        }
        // Si aparece otro bloque que interrumpe (heading, hr, fence, quote, table)
        if (i > startIdx && (_isHeadingLine(cur.content) || _isHrLine(cur.content) || _isFenceLine(cur.content) || _isQuoteLine(cur.content) || _isTableStart(lines, i))) {
            break;
        }

        // Si es un ítem de lista o línea con sangría
        if (_isListStart(cur.content) || cur.content.match(/^[ \t]{2,}/)) {
            rawLines.push(cur.content);
            i++;
        } else {
            break;
        }
    }

    var sep = lines[i - 1].eol;
    while (i < lines.length && lines[i].content.trim() === "") {
        sep += lines[i].content + lines[i].eol;
        i++;
    }

    return {
        nextIndex: i,
        block: {
            bid: getNextBid(),
            type: "list",
            raw: _joinLinesPreservingEols(lines, startIdx, i - 1, rawLines),
            sep: sep
        }
    };
}

function _consumeHtmlBlock(lines, startIdx) {
    var rawLines = [];
    var i = startIdx;

    while (i < lines.length) {
        var cur = lines[i];
        if (cur.content.trim() === "") {
            break;
        }
        rawLines.push(cur.content);
        i++;
    }

    var sep = lines[i - 1].eol;
    while (i < lines.length && lines[i].content.trim() === "") {
        sep += lines[i].content + lines[i].eol;
        i++;
    }

    return {
        nextIndex: i,
        block: {
            bid: getNextBid(),
            type: "html",
            raw: _joinLinesPreservingEols(lines, startIdx, i - 1, rawLines),
            sep: sep
        }
    };
}

function _consumeParagraphBlock(lines, startIdx) {
    var rawLines = [];
    var i = startIdx;

    while (i < lines.length) {
        var cur = lines[i];
        if (cur.content.trim() === "") {
            break;
        }

        // Si una línea posterior interrumpe el párrafo
        if (i > startIdx) {
            if (_isHeadingLine(cur.content) ||
                _isHrLine(cur.content) ||
                _isFenceLine(cur.content) ||
                _isQuoteLine(cur.content) ||
                _isListStart(cur.content) ||
                _isImageLine(cur.content) ||
                _isTableStart(lines, i)) {
                break;
            }
        }

        rawLines.push(cur.content);
        i++;
    }

    var sep = lines[i - 1].eol;
    while (i < lines.length && lines[i].content.trim() === "") {
        sep += lines[i].content + lines[i].eol;
        i++;
    }

    return {
        nextIndex: i,
        block: {
            bid: getNextBid(),
            type: "paragraph",
            raw: _joinLinesPreservingEols(lines, startIdx, i - 1, rawLines),
            sep: sep
        }
    };
}

// Reconstruye el raw multilínea uniendo con los eols intermedios exactos
function _joinLinesPreservingEols(lines, startIdx, endIdx, rawLines) {
    if (rawLines.length <= 1) {
        return rawLines.length === 1 ? rawLines[0] : "";
    }
    var out = "";
    for (var k = 0; k < rawLines.length; k++) {
        out += rawLines[k];
        if (k < rawLines.length - 1) {
            out += lines[startIdx + k].eol;
        }
    }
    return out;
}

// ── Detectores de sintaxis de línea ──────────────────────────────────────────

function _isHeadingLine(str) {
    return /^[ \t]*#{1,6}(?:[ \t]+.*)?$/.test(str);
}

function _isHrLine(str) {
    return /^[ \t]*(?:(?:-[ \t]*){3,}|(?:_[ \t]*){3,}|(?:\*[ \t]*){3,})$/.test(str);
}

function _isFenceLine(str) {
    return /^[ \t]*(`{3,}|~{3,})/.test(str);
}

function _isQuoteLine(str) {
    return /^[ \t]*>/.test(str);
}

function _isListStart(str) {
    return /^[ \t]*(?:[-*+]|\d+[.)])[ \t]+/.test(str);
}

function _isTableStart(lines, idx) {
    if (idx + 1 >= lines.length) return false;
    var line1 = lines[idx].content;
    var line2 = lines[idx + 1].content;
    if (line1.indexOf("|") === -1 || line2.indexOf("|") === -1) return false;
    // La segunda línea debe ser la fila delimitadora |---|---|
    return /^[ \t]*\|?([ \t]*:?-+:?[ \t]*\|)+([ \t]*:?-+:?[ \t]*)?\|?[ \t]*$/.test(line2);
}

function _isImageLine(str) {
    var trimmed = str.trim();
    if (!trimmed) return false;
    // Detecta una o varias imágenes o imágenes con enlace
    // Ejemplo: ![alt](url) o [![alt](url)](url)
    var imgPattern = /^(?:\[!\[[^\]]*\]\([^)]+\)\]\([^)]+\)|!\[[^\]]*\]\([^)]+\))(?:[ \t]*(?:\[!\[[^\]]*\]\([^)]+\)\]\([^)]+\)|!\[[^\]]*\]\([^)]+\)))*$/;
    return imgPattern.test(trimmed);
}

function _isHtmlBlockStart(str) {
    return /^[ \t]*<(?:div|p|table|tbody|tr|td|th|ul|ol|li|blockquote|pre|details|summary|section|article|header|footer|nav|aside|h[1-6]|hr|iframe|script|style|figure|figcaption|!--)[ \t>/\n]/i.test(str);
}

function isMergeableBlockType(type) {
    return type === "paragraph" || type === "heading" || type === "quote" || type === "list";
}

function canMergeBlocks(typeA, typeB) {
    return isMergeableBlockType(typeA) && isMergeableBlockType(typeB);
}

// Posición del cursor dentro del contenido editable tras convertir un párrafo a otro tipo.
// 'auto' es el resultado de detectAutoformat; 'cursor' es la posición en el raw antes de convertir.
function cursorAfterAutoformat(auto, cursor) {
    if (!auto || !auto.matched) return Math.max(0, cursor || 0);
    var plen = (auto.prefix || "").length;
    return Math.max(0, (cursor || 0) - plen);
}

// Estima en O(1) la altura de un bloque no montado (en píxeles) para reservar espacio en el scroll
function estimateBlockHeight(type, raw, pageW) {
    var pw = (typeof pageW === "number" && pageW > 100) ? pageW : 700;
    var str = (typeof raw === "string") ? raw : "";
    var charsPerLine = Math.max(20, Math.floor(pw / 8.5));

    switch (type) {
        case "heading": {
            var levelMatch = str.match(/^[ \t]*(#{1,6})/);
            var lvl = levelMatch ? levelMatch[1].length : 1;
            var hBase = 46;
            if (lvl === 1) hBase = 52;
            else if (lvl === 2) hBase = 44;
            else if (lvl === 3) hBase = 38;
            else if (lvl >= 4) hBase = 32;
            var textLines = Math.max(1, Math.ceil(str.length / Math.max(15, Math.floor(pw / 12))));
            return hBase + (textLines - 1) * (hBase - 12);
        }
        case "paragraph": {
            if (!str) return 34;
            var pLines = str.split(/\r?\n/);
            var totalPVisualLines = 0;
            for (var i = 0; i < pLines.length; i++) {
                totalPVisualLines += Math.max(1, Math.ceil(pLines[i].length / charsPerLine));
            }
            return Math.max(30, totalPVisualLines * 22 + 10);
        }
        case "list": {
            if (!str) return 32;
            var lLines = str.split(/\r?\n/);
            var totalLVisualLines = 0;
            for (var j = 0; j < lLines.length; j++) {
                totalLVisualLines += Math.max(1, Math.ceil(lLines[j].length / (charsPerLine - 4)));
            }
            return Math.max(30, totalLVisualLines * 26 + 8);
        }
        case "quote": {
            if (!str) return 38;
            var isCallout = /^[ \t]*>[ \t]*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]/i.test(str);
            var qLines = str.split(/\r?\n/);
            var totalQVisualLines = 0;
            for (var k = 0; k < qLines.length; k++) {
                totalQVisualLines += Math.max(1, Math.ceil(qLines[k].length / (charsPerLine - 6)));
            }
            var h = Math.max(36, totalQVisualLines * 24 + 14);
            if (isCallout) h += Math.max(20, Math.round(28 * (pw / 700))); // Espacio extra para cabecera de callout (ícono + título + márgenes escalados)
            return h;
        }
        case "code": {
            if (!str) return 70;
            var cLines = str.split(/\r?\n/).length;
            return Math.max(64, 32 + cLines * 20 + 24);
        }
        case "mermaid": {
            return 260;
        }
        case "table": {
            if (!str) return 90;
            var tRows = str.split(/\r?\n/).length;
            return Math.max(64, tRows * 34 + 20);
        }
        case "image": {
            if (str && _isBadgeLikeText(str)) {
                return 36;
            }
            return 240;
        }
        case "hr": {
            return 24;
        }
        default: {
            var rLines = str ? str.split(/\r?\n/).length : 1;
            return Math.max(28, rLines * 22 + 10);
        }
    }
}

function _isBadgeLikeText(str) {
    if (!str) return false;
    var low = str.toLowerCase();
    return low.indexOf("shields.io") !== -1 ||
           low.indexOf("/badge/") !== -1 ||
           low.indexOf("badge.svg") !== -1 ||
           low.indexOf("-badge.svg") !== -1 ||
           low.indexOf("badgen.net") !== -1 ||
           low.indexOf("codecov.io") !== -1 ||
           low.indexOf("actions/workflows") !== -1;
}

// Detecta si al presionar Enter el cursor está al final de la línea de cierre de un fence (``` o ~~~)
// para salir del bloque hacia un nuevo párrafo normal, limpiando posibles \n sobrantes.
function fenceExit(text, cursor) {
    if (typeof text !== "string") return { exit: false };
    var trimmed = text.replace(/[ \t\r\n]+$/, "");
    var lines = trimmed.split(/\r?\n/);
    if (lines.length < 2) return { exit: false };
    var open = /^[ \t]*(`{3,}|~{3,})/.test(lines[0]);
    var close = /^[ \t]*(`{3,}|~{3,})[ \t]*$/.test(lines[lines.length - 1]);
    return { exit: open && close && cursor >= trimmed.length, raw: trimmed };
}

