// MarkdownParser.js — Parser y serializador de notas Markdown con YAML frontmatter
.pragma library

function _parseTags(entry) {
    var tags = [];
    var v = entry.inlineValue ? entry.inlineValue.trim() : "";
    if (v) {
        if (v.startsWith("[") && v.endsWith("]")) {
            var inner = v.substring(1, v.length - 1).trim();
            if (inner.length > 0) {
                var parts = inner.split(",");
                for (var p = 0; p < parts.length; p++) {
                    var item = parts[p].trim();
                    if ((item.startsWith('"') && item.endsWith('"')) || (item.startsWith("'") && item.endsWith("'"))) {
                        item = item.substring(1, item.length - 1);
                    }
                    if (item) tags.push(item);
                }
            }
            return tags;
        } else if (v.length > 0) {
            var item = v;
            if ((item.startsWith('"') && item.endsWith('"')) || (item.startsWith("'") && item.endsWith("'"))) {
                item = item.substring(1, item.length - 1);
            }
            if (item) tags.push(item);
        }
    }
    for (var i = 1; i < entry.rawLines.length; i++) {
        var line = entry.rawLines[i].trim();
        var m = line.match(/^-\s+(.*)$/);
        if (m) {
            var val = m[1].trim();
            if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
                val = val.substring(1, val.length - 1);
            }
            if (val) tags.push(val);
        }
    }
    return tags;
}

function _parseScalar(rawVal) {
    if (!rawVal) return "";
    var v = rawVal.trim();
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
        v = v.substring(1, v.length - 1).replace(/\\"/g, '"');
    }
    return v;
}

function _arraysEqual(a, b) {
    if (!Array.isArray(a) || !Array.isArray(b)) return false;
    if (a.length !== b.length) return false;
    for (var i = 0; i < a.length; i++) {
        if (a[i] !== b[i]) return false;
    }
    return true;
}

function _parseFrontmatterEntries(fmText) {
    var rawLines = fmText.split(/\r?\n/);
    var entries = [];
    var currentEntry = null;

    for (var i = 0; i < rawLines.length; i++) {
        var rawLine = rawLines[i];

        if (currentEntry && (rawLine.startsWith(" ") || rawLine.startsWith("\t"))) {
            currentEntry.rawLines.push(rawLine);
            continue;
        }

        var keyMatch = rawLine.match(/^([A-Za-z0-9_-]+)\s*:(.*)$/);
        if (keyMatch) {
            var k = keyMatch[1].trim();
            var v = keyMatch[2].trim();
            currentEntry = {
                type: "key",
                key: k.toLowerCase(),
                rawKey: k,
                rawLines: [rawLine],
                inlineValue: v
            };
            entries.push(currentEntry);
        } else {
            currentEntry = {
                type: "other",
                rawLines: [rawLine]
            };
            entries.push(currentEntry);
        }
    }
    return entries;
}

/**
 * Extrae de forma segura el bloque frontmatter reconociendo pares clave: valor y entradas YAML.
 */
function _extractFrontmatter(text) {
    if (!text || typeof text !== "string") return null;
    var fmMatch = text.match(/^---\s*\r?\n([\s\S]*?)\r?\n---\s*(\r?\n|$)/);
    if (!fmMatch) return null;

    var fmText = fmMatch[1];
    var entries = _parseFrontmatterEntries(fmText);
    if (entries.length === 0) return null;

    var keyCount = 0;
    var validMeta = {};
    for (var i = 0; i < entries.length; i++) {
        var e = entries[i];
        if (e.type === "key") {
            keyCount++;
            if (e.key === "tags") {
                validMeta.tags = _parseTags(e);
            } else if (e.key === "pinned") {
                var pv = _parseScalar(e.inlineValue);
                validMeta.pinned = (pv.toLowerCase() === "true" || pv === "1" || pv.toLowerCase() === "yes");
            } else {
                validMeta[e.key] = _parseScalar(e.inlineValue);
            }
        }
    }
    if (keyCount === 0) return null;

    return {
        matchedLength: fmMatch[0].length,
        meta: validMeta,
        entries: entries,
        rawFmText: fmText
    };
}

/**
 * Sanitiza documentos de texto generados por Qt RichText para extraer texto plano o cadena vacía.
 */
function sanitizeQtHtml(str) {
    if (!str || typeof str !== "string") return "";
    if (str.indexOf("<!DOCTYPE HTML") !== -1 || str.indexOf("<meta name=\"qrichtext\"") !== -1) {
        if (str.indexOf("-qt-paragraph-type:empty") !== -1 && str.replace(/<[^>]+>/g, "").trim() === "") {
            return "";
        }
        return str.replace(/<style[\s\S]*?<\/style>/gi, "")
                  .replace(/<head[\s\S]*?<\/head>/gi, "")
                  .replace(/<p[^>]*>/gi, "")
                  .replace(/<\/p>/gi, "\n")
                  .replace(/<br\s*\/?>/gi, "\n")
                  .replace(/<[^>]+>/g, "")
                  .replace(/&amp;/g, "&")
                  .replace(/&lt;/g, "<")
                  .replace(/&gt;/g, ">")
                  .replace(/&quot;/g, '"')
                  .replace(/&#39;/g, "'")
                  .trim();
    }
    return str;
}

/**
 * Deriva título y subtítulo a partir del cuerpo Markdown y un nombre base de archivo.
 * Salta fences (``` o ~~~). El título solo se toma si la primera línea no vacía
 * fuera de un fence es un encabezado '# '.
 */
function _deriveTitle(body, baseName) {
    baseName = baseName || "";
    var lines = (body || "").split(/\r?\n/);
    var firstNonEmpty = null;
    var secondNonEmpty = null;
    var inFence = false;
    var fenceChar = "";
    var fenceLen = 0;

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var trimmed = line.trim();
        if (trimmed === "") continue;

        var fenceMatch = trimmed.match(/^(`{3,}|~{3,})/);
        if (fenceMatch) {
            var marker = fenceMatch[1];
            if (!inFence) {
                inFence = true;
                fenceChar = marker[0];
                fenceLen = marker.length;
                if (firstNonEmpty === null) {
                    firstNonEmpty = { isFence: true, text: trimmed };
                }
                continue;
            } else {
                if (marker[0] === fenceChar && marker.length >= fenceLen) {
                    inFence = false;
                    continue;
                }
            }
        }

        if (inFence) continue;

        if (firstNonEmpty === null) {
            firstNonEmpty = { isFence: false, text: trimmed };
        } else if (secondNonEmpty === null) {
            secondNonEmpty = { isFence: false, text: trimmed };
            break;
        }
    }

    var title = baseName;
    var subtitle = "";

    if (firstNonEmpty && !firstNonEmpty.isFence) {
        var t = firstNonEmpty.text;
        if (t.startsWith("# ")) {
            title = t.substring(2).trim();
            if (secondNonEmpty && !secondNonEmpty.isFence) {
                var s = secondNonEmpty.text;
                if (!s.startsWith("#")) {
                    subtitle = s.trim();
                } else if (s.startsWith("## ")) {
                    subtitle = s.substring(3).trim();
                }
            }
        }
    }

    return { title: title, subtitle: subtitle };
}

/**
 * Parsea el contenido crudo de una nota Markdown y extrae metadatos y cuerpo.
 * En .txt (format "txt") NO hay frontmatter ni metadatos: el contenido es literal.
 */
function parseNote(fileName, filePath, fileIsDir, rawContent) {
    fileName = fileName || "";
    filePath = filePath || "";
    var isTxt = /\.txt$/i.test(fileName);
    var format = isTxt ? "txt" : "md";
    var meta = {
        title: "",
        subtitle: "",
        created: "",
        modified: "",
        type: "text",
        pinned: false,
        tags: []
    };

    var content = rawContent || "";
    var body = content;

    // 1. Extraer YAML Frontmatter delimitado por '---' (máximo un bloque, al inicio).
    // En .txt NO se interpreta: un "---" inicial es texto literal.
    var hadFm = false;
    var fm = isTxt ? null : _extractFrontmatter(content);
    if (fm) {
        hadFm = true;
        body = content.substring(fm.matchedLength);
        if (fm.meta.title !== undefined) meta.title = fm.meta.title;
        if (fm.meta.subtitle !== undefined) meta.subtitle = fm.meta.subtitle;
        if (fm.meta.created !== undefined) meta.created = fm.meta.created;
        if (fm.meta.modified !== undefined) meta.modified = fm.meta.modified;
        if (fm.meta.type !== undefined) meta.type = fm.meta.type.toLowerCase();
        if (fm.meta.pinned !== undefined) meta.pinned = (fm.meta.pinned === true);
        if (fm.meta.tags !== undefined) meta.tags = fm.meta.tags;
    }

    body = sanitizeQtHtml(body);

    var rawName = fileName.replace(/\.(md|txt)$/i, "");
    var baseName = rawName.indexOf("/") !== -1 ? rawName.substring(rawName.lastIndexOf("/") + 1) : rawName;
    var slug = rawName.toLowerCase();

    if (!meta.title || meta.title === "") {
        var derived = _deriveTitle(body, baseName);
        meta.title = derived.title;
        if (!meta.subtitle && derived.subtitle) {
            meta.subtitle = derived.subtitle;
        }
    }
    if (!meta.title || meta.title === "") {
        meta.title = baseName;
    }

    // 2. Extraer assets e imágenes referenciadas en el Markdown
    var assets = [];
    var imgRegex = /!\[.*?\]\((.*?)\)/g;
    var match;
    while ((match = imgRegex.exec(body)) !== null) {
        if (match[1] && match[1].trim().length > 0) {
            assets.push(match[1].trim());
        }
    }

    var baseFolder = "";
    if (filePath) {
        var isActualFile = /\.(md|txt)$/i.test(filePath || "");
        if (fileIsDir && !isActualFile) {
            baseFolder = filePath;
        } else {
            var lastSlash = filePath.lastIndexOf("/");
            baseFolder = (lastSlash !== -1) ? filePath.substring(0, lastSlash) : "";
        }
    }

    // Previsualización limpia para la tarjeta (sin etiquetas de imagen para evitar advertencias de carga)
    // Acotamos a los primeros 2000 caracteres para no correr regex pesados sobre archivos enormes
    var bodySlice = (body.length > 2000) ? body.substring(0, 2000) : body;
    var cleanBodyForPreview = bodySlice.replace(/!\[.*?\]\(.*?\)/g, "").trim();
    var firstH1Match = cleanBodyForPreview.match(/^#+\s*(.+)\r?\n+/);
    if (firstH1Match) {
        var h1Text = firstH1Match[1].trim().toLowerCase();
        var titleText = (meta.title || "").trim().toLowerCase();
        if (titleText && (h1Text === titleText || h1Text.indexOf(titleText) === 0 || titleText.indexOf(h1Text) === 0)) {
            cleanBodyForPreview = cleanBodyForPreview.substring(firstH1Match[0].length).trim();
        }
    }
    var cleanPreview = cleanBodyForPreview;
    if (cleanPreview.length > 500) {
        var cut = cleanPreview.substring(0, 500);
        var lastNl = cut.lastIndexOf("\n");
        cleanPreview = (lastNl > 180) ? cut.substring(0, lastNl).trim() : cut.trim();
    }
    if ((cleanPreview.match(/```/g) || []).length % 2 === 1) {
        cleanPreview += "\n```";
    }
    var tagsStr = (meta.tags && Array.isArray(meta.tags)) ? meta.tags.join(" ") : "";
    var searchBlob = normalizeSearchText((meta.title || "") + " " + (meta.subtitle || "") + " " + tagsStr + " " + body);

    var firstPreviewImg = "";
    if (assets.length > 0) {
        for (var aIdx = 0; aIdx < assets.length; aIdx++) {
            var cand = assets[aIdx];
            var candLow = (typeof cand === "string") ? cand.toLowerCase() : "";
            if (candLow.indexOf("shields.io") === -1 && candLow.indexOf("/badge/") === -1 && candLow.indexOf("/actions/workflows/") === -1) {
                firstPreviewImg = cand;
                break;
            }
        }
    }

    return {
        id: slug,
        slug: slug,
        format: format, // "md" | "txt" (F6: el editor no interpreta Markdown en txt)
        fileName: fileName,
        filePath: filePath,
        baseFolder: baseFolder,
        isFolderNote: fileIsDir,
        title: meta.title,
        subtitle: meta.subtitle,
        created: meta.created,
        modified: meta.modified,
        type: meta.type || "text",
        pinned: meta.pinned === true,
        tags: meta.tags || [],
        _frontmatterEntries: fm ? fm.entries : null,
        content: content,
        body: body,
        preview: cleanPreview,
        previewImage: firstPreviewImg,
        searchBlob: searchBlob,
        hasImages: assets.length > 0,
        assets: assets
    };
}

/**
 * Serializa metadatos y cuerpo en un documento Markdown con frontmatter estructurado.
 * En .txt (meta.format === "txt" o fileName .txt) devuelve el cuerpo tal cual,
 * sin inyectar frontmatter ni reescribir nada.
 */
function serializeNote(meta, body) {
    meta = meta || {};
    var cleanBody = (body !== undefined && body !== null ? body : "");
    cleanBody = sanitizeQtHtml(cleanBody);
    cleanBody = cleanBody.replace(/[\u200B\uFEFF]/g, "");

    var fn0 = meta.fileName || meta.filePath || "";
    if (meta.format === "txt" || (/\.txt$/i.test(fn0))) {
        return cleanBody;
    }

    var fmCheck = _extractFrontmatter(cleanBody);
    var existingEntries = null;
    if (fmCheck) {
        cleanBody = cleanBody.substring(fmCheck.matchedLength);
        existingEntries = fmCheck.entries;
    }
    cleanBody = cleanBody.replace(/^\r?\n+/, "");

    var entries = meta._frontmatterEntries || existingEntries;
    var fmLines = [];

    var fn = meta.fileName || meta.filePath || meta.slug || meta.id || "";
    var rawFn = fn.replace(/\.(md|txt)$/i, "");
    var baseFn = rawFn.indexOf("/") !== -1 ? rawFn.substring(rawFn.lastIndexOf("/") + 1) : rawFn;
    var derived = _deriveTitle(cleanBody, baseFn);

    if (entries && entries.length > 0) {
        var handledKeys = {};
        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i];
            if (entry.type === "other") {
                for (var r = 0; r < entry.rawLines.length; r++) {
                    fmLines.push(entry.rawLines[r]);
                }
                continue;
            }

            var k = entry.key;
            handledKeys[k] = true;

            if (k === "pinned") {
                if (meta.pinned === true) {
                    fmLines.push("pinned: true");
                }
            } else if (k === "tags") {
                if (meta.tags && Array.isArray(meta.tags) && meta.tags.length > 0) {
                    var origTags = _parseTags(entry);
                    if (_arraysEqual(origTags, meta.tags)) {
                        for (var rt = 0; rt < entry.rawLines.length; rt++) {
                            fmLines.push(entry.rawLines[rt]);
                        }
                    } else {
                        fmLines.push("tags: [" + meta.tags.map(function(t) { return '"' + t + '"'; }).join(", ") + "]");
                    }
                }
            } else if (k === "title") {
                if (meta.title !== undefined && meta.title !== "") {
                    var origTitle = _parseScalar(entry.inlineValue);
                    if (origTitle === meta.title) {
                        for (var rti = 0; rti < entry.rawLines.length; rti++) {
                            fmLines.push(entry.rawLines[rti]);
                        }
                    } else {
                        fmLines.push(entry.rawKey + ': "' + meta.title.replace(/"/g, '\\"') + '"');
                    }
                }
            } else if (k === "subtitle") {
                if (meta.subtitle !== undefined && meta.subtitle !== "") {
                    var origSub = _parseScalar(entry.inlineValue);
                    if (origSub === meta.subtitle) {
                        for (var rs = 0; rs < entry.rawLines.length; rs++) {
                            fmLines.push(entry.rawLines[rs]);
                        }
                    } else {
                        fmLines.push(entry.rawKey + ': "' + meta.subtitle.replace(/"/g, '\\"') + '"');
                    }
                }
            } else if (k === "created") {
                if (meta.created !== undefined && meta.created !== "") {
                    var origCreated = _parseScalar(entry.inlineValue);
                    if (origCreated === meta.created) {
                        for (var rc = 0; rc < entry.rawLines.length; rc++) {
                            fmLines.push(entry.rawLines[rc]);
                        }
                    } else {
                        fmLines.push(entry.rawKey + ': "' + meta.created.replace(/"/g, '\\"') + '"');
                    }
                }
            } else if (k === "modified") {
                if (meta.modified !== undefined && meta.modified !== "") {
                    var origMod = _parseScalar(entry.inlineValue);
                    if (origMod === meta.modified) {
                        for (var rm = 0; rm < entry.rawLines.length; rm++) {
                            fmLines.push(entry.rawLines[rm]);
                        }
                    } else {
                        fmLines.push(entry.rawKey + ': "' + meta.modified.replace(/"/g, '\\"') + '"');
                    }
                }
            } else if (k === "type") {
                if (meta.type !== undefined && meta.type !== "") {
                    var origType = _parseScalar(entry.inlineValue);
                    if (origType.toLowerCase() === meta.type.toLowerCase()) {
                        for (var rty = 0; rty < entry.rawLines.length; rty++) {
                            fmLines.push(entry.rawLines[rty]);
                        }
                    } else {
                        fmLines.push(entry.rawKey + ': "' + meta.type + '"');
                    }
                }
            } else {
                // Unknown or other key: preserve exactly
                for (var ro = 0; ro < entry.rawLines.length; ro++) {
                    fmLines.push(entry.rawLines[ro]);
                }
            }
        }

        if (meta.title && typeof meta.title === "string" && meta.title.trim().length > 0 && !handledKeys["title"] && meta.title !== derived.title) {
            fmLines.push('title: "' + meta.title.trim().replace(/"/g, '\\"') + '"');
        }
        if (meta.pinned === true && !handledKeys["pinned"]) {
            fmLines.push("pinned: true");
        }
        if (meta.tags && Array.isArray(meta.tags) && meta.tags.length > 0 && !handledKeys["tags"]) {
            fmLines.push("tags: [" + meta.tags.map(function(t) { return '"' + t + '"'; }).join(", ") + "]");
        }
    } else {
        var allowAutoFm = (!meta.isExternal || meta.hadFrontmatter === true);
        if (allowAutoFm && meta.title && typeof meta.title === "string" && meta.title.trim().length > 0 && meta.title !== derived.title) {
            fmLines.push('title: "' + meta.title.trim().replace(/"/g, '\\"') + '"');
        }
        if (allowAutoFm && meta.pinned === true) {
            fmLines.push("pinned: true");
        }
        if (meta.tags && Array.isArray(meta.tags) && meta.tags.length > 0) {
            fmLines.push("tags: [" + meta.tags.map(function(t) { return '"' + t + '"'; }).join(", ") + "]");
        }
        if (allowAutoFm && meta.created && typeof meta.created === "string" && meta.created.trim().length > 0) {
            fmLines.push('created: "' + meta.created.trim().replace(/"/g, '\\"') + '"');
        }
    }

    if (fmLines.length === 0) {
        return cleanBody.endsWith("\n") ? cleanBody : cleanBody + "\n";
    }

    var lines = [
        "---",
        fmLines.join("\n"),
        "---",
        cleanBody
    ];

    var out = lines.join("\n");
    return out.endsWith("\n") ? out : out + "\n";
}

/**
 * Sanitiza un título a slug para nombre de archivo en Linux.
 */
function slugify(text) {
    function _pad2(n) { return n < 10 ? "0" + n : "" + n; }
    function _genFallback() {
        var now = new Date();
        return "nota_" + now.getFullYear() + _pad2(now.getMonth() + 1) + _pad2(now.getDate()) + "_" +
               _pad2(now.getHours()) + _pad2(now.getMinutes()) + _pad2(now.getSeconds());
    }

    if (!text || typeof text !== "string") return _genFallback();
    var s = text.trim();
    if (typeof s.normalize === "function") {
        s = s.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    }
    s = s.toLowerCase();
    // Reemplazar caracteres prohibidos del sistema de archivos por espacio
    s = s.replace(/[\/\\:*?"<>|\x00-\x1f\x7f¿¡]/g, " ");
    s = s.replace(/[\s\-_]+/g, "_");
    s = s.replace(/^_+|_+$/g, "");
    s = s.substring(0, 80);
    if (!s || s.length === 0) {
        return _genFallback();
    }
    return s;
}

/**
 * Extrae de forma segura el cuerpo limpio sin ningún frontmatter YAML.
 */
function getCleanBody(note) {
    if (!note) return "";
    var body = (note.body !== undefined && note.body !== null) ? note.body : (note.content || "");
    var fm = _extractFrontmatter(body);
    if (fm) {
        body = body.substring(fm.matchedLength);
    }
    return sanitizeQtHtml(body);
}

/**
 * Genera una previsualización limpia de texto plano lista para renderizar en NoteCard.
 */
function getCleanPreview(rawContent) {
    if (!rawContent || typeof rawContent !== "string") return "";
    var body = rawContent;
    var fm = _extractFrontmatter(body);
    if (fm) {
        body = body.substring(fm.matchedLength);
    }
    return body.replace(/!\[.*?\]\(.*?\)/g, "").substring(0, 350).trim();
}

/**
 * Normaliza texto para búsqueda: minúsculas, sin diacríticos (NFD) ni espacios sobrantes.
 */
function normalizeSearchText(text) {
    if (!text || typeof text !== "string") return "";
    var s = text.trim();
    if (typeof s.normalize === "function") {
        s = s.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    }
    return s.toLowerCase();
}

