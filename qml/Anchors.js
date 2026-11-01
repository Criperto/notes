.pragma library

// Anchors.js — Índice y resolución de anclas internas y slugs de encabezados

function githubSlug(text) {
    if (!text || typeof text !== "string") return "";
    var s = text.trim().toLowerCase();
    // Quitar sintaxis de formato markdown básica
    s = s.replace(/[*_~`]/g, "");
    // Quitar caracteres de puntuación especiales pero mantener letras, números, espacios y guiones
    s = s.replace(/[^\p{L}\p{N}\s-]/gu, "");
    // Espacios a guiones
    s = s.replace(/\s+/g, "-");
    // Colapsar guiones múltiples
    s = s.replace(/-+/g, "-");
    // Quitar guiones iniciales o finales
    s = s.replace(/^-+|-+$/g, "");
    return s;
}

function buildAnchorIndex(blocks) {
    var index = {};
    var counts = {};
    if (!blocks || !Array.isArray(blocks)) return index;

    for (var i = 0; i < blocks.length; i++) {
        var b = blocks[i];
        if (!b || !b.raw) continue;

        // 1. Encabezados
        if (b.type === "heading") {
            var m = b.raw.match(/^[ \t]*#{1,6}[ \t]+(.*?)(?:[ \t]+#+)?$/);
            var titleText = m ? m[1] : b.raw;
            // Verificar si tiene id explícito {#mi-id}
            var customMatch = titleText.match(/\{#([a-zA-Z0-9_-]+)\}/);
            if (customMatch) {
                var cId = customMatch[1].toLowerCase();
                index[cId] = { bid: b.bid, blockIndex: i, type: "heading_custom" };
                titleText = titleText.replace(/\{#([a-zA-Z0-9_-]+)\}/, "").trim();
            }

            var baseSlug = githubSlug(titleText);
            if (baseSlug) {
                var finalSlug = baseSlug;
                if (counts[baseSlug] !== undefined) {
                    counts[baseSlug]++;
                    finalSlug = baseSlug + "-" + counts[baseSlug];
                } else {
                    counts[baseSlug] = 0;
                }
                index[finalSlug] = { bid: b.bid, blockIndex: i, type: "heading" };
            }
        }

        // 2. Anclas explícitas HTML: <a id="x"></a> o <a name="x"></a>
        var anchorRegex = /<a\s+(?:id|name)=["']([^"']+)["']/gi;
        var aMatch;
        while ((aMatch = anchorRegex.exec(b.raw)) !== null) {
            var aid = aMatch[1].toLowerCase();
            index[aid] = { bid: b.bid, blockIndex: i, type: "html_anchor" };
        }
    }

    return index;
}

function parseInternalLink(link, currentSlug) {
    if (!link || typeof link !== "string") return null;

    var target = link.trim();
    // Soporte para wikilinks: [[nota]] o [[nota|alias]]
    if (target.startsWith("[[") && target.endsWith("]]")) {
        target = target.substring(2, target.length - 2).trim();
        var pipeIdx = target.indexOf("|");
        if (pipeIdx !== -1) {
            target = target.substring(0, pipeIdx).trim();
        }
    }

    // Extraer ancla si existe: ruta#ancla
    var anchor = "";
    var hashIdx = target.indexOf("#");
    if (hashIdx !== -1) {
        anchor = target.substring(hashIdx + 1).trim();
        target = target.substring(0, hashIdx).trim();
    }

    if (!target && anchor) {
        return { isSameNote: true, anchor: anchor };
    }

    if (target.endsWith(".md")) {
        target = target.substring(0, target.length - 3);
    }

    // Resolver ruta relativa contra la carpeta de la nota actual
    var resolvedSlug = target;
    if (currentSlug && (target.startsWith("./") || target.startsWith("../") || target.indexOf("/") !== -1)) {
        var baseParts = currentSlug.split("/");
        baseParts.pop();
        var relParts = target.split("/");
        for (var p = 0; p < relParts.length; p++) {
            var part = relParts[p];
            if (part === "" || part === ".") continue;
            if (part === "..") {
                if (baseParts.length > 0) baseParts.pop();
            } else {
                baseParts.push(part);
            }
        }
        resolvedSlug = baseParts.join("/");
    } else {
        resolvedSlug = resolvedSlug.replace(/^\.\//, "");
    }

    resolvedSlug = resolvedSlug.toLowerCase();
    var isSame = currentSlug && (resolvedSlug === currentSlug.toLowerCase());

    return {
        isSameNote: isSame,
        slug: resolvedSlug,
        anchor: anchor
    };
}
