.pragma library

// PreviewLogic.js — Lógica pura de extracción de imágenes, filtrado de badges y masonry

var PREVIEW_IMG_MIN_W = 320;
var PREVIEW_IMG_MIN_H = 120;
var PREVIEW_IMG_MAX_ASPECT = 6;
var CARD_MIN_H = 110;
var CARD_MAX_H = 316;

/**
 * Extrae todas las imágenes de una lista de bloques o markdown crudo en orden de aparición.
 * @param {Array|string} blocksOrMd
 * @returns {Array<{ alt: string, url: string, link: string }>}
 */
function extractImages(blocksOrMd) {
    var rawText = "";
    if (typeof blocksOrMd === "string") {
        rawText = blocksOrMd;
    } else if (Array.isArray(blocksOrMd)) {
        for (var i = 0; i < blocksOrMd.length; i++) {
            var b = blocksOrMd[i];
            if (b && b.type === "code") {
                continue;
            }
            if (b && b.raw) {
                rawText += b.raw + "\n";
            }
        }
    }

    var images = [];
    if (!rawText) return images;

    // Ignorar bloques de código cercados (```...```) y fragmentos inline (`...`)
    var cleanText = rawText
        .replace(/```[\s\S]*?```/g, "")
        .replace(/`[^`\n]+`/g, "");

    // Patrón 1: [![alt](img)](link)
    // Patrón 2: ![alt](img)
    var imgRegex = /(?:\[!\[([^\]]*)\]\(([^)]+)\)\]\(([^)]+)\)|!\[([^\]]*)\]\(([^)]+)\))/g;
    var match;
    while ((match = imgRegex.exec(cleanText)) !== null) {
        var alt = match[1] || match[4] || "";
        var url = match[2] || match[5] || "";
        var link = match[3] || "";
        url = url.trim().replace(/^<|>$/g, "").split(/\s+/)[0];
        images.push({
            alt: alt.trim(),
            url: url,
            link: link.trim()
        });
    }

    return images;
}

/**
 * Determina si una imagen es probablemente un badge / escudo / icono de status.
 * @param {string} url
 * @param {string} alt
 * @returns {boolean}
 */
function isBadgeLike(url, alt) {
    if (!url) return true;

    var lowUrl = url.toLowerCase();
    var lowAlt = (alt || "").toLowerCase();

    if (lowAlt.indexOf("badge") !== -1 || lowAlt.indexOf("shield") !== -1 || lowAlt.indexOf("build status") !== -1) {
        return true;
    }

    var badgeDomains = [
        "img.shields.io",
        "badgen.net",
        "shield.deno.dev",
        "codecov.io",
        "travis-ci.org",
        "travis-ci.com",
        "coveralls.io",
        "badge.fury.io",
        "nodei.co",
        "flat.badgen.net"
    ];

    for (var i = 0; i < badgeDomains.length; i++) {
        if (lowUrl.indexOf(badgeDomains[i]) !== -1) {
            return true;
        }
    }

    if (lowUrl.indexOf("/workflows/") !== -1 && lowUrl.indexOf("/badge.svg") !== -1) {
        return true;
    }
    if (lowUrl.indexOf("badge.svg") !== -1 || lowUrl.indexOf("-badge.svg") !== -1) {
        return true;
    }
    if (lowUrl.indexOf("/actions/workflows/") !== -1) {
        return true;
    }
    if (lowUrl.indexOf("/badge/") !== -1) {
        return true;
    }

    return false;
}

/**
 * Obtiene todas las imágenes candidatas válidas (no badge) para la preview de una nota,
 * en orden de aparición en el documento (arriba hacia abajo).
 * @param {Object} noteData
 * @returns {Array<string>}
 */
function getPreviewImages(noteData) {
    if (!noteData) return [];
    var result = [];

    // 1. O(assets) vía assets ya extraídos (si ya se analizó, no tocar body)
    if (Array.isArray(noteData.assets)) {
        for (var i = 0; i < noteData.assets.length; i++) {
            var a = noteData.assets[i];
            if (!isBadgeLike(a, "")) {
                result.push(a);
            }
        }
        return result;
    }

    // 2. Si solo tiene previewImage precalculado
    if (typeof noteData.previewImage === "string" && noteData.previewImage !== "") {
        return [noteData.previewImage];
    }

    // 3. Fallback solo si es un objeto crudo sin parsear: chequeo rápido antes de regex
    if (typeof noteData.body === "string" && (noteData.body.indexOf("![") !== -1 || noteData.body.indexOf("<img") !== -1)) {
        var images = extractImages(noteData.body);
        for (var j = 0; j < images.length; j++) {
            if (!isBadgeLike(images[j].url, images[j].alt)) {
                result.push(images[j].url);
            }
        }
    }

    return result;
}

/**
 * Obtiene la primera imagen candidata válida (no badge) para la preview de una nota.
 * @param {Object} noteData
 * @returns {string} url o ""
 */
function getPreviewImage(noteData) {
    if (!noteData) return "";
    var list = getPreviewImages(noteData);
    return list.length > 0 ? list[0] : "";
}

/**
 * Formatea una fecha a tiempo relativo en español (ej. "hace 2 h", "ayer", "12 sep").
 * Interpreta fechas UTC ISO sin 'Z' añadiendo 'Z' para respetar hora local.
 * @param {string|Date} dateVal
 * @param {number} [nowMs] Para testing determinista
 * @returns {string}
 */
function formatRelative(dateVal, nowMs) {
    if (!dateVal) return "";
    var d = null;
    if (dateVal instanceof Date) {
        d = dateVal;
    } else if (typeof dateVal === "string") {
        var str = dateVal.trim();
        if (!str) return "";
        if (str.indexOf("T") === -1 && str.indexOf(" ") !== -1) {
            str = str.replace(" ", "T");
        }
        if (str.indexOf("Z") === -1 && !/[+-]\d{2}:?\d{2}$/.test(str)) {
            str += "Z";
        }
        d = new Date(str);
    }
    if (!d || isNaN(d.getTime())) {
        return typeof dateVal === "string" ? dateVal : "";
    }

    var now = typeof nowMs === "number" ? nowMs : Date.now();
    var diffMs = now - d.getTime();
    if (diffMs < 0) diffMs = 0;
    var diffSecs = Math.floor(diffMs / 1000);
    var diffMins = Math.floor(diffSecs / 60);
    var diffHours = Math.floor(diffMins / 60);
    var diffDays = Math.floor(diffHours / 24);

    if (diffSecs < 45) return "recién";
    if (diffMins < 60) return "hace " + diffMins + " min";
    if (diffHours < 24) return "hace " + diffHours + " h";
    if (diffDays === 1) return "ayer";
    if (diffDays < 7) return "hace " + diffDays + " d";

    var months = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
    var day = d.getDate();
    var month = months[d.getMonth()];
    var nowYear = new Date(now).getFullYear();
    var noteYear = d.getFullYear();

    if (nowYear === noteYear) {
        return day + " " + month;
    }
    return day + " " + month + " " + noteYear;
}

/**
 * Genera un resumen en texto plano a partir del cuerpo Markdown para tarjetas de vista previa.
 * Elimina fences, encabezados, citas, formatos inline y corta respetando límites de palabras.
 * @param {string} body
 * @param {number} [maxLen]
 * @returns {string}
 */

/**
 * Limpia solo la sintaxis propia de la app que Qt MarkdownText no conoce.
 * El markdown estándar se conserva para que la tarjeta lo renderice.
 * - imágenes ![alt](url) → "" (evita intentos de carga en la preview)
 * - [[destino|alias]] → alias, [[destino]] → destino
 * - ==resaltado== → resaltado
 */
function cleanCardText(md) {
    if (!md || typeof md !== "string") return "";
    return md
        .replace(/^[ \t]*(`{3,}|~{3,})[ \t]*mermaid[\s\S]*?\1[ \t]*$/gmi, "📊 Diagrama")
        .replace(/!\[([^\]]*)\]\((?:[^()\s]+|\([^()\s]*\))(?:\s+"[^"]*")?\)/g, "")
        .replace(/\[\[([^\]|]+)\|([^\]]+)\]\]/g, "$2")
        .replace(/\[\[([^\]]+)\]\]/g, "$1")
        .replace(/(^|[\s(])==([^\s=]|[^\s=][\s\S]*?[^\s=])==(?=[\s),.?!:;]|$)/g, "$1$2");
}

/**
 * Subtítulo limpio para la tarjeta: sin marcas de bloque ni inline,
 * links reducidos a su texto. Una sola línea.
 */
function cleanSubtitle(s) {
    if (!s || typeof s !== "string") return "";
    var t = s;
    t = t.replace(/^[ \t]*(`{3,}|~{3,})[ \t]*mermaid[\s\S]*?\1[ \t]*$/gmi, "📊 Diagrama");
    t = t.replace(/!\[([^\]]*)\]\([^)]+\)/g, "$1");
    t = t.replace(/\[\[([^\]|]+)\|([^\]]+)\]\]/g, "$2");
    t = t.replace(/\[\[([^\]]+)\]\]/g, "$1");
    t = t.replace(/\[([^\]]+)\]\([^)]+\)/g, "$1");
    t = t.replace(/`([^`]+)`/g, "$1");
    t = t.replace(/\*\*([^*]+)\*\*/g, "$1");
    t = t.replace(/__([^_]+)__/g, "$1");
    t = t.replace(/\*([^*]+)\*/g, "$1");
    t = t.replace(/_([^_]+)_/g, "$1");
    t = t.replace(/~~([^~]+)~~/g, "$1");
    t = t.replace(/==([^=]+)==/g, "$1");
    t = t.replace(/<\/?u>/gi, "");
    // Prefijos de bloque: cita, lista/tarea/ordenada y después encabezado
    // (una viñeta puede contener "## ": primero sale la viñeta y después el #)
    t = t.replace(/^[ \t]*>[ \t]?/gm, "");
    t = t.replace(/^[ \t]*(?:[-*+][ \t]+(?:\[[ xX]\][ \t]+)?|\d+[.)][ \t]+)/gm, "");
    t = t.replace(/^[ \t]*#{1,6}[ \t]+/gm, "");
    t = t.replace(/\s+/g, " ").trim();
    return t;
}

/**
 * Si la preview arranca con el mismo bloque del subtítulo (derivado del cuerpo),
 * recorta esa primera línea para no leerla dos veces. Se compara la
 * primera línea limpia contra el subtítulo limpio; con subtítulo de frontmatter
 * no coincide y no toca nada. Devuelve el resto en crudo.
 */
function stripDuplicateLead(preview, subtitle) {
    var p = (preview !== undefined && preview !== null) ? preview : "";
    var s = cleanSubtitle(subtitle || "").trim();
    if (!p || !s) return p;
    var nl = p.indexOf("\n");
    var first = (nl === -1 ? p : p.substring(0, nl)).trim();
    if (cleanSubtitle(first).toLowerCase() === s.toLowerCase()) {
        if (nl === -1) return "";
        return p.substring(nl + 1).replace(/^\s+/, "");
    }
    return p;
}

/**
 * Rectángulo del toast de deshacer (F18): centrado abajo, mismo cálculo que
 * el toast QML (bottomMargin 24, alto 48, ancho min(360, W-32)).
 */
function toastTargetRect(viewW, viewH) {
    var w = Math.max(200, Math.min(360, viewW - 32));
    var h = 48;
    var margin = 24;
    return {
        x: Math.round((viewW - w) / 2),
        y: Math.round(viewH - margin - h),
        w: w,
        h: h
    };
}

/**
 * Parámetros del cierre por borrado (F18): escala uniforme + traslación para
 * llevar el centro del contenedor al centro del toast, sin tocar su geometría
 * bindeada (se anima scale/Translate/opacity, nunca x/y/width/height).
 */
function deleteMorphTarget(viewW, viewH, boxW, boxH) {
    var t = toastTargetRect(viewW, viewH);
    var bw = Math.max(1, boxW);
    var bh = Math.max(1, boxH);
    var scale = Math.min(1, 320 / bw);
    var dx = Math.round((t.x + t.w / 2) - bw / 2);
    var dy = Math.round((t.y + t.h / 2) - bh / 2);
    return { scale: scale, dx: dx, dy: dy };
}
function estimateCardHeight(noteData) {
    if (!noteData) return CARD_MIN_H;

    var baseH = 80;
    if (noteData.subtitle) baseH += 18;
    if (Array.isArray(noteData.tags) && noteData.tags.length > 0) baseH += 22;

    var preview = (typeof noteData.preview === "string" && noteData.preview !== "")
        ? noteData.preview
        : ((typeof noteData.body === "string" && noteData.body !== "") ? noteData.body.substring(0, 500) : "");
    var textH = 0;
    if (preview.length > 0) {
        var nlCount = (preview.match(/\n/g) || []).length;
        var lines = Math.max(nlCount + 1, Math.ceil(preview.length / 38));
        lines = Math.max(1, Math.min(lines, 7));
        textH = lines * 18 + 8;
    }

    var showImg = (typeof NotesConfig !== "undefined" && NotesConfig.showImagePreviews !== undefined)
        ? NotesConfig.showImagePreviews : true;
    var hasImg = showImg && !!getPreviewImage(noteData);
    var imgH = hasImg ? 120 : 0;

    var total = baseH + textH + imgH;
    return Math.max(CARD_MIN_H, Math.min(CARD_MAX_H, total));
}

/**
 * Distribuye una lista de notas en N columnas para masonry.
 * @param {Array} notes
 * @param {number} numCols
 * @returns {Array<Array>} columnas con notas
 */
function distributeToColumns(notes, numCols) {    var cols = Math.max(1, numCols || 2);
    var result = [];
    var heights = [];
    for (var i = 0; i < cols; i++) {
        result.push([]);
        heights.push(0);
    }

    if (!Array.isArray(notes)) return result;

    for (var n = 0; n < notes.length; n++) {
        var note = notes[n];
        var minCol = 0;
        var minH = heights[0];
        for (var c = 1; c < cols; c++) {
            if (heights[c] < minH) {
                minH = heights[c];
                minCol = c;
            }
        }

        result[minCol].push(note);
        var cardH = estimateCardHeight(note);
        heights[minCol] += cardH + 14;
    }

    return result;
}

/**
 * F26 (FLIP): calcula qué tarjetas se movieron entre dos fotos de posiciones.
 * oldMap/newMap: { key: {x, y} } en un sistema común (p.ej. contenido del scroll).
 * Devuelve { moved: [{key, dx, dy}], entered: [keys], removed: [keys] }.
 * - moved: presente en ambos con delta != 0 (dx = newX - oldX, dy = newY - oldY).
 * - entered: solo en newMap (fundido de entrada, sin slide).
 * - removed: solo en oldMap (ya no están; la grilla las destruyó).
 * Sin cambios → moved/entered/removed vacíos.
 */
function computeSlideDeltas(oldMap, newMap) {
    var moved = [];
    var entered = [];
    var removed = [];
    var o = oldMap || {};
    var n = newMap || {};
    for (var k in n) {
        if (o[k] === undefined || o[k] === null) {
            entered.push(k);
        } else {
            var dx = (n[k].x || 0) - (o[k].x || 0);
            var dy = (n[k].y || 0) - (o[k].y || 0);
            if (dx !== 0 || dy !== 0) {
                moved.push({ key: k, dx: dx, dy: dy });
            }
        }
    }
    for (var j in o) {
        if (n[j] === undefined || n[j] === null) {
            removed.push(j);
        }
    }
    return { moved: moved, entered: entered, removed: removed };
}
