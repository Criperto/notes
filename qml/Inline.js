.pragma library

// Color por defecto del resaltado (==texto==); lo fija EditorMetrics desde Theme.color3.
var _defaultHighlightBg = "rgba(240, 198, 116, 0.35)";
function setHighlightBg(c) { if (typeof c === "string" && c !== "" && _defaultHighlightBg !== c) _defaultHighlightBg = c; }

// Renderizador LaTeX reactivo para fórmulas matemáticas inline ($...$)
var _latexRenderer = null;
function setLatexRenderer(fn) {
    if (typeof fn === "function" || fn === null) _latexRenderer = fn;
}

// Parser HTML/CSS inyectado desde HtmlStyleParser.js (v0.4.0)
var _htmlParser = null;
function setHtmlParser(mod) {
    if (mod && typeof mod.sanitizeAndConvertInlineTags === "function") {
        _htmlParser = mod;
    } else if (mod === null) {
        _htmlParser = null;
    }
}

function renderLatexInline(formula, opts) {
    var fn = (opts && typeof opts.renderLatex === "function") ? opts.renderLatex : _latexRenderer;
    var defaultTextColor = _defaultTheme.lightMode ? "#1a1a1a" : (_defaultTheme.textColor || "#ffffff");
    var colorHex = (opts && opts.mathColor) ? opts.mathColor : ((opts && opts.textColor) ? opts.textColor : defaultTextColor);
    var zoomVal = (opts && typeof opts.zoom === "number") ? opts.zoom : _defaultZoom;
    var defaultPt = Math.max(10.0, 16.5 * zoomVal);
    var ptSize = (opts && opts.mathPtSize) ? opts.mathPtSize : defaultPt;

    var res = "";
    if (typeof fn === "function") {
        res = fn(formula, false, colorHex, ptSize);
    } else if (typeof Sys !== "undefined" && Sys && typeof Sys.renderLatexSvg === "function") {
        res = Sys.renderLatexSvg(formula, false, colorHex, ptSize);
    }

    if (res && res.indexOf("ERROR:") !== 0 && res.indexOf("<svg") !== -1) {
        var uri = "data:image/svg+xml;utf8," + encodeURIComponent(res);
        return '<img src="' + uri + '" align="middle"/>';
    }

    // Fallback: visualización legible con fuente mono/cursiva
    return '<span style="font-style: italic; font-family: monospace;">$' + escapeHtml(formula) + '$</span>';
}

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

// Configuración global reactiva sincronizada con EditorMetrics y Theme
var _defaultZoom = 1.0;
function setZoom(z) {
    if (typeof z === "number" && z > 0 && Math.abs(_defaultZoom - z) > 0.001) {
        _defaultZoom = z;
    }
}

var _defaultTheme = {
    accent: "#e56018",
    lightMode: false,
    surface: "#1c1815",
    textColor: "#ffffff",
    color15: "#ffffff",
    fontFamilyMonospace: "JetBrains Mono, monospace"
};
function setThemeConfig(cfg) {
    if (!cfg || typeof cfg !== "object") return;
    if (cfg.accent) _defaultTheme.accent = String(cfg.accent);
    if (cfg.textColor) _defaultTheme.textColor = String(cfg.textColor);
    if (cfg.text) _defaultTheme.textColor = String(cfg.text);
    if (cfg.lightMode !== undefined) _defaultTheme.lightMode = Boolean(cfg.lightMode);
    if (cfg.surface) _defaultTheme.surface = String(cfg.surface);
    if (cfg.color15) _defaultTheme.color15 = String(cfg.color15);
    if (cfg.fontFamilyMonospace) _defaultTheme.fontFamilyMonospace = String(cfg.fontFamilyMonospace);
}
function setFontFamilyMonospace(f) {
    if (typeof f === "string" && f.trim() !== "") {
        _defaultTheme.fontFamilyMonospace = f.trim();
    }
}

// Genera un SVG data URI con diseño 3D realista multicapa de tecla de teclado (keycap),
// inspirado en keycap_base.svg y keycap_body.svg de shortcuts_viewer, adaptado dinámicamente al color de acento del tema y zoom del editor.
function renderKeycapSvg(label, opts) {
    var rawText = (label !== undefined && label !== null) ? String(label).trim() : "";
    var options = opts || {};
    var isLight = (options.lightMode !== undefined) ? Boolean(options.lightMode) : _defaultTheme.lightMode;

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

    // Escalar proporciones geométricas armónicamente según el nivel de zoom del editor
    var z = (typeof options.zoom === "number" && options.zoom > 0) ? options.zoom : _defaultZoom;
    z = Math.max(0.4, Math.min(3.5, z));

    var charW = 7.5 * z;
    var contentW = Math.max(10 * z, disp.length * charW);
    var w = Math.max(Math.round(30 * z), Math.round(contentW + 18 * z));
    var h = Math.max(16, Math.round(26 * z));

    // Colores dinámicos del tema: el bisel exterior se tiñe del color de acento del tema (Theme.accent)
    var defaultAccent = options.accent || options.linkColor || _defaultTheme.accent;
    var bezelColor = options.kbdBezel || (isLight ? "#dcdcdc" : defaultAccent);
    var shadowColor1 = options.kbdShadow1 || options.kbdShadow || _darkenColor(bezelColor, 1.55);
    var shadowColor2 = options.kbdShadow2 || _darkenColor(bezelColor, 1.25);
    var plateColor = options.kbdPlate || (isLight ? "#ffffff" : _defaultTheme.surface);
    var textColor = options.kbdText || (isLight ? "#1c1c1c" : (options.kbdColor || _defaultTheme.color15));

    // Tipografía mono / code del tema (JetBrains Mono con fallback a monospace)
    var rawFont = options.fontFamilyMonospace || options.fontFamily || _defaultTheme.fontFamilyMonospace;
    var cleanFont = rawFont ? String(rawFont).replace(/['"]/g, "").trim() : "JetBrains Mono";
    if (cleanFont.toLowerCase().indexOf("monospace") === -1) {
        cleanFont = "'" + cleanFont + "', monospace";
    } else if (cleanFont.indexOf("'") === -1 && cleanFont.indexOf('"') === -1) {
        var baseName = cleanFont.replace(/,\s*monospace/i, "").trim();
        cleanFont = (baseName.length > 0) ? ("'" + baseName + "', monospace") : "monospace";
    }
    var fontFamily = cleanFont;

    var safeText = disp
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");

    var bodyH = Math.round(21.0 * z * 10) / 10;
    var shadowY = Math.round(4.0 * z * 10) / 10;
    var shadowMidY = Math.round((shadowY - 1.4 * z) * 10) / 10;
    var plateX = Math.round(3.8 * z * 10) / 10;
    var plateY = Math.round(3.2 * z * 10) / 10;
    var plateW = Math.round((w - plateX * 2) * 10) / 10;
    var plateH = Math.round(15.0 * z * 10) / 10;
    var rx = Math.round(5.0 * z * 10) / 10;
    var plateRx = Math.round(2.6 * z * 10) / 10;
    var fontSize = Math.round(10.0 * z * 10) / 10;
    var textY = Math.round((plateY + plateH / 2.0) * 10) / 10;

    var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="' + w + '" height="' + h + '" viewBox="0 0 ' + w + ' ' + h + '">' +
        '<!-- Capa 3D inferior / Profundidad (keycap_base.svg) -->' +
        '<rect x="1" y="' + shadowY + '" width="' + (w - 2) + '" height="' + bodyH + '" rx="' + rx + '" fill="' + shadowColor1 + '"/>' +
        '<!-- Capa 3D intermedia / Bisel -->' +
        '<rect x="1" y="' + shadowMidY + '" width="' + (w - 2) + '" height="' + bodyH + '" rx="' + rx + '" fill="' + shadowColor2 + '"/>' +
        '<!-- Capa superior / Bisel del cuerpo (keycap_body.svg) -->' +
        '<rect x="1" y="1" width="' + (w - 2) + '" height="' + bodyH + '" rx="' + rx + '" fill="' + bezelColor + '"/>' +
        '<!-- Placa central interna recesada (Theme.surface) -->' +
        '<rect x="' + plateX + '" y="' + plateY + '" width="' + plateW + '" height="' + plateH + '" rx="' + plateRx + '" fill="' + plateColor + '"/>' +
        '<!-- Leyenda centrada en la placa interna -->' +
        '<text x="' + (w / 2.0) + '" y="' + textY + '" fill="' + textColor + '" font-family="' + fontFamily + '" font-size="' + fontSize + '" font-weight="bold" text-anchor="middle" dominant-baseline="central">' + safeText + '</text>' +
        '</svg>';

    return "data:image/svg+xml;utf8," + encodeURIComponent(svg);
}

// Convierte texto markdown inline a HTML seguro para componentes Text de Qt
// Extrae código inline (`...` o ``...``) y escapes \\ / \` antes de procesar LaTeX ($) o Markdown,
// evitando que variables de shell dentro de backticks (ej. `$QSDIR`, `"$link_dir" "$new_abs"`) sean interpretadas como LaTeX.
function _extractCodeSpansFirst(text, escapes, codeSpans, codeBg, codeColor) {
    var out = "";
    var i = 0;
    var n = text.length;
    while (i < n) {
        var ch = text[i];
        if (ch === "\\" && i + 1 < n && (text[i + 1] === "\\" || text[i + 1] === "`")) {
            var escTok = "\uE000ESC_" + escapes.length + "\uE000";
            escapes.push(text[i + 1]);
            out += escTok;
            i += 2;
            continue;
        }
        if (ch === "`") {
            var tickLen = 1;
            while (i + tickLen < n && text[i + tickLen] === "`") tickLen++;
            var j = i + tickLen;
            var foundEnd = -1;
            while (j < n && text[j] !== "\r" && text[j] !== "\n") {
                if (text[j] === "`") {
                    var closeLen = 1;
                    while (j + closeLen < n && text[j + closeLen] === "`") closeLen++;
                    if (closeLen === tickLen) {
                        foundEnd = j;
                        break;
                    }
                    j += closeLen;
                    continue;
                }
                j++;
            }
            if (foundEnd !== -1 && foundEnd > i + tickLen) {
                var codeContent = text.substring(i + tickLen, foundEnd);
                if (tickLen > 1 && codeContent.length >= 2 && codeContent[0] === " " && codeContent[codeContent.length - 1] === " " && /[^ ]/.test(codeContent)) {
                    codeContent = codeContent.substring(1, codeContent.length - 1);
                }
                var tok = "\uE000CODE_" + codeSpans.length + "\uE000";
                var safeCode = escapeHtml(codeContent);
                var html = '<span style="font-family: monospace; background-color: ' + codeBg + '; color: ' + codeColor + '; padding: 1px 4px; border-radius: 4px;">' + safeCode + '</span>';
                codeSpans.push(html);
                out += tok;
                i = foundEnd + tickLen;
                continue;
            }
            out += text.substring(i, i + tickLen);
            i += tickLen;
            continue;
        }
        out += ch;
        i++;
    }
    return out;
}

function inlineToHtml(src, opts) {
    if (!src || typeof src !== "string") return "";
    var options = opts || {};
    var linkColor = options.linkColor || "#5294e2";
    var defaultTextColor = _defaultTheme.lightMode ? "#1a1a1a" : (_defaultTheme.textColor || "#ffffff");
    var textColor = options.textColor || defaultTextColor;
    var mathColor = options.mathColor || textColor;
    var zoomVal = (typeof options.zoom === "number") ? options.zoom : _defaultZoom;
    var mathPtSize = options.mathPtSize || Math.max(10.0, 16.5 * zoomVal);
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

    // 0. Extraer código inline (`code`) y escapes \\ / \` ANTES de dólares o Markdown
    var escapes = [];
    var codeSpans = [];
    text = _extractCodeSpansFirst(text, escapes, codeSpans, codeBg, codeColor);

    // 0b. Proteger dólares escapados con barra (\$) para que no abran fórmulas matemáticas
    var escapedDollars = [];
    text = text.replace(/\\\$/g, function() {
        var token = "\uE000ESCDOLLAR_" + escapedDollars.length + "\uE000";
        escapedDollars.push("$");
        return token;
    });

    // 0c. Extraer fórmulas matemáticas inline ($formula$) de forma íntegra antes de escapes de Markdown
    var mathSpans = [];
    text = text.replace(/(?:^|[^\$])\$([^\s\$](?:[^\$\r\n]*?[^\s\$])?)\$(?!\$|\d)/g, function(match, formula) {
        var pfx = match.startsWith("$") ? "" : match[0];
        var token = "\uE000MATH_" + mathSpans.length + "\uE000";
        var mathOpts = Object.assign({}, options, { mathColor: mathColor, mathPtSize: mathPtSize });
        var rendered = renderLatexInline(formula, mathOpts);
        mathSpans.push(rendered);
        return pfx + token;
    });

    // 1. Escapar restantes caracteres con barra invertida
    text = text.replace(/\\([*_[\]~=\\`#\-!().|{}+>$])/g, function(match, char) {
        var token = "\uE000ESC_" + escapes.length + "\uE000";
        escapes.push(char);
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

    // 3. Extraer imágenes markdown y HTML (<img ...>) antes que enlaces
    // Con imageSkipMissing las locales inexistentes se reemplazan por su
    // texto (sin <img>) para no disparar warnings de carga. Necesita baseFolder
    // e imageExists(absPath)->bool; sin ellos se mantiene lo de siempre.
    function _normalizeImgLocal(pathStr) {
        if (!pathStr || typeof pathStr !== "string") return "";
        var s = pathStr.trim();
        if (s === "") return "";
        var isAbs = s.startsWith("/");
        var parts = s.split("/");
        var stack = [];
        for (var i = 0; i < parts.length; i++) {
            var seg = parts[i];
            if (seg === "" || seg === ".") continue;
            if (seg === "..") {
                if (stack.length > 0 && stack[stack.length - 1] !== "..") stack.pop();
                else if (!isAbs) stack.push("..");
                continue;
            }
            stack.push(seg);
        }
        return (isAbs ? "/" : "") + stack.join("/");
    }

    function _buildInlineImgHtml(rawUrl, altText, reqWidth, reqHeight, titleText) {
        var url = (rawUrl || "").trim();
        var alt = (altText || "");
        var isRemoteOrData = /^(?:https?:\/\/|data:)/i.test(url);
        var resolvedUrl = url;
        if (options.baseFolder && !isRemoteOrData && !/^(?:file:\/\/|\/)/i.test(resolvedUrl)) {
            resolvedUrl = _normalizeImgLocal(options.baseFolder + "/" + resolvedUrl);
        } else if (resolvedUrl.startsWith("/")) {
            resolvedUrl = _normalizeImgLocal(resolvedUrl);
        }
        if (options.imageSkipMissing && typeof options.imageExists === "function") {
            var probePath = "";
            if (isRemoteOrData) {
                probePath = "";
            } else if (/^file:\/\//i.test(url)) {
                probePath = url.replace(/^file:\/\/(localhost\/)?/i, "").replace(/[?#].*$/, "");
                try { probePath = decodeURIComponent(probePath); } catch (e) {}
                probePath = _normalizeImgLocal(probePath);
            } else if (url.startsWith("/")) {
                probePath = _normalizeImgLocal(url.replace(/[?#].*$/, ""));
            } else if (options.baseFolder) {
                probePath = _normalizeImgLocal(options.baseFolder + "/" + url.replace(/[?#].*$/, ""));
            }
            if (probePath !== "" && !options.imageExists(probePath)) {
                return escapeHtml("[" + alt + "]");
            }
        }
        var safeUrl = escapeHtml(resolvedUrl);
        var safeAlt = escapeHtml(alt);
        var titleAttr = titleText ? ' title="' + escapeHtml(titleText) + '"' : '';
        var w = (typeof reqWidth === "number" && reqWidth > 0) ? Math.round(reqWidth * zoomVal) : 0;
        var h = (typeof reqHeight === "number" && reqHeight > 0) ? Math.round(reqHeight * zoomVal) : 0;
        if (options.maxImgWidth && options.maxImgWidth > 0 && w > options.maxImgWidth) {
            if (h > 0 && w > 0) h = Math.max(1, Math.round(h * options.maxImgWidth / w));
            w = Math.round(options.maxImgWidth);
        }
        var widthAttr = w > 0 ? ' width="' + w + '"' : '';
        var heightAttr = h > 0 ? ' height="' + h + '"' : '';
        return '<img src="' + safeUrl + '" alt="' + safeAlt + '"' + widthAttr + heightAttr + titleAttr + ' />';
    }

    var images = [];
    var imgRegex = /!\[([^\]]*)\]\(((?:[^()\s]+|\([^()\s]*\))+)(?:\s+"([^"]*)")?\)/g;
    text = text.replace(imgRegex, function(match, rawAlt, url, title) {
        var parsedAlt = parseImageAlt(rawAlt);
        var token = "\uE000IMG_" + images.length + "\uE000";
        images.push(_buildInlineImgHtml(url, parsedAlt.alt, parsedAlt.width, parsedAlt.height, title));
        return token;
    });

    // 3b. Extraer etiquetas HTML <img ...> reales (fuera de inline code)
    var htmlImgRegex = /<img\b([^>]*?)\/?\s*>/gi;
    text = text.replace(htmlImgRegex, function(match, attrsStr) {
        var parsedTag = parseHtmlImgTag(match);
        if (!parsedTag || !parsedTag.src) return match;
        var token = "\uE000IMG_" + images.length + "\uE000";
        images.push(_buildInlineImgHtml(parsedTag.src, parsedTag.alt, parsedTag.width, parsedTag.height, parsedTag.title));
        return token;
    });

    // 3c. Preservar <a href="...">...</a> HTML simple (e.g. imágenes o texto enlazado en tablas/README)
    var links = [];
    var htmlAnchorRegex = /<a\b[^>]*\bhref\s*=\s*(?:"([^"]*)"|'([^']*)')[^>]*>([\s\S]*?)<\/a>/gi;
    text = text.replace(htmlAnchorRegex, function(match, h1, h2, innerBody) {
        var href = (h1 !== undefined ? h1 : (h2 || "")).trim();
        if (!href || /^(?:javascript|data:text\/html)/i.test(href)) href = "#";
        var token = "\uE000LINK_" + links.length + "\uE000";
        var safeBody = innerBody.replace(/<[^>]+>/g, "");
        var html = '<a href="' + escapeHtml(href) + '" style="color: ' + linkColor + '; text-decoration: none;">' + safeBody + '</a>';
        links.push(html);
        return token;
    });

    // 4. Autolinks: <https://...> o <http://...> o <mailto:...>
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
    // Usa (^|[^A-Za-z0-9:/=]) para aceptar delimitadores previos como _https://..._ sin confundir URLs pegadas a texto/atributos,
    // y preserva delimitadores de énfasis/formato de cierre (** __ ~~ == * _) si fueron abiertos antes en el párrafo.
    var bareRegex = /(^|[^A-Za-z0-9:/=])(https?:\/\/[^\s<>)"]+)/g;
    text = text.replace(bareRegex, function(match, prefix, url, offset, fullStr) {
        var urlOffset = offset + prefix.length;
        var paraStart = fullStr.lastIndexOf("\n\n", urlOffset);
        paraStart = (paraStart === -1) ? 0 : paraStart + 2;
        var before = fullStr.slice(paraStart, urlOffset);
        var trailing = "";
        var trimmed = true;
        while (trimmed && url.length > 0) {
            trimmed = false;
            var pm = url.match(/[.,:;!?]+$/);
            if (pm) {
                trailing = pm[0] + trailing;
                url = url.slice(0, -pm[0].length);
                trimmed = true;
                continue;
            }
            var dm = url.match(/(\*{3}|\*{2}|__|~~|==|\*|_)$/);
            if (dm) {
                var tok = dm[1];
                var isUnclosed = false;
                if (tok === "*" || tok === "_") {
                    var doubleTok = (tok === "*") ? /\*\*/g : /__/g;
                    var stripped = before.replace(doubleTok, "");
                    isUnclosed = (stripped.split(tok).length - 1) % 2 === 1;
                } else {
                    isUnclosed = (before.split(tok).length - 1) % 2 === 1;
                }
                if (isUnclosed) {
                    trailing = tok + trailing;
                    url = url.slice(0, -tok.length);
                    trimmed = true;
                }
            }
        }
        var token = "\uE000LINK_" + links.length + "\uE000";
        var safeUrl = escapeHtml(url);
        var html = '<a href="' + safeUrl + '" style="color: ' + linkColor + '; text-decoration: none;">' + safeUrl + '</a>';
        links.push(html);
        return prefix + token + trailing;
    });

    // 6. Proteger etiquetas HTML inline permitidas (<span>, <font>, <sup>, <sub>, <mark>, <u>, <b>, <i>, <s>, <del>, <ins>, <small>, <br>)
    var allowedTags = [];
    var preservedHtml = [];
    if (_htmlParser && typeof _htmlParser.sanitizeAndConvertInlineTags === "function") {
        var htmlRes = _htmlParser.sanitizeAndConvertInlineTags(text, options);
        text = htmlRes.text;
        preservedHtml = htmlRes.preserved;
    } else {
        text = text.replace(/<\/?(?:u|b|i|s|sup|sub)>|<br\s*\/?>/gi, function(tag) {
            var token = "\uE000ALLOWED_" + allowedTags.length + "\uE000";
            allowedTags.push(tag.toLowerCase());
            return token;
        });
    }

    // Escapar cualquier otro HTML (<script>, <div>, &, <, >, etc.)
    text = escapeHtml(text);

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

    // 7b. Preservar saltos de línea en RichText para no colapsar párrafos multilínea al desenfocar
    text = text.replace(/\r?\n/g, "<br/>");

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

    // 10c. Restaurar fórmulas matemáticas inline
    for (var m = 0; m < mathSpans.length; m++) {
        var mathHtml = mathSpans[m];
        text = text.replace("\uE000MATH_" + m + "\uE000", function() { return mathHtml; });
    }

    // 10d. Restaurar etiquetas HTML/CSS inline seguras después de procesar **/*/~
    if (_htmlParser && typeof _htmlParser.restorePreservedInlineTags === "function" && preservedHtml.length > 0) {
        text = _htmlParser.restorePreservedInlineTags(text, preservedHtml);
    } else if (allowedTags.length > 0) {
        for (var a = 0; a < allowedTags.length; a++) {
            var tagHtml = allowedTags[a];
            text = text.replace("\uE000ALLOWED_" + a + "\uE000", function() { return tagHtml; });
        }
    }

    // 11. Restaurar caracteres escapados a texto plano seguro
    for (var e = 0; e < escapes.length; e++) {
        var escText = escapeHtml(escapes[e]);
        text = text.replace("\uE000ESC_" + e + "\uE000", function() { return escText; });
    }

    // 11b. Restaurar dólares escapados a texto plano ($)
    for (var ed = 0; ed < escapedDollars.length; ed++) {
        text = text.replace("\uE000ESCDOLLAR_" + ed + "\uE000", "$");
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

    // Manejo especial para HTML inline pareado (<u>, <sup>, <sub>, <kbd>, <mark>, <ins>, <del>)
    if (marker === "<u>" || marker === "</u>" || marker === "<u></u>") {
        return _toggleTagWrap(text, s, e, "<u>", "</u>");
    }
    if (marker === "<sup>" || marker === "<sub>" || marker === "<kbd>" || marker === "<mark>" || marker === "<ins>" || marker === "<del>" || marker === "<small>") {
        var tagName = marker.slice(1, -1);
        return _toggleTagWrap(text, s, e, "<" + tagName + ">", "</" + tagName + ">");
    }
    if (typeof marker === "string" && (marker.startsWith("<color:") || marker.startsWith("<bg:")) && marker.endsWith(">")) {
        var isBg = marker.startsWith("<bg:");
        var cssProp = isBg ? "background-color" : "color";
        var cssVal = marker.slice(isBg ? 4 : 7, -1).trim();
        return _toggleStyledSpanWrap(text, s, e, cssProp, cssVal);
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

// Aplica, reemplaza o elimina un wrapper <span style="color|background-color: ...">...</span> sobre [s, e]
function _toggleStyledSpanWrap(text, s, e, cssProp, cssVal) {
    var selected = text.substring(s, e);
    var propRe = new RegExp("^<span\\b[^>]*style\\s*=\\s*[\"'][^\"']*\\b" + cssProp + "\\s*:[^\"']*[\"'][^>]*>([\\s\\S]*)<\\/span>$", "i");
    var innerM = selected.match(propRe);
    if (innerM) {
        if (!cssVal) {
            return { text: text.substring(0, s) + innerM[1] + text.substring(e), newSelStart: s, newSelEnd: s + innerM[1].length };
        }
        var openNew = '<span style="' + cssProp + ': ' + cssVal + ';">';
        var wrappedNew = openNew + innerM[1] + '</span>';
        return { text: text.substring(0, s) + wrappedNew + text.substring(e), newSelStart: s + openNew.length, newSelEnd: s + openNew.length + innerM[1].length };
    }

    var beforeTxt = text.substring(0, s);
    var afterTxt = text.substring(e);
    var openBeforeM = beforeTxt.match(new RegExp("<span\\b[^>]*style\\s*=\\s*[\"'][^\"']*\\b" + cssProp + "\\s*:[^\"']*[\"'][^>]*>$", "i"));
    if (openBeforeM && /^<\/span>/i.test(afterTxt)) {
        var oStart = s - openBeforeM[0].length;
        if (!cssVal || openBeforeM[0].toLowerCase().indexOf(cssVal.toLowerCase()) !== -1) {
            return {
                text: text.substring(0, oStart) + selected + afterTxt.substring(7),
                newSelStart: oStart,
                newSelEnd: oStart + selected.length
            };
        }
        var repOpen = '<span style="' + cssProp + ': ' + cssVal + ';">';
        return {
            text: text.substring(0, oStart) + repOpen + selected + afterTxt,
            newSelStart: oStart + repOpen.length,
            newSelEnd: oStart + repOpen.length + selected.length
        };
    }

    if (!cssVal) {
        return { text: text, newSelStart: s, newSelEnd: e };
    }
    var newOpen = '<span style="' + cssProp + ': ' + cssVal + ';">';
    var newClose = '</span>';
    return {
        text: text.substring(0, s) + newOpen + selected + newClose + text.substring(e),
        newSelStart: s + newOpen.length,
        newSelEnd: s + newOpen.length + selected.length
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

    // 1. Detectar código inline (`...` o ``...``) primero y enmascararlo antes que cualquier otro delimitador
    var maskedChars = src.split("");
    var iCode = 0;
    var nSrc = src.length;
    while (iCode < nSrc) {
        if (src[iCode] === "\\" && iCode + 1 < nSrc && (src[iCode + 1] === "\\" || src[iCode + 1] === "`")) {
            maskedChars[iCode] = "\uE000";
            maskedChars[iCode + 1] = "\uE000";
            iCode += 2;
            continue;
        }
        if (src[iCode] === "`") {
            var tLen = 1;
            while (iCode + tLen < nSrc && src[iCode + tLen] === "`") tLen++;
            var jCode = iCode + tLen;
            var endIdx = -1;
            while (jCode < nSrc && src[jCode] !== "\r" && src[jCode] !== "\n") {
                if (src[jCode] === "`") {
                    var cLen = 1;
                    while (jCode + cLen < nSrc && src[jCode + cLen] === "`") cLen++;
                    if (cLen === tLen) {
                        endIdx = jCode;
                        break;
                    }
                    jCode += cLen;
                    continue;
                }
                jCode++;
            }
            if (endIdx !== -1 && endIdx > iCode + tLen) {
                var spanEnd = endIdx + tLen;
                var delim = src.substring(iCode, iCode + tLen);
                spans.push({
                    type: "code",
                    start: iCode,
                    end: spanEnd,
                    openDelim: delim,
                    closeDelim: delim,
                    inner: src.substring(iCode + tLen, endIdx)
                });
                for (var k = iCode; k < spanEnd; k++) {
                    maskedChars[k] = "\uE000";
                }
                iCode = spanEnd;
                continue;
            }
            iCode += tLen;
            continue;
        }
        iCode++;
    }

    // Enmascarar caracteres escapados restantes con barra invertida para que no activen delimitadores falsos
    var maskedSrc = maskedChars.join("").replace(/\\([*_[\]~=\\`!#$])/g, "\uE000\uE000");
    var m;

    // 2. Imágenes markdown: ![alt](url) (slicing desde `src` para nunca filtrar \uE000 de maskedSrc)
    var imgRegex = /!\[([^\]]*)\]\(([^)]+)\)/g;
    while ((m = imgRegex.exec(maskedSrc)) !== null) {
        var imgAltLen = m[1].length;
        var imgUrlLen = m[2].length;
        var alt = src.substr(m.index + 2, imgAltLen);
        var url = src.substr(m.index + 2 + imgAltLen + 2, imgUrlLen);
        spans.push({ type: "image", start: m.index, end: m.index + m[0].length, openDelim: "![", closeDelim: "](" + url + ")", inner: alt, url: url });
    }

    // 3. Wikilinks: [[nota]] o [[nota|alias]]
    var wikiRegex = /\[\[([^\]\r\n]+)\]\]/g;
    while ((m = wikiRegex.exec(maskedSrc)) !== null) {
        var full = src.substr(m.index + 2, m[1].length);
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
        var labelLen = m[2].length;
        var urlLen = m[3].length;
        var label = src.substr(s + 1, labelLen);
        var url = src.substr(s + 1 + labelLen + 2, urlLen);
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

    // 9. Subrayado: <u>...</u>, <ins>...</ins> o &lt;u&gt;...&lt;/u&gt;
    var uRegex = /<(u|ins)>([\s\S]*?)<\/\1>|&lt;u&gt;([\s\S]*?)&lt;\/u&gt;/gi;
    while ((m = uRegex.exec(maskedSrc)) !== null) {
        var isEsc = (m[0].toLowerCase().indexOf("&lt;") === 0);
        var uTag = isEsc ? "u" : m[1].toLowerCase();
        var innerULen = (m[2] !== undefined ? m[2] : m[3]).length;
        var openULen = isEsc ? 9 : (uTag.length + 2);
        var inner = src.substr(m.index + openULen, innerULen);
        spans.push({ type: "underline", start: m.index, end: m.index + m[0].length, openDelim: isEsc ? "&lt;u&gt;" : ("<" + uTag + ">"), closeDelim: isEsc ? "&lt;/u&gt;" : ("</" + uTag + ">"), inner: inner });
    }

    // 9b. Teclas de atajo: <kbd>...</kbd> o &lt;kbd&gt;...&lt;/kbd&gt;
    var kbdRegex = /<kbd>([\s\S]*?)<\/kbd>|&lt;kbd&gt;([\s\S]*?)&lt;\/kbd&gt;/gi;
    while ((m = kbdRegex.exec(maskedSrc)) !== null) {
        var isEscKbd = (m[0].toLowerCase().indexOf("&lt;") === 0);
        var innerKbdLen = (m[1] !== undefined ? m[1] : m[2]).length;
        var openKbdLen = isEscKbd ? 11 : 5;
        var innerKbd = src.substr(m.index + openKbdLen, innerKbdLen);
        spans.push({
            type: "kbd",
            start: m.index,
            end: m.index + m[0].length,
            openDelim: isEscKbd ? "&lt;kbd&gt;" : "<kbd>",
            closeDelim: isEscKbd ? "&lt;/kbd&gt;" : "</kbd>",
            inner: innerKbd
        });
    }

    // 9c. Etiquetas HTML inline estilizadas: <span ...>...</span>, <font ...>...</font>, <sup>, <sub>, <mark>, <del>, <small>
    var styledSpanRe = /<(span|font)\b([^>]*)>((?:(?!<\1\b)[\s\S])*?)<\/\1>/gi;
    while ((m = styledSpanRe.exec(maskedSrc)) !== null) {
        var sTag = m[1].toLowerCase();
        var openFullLen = sTag.length + 1 + m[2].length + 1;
        var openRaw = src.substr(m.index, openFullLen);
        var closeRaw = src.substr(m.index + m[0].length - (sTag.length + 3), sTag.length + 3);
        var innerSpan = src.substr(m.index + openFullLen, m[3].length);
        spans.push({
            type: "html_span",
            tag: sTag,
            rawAttrs: src.substr(m.index + sTag.length + 1, m[2].length),
            start: m.index,
            end: m.index + m[0].length,
            openDelim: openRaw,
            closeDelim: closeRaw,
            inner: innerSpan
        });
    }

    var supSubRe = /<(sup|sub|mark|del|small)\b([^>]*)>([\s\S]*?)<\/\1>/gi;
    while ((m = supSubRe.exec(maskedSrc)) !== null) {
        var tagN = m[1].toLowerCase();
        var openL = 1 + m[1].length + m[2].length + 1;
        var openStr = src.substr(m.index, openL);
        var closeStr = src.substr(m.index + m[0].length - (m[1].length + 3), m[1].length + 3);
        var innerTxt = src.substr(m.index + openL, m[3].length);
        var spType = tagN === "mark" ? "highlight" : (tagN === "del" ? "strike" : tagN);
        spans.push({ type: spType, start: m.index, end: m.index + m[0].length, openDelim: openStr, closeDelim: closeStr, inner: innerTxt });
    }

    // 10. Resaltado: ==...==
    var hlRegex = /==([^\s=]|[^\s=][\s\S]*?[^\s=])==/g;
    while ((m = hlRegex.exec(maskedSrc)) !== null) {
        spans.push({ type: "highlight", start: m.index, end: m.index + m[0].length, openDelim: "==", closeDelim: "==", inner: src.substring(m.index + 2, m.index + m[0].length - 2) });
    }

    // 11. Fórmulas matemáticas inline: $formula$
    var mathRegex = /(?:^|[^\$])\$([^\s\$](?:[^\$\r\n]*?[^\s\$])?)\$(?!\$|\d)/g;
    while ((m = mathRegex.exec(maskedSrc)) !== null) {
        var pfxLen = m[0].startsWith("$") ? 0 : 1;
        var s = m.index + pfxLen;
        var inner = src.substr(s + 1, m[1].length);
        var totalLen = inner.length + 2;
        spans.push({
            type: "math",
            start: s,
            end: s + totalLen,
            openDelim: "$",
            closeDelim: "$",
            inner: inner
        });
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
        if (sp.type === "code" || sp.type === "kbd" || sp.type === "math" || sp.type === "image") {
            innerHtml = escapeHtml(sp.inner);
        } else {
            // Formatear recursivamente el contenido interno (soporta formatos anidados como **negrita *cursiva*** y [`código`](url))
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
            case "math":
                out += '<span style="font-family: monospace; font-style: italic; background-color: ' + (options.mathBg || codeBg) + '; color: ' + (options.mathColor || codeColor) + '; border-radius: 4px; padding: 1px 4px;">' + openHtml + innerHtml + closeHtml + '</span>';
                break;
            case "html_span": {
                var cssInline = "";
                if (_htmlParser && typeof _htmlParser.sanitizeAndConvertInlineTags === "function") {
                    var convTag = _htmlParser.sanitizeAndConvertInlineTags(sp.openDelim + "x" + sp.closeDelim, options);
                    var openRestored = _htmlParser.restorePreservedInlineTags(convTag.text, convTag.preserved);
                    var mStyle = openRestored.match(/^<span\s+style="([^"]*)"/i);
                    if (mStyle) cssInline = mStyle[1];
                }
                if (cssInline) {
                    out += '<span style="' + cssInline + '">' + openHtml + innerHtml + closeHtml + '</span>';
                } else {
                    out += openHtml + innerHtml + closeHtml;
                }
                break;
            }
            case "sup":
                out += '<sup>' + openHtml + innerHtml + closeHtml + '</sup>';
                break;
            case "sub":
                out += '<sub>' + openHtml + innerHtml + closeHtml + '</sub>';
                break;
            case "small":
                out += '<span style="font-size: small;">' + openHtml + innerHtml + closeHtml + '</span>';
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
        link: false,
        sup: false,
        sub: false,
        kbd: false,
        text_color: false,
        bg_color: false
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

    // 8. HTML inline (sup, sub, color, background-color)
    var supRe = /<sup>[\s\S]*?<\/sup>/gi;
    while ((m = supRe.exec(src)) !== null) {
        if (isSpanActive(m.index, m.index + m[0].length)) { res.sup = true; break; }
    }
    var subRe = /<sub>[\s\S]*?<\/sub>/gi;
    while ((m = subRe.exec(src)) !== null) {
        if (isSpanActive(m.index, m.index + m[0].length)) { res.sub = true; break; }
    }
    var kbdRe = /<kbd>[\s\S]*?<\/kbd>/gi;
    while ((m = kbdRe.exec(src)) !== null) {
        if (isSpanActive(m.index, m.index + m[0].length)) { res.kbd = true; break; }
    }
    var colorRe = /<(?:span|font)\b[^>]*(?:\bcolor\s*[:=])[^>]*>[\s\S]*?<\/(?:span|font)>/gi;
    while ((m = colorRe.exec(src)) !== null) {
        if (isSpanActive(m.index, m.index + m[0].length)) {
            if (/\bbackground(?:-color)?\s*:/i.test(m[0])) res.bg_color = true;
            if (/(?:^|[\s;"'])\bcolor\s*[:=]/i.test(m[0])) res.text_color = true;
            break;
        }
    }

    // Si solo se pasó un string seleccionado directamente (sin offsets s y e)
    if (s < 0 && e < 0 && src.length > 0) {
        if (/\*\*[\s\S]*?\*\*|__[\s\S]*?__/.test(src)) res.bold = true;
        if (/(?:^|[^\*])\*[\s\S]*?\*(?=[^\*]|$)|(?:^|[^_])_[\s\S]*?_(?=[^_]|$)/.test(src)) res.italic = true;
        if (/<(?:u|ins)>[\s\S]*?<\/(?:u|ins)>/i.test(src)) res.underline = true;
        if (/~~[\s\S]*?~~|<del>[\s\S]*?<\/del>/i.test(src)) res.strike = true;
        if (/==[\s\S]*?==|<mark\b[^>]*>[\s\S]*?<\/mark>/i.test(src)) res.highlight = true;
        if (/`[^`\r\n]+`/.test(src)) res.inline_code = true;
        if (/\[[^\]]+\]\([^)]+\)|\[\[[^\]]+\]\]/.test(src)) res.link = true;
        if (/<sup>[\s\S]*?<\/sup>/i.test(src)) res.sup = true;
        if (/<sub>[\s\S]*?<\/sub>/i.test(src)) res.sub = true;
        if (/<kbd>[\s\S]*?<\/kbd>/i.test(src)) res.kbd = true;
        if (/(?:^|[\s;"'])\bcolor\s*[:=]/i.test(src)) res.text_color = true;
        if (/\bbackground(?:-color)?\s*:/i.test(src)) res.bg_color = true;
    }

    return res;
}

// Normaliza texto plano de un elemento TextEdit o string, convirtiendo saltos U+2028/U+2029 a \n
function plainText(te) {
    if (!te) return "";
    var txt = (typeof te === "string") ? te : ((typeof te.getText === "function") ? te.getText(0, te.length) : (te.text || ""));
    return txt.replace(/[\u2028\u2029]/g, "\n");
}

// Encuentra la posición final de la siguiente palabra o delimitador hacia adelante (para Ctrl+Suprimir)
function findNextWordEnd(text, pos) {
    if (typeof text !== "string" || pos < 0) return 0;
    if (pos >= text.length) return text.length;
    var sub = text.substring(pos);
    var m = sub.match(/^(\s+|[^\s\w\u00C0-\u024F\u0400-\u04FF]+|[\w\u00C0-\u024F\u0400-\u04FF]+)\s*/);
    return pos + (m ? m[0].length : 1);
}

// Parsea sintaxis Obsidian ![alt|ancho](url) o ![alt|anchoxalto](url).
function parseImageAlt(rawAlt) {
    var s = (typeof rawAlt === "string") ? rawAlt : "";
    var pipeIdx = s.lastIndexOf("|");
    if (pipeIdx !== -1) {
        var suffix = s.substring(pipeIdx + 1).trim();
        var dimMatch = suffix.match(/^(\d{2,4})(?:x(\d{2,4}))?$/);
        if (dimMatch) {
            return {
                alt: s.substring(0, pipeIdx),
                width: parseInt(dimMatch[1], 10),
                height: dimMatch[2] ? parseInt(dimMatch[2], 10) : 0
            };
        }
    }
    return { alt: s, width: 0, height: 0 };
}

// Actualiza o inserta `|W` (estilo Obsidian) para la imagen imgIndex en raw.
function setImageWidthInRaw(raw, imgIndex, newWidth) {
    if (typeof raw !== "string") return raw;
    var idx = 0;
    var targetW = Math.max(40, Math.round(Number(newWidth) || 0));
    return raw.replace(/!\[([^\]]*)\]\(((?:[^()\s]+|\([^()\s]*\))+)(\s+"[^"]*")?\)/g, function(m, rawAlt, url, titlePart) {
        if (idx++ !== imgIndex) return m;
        var parsed = parseImageAlt(rawAlt);
        var nextAlt = parsed.alt + "|" + targetW;
        return "![" + nextAlt + "](" + url + (titlePart || "") + ")";
    });
}

function _readHtmlAttr(attrsStr, attrName) {
    if (!attrsStr || !attrName) return "";
    var re = new RegExp("(?:^|\\s)" + attrName + "\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'=<>`]+))", "i");
    var m = re.exec(attrsStr);
    if (!m) return "";
    return (m[1] !== undefined ? m[1] : (m[2] !== undefined ? m[2] : (m[3] || ""))).trim();
}

// Parsea una etiqueta HTML <img ...> extrayendo src, alt, width, height y title.
function parseHtmlImgTag(tagHtml) {
    if (!tagHtml || typeof tagHtml !== "string") return null;
    var m = tagHtml.match(/^<img\b([\s\S]*?)\/?\s*>$/i);
    if (!m) return null;
    var attrs = m[1] || "";
    var src = _readHtmlAttr(attrs, "src");
    if (!src) return null;
    var alt = _readHtmlAttr(attrs, "alt");
    var title = _readHtmlAttr(attrs, "title");
    var wRaw = _readHtmlAttr(attrs, "width");
    var hRaw = _readHtmlAttr(attrs, "height");
    var w = /^\d{1,5}(?:px)?$/i.test(wRaw) ? parseInt(wRaw, 10) : 0;
    var h = /^\d{1,5}(?:px)?$/i.test(hRaw) ? parseInt(hRaw, 10) : 0;
    return { src: src, alt: alt, width: w, height: h, title: title };
}

// Segmenta una celda de tabla en bloques ordenados de texto e imagen (Markdown o HTML <img>).
// Devuelve [] si la celda no contiene imágenes (vía rápida para solo-texto).
function extractTableCellSegments(raw) {
    if (!raw || typeof raw !== "string") return [];
    if (raw.indexOf("![") === -1 && !/<img\b/i.test(raw)) return [];

    // Enmascarar tramos de código `...` para no extraer <img> ni ![]() literales dentro de backticks.
    var codeMasks = [];
    var masked = raw.replace(/`+[^`\r\n]*`+/g, function(m) {
        var tok = "\uE001TCODE_" + codeMasks.length + "\uE001";
        codeMasks.push(m);
        return tok;
    });
    function unmask(s) {
        var out = s;
        for (var i = 0; i < codeMasks.length; i++) {
            out = out.replace("\uE001TCODE_" + i + "\uE001", function() { return codeMasks[i]; });
        }
        return out;
    }

    var tokenRe = /(<a\b[^>]*\bhref\s*=\s*(?:"([^"]*)"|'([^']*)')[^>]*>\s*(<img\b[^>]*>)\s*<\/a>)|(\[!\[([^\]]*)\]\(((?:[^()\s]+|\([^()\s]*\))+)(?:\s+"([^"]*)")?\)\]\(([^)]+)\))|(!\[([^\]]*)\]\(((?:[^()\s]+|\([^()\s]*\))+)(?:\s+"([^"]*)")?\))|(<img\b[^>]*\/?\s*>)/gi;
    var segments = [];
    var lastIdx = 0;
    var m;
    while ((m = tokenRe.exec(masked)) !== null) {
        if (m.index > lastIdx) {
            var pre = unmask(masked.substring(lastIdx, m.index)).replace(/^(?:\s|<br\s*\/?>)+|(?:\s|<br\s*\/?>)+$/gi, "");
            if (pre !== "") segments.push({ type: "text", text: pre });
        }
        if (m[1]) {
            var parsedLinkedHtml = parseHtmlImgTag(m[4]);
            if (parsedLinkedHtml && parsedLinkedHtml.src) {
                segments.push({
                    type: "image",
                    src: parsedLinkedHtml.src,
                    alt: parsedLinkedHtml.alt,
                    width: parsedLinkedHtml.width,
                    height: parsedLinkedHtml.height,
                    title: parsedLinkedHtml.title,
                    link: (m[2] !== undefined ? m[2] : (m[3] || "")).trim()
                });
            } else {
                segments.push({ type: "text", text: unmask(m[0]) });
            }
        } else if (m[5]) {
            var pLinkedMd = parseImageAlt(m[6]);
            segments.push({
                type: "image",
                src: m[7],
                alt: pLinkedMd.alt,
                width: pLinkedMd.width,
                height: pLinkedMd.height,
                title: m[8] || "",
                link: (m[9] || "").trim()
            });
        } else if (m[10]) {
            var pMd = parseImageAlt(m[11]);
            segments.push({
                type: "image",
                src: m[12],
                alt: pMd.alt,
                width: pMd.width,
                height: pMd.height,
                title: m[13] || "",
                link: ""
            });
        } else if (m[14]) {
            var pHtml = parseHtmlImgTag(m[14]);
            if (pHtml && pHtml.src) {
                segments.push({
                    type: "image",
                    src: pHtml.src,
                    alt: pHtml.alt,
                    width: pHtml.width,
                    height: pHtml.height,
                    title: pHtml.title,
                    link: ""
                });
            } else {
                segments.push({ type: "text", text: unmask(m[0]) });
            }
        }
        lastIdx = tokenRe.lastIndex;
    }
    if (segments.length === 0) return [];
    if (lastIdx < masked.length) {
        var tail = unmask(masked.substring(lastIdx)).replace(/^(?:\s|<br\s*\/?>)+|(?:\s|<br\s*\/?>)+$/gi, "");
        if (tail !== "") segments.push({ type: "text", text: tail });
    }
    return segments;
}
