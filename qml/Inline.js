.pragma library

// Color por defecto del resaltado (==texto==); lo fija EditorMetrics desde Theme.color3.
var _defaultHighlightBg = "rgba(240, 198, 116, 0.35)";
function setHighlightBg(c) { if (typeof c === "string" && c !== "" && _defaultHighlightBg !== c) _defaultHighlightBg = c; }

// Inline.js — Formateo y renderizado inline enriquecido para bloques Markdown
// Soporta: negrita, cursiva, subrayado, tachado, resaltado, código inline, enlaces, escapes.

function escapeHtml(text) {
    if (!text || typeof text !== "string") return "";
    return text
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
}

// Helper para oscurecer colores CSS (hex #rrggbb o rgb/rgba) para sombras 3D vectoriales
function _darkenColor(colorStr, factor) {
    if (!colorStr || typeof colorStr !== "string") return "#555555";
    var c = colorStr.trim();
    var f = (typeof factor === "number" && factor > 0) ? factor : 1.4;
    if (c[0] === "#") {
        var hex = c.substring(1);
        if (hex.length === 3) {
            hex = hex[0] + hex[0] + hex[1] + hex[1] + hex[2] + hex[2];
        }
        if (hex.length >= 6) {
            var r = Math.max(0, Math.min(255, Math.round(parseInt(hex.substring(0, 2), 16) / f)));
            var g = Math.max(0, Math.min(255, Math.round(parseInt(hex.substring(2, 4), 16) / f)));
            var b = Math.max(0, Math.min(255, Math.round(parseInt(hex.substring(4, 6), 16) / f)));
            return "rgb(" + r + "," + g + "," + b + ")";
        }
    }
    var m = c.match(/rgba?\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/i);
    if (m) {
        var r = Math.max(0, Math.min(255, Math.round(parseInt(m[1], 10) / f)));
        var g = Math.max(0, Math.min(255, Math.round(parseInt(m[2], 10) / f)));
        var b = Math.max(0, Math.min(255, Math.round(parseInt(m[3], 10) / f)));
        return "rgb(" + r + "," + g + "," + b + ")";
    }
    return colorStr;
}

// Genera un SVG data URI con diseño 3D realista multicapa de tecla de teclado (keycap),
// inspirado en keycap_base.svg y keycap_body.svg de shortcuts_viewer, adaptado dinámicamente al color de acento del tema.
function renderKeycapSvg(label, opts) {
    var rawText = (label !== undefined && label !== null) ? String(label).trim() : "";
    var options = opts || {};
    var isLight = Boolean(options.lightMode);

    // Normalizar texto a mayúsculas estilo shortcuts_viewer para modificadores y letras
    var disp = rawText;
    var lower = rawText.toLowerCase();
    if (lower === "ctrl" || lower === "shift" || lower === "alt" || lower === "esc" ||
        lower === "enter" || lower === "space" || lower === "tab" || lower === "del" ||
        lower === "backspace" || lower === "home" || lower === "end" || lower === "super" || lower === "win") {
        disp = (lower === "super" || lower === "win") ? "SUPER" : lower.toUpperCase();
    } else if (rawText.length === 1 && /[a-z]/i.test(rawText)) {
        disp = rawText.toUpperCase();
    }

    var charW = 7.5;
    var contentW = Math.max(10, disp.length * charW);
    var w = Math.max(32, Math.round(contentW + 18));
    var h = 28;

    // Colores dinámicos del tema: el bisel exterior se tiñe del color de acento del tema (Theme.accent)
    var defaultAccent = options.accent || options.linkColor || "#e56018";
    var bezelColor = options.kbdBezel || (isLight ? "#dcdcdc" : defaultAccent);
    var shadowColor1 = options.kbdShadow1 || options.kbdShadow || _darkenColor(bezelColor, 1.55);
    var shadowColor2 = options.kbdShadow2 || _darkenColor(bezelColor, 1.25);
    var plateColor = options.kbdPlate || (isLight ? "#ffffff" : "#1c1815");
    var textColor = options.kbdText || (isLight ? "#1c1c1c" : (options.kbdColor || "#ffffff"));
    var fontFamily = options.fontFamilyMonospace || options.fontFamily || "monospace";

    var safeText = disp
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");

    var bodyH = 23;
    var shadowY = 4.5;
    var plateX = 4.0;
    var plateY = 3.5;
    var plateH = 16.0;
    var rx = 5.5;
    var plateRx = 2.8;
    var textY = 11.5;

    var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="' + w + '" height="' + h + '" viewBox="0 0 ' + w + ' ' + h + '">' +
        '<!-- Capa 3D inferior / Profundidad (keycap_base.svg) -->' +
        '<rect x="1" y="' + shadowY + '" width="' + (w - 2) + '" height="' + bodyH + '" rx="' + rx + '" fill="' + shadowColor1 + '"/>' +
        '<!-- Capa 3D intermedia / Bisel -->' +
        '<rect x="1" y="' + (shadowY - 1.5) + '" width="' + (w - 2) + '" height="' + bodyH + '" rx="' + rx + '" fill="' + shadowColor2 + '"/>' +
        '<!-- Capa superior / Bisel del cuerpo (keycap_body.svg) -->' +
        '<rect x="1" y="1" width="' + (w - 2) + '" height="' + bodyH + '" rx="' + rx + '" fill="' + bezelColor + '"/>' +
        '<!-- Placa central interna recesada (Theme.surface) -->' +
        '<rect x="' + plateX + '" y="' + plateY + '" width="' + (w - plateX * 2) + '" height="' + plateH + '" rx="' + plateRx + '" fill="' + plateColor + '"/>' +
        '<!-- Leyenda centrada en la placa interna -->' +
        '<text x="' + (w / 2.0) + '" y="' + textY + '" fill="' + textColor + '" font-family="' + fontFamily + '" font-size="10.5" font-weight="bold" text-anchor="middle" dominant-baseline="central">' + safeText + '</text>' +
        '</svg>';

    return "data:image/svg+xml;utf8," + encodeURIComponent(svg);
}

// Convierte texto markdown inline a HTML seguro para componentes Text de Qt
function inlineToHtml(src, opts) {
    if (!src || typeof src !== "string") return "";
    var options = opts || {};
    var linkColor = options.linkColor || "#5294e2";
    var codeBg = options.codeBg || "rgba(255, 255, 255, 0.08)";
    var codeColor = options.codeColor || "#f0f0f0";
    var kbdBg = options.kbdBg || "rgba(255, 255, 255, 0.10)";
    var kbdColor = options.kbdColor || options.codeColor || "#f0f0f0";
    var kbdBorder = options.kbdBorder || "rgba(255, 255, 255, 0.22)";
    var highlightBg = options.highlightBg || _defaultHighlightBg;

    var text = src;

    // Prefijo de encabezado (p.ej. "## título" dentro de un ítem de lista), solo si se pasa headingSizes
    var headingSize = 0;
    if (options.headingSizes) {
        var hm = text.match(/^(#{1,6})[ \t]+([\s\S]*)$/);
        if (hm && options.headingSizes[hm[1].length]) {
            headingSize = options.headingSizes[hm[1].length];
            text = hm[2];
        }
    }

    // 1. Escapar caracteres con barra invertida
    var escapes = [];
    text = text.replace(/\\([*_[\]~=\\`#\-!().|{}+>])/g, function(match, char) {
        var token = "\uE000ESC_" + escapes.length + "\uE000";
        escapes.push(char);
        return token;
    });

    // 2. Extraer código inline (`code`) antes de procesar cualquier formato
    var codeSpans = [];
    text = text.replace(/`([^`\r\n]+)`/g, function(match, codeContent) {
        var token = "\uE000CODE_" + codeSpans.length + "\uE000";
        var safeCode = escapeHtml(codeContent);
        var html = '<span style="font-family: monospace; background-color: ' + codeBg + '; color: ' + codeColor + '; padding: 1px 4px; border-radius: 4px;">' + safeCode + '</span>';
        codeSpans.push(html);
        return token;
    });

    // 2b. Extraer etiquetas <kbd>...</kbd> antes de escapar HTML
    var kbds = [];
    text = text.replace(/<kbd>([\s\S]*?)<\/kbd>|&lt;kbd&gt;([\s\S]*?)&lt;\/kbd&gt;/gi, function(match, c1, c2) {
        var token = "\uE000KBD_" + kbds.length + "\uE000";
        var kbdContent = (c1 !== undefined) ? c1 : c2;
        var cleanContent = kbdContent.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">");
        var svgUri = renderKeycapSvg(cleanContent, options);
        var html = '<img src="' + svgUri + '" align="middle"/>';
        kbds.push(html);
        return token;
    });

    // 3. Extraer imágenes markdown antes que enlaces: ![alt](url)
    // Con imageSkipMissing las locales inexistentes se reemplazan por su
    // texto (sin <img>) para no disparar warnings de carga. Necesita baseFolder
    // e imageExists(absPath)->bool; sin ellos se mantiene lo de siempre.
    var images = [];
    var imgRegex = /!\[([^\]]*)\]\(((?:[^()\s]+|\([^()\s]*\))+)(?:\s+"([^"]*)")?\)/g;
    text = text.replace(imgRegex, function(match, alt, url, title) {
        var token = "\uE000IMG_" + images.length + "\uE000";
        var resolvedUrl = url;
        if (options.baseFolder && !/^(?:https?:\/\/|file:\/\/|\/)/i.test(resolvedUrl)) {
            resolvedUrl = options.baseFolder + "/" + resolvedUrl;
        }
        if (options.imageSkipMissing && typeof options.imageExists === "function") {
            var probePath = "";
            if (/^(?:https?:\/\/)/i.test(url)) {
                probePath = ""; // remota: no pre-verificable, se carga igual
            } else if (/^file:\/\//i.test(url)) {
                probePath = url.replace(/^file:\/\/(localhost\/)?/i, "");
                try { probePath = decodeURIComponent(probePath); } catch (e) {}
            } else if (url.startsWith("/")) {
                probePath = url;
            } else if (options.baseFolder) {
                probePath = resolvedUrl;
            }
            if (probePath !== "" && !options.imageExists(probePath)) {
                // Local inexistente: texto plano escapado en vez de <img>
                images.push(escapeHtml("[" + alt + "]"));
                return token;
            }
        }
        var safeUrl = escapeHtml(resolvedUrl);
        var safeAlt = escapeHtml(alt);
        var titleAttr = title ? ' title="' + escapeHtml(title) + '"' : '';
        var html = '<img src="' + safeUrl + '" alt="' + safeAlt + '"' + titleAttr + ' />';
        images.push(html);
        return token;
    });

    // 4. Autolinks: <https://...> o <http://...> o <mailto:...>
    var links = [];
    text = text.replace(/<(https?:\/\/[^\s>]+|mailto:[^\s>]+)>/g, function(match, url) {
        var token = "\uE000LINK_" + links.length + "\uE000";
        var safeUrl = escapeHtml(url);
        var html = '<a href="' + safeUrl + '" style="color: ' + linkColor + '; text-decoration: none;">' + safeUrl + '</a>';
        links.push(html);
        return token;
    });

    // 5. Extraer enlaces markdown: [texto](url) o [texto](url "titulo")
    var linkRegex = /\[([^\]]+)\]\(((?:[^()\s]+|\([^()\s]*\))+)(?:\s+"([^"]*)")?\)/g;
    text = text.replace(linkRegex, function(match, linkText, url, title) {
        var token = "\uE000LINK_" + links.length + "\uE000";
        var innerOpts = {};
        for (var k in options) innerOpts[k] = options[k];
        innerOpts.searchQuery = "";
        var innerHtml = inlineToHtml(linkText, innerOpts);
        var safeUrl = url.trim();
        if (/^(?:javascript|data:text\/html)/i.test(safeUrl)) {
            safeUrl = "#";
        }
        var titleAttr = title ? ' title="' + escapeHtml(title) + '"' : '';
        var html = '<a href="' + escapeHtml(safeUrl) + '"' + titleAttr + ' style="color: ' + linkColor + '; text-decoration: none;">' + innerHtml + '</a>';
        links.push(html);
        return token;
    });

    // 5b. Wikilinks: [[destino]] o [[destino|alias]]
    var wikiRegex = /\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g;
    text = text.replace(wikiRegex, function(match, target, alias) {
        var token = "\uE000LINK_" + links.length + "\uE000";
        var label = (alias !== undefined && alias !== null) ? alias : target;
        var innerHtml = escapeHtml(label.trim());
        var href = target.trim();
        var html = '<a href="' + escapeHtml(href) + '" style="color: ' + linkColor + '; text-decoration: underline;">' + innerHtml + '</a>';
        links.push(html);
        return token;
    });

    // 5c. Linkificar URLs peladas (bare URLs): https?://[^\s<>)"]+
    var bareRegex = /\b(https?:\/\/[^\s<>)"]+)/g;
    text = text.replace(bareRegex, function(match, url) {
        var trailing = "";
        var m = url.match(/[.,:;!?]+$/);
        if (m) {
            trailing = m[0];
            url = url.slice(0, -trailing.length);
        }
        var token = "\uE000LINK_" + links.length + "\uE000";
        var safeUrl = escapeHtml(url);
        var html = '<a href="' + safeUrl + '" style="color: ' + linkColor + '; text-decoration: none;">' + safeUrl + '</a>';
        links.push(html);
        return token + trailing;
    });

    // 6. Proteger etiquetas HTML permitidas (<u>, </u>, <br>, <br/>, <br />) y escapar las demás
    var allowedTags = [];
    text = text.replace(/<\/?u>|<br\s*\/?>/gi, function(tag) {
        var token = "\uE000ALLOWED_" + allowedTags.length + "\uE000";
        allowedTags.push(tag.toLowerCase());
        return token;
    });

    // Escapar cualquier otro HTML (<script>, <div>, &, <, >, etc.)
    text = escapeHtml(text);

    // Restaurar etiquetas HTML permitidas
    for (var a = 0; a < allowedTags.length; a++) {
        var tagHtml = allowedTags[a];
        text = text.replace("\uE000ALLOWED_" + a + "\uE000", function() { return tagHtml; });
    }

    // 7. Formato inline

    // Negrita + Cursiva (***texto*** o ___texto___)
    text = text.replace(/\*\*\*([^\s*]|[^\s*][\s\S]*?[^\s*])\*\*\*/g, "<b><i>$1</i></b>");
    text = text.replace(/(?:^|[^\w])___([^\s_]|[^\s_][\s\S]*?[^\s_])___(?=[^\w]|$)/g, function(match, p1) {
        var prefix = match.substring(0, match.indexOf("___"));
        return prefix + "<b><i>" + p1 + "</i></b>";
    });

    // Negrita (**texto** o __texto__)
    text = text.replace(/\*\*([^\s*]|[^\s*][\s\S]*?[^\s*])\*\*/g, "<b>$1</b>");
    text = text.replace(/(?:^|[^\w])__([^\s_]|[^\s_][\s\S]*?[^\s_])__(?=[^\w]|$)/g, function(match, p1) {
        var prefix = match.substring(0, match.indexOf("__"));
        return prefix + "<b>" + p1 + "</b>";
    });

    // Cursiva (*texto*)
    text = text.replace(/\*([^\s*]|[^\s*][\s\S]*?[^\s*])\*/g, "<i>$1</i>");

    // Cursiva con guion bajo (_texto_): SOLO si no es snake_case_name
    text = text.replace(/(^|[^\w])_([^\s_]|[^\s_][\s\S]*?[^\s_])_([^\w]|$)/g, function(match, before, inner, after) {
        return before + "<i>" + inner + "</i>" + after;
    });

    // Tachado (~~texto~~)
    text = text.replace(/~~([^\s~]|[^\s~][\s\S]*?[^\s~])~~/g, "<s>$1</s>");

    // Resaltado (==texto==) con límite de palabra/espacio
    text = text.replace(/(^|[\s(])==([^\s=]|[^\s=][\s\S]*?[^\s=])==(?=[\s),.?!:;]|$)/g, function(match, prefix, inner) {
        return prefix + '<span style="background-color: ' + highlightBg + '; padding: 0 3px; border-radius: 3px;">' + inner + '</span>';
    });

    // 8. Restaurar imágenes
    for (var m = 0; m < images.length; m++) {
        var imgHtml = images[m];
        text = text.replace("\uE000IMG_" + m + "\uE000", function() { return imgHtml; });
    }

    // 9. Restaurar enlaces
    for (var l = 0; l < links.length; l++) {
        var linkHtml = links[l];
        text = text.replace("\uE000LINK_" + l + "\uE000", function() { return linkHtml; });
    }

    // 10. Restaurar código inline
    for (var c = 0; c < codeSpans.length; c++) {
        var codeHtml = codeSpans[c];
        text = text.replace("\uE000CODE_" + c + "\uE000", function() { return codeHtml; });
    }

    // 10b. Restaurar etiquetas kbd estilizadas
    for (var k = 0; k < kbds.length; k++) {
        var kbdHtml = kbds[k];
        text = text.replace("\uE000KBD_" + k + "\uE000", function() { return kbdHtml; });
    }

    // 11. Restaurar caracteres escapados a texto plano seguro
    for (var e = 0; e < escapes.length; e++) {
        var escText = escapeHtml(escapes[e]);
        text = text.replace("\uE000ESC_" + e + "\uE000", function() { return escText; });
    }

    // 12. Resaltar coincidencias de búsqueda si se proveyó searchQuery
    if (options.searchQuery) {
        text = highlightInHtml(text, options.searchQuery, options.searchHighlightBg,
            options.searchHighlightActiveBg, options.searchActiveOrdinal, options.searchHighlightActiveFg);
    }

    if (headingSize) {
        text = '<span style="font-size: ' + headingSize + 'px;"><b>' + text + '</b></span>';
    }

    return text;
}

// Helper para normalizar caracteres a su forma base sin variar la longitud de string
function _stripAccentsSameLen(str) {
    if (!str || typeof str !== "string") return "";
    var out = "";
    for (var i = 0; i < str.length; i++) {
        var c = str[i];
        var n = (typeof c.normalize === "function") ? c.normalize("NFD") : c;
        out += (n.length > 0 ? n[0] : c);
    }
    return out;
}

// Resalta apariciones de búsqueda en un string HTML sin alterar etiquetas ni entidades HTML.
// Parámetros activos opcionales: si activeBg y activeOrdinal
// (>= 0) se dan, la ocurrencia número activeOrdinal (en orden de pintado) usa el
// fondo activo + color de texto activo en vez del fondo suave.
function highlightInHtml(html, query, highlightBg, activeBg, activeOrdinal, activeFg) {
    if (!html || !query || typeof html !== "string" || typeof query !== "string") return html || "";
    var trimmed = query.trim();
    if (!trimmed) return html;

    var bg = highlightBg || "rgba(100, 149, 237, 0.38)";
    var normQuery = _stripAccentsSameLen(trimmed).toLowerCase();
    var qLen = normQuery.length;
    if (qLen === 0) return html;

    var hasActive = (typeof activeOrdinal === "number" && activeOrdinal >= 0 && !!activeBg);
    var ordinal = 0;

    var parts = html.split(/(<[^>]+>|&[#A-Za-z0-9]+;)/g);
    for (var i = 0; i < parts.length; i++) {
        // Los índices pares son texto visible fuera de tags HTML y entidades (&...;)
        if (i % 2 === 0 && parts[i]) {
            var chunk = parts[i];
            var normChunk = _stripAccentsSameLen(chunk).toLowerCase();
            var res = "";
            var lastIdx = 0;
            var idx = normChunk.indexOf(normQuery, 0);
            while (idx !== -1) {
                res += chunk.substring(lastIdx, idx);
                var origMatch = chunk.substring(idx, idx + qLen);
                if (hasActive && ordinal === activeOrdinal) {
                    res += '<span style="background-color: ' + activeBg + ';' + (activeFg ? ' color: ' + activeFg + ';' : '') + ' border-radius: 3px; padding: 0 2px;">' + origMatch + '</span>';
                } else {
                    res += '<span style="background-color: ' + bg + '; border-radius: 3px; padding: 0 2px;">' + origMatch + '</span>';
                }
                ordinal++;
                lastIdx = idx + qLen;
                idx = normChunk.indexOf(normQuery, lastIdx);
            }
            res += chunk.substring(lastIdx);
            parts[i] = res;
        }
    }
    return parts.join("");
}

// Elimina imágenes markdown dejando el texto
// texto; solo aparece en el placeholder de error. Ver extractImages.)
function stripImages(md) {
    if (!md || typeof md !== "string") return "";
    return md.replace(/(?:\[!\[([^\]]*)\]\(([^)]+)\)\]\(([^)]+)\)|!\[([^\]]*)\]\(([^)]+)\))/g, "");
}

// Extrae todas las imágenes markdown (misma regex que BlockImage.imagesList)
function extractImages(src) {
    if (!src || typeof src !== "string") return [];
    var out = [];
    var re = /(?:\[!\[([^\]]*)\]\(([^)]+)\)\]\(([^)]+)\)|!\[([^\]]*)\]\(([^)]+)\))/g;
    var m;
    while ((m = re.exec(src)) !== null) {
        out.push({
            alt: m[1] || m[4] || "",
            src: m[2] || m[5] || "",
            link: m[3] || ""
        });
    }
    return out;
}

// Aplica o quita marcadores de formato envolvente (toggleWrap)
// Funciona estrictamente sobre el rango [selStart, selEnd], sin efectos colaterales globales.
function toggleWrap(text, selStart, selEnd, marker) {
    if (typeof text !== "string") return { text: "", newSelStart: 0, newSelEnd: 0 };
    var s = Math.min(selStart, selEnd);
    var e = Math.max(selStart, selEnd);
    if (s < 0) s = 0;
    if (e > text.length) e = text.length;

    // T12: Si hay selección, recortar espacios en los bordes antes de envolver
    if (s !== e) {
        var origS = s;
        var origE = e;
        while (s < e && /\s/.test(text[s])) s++;
        while (e > s && /\s/.test(text[e - 1])) e--;
        if (s === e) {
            return { text: text, newSelStart: origS, newSelEnd: origE };
        }
    }

    // Manejo especial para HTML <u> ... </u>
    if (marker === "<u>" || marker === "</u>" || marker === "<u></u>") {
        return _toggleTagWrap(text, s, e, "<u>", "</u>");
    }

    // Manejo de asteriscos (* y **) y guiones bajos (_ y __)
    if (marker === "*" || marker === "**" || marker === "_" || marker === "__") {
        return _toggleAsteriskOrUnderscore(text, s, e, marker);
    }

    // Manejo general para ~~ y `
    var openMarker = marker;
    var closeMarker = marker;
    var openLen = openMarker.length;
    var closeLen = closeMarker.length;

    if (s === e) {
        var beforeCursor = text.substring(Math.max(0, s - openLen), s);
        var afterCursor = text.substring(s, Math.min(text.length, s + closeLen));
        if (beforeCursor === openMarker && afterCursor === closeMarker) {
            return {
                text: text.substring(0, s - openLen) + text.substring(s + closeLen),
                newSelStart: s - openLen,
                newSelEnd: s - openLen
            };
        } else {
            return {
                text: text.substring(0, s) + openMarker + closeMarker + text.substring(s),
                newSelStart: s + openLen,
                newSelEnd: s + openLen
            };
        }
    }

    var selected = text.substring(s, e);
    if (selected.length >= openLen + closeLen && selected.startsWith(openMarker) && selected.endsWith(closeMarker)) {
        var unwrapInside = selected.substring(openLen, selected.length - closeLen);
        return {
            text: text.substring(0, s) + unwrapInside + text.substring(e),
            newSelStart: s,
            newSelEnd: s + unwrapInside.length
        };
    }

    var beforeSel = text.substring(Math.max(0, s - openLen), s);
    var afterSel = text.substring(e, Math.min(text.length, e + closeLen));
    if (beforeSel === openMarker && afterSel === closeMarker) {
        return {
            text: text.substring(0, s - openLen) + selected + text.substring(e + closeLen),
            newSelStart: s - openLen,
            newSelEnd: s - openLen + selected.length
        };
    }

    return {
        text: text.substring(0, s) + openMarker + selected + closeMarker + text.substring(e),
        newSelStart: s + openLen,
        newSelEnd: s + openLen + selected.length
    };
}

function _toggleTagWrap(text, s, e, openTag, closeTag) {
    var oLen = openTag.length;
    var cLen = closeTag.length;

    if (s === e) {
        var b = text.substring(Math.max(0, s - oLen), s);
        var a = text.substring(s, Math.min(text.length, s + cLen));
        if (b.toLowerCase() === openTag && a.toLowerCase() === closeTag) {
            return {
                text: text.substring(0, s - oLen) + text.substring(s + cLen),
                newSelStart: s - oLen,
                newSelEnd: s - oLen
            };
        }
        return {
            text: text.substring(0, s) + openTag + closeTag + text.substring(s),
            newSelStart: s + oLen,
            newSelEnd: s + oLen
        };
    }

    var selected = text.substring(s, e);
    if (selected.length >= oLen + cLen &&
        selected.substring(0, oLen).toLowerCase() === openTag &&
        selected.substring(selected.length - cLen).toLowerCase() === closeTag) {
        var inner = selected.substring(oLen, selected.length - cLen);
        return {
            text: text.substring(0, s) + inner + text.substring(e),
            newSelStart: s,
            newSelEnd: s + inner.length
        };
    }

    var beforeSel = text.substring(Math.max(0, s - oLen), s);
    var afterSel = text.substring(e, Math.min(text.length, e + cLen));
    if (beforeSel.toLowerCase() === openTag && afterSel.toLowerCase() === closeTag) {
        return {
            text: text.substring(0, s - oLen) + selected + text.substring(e + cLen),
            newSelStart: s - oLen,
            newSelEnd: s - oLen + selected.length
        };
    }

    return {
        text: text.substring(0, s) + openTag + selected + closeTag + text.substring(e),
        newSelStart: s + oLen,
        newSelEnd: s + oLen + selected.length
    };
}

function _toggleAsteriskOrUnderscore(text, s, e, marker) {
    var char = marker[0];
    var isDouble = (marker.length === 2);

    if (s === e) {
        var bChar = (s > 0 ? text[s - 1] : "");
        var aChar = (s < text.length ? text[s] : "");
        if (bChar === char && aChar === char) {
            var removeCount = isDouble ? 2 : 1;
            var canRemove = (s >= removeCount && s + removeCount <= text.length &&
                             text.substring(s - removeCount, s) === marker &&
                             text.substring(s, s + removeCount) === marker);
            if (canRemove) {
                return {
                    text: text.substring(0, s - removeCount) + text.substring(s + removeCount),
                    newSelStart: s - removeCount,
                    newSelEnd: s - removeCount
                };
            }
        }
        return {
            text: text.substring(0, s) + marker + marker + text.substring(s),
            newSelStart: s + marker.length,
            newSelEnd: s + marker.length
        };
    }

    var countBefore = 0;
    while (s - 1 - countBefore >= 0 && text[s - 1 - countBefore] === char) {
        countBefore++;
    }
    var countAfter = 0;
    while (e + countAfter < text.length && text[e + countAfter] === char) {
        countAfter++;
    }

    var selected = text.substring(s, e);
    var insideLead = 0;
    while (insideLead < selected.length && selected[insideLead] === char) {
        insideLead++;
    }
    var insideTrail = 0;
    while (selected.length - 1 - insideTrail >= 0 && selected[selected.length - 1 - insideTrail] === char) {
        insideTrail++;
    }

    if (isDouble) {
        if (insideLead >= 2 && insideTrail >= 2 && selected.length >= 4) {
            var unwrapped = selected.substring(2, selected.length - 2);
            return {
                text: text.substring(0, s) + unwrapped + text.substring(e),
                newSelStart: s,
                newSelEnd: s + unwrapped.length
            };
        }
        if (countBefore >= 2 && countAfter >= 2) {
            var newT = text.substring(0, s - 2) + selected + text.substring(e + 2);
            return {
                text: newT,
                newSelStart: s - 2,
                newSelEnd: s - 2 + selected.length
            };
        }
        var addT = text.substring(0, s) + marker + selected + marker + text.substring(e);
        return {
            text: addT,
            newSelStart: s + 2,
            newSelEnd: s + 2 + selected.length
        };
    } else {
        var totalOutside = Math.min(countBefore, countAfter);
        var totalInside = Math.min(insideLead, insideTrail);

        if (totalInside === 1 || totalInside === 3) {
            var unwrappedI = selected.substring(1, selected.length - 1);
            return {
                text: text.substring(0, s) + unwrappedI + text.substring(e),
                newSelStart: s,
                newSelEnd: s + unwrappedI.length
            };
        }

        if (totalOutside === 1 || totalOutside === 3) {
            var newTI = text.substring(0, s - 1) + selected + text.substring(e + 1);
            return {
                text: newTI,
                newSelStart: s - 1,
                newSelEnd: s - 1 + selected.length
            };
        }

        var addTI = text.substring(0, s) + marker + selected + marker + text.substring(e);
        return {
            text: addTI,
            newSelStart: s + 1,
            newSelEnd: s + 1 + selected.length
        };
    }
}

// Helper interno: recolecta todos los tramos de formato inline con sus rangos [start, end] en `src`
function _collectInlineSpans(src) {
    var spans = [];
    if (!src || typeof src !== "string") return spans;

    // Enmascarar caracteres escapados con barra invertida para que no activen delimitadores falsos
    var maskedSrc = src.replace(/\\([*_[\]~=\\`!#])/g, "\uE000\uE000");

    // 1. Código inline: `...`
    var codeRegex = /`([^`\r\n]+)`/g;
    var m;
    while ((m = codeRegex.exec(maskedSrc)) !== null) {
        spans.push({ type: "code", start: m.index, end: m.index + m[0].length, openDelim: "`", closeDelim: "`", inner: src.substring(m.index + 1, m.index + m[0].length - 1) });
    }

    // 2. Imágenes markdown: ![alt](url)
    var imgRegex = /!\[([^\]]*)\]\(([^)]+)\)/g;
    while ((m = imgRegex.exec(maskedSrc)) !== null) {
        var alt = m[1];
        var url = m[2];
        spans.push({ type: "image", start: m.index, end: m.index + m[0].length, openDelim: "![", closeDelim: "](" + url + ")", inner: alt, url: url });
    }

    // 3. Wikilinks: [[nota]] o [[nota|alias]]
    var wikiRegex = /\[\[([^\]\r\n]+)\]\]/g;
    while ((m = wikiRegex.exec(maskedSrc)) !== null) {
        var full = m[1];
        var pipeIdx = full.indexOf("|");
        var target = pipeIdx !== -1 ? full.substring(0, pipeIdx) : full;
        var label = pipeIdx !== -1 ? full.substring(pipeIdx + 1) : full;
        spans.push({
            type: "wikilink",
            start: m.index,
            end: m.index + m[0].length,
            openDelim: pipeIdx !== -1 ? "[[" + target + "|" : "[[",
            closeDelim: "]]",
            inner: label,
            target: target
        });
    }

    // 4. Enlaces markdown: [label](url) (no precedidos por !)
    var linkRegex = /(^|[^!])\[([^\]]+)\]\(([^)]+)\)/g;
    while ((m = linkRegex.exec(maskedSrc)) !== null) {
        var pfxLen = m[1].length;
        var s = m.index + pfxLen;
        var label = m[2];
        var url = m[3];
        var matchLen = m[0].length - pfxLen;
        spans.push({ type: "link", start: s, end: s + matchLen, openDelim: "[", closeDelim: "](" + url + ")", inner: label, url: url });
    }

    // 5. Negrita + Cursiva: ***...*** o ___...___
    var biRegex = /\*\*\*([^\s*]|[^\s*][\s\S]*?[^\s*])\*\*\*/g;
    while ((m = biRegex.exec(maskedSrc)) !== null) {
        spans.push({ type: "bold_italic", start: m.index, end: m.index + m[0].length, openDelim: "***", closeDelim: "***", inner: src.substring(m.index + 3, m.index + m[0].length - 3) });
    }
    var biUnderRegex = /(?:^|[^\w])___([^\s_]|[^\s_][\s\S]*?[^\s_])___(?=[^\w]|$)/g;
    while ((m = biUnderRegex.exec(maskedSrc)) !== null) {
        var pfxLen = m[0].startsWith("___") ? 0 : 1;
        var s = m.index + pfxLen;
        var innerLen = m[0].length - pfxLen - 6;
        spans.push({ type: "bold_italic", start: s, end: s + m[0].length - pfxLen, openDelim: "___", closeDelim: "___", inner: src.substring(s + 3, s + 3 + innerLen) });
    }

    // 6. Negrita: **...** o __...__
    var boldRegex = /\*\*([^\s*][\s\S]*?)\*\*(?!\*)/g;
    while ((m = boldRegex.exec(maskedSrc)) !== null) {
        spans.push({ type: "bold", start: m.index, end: m.index + m[0].length, openDelim: "**", closeDelim: "**", inner: src.substring(m.index + 2, m.index + m[0].length - 2) });
    }
    var boldUnderRegex = /(?:^|[^\w])__([^\s_]|[^\s_][\s\S]*?[^\s_])__(?=[^\w]|$)/g;
    while ((m = boldUnderRegex.exec(maskedSrc)) !== null) {
        var pfxLen = m[0].startsWith("__") ? 0 : 1;
        var s = m.index + pfxLen;
        var innerLen = m[0].length - pfxLen - 4;
        spans.push({ type: "bold", start: s, end: s + m[0].length - pfxLen, openDelim: "__", closeDelim: "__", inner: src.substring(s + 2, s + 2 + innerLen) });
    }

    // 7. Cursiva: *...* o _..._
    var italicRegex = /(?:^|[^\*])\*([^\*\s][^\*]*?)\*(?=[^\*]|$)/g;
    while ((m = italicRegex.exec(maskedSrc)) !== null) {
        var pfxLen = m[0].startsWith("*") ? 0 : 1;
        var s = m.index + pfxLen;
        var innerLen = m[0].length - pfxLen - 2;
        spans.push({ type: "italic", start: s, end: s + m[0].length - pfxLen, openDelim: "*", closeDelim: "*", inner: src.substring(s + 1, s + 1 + innerLen) });
    }
    var italicUnderRegex = /(^|[^\w])_([^\s_]|[^\s_][\s\S]*?[^\s_])_([^\w]|$)/g;
    while ((m = italicUnderRegex.exec(maskedSrc)) !== null) {
        var pfxLen = m[1].length;
        var s = m.index + pfxLen;
        var matchLen = m[0].length - pfxLen - m[3].length;
        var innerLen = matchLen - 2;
        spans.push({ type: "italic", start: s, end: s + matchLen, openDelim: "_", closeDelim: "_", inner: src.substring(s + 1, s + 1 + innerLen) });
    }

    // 8. Tachado: ~~...~~
    var strikeRegex = /~~([^\s~]|[^\s~][\s\S]*?[^\s~])~~/g;
    while ((m = strikeRegex.exec(maskedSrc)) !== null) {
        spans.push({ type: "strike", start: m.index, end: m.index + m[0].length, openDelim: "~~", closeDelim: "~~", inner: src.substring(m.index + 2, m.index + m[0].length - 2) });
    }

    // 9. Subrayado: <u>...</u> o &lt;u&gt;...&lt;/u&gt;
    var uRegex = /<u>([\s\S]*?)<\/u>|&lt;u&gt;([\s\S]*?)&lt;\/u&gt;/gi;
    while ((m = uRegex.exec(maskedSrc)) !== null) {
        var inner = m[1] !== undefined ? m[1] : m[2];
        var isEsc = (m[0].indexOf("&lt;") !== -1);
        spans.push({ type: "underline", start: m.index, end: m.index + m[0].length, openDelim: isEsc ? "&lt;u&gt;" : "<u>", closeDelim: isEsc ? "&lt;/u&gt;" : "</u>", inner: inner });
    }

    // 9b. Teclas de atajo: <kbd>...</kbd> o &lt;kbd&gt;...&lt;/kbd&gt;
    var kbdRegex = /<kbd>([\s\S]*?)<\/kbd>|&lt;kbd&gt;([\s\S]*?)&lt;\/kbd&gt;/gi;
    while ((m = kbdRegex.exec(maskedSrc)) !== null) {
        var innerKbd = m[1] !== undefined ? m[1] : m[2];
        var isEscKbd = (m[0].indexOf("&lt;") !== -1);
        spans.push({
            type: "kbd",
            start: m.index,
            end: m.index + m[0].length,
            openDelim: isEscKbd ? "&lt;kbd&gt;" : "<kbd>",
            closeDelim: isEscKbd ? "&lt;/kbd&gt;" : "</kbd>",
            inner: innerKbd
        });
    }

    // 10. Resaltado: ==...==
    var hlRegex = /==([^\s=]|[^\s=][\s\S]*?[^\s=])==/g;
    while ((m = hlRegex.exec(maskedSrc)) !== null) {
        spans.push({ type: "highlight", start: m.index, end: m.index + m[0].length, openDelim: "==", closeDelim: "==", inner: src.substring(m.index + 2, m.index + m[0].length - 2) });
    }

    // Ordenar spans por start ascendente, y los más largos primero
    spans.sort(function(a, b) {
        if (a.start !== b.start) return a.start - b.start;
        return (b.end - b.start) - (a.end - a.start);
    });

    // Descartar solapamientos conflictivos
    var nonOverlapping = [];
    var lastEnd = 0;
    for (var i = 0; i < spans.length; i++) {
        var sp = spans[i];
        if (sp.start >= lastEnd) {
            nonOverlapping.push(sp);
            lastEnd = sp.end;
        }
    }
    return nonOverlapping;
}

// Formatea texto markdown para edición en vivo estilo Typora:
// Mantiene activos los formatos visuales (tachado, negrita, cursiva, subrayado)
// mientras muestra los caracteres de sintaxis (~~, **, *, <u>) en color atenuado
// EXCLUSIVAMENTE cuando el cursor_text o selección está tocando la palabra formatada.
// Si el cursor está fuera, los caracteres de sintaxis se ocultan visualmente (font-size: 1px; color: transparent;)
// preservando 100% el texto crudo y su integridad al guardar.
function formatForLiveEditing(src, opts) {
    if (!src || typeof src !== "string") return "";

    var options = opts || {};
    var dimColor = options.dimColor || "#888888";
    var codeBg = options.codeBg || "rgba(255, 255, 255, 0.12)";
    var codeColor = options.codeColor || "#f0f0f0";
    var kbdBg = options.kbdBg || "rgba(255, 255, 255, 0.10)";
    var kbdColor = options.kbdColor || options.codeColor || "#f0f0f0";
    var kbdBorder = options.kbdBorder || "rgba(255, 255, 255, 0.22)";
    var linkColor = options.linkColor || "#5294e2";
    var highlightBg = options.highlightBg || _defaultHighlightBg;
    var alwaysRevealAll = !!options.alwaysRevealAll;
    var hideSyntax = !!options.hideSyntax;

    var s = (typeof options.selStart === "number") ? options.selStart : -1;
    var e = (typeof options.selEnd === "number") ? options.selEnd : -1;
    var cur = (typeof options.cursorPos === "number") ? options.cursorPos : -1;

    var hasSel = (s >= 0 && e >= 0 && s !== e);
    var selMin = hasSel ? Math.min(s, e) : cur;
    var selMax = hasSel ? Math.max(s, e) : cur;

    // Encabezados con numerales (# a ######).
    var hm = src.match(/^(#{1,6}) ([\s\S]*)$/);
    if (hm) {
        var hashes = hm[1];
        var title = hm[2];
        var pfxLen = hashes.length + 1;
        var isPfxTouching = !hideSyntax && (alwaysRevealAll || (hasSel ? (selMin <= pfxLen && selMax >= 0) : (cur >= 0 && cur <= pfxLen)));
        var pfxHtml = isPfxTouching
            ? ('<font color="' + dimColor + '">' + hashes + ' </font>')
            : (hideSyntax ? "" : ('<span style="font-size: 1px; color: transparent;">' + hashes + ' </span>'));

        var titleOpts = {};
        for (var k in options) titleOpts[k] = options[k];
        titleOpts.cursorPos = (cur >= 0) ? Math.max(-1, cur - pfxLen) : -1;
        titleOpts.selStart = (s >= 0) ? Math.max(-1, s - pfxLen) : -1;
        titleOpts.selEnd = (e >= 0) ? Math.max(-1, e - pfxLen) : -1;
        delete titleOpts.headingSizes;

        var formattedTitle = formatForLiveEditing(title, titleOpts);
        // Quitar envoltura externa pre-wrap de formattedTitle para anidarla limpiamente
        formattedTitle = formattedTitle.replace(/^<span style="white-space: pre-wrap;">([\s\S]*)<\/span>$/, "$1");

        var sz = (options.headingSizes && options.headingSizes[hashes.length]) ? options.headingSizes[hashes.length] : 0;
        var fullHeading = '<b>' + pfxHtml + formattedTitle + '</b>';
        if (sz > 0) fullHeading = '<span style="font-size: ' + sz + 'px;">' + fullHeading + '</span>';
        return '<span style="white-space: pre-wrap;">' + fullHeading + '</span>';
    }

    var spans = _collectInlineSpans(src);
    var out = "";
    var curIdx = 0;

    for (var i = 0; i < spans.length; i++) {
        var sp = spans[i];
        if (sp.start > curIdx) {
            out += escapeHtml(src.substring(curIdx, sp.start));
        }

        var isTouching = !hideSyntax && (alwaysRevealAll || (hasSel
            ? (selMin <= sp.end && selMax >= sp.start)
            : (cur >= 0 && cur >= sp.start && cur <= sp.end)));

        var openHtml = isTouching
            ? ('<font color="' + dimColor + '">' + escapeHtml(sp.openDelim) + '</font>')
            : (hideSyntax ? "" : ('<span style="font-size: 1px; color: transparent;">' + escapeHtml(sp.openDelim) + '</span>'));

        var closeHtml = isTouching
            ? ('<font color="' + dimColor + '">' + escapeHtml(sp.closeDelim) + '</font>')
            : (hideSyntax ? "" : ('<span style="font-size: 1px; color: transparent;">' + escapeHtml(sp.closeDelim) + '</span>'));

        var innerHtml = "";
        if (sp.type === "code" || sp.type === "kbd" || sp.type === "link" || sp.type === "image" || sp.type === "wikilink") {
            innerHtml = escapeHtml(sp.inner);
        } else {
            // Formatear recursivamente el contenido interno (soporta formatos anidados como **negrita *cursiva***)
            var innerOpts = {};
            for (var k in options) innerOpts[k] = options[k];
            var innerOffset = sp.start + sp.openDelim.length;
            innerOpts.cursorPos = (cur >= 0) ? Math.max(-1, cur - innerOffset) : -1;
            innerOpts.selStart = (s >= 0) ? Math.max(-1, s - innerOffset) : -1;
            innerOpts.selEnd = (e >= 0) ? Math.max(-1, e - innerOffset) : -1;
            innerHtml = formatForLiveEditing(sp.inner, innerOpts);
            innerHtml = innerHtml.replace(/^<span style="white-space: pre-wrap;">([\s\S]*)<\/span>$/, "$1");
        }

        switch (sp.type) {
            case "bold":
                out += '<b>' + openHtml + innerHtml + closeHtml + '</b>';
                break;
            case "italic":
                out += '<i>' + openHtml + innerHtml + closeHtml + '</i>';
                break;
            case "bold_italic":
                out += '<b><i>' + openHtml + innerHtml + closeHtml + '</i></b>';
                break;
            case "strike":
                out += '<s>' + openHtml + innerHtml + closeHtml + '</s>';
                break;
            case "underline":
                out += '<u>' + openHtml + innerHtml + closeHtml + '</u>';
                break;
            case "highlight":
                out += '<span style="background-color: ' + highlightBg + '; padding: 0 3px; border-radius: 3px;">' + openHtml + innerHtml + closeHtml + '</span>';
                break;
            case "code":
                out += '<span style="font-family: monospace; background-color: ' + codeBg + '; color: ' + codeColor + '; border-radius: 4px; padding: 1px 4px;">' + openHtml + innerHtml + closeHtml + '</span>';
                break;
            case "kbd":
                out += '<span style="font-family: monospace; font-size: 0.9em; background-color: ' + kbdBg + '; color: ' + kbdColor + '; border: 1px solid ' + kbdBorder + '; border-radius: 4px; padding: 1px 5px;">' + openHtml + innerHtml + closeHtml + '</span>';
                break;
            case "link":
                out += '<span style="color: ' + linkColor + '; text-decoration: underline;">' + openHtml + innerHtml + closeHtml + '</span>';
                break;
            case "wikilink":
                out += '<span style="color: ' + linkColor + '; text-decoration: underline;">' + openHtml + innerHtml + closeHtml + '</span>';
                break;
            case "image":
                out += '<span style="color: ' + linkColor + ';">' + openHtml + (innerHtml ? ('🖼️ ' + innerHtml) : '🖼️') + closeHtml + '</span>';
                break;
            default:
                out += openHtml + innerHtml + closeHtml;
        }

        curIdx = sp.end;
    }

    if (curIdx < src.length) {
        out += escapeHtml(src.substring(curIdx));
    }

    // Convert newlines to <br/> so RichText preserves line breaks
    out = out.replace(/\r?\n/g, "<br/>");
    return '<span style="white-space: pre-wrap;">' + out + '</span>';
}

// Detección de formatos inline activos para un rango de texto o posición de cursor
function detectFormats(src, selStart, selEnd, cursorPos) {
    var res = {
        bold: false,
        italic: false,
        underline: false,
        strike: false,
        highlight: false,
        inline_code: false,
        link: false
    };
    if (!src || typeof src !== "string") return res;

    var s = (typeof selStart === "number") ? selStart : -1;
    var e = (typeof selEnd === "number") ? selEnd : -1;
    var cur = (typeof cursorPos === "number") ? cursorPos : (s >= 0 ? s : 0);

    var hasSel = (s >= 0 && e >= 0 && s !== e);
    var rangeMin = hasSel ? Math.min(s, e) : cur;
    var rangeMax = hasSel ? Math.max(s, e) : cur;

    function isSpanActive(spanStart, spanEnd) {
        if (hasSel) {
            return rangeMin < spanEnd && rangeMax > spanStart;
        } else {
            return cur >= spanStart && cur <= spanEnd;
        }
    }

    // 1. Bold: **...** o __...__ o ***...***
    var boldRegex = /(\*\*|__)([\s\S]*?)\1|\*\*\*([\s\S]*?)\*\*\*/g;
    var m;
    while ((m = boldRegex.exec(src)) !== null) {
        if (isSpanActive(m.index, m.index + m[0].length)) {
            res.bold = true;
            if (m[0].startsWith("***")) res.italic = true;
            break;
        }
    }

    // 2. Italic: *...* o _..._ o ***...***
    var italicRegex = /(?:^|[^\*])(\*([^\*\s][\s\S]*?)\*)(?=[^\*]|$)|(?:^|[^_])(_([^_\s][\s\S]*?)_)(?=[^_]|$)/g;
    while ((m = italicRegex.exec(src)) !== null) {
        var matchIdx = m.index + (m[0].length - (m[1] ? m[1].length : (m[3] ? m[3].length : 0)));
        var matchLen = (m[1] ? m[1].length : (m[3] ? m[3].length : 0));
        if (isSpanActive(matchIdx, matchIdx + matchLen)) {
            res.italic = true;
            break;
        }
    }

    // 3. Underline: <u>...</u>
    var uRegex = /<u>([\s\S]*?)<\/u>/gi;
    while ((m = uRegex.exec(src)) !== null) {
        if (isSpanActive(m.index, m.index + m[0].length)) {
            res.underline = true;
            break;
        }
    }

    // 4. Strikethrough: ~~...~~
    var strikeRegex = /~~([\s\S]*?)~~/g;
    while ((m = strikeRegex.exec(src)) !== null) {
        if (isSpanActive(m.index, m.index + m[0].length)) {
            res.strike = true;
            break;
        }
    }

    // 5. Highlight: ==...==
    var hlRegex = /==([\s\S]*?)==/g;
    while ((m = hlRegex.exec(src)) !== null) {
        if (isSpanActive(m.index, m.index + m[0].length)) {
            res.highlight = true;
            break;
        }
    }

    // 6. Inline code: `...`
    var codeRegex = /`([^`\r\n]+)`/g;
    while ((m = codeRegex.exec(src)) !== null) {
        if (isSpanActive(m.index, m.index + m[0].length)) {
            res.inline_code = true;
            break;
        }
    }

    // 7. Link: [...](...)
    var linkRegex = /\[([^\]]+)\]\(([^)]+)\)|\[\[([^\]]+)\]\]/g;
    while ((m = linkRegex.exec(src)) !== null) {
        if (isSpanActive(m.index, m.index + m[0].length)) {
            res.link = true;
            break;
        }
    }

    // Si solo se pasó un string seleccionado directamente (sin offsets s y e)
    if (s < 0 && e < 0 && src.length > 0) {
        if (/\*\*[\s\S]*?\*\*|__[\s\S]*?__/.test(src)) res.bold = true;
        if (/(?:^|[^\*])\*[\s\S]*?\*(?=[^\*]|$)|(?:^|[^_])_[\s\S]*?_(?=[^_]|$)/.test(src)) res.italic = true;
        if (/<u>[\s\S]*?<\/u>/i.test(src)) res.underline = true;
        if (/~~[\s\S]*?~~/.test(src)) res.strike = true;
        if (/==[\s\S]*?==/.test(src)) res.highlight = true;
        if (/`[^`\r\n]+`/.test(src)) res.inline_code = true;
        if (/\[[^\]]+\]\([^)]+\)|\[\[[^\]]+\]\]/.test(src)) res.link = true;
    }

    return res;
}

// Normaliza texto plano de un elemento TextEdit o string, convirtiendo saltos U+2028/U+2029 a \n
function plainText(te) {
    if (!te) return "";
    var txt = (typeof te === "string") ? te : ((typeof te.getText === "function") ? te.getText(0, te.length) : (te.text || ""));
    return txt.replace(/[\u2028\u2029]/g, "\n");
}
