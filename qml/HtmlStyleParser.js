.pragma library

// HtmlStyleParser.js — Parser nativo seguro y ligero de HTML y CSS básico (estilo GitHub README)
// 100 % JavaScript puro: sanitización XSS, parsing de CSS inline/<style>, árbol AST mixto HTML + Markdown
// y compilación de etiquetas inline a HTML seguro compatible con Qt RichText (sin QtWebEngine).

var NAMED_CSS_COLORS = {
    "transparent": "transparent",
    "black": "#000000", "white": "#ffffff", "silver": "#c0c0c0", "gray": "#808080", "grey": "#808080",
    "darkgray": "#a9a9a9", "darkgrey": "#a9a9a9", "lightgray": "#d3d3d3", "lightgrey": "#d3d3d3",
    "dimgray": "#696969", "dimgrey": "#696969", "slategray": "#708090", "slategrey": "#708090",
    "red": "#ff4444", "crimson": "#dc143c", "firebrick": "#b22222", "darkred": "#8b0000",
    "tomato": "#ff6347", "coral": "#ff7f50", "salmon": "#fa8072", "indianRed": "#cd5c5c",
    "orange": "#ffa500", "darkorange": "#ff8c00", "orangered": "#ff4500", "gold": "#ffd700",
    "yellow": "#ffff00", "khaki": "#f0e68c", "amber": "#ffbf00",
    "green": "#22c55e", "lime": "#00ff00", "limegreen": "#32cd32", "forestgreen": "#228b22",
    "seagreen": "#2e8b57", "mediumseagreen": "#3cb371", "springgreen": "#00ff7f", "olive": "#808000",
    "teal": "#008080", "cyan": "#00ffff", "aqua": "#00ffff", "turquoise": "#40e0d0",
    "skyblue": "#87ceeb", "deepskyblue": "#00bfff", "dodgerblue": "#1e90ff",
    "blue": "#3b82f6", "royalblue": "#4169e1", "steelblue": "#4682b4", "navy": "#000080",
    "midnightblue": "#191970", "indigo": "#4b0082",
    "purple": "#a855f7", "rebeccapurple": "#663399", "blueviolet": "#8a2be2",
    "mediumpurple": "#9370db", "violet": "#ee82ee", "plum": "#dda0dd", "orchid": "#da70d6",
    "magenta": "#ff00ff", "fuchsia": "#ff00ff", "pink": "#ffc0cb", "hotpink": "#ff69b4",
    "deeppink": "#ff1493", "brown": "#a52a2a", "chocolate": "#d2691e", "tan": "#d2b48c",
    "maroon": "#800000"
};

function _escapeHtml(text) {
    if (!text || typeof text !== "string") return "";
    return text
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
}

function _decodeBasicEntities(text) {
    if (!text || typeof text !== "string") return "";
    return text
        .replace(/&nbsp;/gi, " ")
        .replace(/&amp;/gi, "&")
        .replace(/&lt;/gi, "<")
        .replace(/&gt;/gi, ">")
        .replace(/&quot;/gi, '"')
        .replace(/&#39;|&apos;/gi, "'")
        .replace(/&#(\d+);/g, function(_, dec) {
            var code = parseInt(dec, 10);
            return (code > 0 && code < 65536) ? String.fromCharCode(code) : _;
        })
        .replace(/&#x([0-9a-f]+);/gi, function(_, hex) {
            var code = parseInt(hex, 16);
            return (code > 0 && code < 65536) ? String.fromCharCode(code) : _;
        });
}

function isSafeUrl(url) {
    if (!url || typeof url !== "string") return false;
    var u = url.trim().toLowerCase().replace(/[\x00-\x20]/g, "");
    if (u === "") return false;
    if (u.startsWith("javascript:") || u.startsWith("vbscript:") || u.startsWith("data:text/html")) {
        return false;
    }
    return true;
}

function _toHexByte(n) {
    var v = Math.max(0, Math.min(255, Math.round(n)));
    return (v < 16 ? "0" : "") + v.toString(16);
}

function _rgbToCss(r, g, b, alpha) {
    var ri = Math.max(0, Math.min(255, Math.round(r)));
    var gi = Math.max(0, Math.min(255, Math.round(g)));
    var bi = Math.max(0, Math.min(255, Math.round(b)));
    if (typeof alpha === "number" && alpha >= 0 && alpha < 0.999) {
        return "rgba(" + ri + ", " + gi + ", " + bi + ", " + (Math.round(alpha * 1000) / 1000) + ")";
    }
    return "#" + _toHexByte(ri) + _toHexByte(gi) + _toHexByte(bi);
}

function _hslToRgbStr(hDeg, sPct, lPct, alpha) {
    var h = ((Number(hDeg) % 360) + 360) % 360 / 360.0;
    var s = Math.max(0, Math.min(1, Number(sPct) / 100.0));
    var l = Math.max(0, Math.min(1, Number(lPct) / 100.0));
    function hue2rgb(p, q, t) {
        if (t < 0) t += 1;
        if (t > 1) t -= 1;
        if (t < 1 / 6) return p + (q - p) * 6 * t;
        if (t < 1 / 2) return q;
        if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
        return p;
    }
    var r, g, b;
    if (s === 0) {
        r = g = b = l;
    } else {
        var q = l < 0.5 ? l * (1 + s) : l + s - l * s;
        var p = 2 * l - q;
        r = hue2rgb(p, q, h + 1 / 3);
        g = hue2rgb(p, q, h);
        b = hue2rgb(p, q, h - 1 / 3);
    }
    return _rgbToCss(r * 255, g * 255, b * 255, alpha);
}

function resolveCssColor(rawVal, themeColors) {
    if (!rawVal || typeof rawVal !== "string") return "";
    var v = rawVal.trim().replace(/!important/i, "").trim();
    if (!v) return "";
    var low = v.toLowerCase();
    if (low === "none" || low === "inherit" || low === "initial" || low === "unset") return "";
    if (/url\s*\(|expression\s*\(/i.test(low)) return "";

    // Tokens CSS variables básicos integrados al tema de Notas
    var varMatch = v.match(/^var\(\s*(--[a-zA-Z0-9_-]+)(?:\s*,\s*([^)]+))?\s*\)$/);
    if (varMatch) {
        var tc = themeColors || {};
        var key = varMatch[1].toLowerCase();
        var mapVar = {
            "--accent": tc.accent || "#8ab4f8",
            "--primary": tc.accent || "#8ab4f8",
            "--text": tc.text || tc.textColor || "#ffffff",
            "--fg": tc.text || tc.textColor || "#ffffff",
            "--surface": tc.surface || "#1c1815",
            "--bg": tc.surface || "#1c1815",
            "--muted": tc.muted || "#9aa0a6",
            "--danger": tc.danger || "#ff5555",
            "--red": tc.danger || "#ff5555",
            "--success": tc.success || "#3fb950",
            "--green": tc.success || "#3fb950",
            "--warning": tc.warning || "#d29922",
            "--yellow": tc.warning || "#d29922"
        };
        if (mapVar[key]) return String(mapVar[key]);
        if (varMatch[2]) return resolveCssColor(varMatch[2], themeColors);
        return "";
    }

    if (NAMED_CSS_COLORS[low]) return NAMED_CSS_COLORS[low];

    // #RGB, #RGBA, #RRGGBB, #RRGGBBAA
    if (v[0] === "#") {
        var hex = v.substring(1);
        if (/^[0-9a-f]{3}$/i.test(hex)) {
            return "#" + hex[0] + hex[0] + hex[1] + hex[1] + hex[2] + hex[2];
        }
        if (/^[0-9a-f]{4}$/i.test(hex)) {
            var r4 = parseInt(hex[0] + hex[0], 16);
            var g4 = parseInt(hex[1] + hex[1], 16);
            var b4 = parseInt(hex[2] + hex[2], 16);
            var a4 = Math.round((parseInt(hex[3] + hex[3], 16) / 255.0) * 1000) / 1000;
            return "rgba(" + r4 + ", " + g4 + ", " + b4 + ", " + a4 + ")";
        }
        if (/^[0-9a-f]{6}$/i.test(hex)) {
            return "#" + hex.toLowerCase();
        }
        if (/^[0-9a-f]{8}$/i.test(hex)) {
            var r8 = parseInt(hex.substring(0, 2), 16);
            var g8 = parseInt(hex.substring(2, 4), 16);
            var b8 = parseInt(hex.substring(4, 6), 16);
            var a8 = Math.round((parseInt(hex.substring(6, 8), 16) / 255.0) * 1000) / 1000;
            return "rgba(" + r8 + ", " + g8 + ", " + b8 + ", " + a8 + ")";
        }
        return "";
    }

    // rgb() / rgba()
    var rgbM = v.match(/^rgba?\(\s*(\d{1,3})\s*[,\s]\s*(\d{1,3})\s*[,\s]\s*(\d{1,3})(?:\s*[,/]\s*([0-9.]+%?))?\s*\)$/i);
    if (rgbM) {
        var rr = Math.max(0, Math.min(255, parseInt(rgbM[1], 10)));
        var gg = Math.max(0, Math.min(255, parseInt(rgbM[2], 10)));
        var bb = Math.max(0, Math.min(255, parseInt(rgbM[3], 10)));
        var aa = undefined;
        if (rgbM[4] !== undefined) {
            var aaRaw = rgbM[4];
            aa = aaRaw.endsWith("%") ? (parseFloat(aaRaw) / 100.0) : parseFloat(aaRaw);
            aa = Math.max(0, Math.min(1, isNaN(aa) ? 1 : aa));
        }
        return _rgbToCss(rr, gg, bb, aa);
    }

    // hsl() / hsla()
    var hslM = v.match(/^hsla?\(\s*(-?\d+(?:\.\d+)?)(?:deg)?\s*[,\s]\s*(\d+(?:\.\d+)?)%\s*[,\s]\s*(\d+(?:\.\d+)?)%(?:\s*[,/]\s*([0-9.]+%?))?\s*\)$/i);
    if (hslM) {
        var ha = undefined;
        if (hslM[4] !== undefined) {
            ha = hslM[4].endsWith("%") ? (parseFloat(hslM[4]) / 100.0) : parseFloat(hslM[4]);
            ha = Math.max(0, Math.min(1, isNaN(ha) ? 1 : ha));
        }
        return _hslToRgbStr(parseFloat(hslM[1]), parseFloat(hslM[2]), parseFloat(hslM[3]), ha);
    }

    return "";
}

function parseLengthPx(rawVal, basePx) {
    if (rawVal === undefined || rawVal === null) return NaN;
    var s = String(rawVal).trim().toLowerCase();
    if (!s || s === "auto") return NaN;
    var base = (typeof basePx === "number" && basePx > 0) ? basePx : 14;
    if (s === "xx-small") return Math.round(base * 0.65);
    if (s === "x-small" || s === "smaller") return Math.round(base * 0.8);
    if (s === "small") return Math.round(base * 0.9);
    if (s === "medium") return Math.round(base);
    if (s === "large" || s === "larger") return Math.round(base * 1.2);
    if (s === "x-large") return Math.round(base * 1.45);
    if (s === "xx-large") return Math.round(base * 1.8);

    var m = s.match(/^(-?\d+(?:\.\d+)?)(px|em|rem|pt|%)?$/);
    if (!m) return NaN;
    var num = parseFloat(m[1]);
    var unit = m[2] || "px";
    if (unit === "px") return num;
    if (unit === "pt") return num * 1.333;
    if (unit === "em" || unit === "rem") return num * base;
    if (unit === "%") return (num / 100.0) * base;
    return NaN;
}

function parseAttributes(attrStr) {
    var attrs = {};
    if (!attrStr || typeof attrStr !== "string") return attrs;
    var re = /([a-zA-Z_:][a-zA-Z0-9_.:-]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
    var m;
    while ((m = re.exec(attrStr)) !== null) {
        var name = m[1].toLowerCase();
        if (name.startsWith("on")) continue; // Bloquear manejadores JS inline (onclick, onerror, etc.)
        var val = (m[2] !== undefined ? m[2] : (m[3] !== undefined ? m[3] : (m[4] !== undefined ? m[4] : "")));
        attrs[name] = _decodeBasicEntities(val);
    }
    return attrs;
}

function parseStyleDeclaration(styleStr, attrs, opts) {
    var out = {
        textAlign: "",
        color: "",
        backgroundColor: "",
        fontSizePx: 0,
        fontWeight: "",
        fontStyle: "",
        textDecoration: "",
        fontFamily: "",
        paddingTop: 0,
        paddingRight: 0,
        paddingBottom: 0,
        paddingLeft: 0,
        marginTop: 0,
        marginBottom: 0,
        borderWidth: 0,
        borderColor: "",
        borderLeftWidth: 0,
        borderLeftColor: "",
        borderRadius: 0,
        widthPx: 0,
        widthPct: 0,
        maxWidthPx: 0,
        heightPx: 0,
        opacity: 1.0,
        display: "",
        hidden: false
    };

    var options = opts || {};
    var themeColors = options.themeColors || {};
    var basePx = (typeof options.baseFontPx === "number" && options.baseFontPx > 0) ? options.baseFontPx : 14;
    var a = attrs || {};

    if (a.align) {
        var al = String(a.align).trim().toLowerCase();
        if (al === "left" || al === "center" || al === "right" || al === "justify") {
            out.textAlign = al;
        }
    }
    if (a.color) {
        var cAttr = resolveCssColor(String(a.color), themeColors);
        if (cAttr) out.color = cAttr;
    }
    if (a.bgcolor) {
        var bgAttr = resolveCssColor(String(a.bgcolor), themeColors);
        if (bgAttr) out.backgroundColor = bgAttr;
    }
    if (a.width) {
        var ws = String(a.width).trim();
        if (ws.endsWith("%")) {
            var wp = parseFloat(ws);
            if (!isNaN(wp) && wp > 0) out.widthPct = Math.max(0.05, Math.min(1.0, wp / 100.0));
        } else {
            var wPx = parseLengthPx(ws, basePx);
            if (!isNaN(wPx) && wPx > 0) out.widthPx = Math.round(wPx);
        }
    }
    if (a.height) {
        var hPx = parseLengthPx(a.height, basePx);
        if (!isNaN(hPx) && hPx > 0) out.heightPx = Math.round(hPx);
    }

    if (!styleStr || typeof styleStr !== "string") return out;

    var decls = styleStr.split(";");
    for (var i = 0; i < decls.length; i++) {
        var item = decls[i].trim();
        if (!item) continue;
        var colon = item.indexOf(":");
        if (colon === -1) continue;
        var prop = item.substring(0, colon).trim().toLowerCase();
        var val = item.substring(colon + 1).trim();
        if (!val) continue;
        var lowVal = val.toLowerCase().replace(/!important/i, "").trim();

        if (prop === "text-align") {
            if (lowVal === "left" || lowVal === "center" || lowVal === "right" || lowVal === "justify") {
                out.textAlign = lowVal;
            }
        } else if (prop === "color") {
            var cc = resolveCssColor(val, themeColors);
            if (cc) out.color = cc;
        } else if (prop === "background-color" || prop === "background") {
            // Para linear-gradient/background compuesto, extraer primer color válido
            var bgc = resolveCssColor(val, themeColors);
            if (!bgc) {
                var colorTok = val.match(/(#[0-9a-f]{3,8}|rgba?\([^)]+\)|hsla?\([^)]+\)|var\([^)]+\))/i);
                if (colorTok) bgc = resolveCssColor(colorTok[1], themeColors);
            }
            if (bgc) out.backgroundColor = bgc;
        } else if (prop === "font-size") {
            var fs = parseLengthPx(lowVal, basePx);
            if (!isNaN(fs) && fs >= 8 && fs <= 72) out.fontSizePx = Math.round(fs);
        } else if (prop === "font-weight") {
            var fwNum = parseInt(lowVal, 10);
            if (lowVal === "bold" || lowVal === "bolder" || (!isNaN(fwNum) && fwNum >= 600)) {
                out.fontWeight = "bold";
            } else if (lowVal === "normal" || (!isNaN(fwNum) && fwNum < 500)) {
                out.fontWeight = "normal";
            }
        } else if (prop === "font-style") {
            if (lowVal === "italic" || lowVal === "oblique") out.fontStyle = "italic";
        } else if (prop === "text-decoration" || prop === "text-decoration-line") {
            if (lowVal.indexOf("underline") !== -1) out.textDecoration = "underline";
            else if (lowVal.indexOf("line-through") !== -1) out.textDecoration = "line-through";
        } else if (prop === "font-family") {
            if (lowVal.indexOf("mono") !== -1) out.fontFamily = "monospace";
        } else if (prop === "padding") {
            var pParts = lowVal.split(/\s+/).map(function(x) { return Math.max(0, Math.round(parseLengthPx(x, basePx) || 0)); });
            if (pParts.length === 1) {
                out.paddingTop = out.paddingRight = out.paddingBottom = out.paddingLeft = pParts[0];
            } else if (pParts.length === 2) {
                out.paddingTop = out.paddingBottom = pParts[0];
                out.paddingRight = out.paddingLeft = pParts[1];
            } else if (pParts.length === 3) {
                out.paddingTop = pParts[0];
                out.paddingRight = out.paddingLeft = pParts[1];
                out.paddingBottom = pParts[2];
            } else if (pParts.length >= 4) {
                out.paddingTop = pParts[0];
                out.paddingRight = pParts[1];
                out.paddingBottom = pParts[2];
                out.paddingLeft = pParts[3];
            }
        } else if (prop === "padding-top" || prop === "padding-right" || prop === "padding-bottom" || prop === "padding-left") {
            var pOne = parseLengthPx(lowVal, basePx);
            if (!isNaN(pOne) && pOne >= 0) {
                if (prop === "padding-top") out.paddingTop = Math.round(pOne);
                else if (prop === "padding-right") out.paddingRight = Math.round(pOne);
                else if (prop === "padding-bottom") out.paddingBottom = Math.round(pOne);
                else out.paddingLeft = Math.round(pOne);
            }
        } else if (prop === "margin") {
            var mParts = lowVal.split(/\s+/);
            if (mParts.length >= 2 && mParts[1] === "auto" && !out.textAlign) {
                out.textAlign = "center";
            }
            var mTop = parseLengthPx(mParts[0], basePx);
            if (!isNaN(mTop) && mTop >= 0) {
                out.marginTop = Math.round(mTop);
                out.marginBottom = (mParts.length >= 3 && !isNaN(parseLengthPx(mParts[2], basePx)))
                    ? Math.round(parseLengthPx(mParts[2], basePx))
                    : out.marginTop;
            }
        } else if (prop === "margin-top") {
            var mt = parseLengthPx(lowVal, basePx);
            if (!isNaN(mt) && mt >= 0) out.marginTop = Math.round(mt);
        } else if (prop === "margin-bottom") {
            var mb = parseLengthPx(lowVal, basePx);
            if (!isNaN(mb) && mb >= 0) out.marginBottom = Math.round(mb);
        } else if (prop === "border") {
            if (lowVal === "none" || lowVal === "0") {
                out.borderWidth = 0;
            } else {
                var bwM = val.match(/(\d+(?:\.\d+)?)px/i);
                out.borderWidth = bwM ? Math.max(1, Math.round(parseFloat(bwM[1]))) : 1;
                var bColM = val.replace(/\b\d+(?:\.\d+)?px\b/gi, "").replace(/\b(?:solid|dashed|dotted|double|none)\b/gi, "").trim();
                var bCol = resolveCssColor(bColM, themeColors);
                if (bCol) out.borderColor = bCol;
            }
        } else if (prop === "border-left") {
            var blwM = val.match(/(\d+(?:\.\d+)?)px/i);
            out.borderLeftWidth = blwM ? Math.max(1, Math.round(parseFloat(blwM[1]))) : 3;
            var blColM = val.replace(/\b\d+(?:\.\d+)?px\b/gi, "").replace(/\b(?:solid|dashed|dotted|double|none)\b/gi, "").trim();
            var blCol = resolveCssColor(blColM, themeColors);
            if (blCol) out.borderLeftColor = blCol;
        } else if (prop === "border-radius") {
            var br = parseLengthPx(lowVal.split(/\s+/)[0], basePx);
            if (!isNaN(br) && br >= 0) out.borderRadius = Math.round(br);
        } else if (prop === "width") {
            if (lowVal.endsWith("%")) {
                var pct = parseFloat(lowVal);
                if (!isNaN(pct) && pct > 0) out.widthPct = Math.max(0.05, Math.min(1.0, pct / 100.0));
            } else {
                var wp2 = parseLengthPx(lowVal, basePx);
                if (!isNaN(wp2) && wp2 > 0) out.widthPx = Math.round(wp2);
            }
        } else if (prop === "max-width") {
            var mwp = parseLengthPx(lowVal, basePx);
            if (!isNaN(mwp) && mwp > 0) out.maxWidthPx = Math.round(mwp);
        } else if (prop === "height") {
            var hp2 = parseLengthPx(lowVal, basePx);
            if (!isNaN(hp2) && hp2 > 0) out.heightPx = Math.round(hp2);
        } else if (prop === "opacity") {
            var op = parseFloat(lowVal);
            if (!isNaN(op)) out.opacity = Math.max(0, Math.min(1, op));
        } else if (prop === "display") {
            out.display = lowVal;
            if (lowVal === "none") out.hidden = true;
        }
    }

    return out;
}

// Extrae reglas CSS inocuas de bloques <style>...</style> (solo selectores .class, #id y tag)
function extractStyleSheet(html) {
    var rules = {};
    var cleaned = (html || "").replace(/<style\b[^>]*>([\s\S]*?)<\/style>/gi, function(_, cssText) {
        var ruleRe = /([^{}]+)\{([^{}]+)\}/g;
        var m;
        while ((m = ruleRe.exec(cssText)) !== null) {
            var sels = m[1].split(",");
            var body = m[2].trim();
            for (var s = 0; s < sels.length; s++) {
                var sel = sels[s].trim().toLowerCase();
                if (/^[.#]?[a-z0-9_-]+$/.test(sel)) {
                    rules[sel] = (rules[sel] ? (rules[sel] + "; ") : "") + body;
                }
            }
        }
        return "";
    });
    return { cleanedHtml: cleaned, rules: rules };
}

function _lookupSheetStyle(rules, tag, attrs) {
    if (!rules) return "";
    var parts = [];
    if (tag && rules[tag]) parts.push(rules[tag]);
    if (attrs && attrs["class"]) {
        var classes = String(attrs["class"]).trim().split(/\s+/);
        for (var i = 0; i < classes.length; i++) {
            var key = "." + classes[i].toLowerCase();
            if (rules[key]) parts.push(rules[key]);
        }
    }
    if (attrs && attrs.id) {
        var idKey = "#" + String(attrs.id).trim().toLowerCase();
        if (rules[idKey]) parts.push(rules[idKey]);
    }
    return parts.join("; ");
}

function sanitizeHtml(html) {
    if (!html || typeof html !== "string") return "";
    return html
        .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, "")
        .replace(/<iframe\b[^>]*>[\s\S]*?<\/iframe>/gi, "")
        .replace(/<\/?(?:script|iframe|object|embed|applet|meta|base|form)\b[^>]*>/gi, "")
        .replace(/<!--[\s\S]*?-->/g, "")
        .replace(/\son[a-z]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)/gi, "")
        .replace(/(href|src|action)\s*=\s*(?:"\s*(?:javascript|vbscript|data\s*:\s*text\/html):[^"]*"|'\s*(?:javascript|vbscript|data\s*:\s*text\/html):[^']*')/gi, '$1="#"');
}

// Convierte estilos y etiquetas HTML inline comunes (<span>, <font>, <sup>, <sub>, <mark>, <small>,
// <big>, <ins>, <del>, <s>, <b>, <strong>, <i>, <em>, <u>, <kbd>, <abbr>, <code>, <br>) a HTML limpio
// compatible con Text.RichText / TextEdit.RichText de Qt sin filtrar scripts ni atributos peligrosos.
function sanitizeAndConvertInlineTags(text, opts, sheetRules) {
    if (!text || typeof text !== "string") return "";
    var options = opts || {};
    var themeColors = options.themeColors || {
        accent: options.linkColor || "#8ab4f8",
        text: options.textColor || "#ffffff",
        surface: options.surface || "#1c1815",
        muted: options.dimColor || "#9aa0a6"
    };
    var hlBg = options.highlightBg || "rgba(240, 198, 116, 0.35)";
    var codeBg = options.codeBg || "rgba(255, 255, 255, 0.08)";
    var codeColor = options.codeColor || "#f0f0f0";
    var basePx = (typeof options.baseFontPx === "number" && options.baseFontPx > 0) ? options.baseFontPx : 14;

    var preserved = [];
    function pushPreserved(htmlOut) {
        var tok = "\uE000HTMLI_" + preserved.length + "\uE000";
        preserved.push(htmlOut);
        return tok;
    }

    // 1. Etiquetas vacías o de salto
    var work = text.replace(/<(br|wbr)\s*\/?>/gi, function(_, t) {
        return pushPreserved(t.toLowerCase() === "br" ? "<br/>" : "");
    });

    // 2. Etiquetas inline permitidas (apertura y cierre), traduciendo <span style> / <font> / <mark>
    var tagRe = /<(\/?)([a-zA-Z][a-zA-Z0-9]*)\b([^>]*)>/g;
    work = work.replace(tagRe, function(full, slash, rawTag, rawAttrs) {
        var tag = rawTag.toLowerCase();
        var isClose = (slash === "/");

        if (tag === "b" || tag === "strong") return pushPreserved(isClose ? "</b>" : "<b>");
        if (tag === "i" || tag === "em") return pushPreserved(isClose ? "</i>" : "<i>");
        if (tag === "u" || tag === "ins") return pushPreserved(isClose ? "</u>" : "<u>");
        if (tag === "s" || tag === "del" || tag === "strike") return pushPreserved(isClose ? "</s>" : "<s>");
        if (tag === "sup") return pushPreserved(isClose ? "</sup>" : "<sup>");
        if (tag === "sub") return pushPreserved(isClose ? "</sub>" : "<sub>");
        if (tag === "small") return pushPreserved(isClose ? "</span>" : '<span style="font-size: small;">');
        if (tag === "big") return pushPreserved(isClose ? "</span>" : '<span style="font-size: large;">');
        if (tag === "abbr") return pushPreserved(isClose ? "</span>" : '<span style="text-decoration: underline;">');

        if (tag === "code") {
            return pushPreserved(isClose
                ? "</span>"
                : '<span style="font-family: monospace; background-color: ' + codeBg + '; color: ' + codeColor + '; border-radius: 4px; padding: 1px 4px;">');
        }

        if (tag === "mark") {
            if (isClose) return pushPreserved("</span>");
            var mAttrs = parseAttributes(rawAttrs);
            var mSt = parseStyleDeclaration(mAttrs.style || "", mAttrs, { themeColors: themeColors, baseFontPx: basePx });
            var mBg = mSt.backgroundColor || hlBg;
            var mCss = "background-color: " + mBg + "; padding: 0 3px; border-radius: 3px;";
            if (mSt.color) mCss += " color: " + mSt.color + ";";
            return pushPreserved('<span style="' + mCss + '">');
        }

        if (tag === "span" || tag === "font") {
            if (isClose) return pushPreserved("</span>");
            var attrs = parseAttributes(rawAttrs);
            var extraCss = _lookupSheetStyle(sheetRules, tag, attrs);
            var combinedCss = (extraCss ? (extraCss + "; ") : "") + (attrs.style || "");
            var st = parseStyleDeclaration(combinedCss, attrs, { themeColors: themeColors, baseFontPx: basePx });
            if (tag === "font" && attrs.size && st.fontSizePx === 0) {
                var fSz = parseInt(attrs.size, 10);
                var fontMap = { 1: 10, 2: 12, 3: 14, 4: 16, 5: 20, 6: 24, 7: 30 };
                if (fontMap[fSz]) st.fontSizePx = fontMap[fSz];
            }
            var cssParts = [];
            if (st.color) cssParts.push("color: " + st.color);
            if (st.backgroundColor && st.backgroundColor !== "transparent") cssParts.push("background-color: " + st.backgroundColor);
            if (st.fontSizePx > 0) cssParts.push("font-size: " + st.fontSizePx + "px");
            if (st.fontWeight) cssParts.push("font-weight: " + st.fontWeight);
            if (st.fontStyle) cssParts.push("font-style: " + st.fontStyle);
            if (st.textDecoration) cssParts.push("text-decoration: " + st.textDecoration);
            if (st.fontFamily === "monospace") cssParts.push("font-family: monospace");
            return pushPreserved(cssParts.length > 0 ? ('<span style="' + cssParts.join("; ") + ';">') : "<span>");
        }

        // Otras etiquetas no inline seguras se escapan
        return full;
    });

    return { text: work, preserved: preserved };
}

function restorePreservedInlineTags(htmlText, preserved) {
    if (!preserved || preserved.length === 0) return htmlText;
    var out = htmlText;
    for (var i = 0; i < preserved.length; i++) {
        var val = preserved[i];
        out = out.replace("\uE000HTMLI_" + i + "\uE000", function() { return val; });
    }
    return out;
}

// Elige URL de <picture> según preferencia de color (dark vs light) y Theme.lightMode
function resolvePictureSrc(innerHtml, lightMode) {
    if (!innerHtml || typeof innerHtml !== "string") return { src: "", alt: "", width: 0, height: 0, align: "" };
    var targetScheme = lightMode ? "light" : "dark";
    var chosenSrc = "";
    var sourceRe = /<source\b([^>]*?)\/?\s*>/gi;
    var m;
    while ((m = sourceRe.exec(innerHtml)) !== null) {
        var attrs = parseAttributes(m[1] || "");
        var media = (attrs.media || "").toLowerCase();
        var srcset = (attrs.srcset || attrs.src || "").trim().split(/[\s,]+/)[0];
        if (!srcset || !isSafeUrl(srcset)) continue;
        if (media.indexOf("prefers-color-scheme") !== -1) {
            if (media.indexOf(targetScheme) !== -1) {
                chosenSrc = srcset;
                break;
            }
        } else if (!chosenSrc) {
            chosenSrc = srcset;
        }
    }
    var imgMatch = innerHtml.match(/<img\b([^>]*?)\/?\s*>/i);
    var imgAttrs = imgMatch ? parseAttributes(imgMatch[1] || "") : {};
    var fallbackSrc = (imgAttrs.src || "").trim();
    return {
        src: chosenSrc || (isSafeUrl(fallbackSrc) ? fallbackSrc : ""),
        alt: imgAttrs.alt || "",
        width: imgAttrs.width ? Math.round(parseLengthPx(imgAttrs.width, 14) || 0) : 0,
        height: imgAttrs.height ? Math.round(parseLengthPx(imgAttrs.height, 14) || 0) : 0,
        align: (imgAttrs.align || "").toLowerCase()
    };
}

// ── Parser AST ligero para BlockHtml.qml ─────────────────────────────────────
var VOID_TAGS = { "br": true, "hr": true, "img": true, "source": true, "wbr": true, "meta": true, "link": true, "input": true };
var CONTAINER_TAGS = {
    "div": true, "center": true, "section": true, "article": true,
    "header": true, "footer": true, "nav": true, "aside": true,
    "figure": true, "figcaption": true, "p": true, "main": true, "body": true
};
var HEADING_TAGS = { "h1": 1, "h2": 2, "h3": 3, "h4": 4, "h5": 5, "h6": 6 };

function _inheritStyle(parentSt, ownSt, tag) {
    var align = ownSt.textAlign || (tag === "center" ? "center" : "") || (parentSt ? parentSt.textAlign : "");
    return {
        textAlign: align,
        color: ownSt.color || (parentSt ? parentSt.color : ""),
        backgroundColor: ownSt.backgroundColor || "",
        fontSizePx: ownSt.fontSizePx || (parentSt ? parentSt.fontSizePx : 0),
        fontWeight: ownSt.fontWeight || (parentSt ? parentSt.fontWeight : ""),
        fontStyle: ownSt.fontStyle || (parentSt ? parentSt.fontStyle : ""),
        textDecoration: ownSt.textDecoration || (parentSt ? parentSt.textDecoration : ""),
        fontFamily: ownSt.fontFamily || (parentSt ? parentSt.fontFamily : ""),
        paddingTop: ownSt.paddingTop,
        paddingRight: ownSt.paddingRight,
        paddingBottom: ownSt.paddingBottom,
        paddingLeft: ownSt.paddingLeft,
        marginTop: ownSt.marginTop,
        marginBottom: ownSt.marginBottom,
        borderWidth: ownSt.borderWidth,
        borderColor: ownSt.borderColor,
        borderLeftWidth: ownSt.borderLeftWidth,
        borderLeftColor: ownSt.borderLeftColor,
        borderRadius: ownSt.borderRadius,
        widthPx: ownSt.widthPx,
        widthPct: ownSt.widthPct,
        maxWidthPx: ownSt.maxWidthPx,
        heightPx: ownSt.heightPx,
        opacity: (ownSt.opacity < 1.0) ? ownSt.opacity : 1.0,
        display: ownSt.display,
        hidden: ownSt.hidden
    };
}

function _parseImgNode(attrsStr, linkUrl, st) {
    var a = parseAttributes(attrsStr);
    var src = (a.src || "").trim();
    if (!isSafeUrl(src)) return null;
    var w = st.widthPx > 0 ? st.widthPx : (a.width ? Math.round(parseLengthPx(a.width, 14) || 0) : 0);
    var h = st.heightPx > 0 ? st.heightPx : (a.height ? Math.round(parseLengthPx(a.height, 14) || 0) : 0);
    return {
        kind: "image",
        src: src,
        alt: a.alt || "",
        title: a.title || "",
        width: w,
        height: h,
        align: st.textAlign || (a.align || "").toLowerCase(),
        link: (linkUrl && isSafeUrl(linkUrl)) ? linkUrl : ""
    };
}

function _isPureInlineHtmlOrTextChunk(chunk) {
    if (!chunk || chunk.trim() === "") return true;
    // Detecta sintaxis de bloque Markdown (encabezados #, listas -, 1., citas >, código ```, hr ---, tablas |)
    var lines = chunk.split(/\r?\n/);
    for (var i = 0; i < lines.length; i++) {
        var l = lines[i];
        if (/^[ \t]*#{1,6}(?:[ \t]+|$)/.test(l)) return true;
    }
    return true;
}

function _parseTableNode(innerHtml, parentStyle, opts, sheetRules) {
    var headers = [];
    var rows = [];
    var alignments = [];
    var hasThead = false;

    var clean = innerHtml.replace(/<\/?(?:thead|tbody|tfoot)\b[^>]*>/gi, function(m) {
        if (/^<thead/i.test(m)) hasThead = true;
        return "";
    });
    var trRe = /<tr\b[^>]*>([\s\S]*?)<\/tr>/gi;
    var trMatch;
    var rowIndex = 0;
    while ((trMatch = trRe.exec(clean)) !== null) {
        var rowHtml = trMatch[1];
        var cellRe = /<(th|td)\b([^>]*)>([\s\S]*?)<\/\1>/gi;
        var cm;
        var cells = [];
        var cellAligns = [];
        var cellWidths = [];
        var allTh = true;
        while ((cm = cellRe.exec(rowHtml)) !== null) {
            var cTag = cm[1].toLowerCase();
            if (cTag !== "th") allTh = false;
            var cAttrs = parseAttributes(cm[2] || "");
            var cSt = parseStyleDeclaration((_lookupSheetStyle(sheetRules, cTag, cAttrs) + "; " + (cAttrs.style || "")), cAttrs, opts);
            var cAlign = cSt.textAlign || (cTag === "th" ? "left" : (parentStyle.textAlign || "left"));
            cellAligns.push(cAlign);
            cellWidths.push(cSt.widthPct > 0 ? cSt.widthPct : 0);
            var cellBody = cm[3].trim();
            cells.push(cellBody);
        }
        if (cells.length === 0) continue;
        if (rowIndex === 0 && (hasThead || allTh)) {
            headers = cells;
            alignments = cellAligns;
        } else {
            if (headers.length === 0 && rowIndex === 0) {
                headers = cells;
                alignments = cellAligns;
            } else {
                rows.push(cells);
            }
        }
        if (rowIndex === 0 && cellWidths.length > 0) {
            var hasExplicitW = cellWidths.some(function(w) { return w > 0; });
            if (hasExplicitW) parentStyle._colWidths = cellWidths;
        }
        rowIndex++;
    }
    var colWidths = parentStyle._colWidths || [];
    if (parentStyle._colWidths !== undefined) delete parentStyle._colWidths;
    return {
        kind: "table",
        headers: headers,
        rows: rows,
        alignments: alignments,
        colWidths: colWidths,
        style: parentStyle
    };
}

// Convierte una porción plana (sin bloques HTML contenedores exteriores) en nodos Markdown / Imágenes / Enlaces
function _splitMixedMarkdownNodes(segment, inheritedStyle, opts, sheetRules) {
    var out = [];
    if (!segment || segment.trim() === "") return out;

    // Dividir por líneas en blanco preservando fences ```...```
    var lines = segment.split(/\r?\n/);
    var blocks = [];
    var cur = [];
    var inFence = false;
    var fenceMarker = "";

    function flushCur() {
        if (cur.length > 0) {
            blocks.push(cur.join("\n"));
            cur = [];
        }
    }

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var fm = line.match(/^[ \t]*(`{3,}|~{3,})/);
        if (fm) {
            if (!inFence) {
                if (cur.length > 0 && cur[cur.length - 1].trim() !== "") flushCur();
                inFence = true;
                fenceMarker = fm[1][0];
            } else if (line.trim().charAt(0) === fenceMarker) {
                cur.push(line);
                flushCur();
                inFence = false;
                fenceMarker = "";
                continue;
            }
        }
        if (inFence) {
            cur.push(line);
            continue;
        }
        if (line.trim() === "") {
            flushCur();
            continue;
        }
        // Si empieza encabezado #, hr --- o cita > luego de texto plano sin blanco, separar bloque
        if (cur.length > 0 && (/^[ \t]*#{1,6}[ \t]+/.test(line) || /^[ \t]*(?:---|___|\*\*\*)[ \t]*$/.test(line))) {
            flushCur();
            cur.push(line);
            flushCur();
            continue;
        }
        if (/^[ \t]*#{1,6}[ \t]+/.test(line) || /^[ \t]*(?:---|___|\*\*\*)[ \t]*$/.test(line)) {
            flushCur();
            blocks.push(line);
            continue;
        }
        cur.push(line);
    }
    flushCur();

    for (var b = 0; b < blocks.length; b++) {
        var chunk = blocks[b].trim();
        if (!chunk) continue;

        // 1. Fence ```...```
        var fMatch = chunk.match(/^(`{3,}|~{3,})([a-zA-Z0-9_-]*)[ \t]*\r?\n([\s\S]*?)\r?\n\1[ \t]*$/);
        if (fMatch) {
            out.push({ kind: "code", lang: fMatch[2] || "", text: fMatch[3], style: inheritedStyle });
            continue;
        }

        // 2. HR ---
        if (/^(?:(?:-[ \t]*){3,}|(?:_[ \t]*){3,}|(?:\*[ \t]*){3,})$/.test(chunk)) {
            out.push({ kind: "hr", style: inheritedStyle });
            continue;
        }

        // 3. Heading #..######
        var hMatch = chunk.match(/^(#{1,6})[ \t]+([\s\S]*)$/);
        if (hMatch) {
            var hLevel = hMatch[1].length;
            var hStyle = inheritedStyle;
            if (sheetRules) {
                var hSheetCss = _lookupSheetStyle(sheetRules, "h" + hLevel, {});
                if (hSheetCss) {
                    hStyle = _inheritStyle(inheritedStyle, parseStyleDeclaration(hSheetCss, {}, opts), "h" + hLevel);
                }
            }
            out.push({ kind: "heading", level: hLevel, raw: hMatch[2].trim(), style: hStyle });
            continue;
        }

        // 4. Línea compuesta únicamente de imágenes/badges Markdown o HTML (<img ...> / [![...](...)])
        var onlyImagesRe = /^(?:\s*(?:<a\b[^>]*>\s*<img\b[^>]*>\s*<\/a>|<img\b[^>]*\/?\s*>|\[\!\[[^\]]*\]\([^)]+\)\]\([^)]+\)|\![^\[\r\n]*\[[^\]]*\]\([^)]+\)|\!\[[^\]]*\]\([^)]+\))\s*(?:·|\||<br\s*\/?>)?)+$/i;
        if ((/<img\b/i.test(chunk) || chunk.indexOf("![") !== -1) && onlyImagesRe.test(chunk)) {
            var imgs = [];
            var tokRe = /(<a\b[^>]*\bhref\s*=\s*(?:"([^"]*)"|'([^']*)')[^>]*>\s*<img\b([^>]*)>\s*<\/a>)|(<img\b([^>]*?)\/?\s*>)|(\[!\[([^\]]*)\]\(([^)]+)\)\]\(([^)]+)\))|(!\[([^\]]*)\]\(([^)]+)\))/gi;
            var tm;
            while ((tm = tokRe.exec(chunk)) !== null) {
                if (tm[1]) {
                    var imA = _parseImgNode(tm[4], tm[2] || tm[3] || "", inheritedStyle);
                    if (imA) imgs.push(imA);
                } else if (tm[5]) {
                    var imB = _parseImgNode(tm[6], "", inheritedStyle);
                    if (imB) imgs.push(imB);
                } else if (tm[7]) {
                    if (isSafeUrl(tm[9])) imgs.push({ kind: "image", src: tm[9].trim(), alt: tm[8] || "", width: 0, height: 0, align: inheritedStyle.textAlign, link: tm[10].trim() });
                } else if (tm[11]) {
                    if (isSafeUrl(tm[13])) imgs.push({ kind: "image", src: tm[13].trim(), alt: tm[12] || "", width: 0, height: 0, align: inheritedStyle.textAlign, link: "" });
                }
            }
            if (imgs.length > 0) {
                out.push({ kind: "image_row", images: imgs, align: inheritedStyle.textAlign || "left", style: inheritedStyle });
                continue;
            }
        }

        // 5. Quote > ...
        if (/^[ \t]*>/.test(chunk)) {
            var qClean = chunk.replace(/^[ \t]*>[ \t]?/gm, "");
            out.push({ kind: "blockquote", raw: qClean, style: inheritedStyle });
            continue;
        }

        // 5b. Tabla Markdown (| A | B |\n|---|---|)
        var tLines = chunk.split(/\r?\n/);
        if (tLines.length >= 2 && tLines[0].indexOf("|") !== -1 &&
            /^[ \t]*\|?([ \t]*:?-+:?[ \t]*\|)+([ \t]*:?-+:?[ \t]*)?\|?[ \t]*$/.test(tLines[1])) {
            function _splitMdRow(rowStr) {
                var s = rowStr.trim();
                if (s.startsWith("|")) s = s.substring(1);
                if (s.endsWith("|")) s = s.substring(0, s.length - 1);
                return s.split("|").map(function(c) { return c.trim(); });
            }
            var tHeaders = _splitMdRow(tLines[0]);
            var tSep = _splitMdRow(tLines[1]);
            var tAligns = tSep.map(function(c) {
                if (c.startsWith(":") && c.endsWith(":")) return "center";
                if (c.endsWith(":")) return "right";
                if (c.startsWith(":")) return "left";
                return inheritedStyle.textAlign || "left";
            });
            var tRows = [];
            for (var trI = 2; trI < tLines.length; trI++) {
                if (tLines[trI].indexOf("|") !== -1) tRows.push(_splitMdRow(tLines[trI]));
            }
            out.push({ kind: "table", headers: tHeaders, rows: tRows, alignments: tAligns, style: inheritedStyle });
            continue;
        }

        // 5c. Lista Markdown (-, *, +, 1.)
        if (/^[ \t]*(?:[-*+]|\d+[.)])[ \t]+/.test(tLines[0])) {
            var isOrd = /^[ \t]*\d+[.)][ \t]+/.test(tLines[0]);
            var lItems = [];
            for (var li = 0; li < tLines.length; li++) {
                var strippedLi = tLines[li].replace(/^[ \t]*(?:[-*+]|\d+[.)])[ \t]+/, "");
                lItems.push(strippedLi);
            }
            out.push({ kind: "list", ordered: isOrd, items: lItems, style: inheritedStyle });
            continue;
        }

        // 6. Texto / párrafo Markdown + HTML inline
        out.push({ kind: "markdown", raw: chunk, style: inheritedStyle });
    }
    return out;
}

// Parsea un bloque HTML (+ Markdown interno) en un array ordenado de nodos renderizables
function parseHtmlFragment(raw, opts, _inheritedStyle, _sheetRules) {
    if (!raw || typeof raw !== "string") return [];
    var options = opts || {};
    var sheetRules = _sheetRules;
    var work = sanitizeHtml(raw);

    if (!sheetRules) {
        var sheetRes = extractStyleSheet(work);
        work = sheetRes.cleanedHtml;
        sheetRules = sheetRes.rules;
        // Desenvolver documento HTML externo completo si trae <html>/<head>/<body>
        work = work.replace(/<!DOCTYPE[^>]*>/gi, "")
                   .replace(/<head\b[^>]*>[\s\S]*?<\/head>/gi, "")
                   .replace(/<\/?html\b[^>]*>/gi, "")
                   .replace(/<\/?body\b[^>]*>/gi, "");
    }

    var parentStyle = _inheritedStyle || parseStyleDeclaration("", {}, options);
    // Máscara de longitud idéntica sobre fences y spans inline `...` para ignorar `<tag>` literales dentro de código
    var maskedWork = work.replace(/```[\s\S]*?```|~~~[\s\S]*?~~~|`[^`\r\n]*`/g, function(m) {
        return m.replace(/[^\r\n]/g, " ");
    });
    var nodes = [];
    var i = 0;
    var n = work.length;
    var textBuf = "";

    function flushText() {
        if (textBuf && textBuf.trim() !== "") {
            var mdNodes = _splitMixedMarkdownNodes(textBuf, parentStyle, options, sheetRules);
            for (var k = 0; k < mdNodes.length; k++) nodes.push(mdNodes[k]);
        }
        textBuf = "";
    }

    function findMatchingClose(tagName, searchStart) {
        var depth = 1;
        var re = new RegExp("<(\\/?)" + tagName + "\\b[^>]*>", "gi");
        re.lastIndex = searchStart;
        var m;
        while ((m = re.exec(maskedWork)) !== null) {
            if (m[1] === "/") {
                depth--;
                if (depth === 0) {
                    return { closeStart: m.index, closeEnd: m.index + m[0].length };
                }
            } else if (!/\/>$/.test(m[0])) {
                depth++;
            }
        }
        return null;
    }

    while (i < n) {
        var lt = maskedWork.indexOf("<", i);
        if (lt === -1) {
            textBuf += work.substring(i);
            break;
        }
        textBuf += work.substring(i, lt);

        var tagMatch = maskedWork.substring(lt).match(/^<([a-zA-Z][a-zA-Z0-9]*)\b([^>]*)>/);
        if (!tagMatch) {
            // Puede ser tag de cierre suelto </tag> o '<' literal
            var closeTagMatch = maskedWork.substring(lt).match(/^<\/[a-zA-Z][a-zA-Z0-9]*\s*>/);
            if (closeTagMatch) {
                i = lt + closeTagMatch[0].length;
            } else {
                textBuf += "<";
                i = lt + 1;
            }
            continue;
        }

        var rawTagMatch = work.substring(lt, lt + tagMatch[0].length);
        var fullOpen = rawTagMatch;
        var tag = tagMatch[1].toLowerCase();
        var attrsStr = rawTagMatch.replace(/^<[a-zA-Z][a-zA-Z0-9]*\b/, "").replace(/>$/, "");
        var selfClosing = /\/\s*>$/.test(fullOpen) || VOID_TAGS[tag] === true;
        var afterOpen = lt + fullOpen.length;

        // Etiquetas estrictamente inline (<span...>, <font>, <b>, <i>, <u>, <sup>, <sub>, <mark>, <kbd>, <a> con texto)
        // se acumulan en textBuf salvo <a><img/></a> o <img/> aislados o <br/>
        if (tag === "br") {
            textBuf += "<br/>";
            i = afterOpen;
            continue;
        }

        if (tag === "hr") {
            flushText();
            var hrAttrs = parseAttributes(attrsStr);
            var hrSt = parseStyleDeclaration((_lookupSheetStyle(sheetRules, "hr", hrAttrs) + "; " + (hrAttrs.style || "")), hrAttrs, options);
            nodes.push({ kind: "hr", style: hrSt });
            i = afterOpen;
            continue;
        }

        if (tag === "img") {
            // Verificar si alrededor solo hay espacios/otras imágenes en esta línea; por simplicidad dejar en textBuf si hay texto alrededor
            var lineStart = textBuf.lastIndexOf("\n") + 1;
            var linePrefix = textBuf.substring(lineStart).trim();
            if (linePrefix === "" && /^[\s\n]*(?:<(?:\/?(?:div|p|center|figure)|br)\b|$)/i.test(work.substring(afterOpen).split("\n")[0] || "")) {
                flushText();
                var imgAttrs = parseAttributes(attrsStr);
                var imgSt = _inheritStyle(parentStyle, parseStyleDeclaration((_lookupSheetStyle(sheetRules, "img", imgAttrs) + "; " + (imgAttrs.style || "")), imgAttrs, options), "img");
                var imNode = _parseImgNode(attrsStr, "", imgSt);
                if (imNode) nodes.push({ kind: "image_row", images: [imNode], align: imgSt.textAlign || "left", style: imgSt });
                i = afterOpen;
                continue;
            }
            textBuf += fullOpen;
            i = afterOpen;
            continue;
        }

        if (tag === "a" && !selfClosing) {
            var closeA = findMatchingClose("a", afterOpen);
            if (closeA) {
                var aInner = work.substring(afterOpen, closeA.closeStart).trim();
                var aImgOnly = aInner.match(/^<img\b([^>]*?)\/?\s*>$/i);
                var linePreA = textBuf.substring(textBuf.lastIndexOf("\n") + 1).trim();
                var restLineA = (work.substring(closeA.closeEnd).split("\n")[0] || "").trim();
                if (aImgOnly && linePreA === "" && restLineA === "") {
                    flushText();
                    var aAttrs = parseAttributes(attrsStr);
                    var imL = _parseImgNode(aImgOnly[1], aAttrs.href || "", parentStyle);
                    if (imL) nodes.push({ kind: "image_row", images: [imL], align: parentStyle.textAlign || "left", style: parentStyle });
                    i = closeA.closeEnd;
                    continue;
                }
                textBuf += work.substring(lt, closeA.closeEnd);
                i = closeA.closeEnd;
                continue;
            }
        }

        var isBlockTag = CONTAINER_TAGS[tag] || HEADING_TAGS[tag] || tag === "details" || tag === "picture" ||
                         tag === "table" || tag === "ul" || tag === "ol" || tag === "blockquote" || tag === "pre";
        if (!isBlockTag || selfClosing) {
            textBuf += fullOpen;
            i = afterOpen;
            continue;
        }

        var closeInfo = findMatchingClose(tag, afterOpen);
        if (!closeInfo) {
            textBuf += fullOpen;
            i = afterOpen;
            continue;
        }

        flushText();
        var inner = work.substring(afterOpen, closeInfo.closeStart);
        var attrs = parseAttributes(attrsStr);
        var cssMerged = (_lookupSheetStyle(sheetRules, tag, attrs) ? (_lookupSheetStyle(sheetRules, tag, attrs) + "; ") : "") + (attrs.style || "");
        var ownStyle = parseStyleDeclaration(cssMerged, attrs, options);
        if (ownStyle.hidden) {
            i = closeInfo.closeEnd;
            continue;
        }
        var mergedStyle = _inheritStyle(parentStyle, ownStyle, tag);

        if (HEADING_TAGS[tag]) {
            nodes.push({ kind: "heading", level: HEADING_TAGS[tag], raw: inner.trim(), style: mergedStyle });
        } else if (tag === "details") {
            var sumText = "Detalles";
            var bodyHtml = inner.replace(/<summary\b[^>]*>([\s\S]*?)<\/summary>/i, function(_, sInner) {
                sumText = sInner.trim() || "Detalles";
                return "";
            });
            nodes.push({
                kind: "details",
                open: attrs.open !== undefined,
                summaryRaw: sumText,
                style: mergedStyle,
                children: parseHtmlFragment(bodyHtml, options, mergedStyle, sheetRules)
            });
        } else if (tag === "picture") {
            var pic = resolvePictureSrc(inner, !!options.lightMode);
            if (pic.src) {
                var picAlign = pic.align || mergedStyle.textAlign || "left";
                nodes.push({
                    kind: "image_row",
                    images: [{ kind: "image", src: pic.src, alt: pic.alt, width: pic.width, height: pic.height, align: picAlign, link: "" }],
                    align: picAlign,
                    style: mergedStyle
                });
            }
        } else if (tag === "table") {
            nodes.push(_parseTableNode(inner, mergedStyle, options, sheetRules));
        } else if (tag === "pre") {
            var codeBody = inner.replace(/^<code\b[^>]*>([\s\S]*?)<\/code>$/i, "$1");
            nodes.push({ kind: "code", lang: "", text: _decodeBasicEntities(codeBody.replace(/^\r?\n|\r?\n$/g, "")), style: mergedStyle });
        } else if (tag === "blockquote") {
            nodes.push({ kind: "blockquote", children: parseHtmlFragment(inner, options, mergedStyle, sheetRules), raw: inner.trim(), style: mergedStyle });
        } else if (tag === "ul" || tag === "ol") {
            var liItems = [];
            var liRe = /<li\b[^>]*>([\s\S]*?)<\/li>/gi;
            var lm;
            while ((lm = liRe.exec(inner)) !== null) {
                liItems.push(lm[1].trim());
            }
            nodes.push({ kind: "list", ordered: (tag === "ol"), items: liItems, style: mergedStyle });
        } else {
            // div, center, p, section, figure, etc.
            var childNodes = parseHtmlFragment(inner, options, mergedStyle, sheetRules);
            var hasBoxDecoration = (ownStyle.backgroundColor && ownStyle.backgroundColor !== "transparent") ||
                                   ownStyle.borderWidth > 0 || ownStyle.borderLeftWidth > 0 ||
                                   ownStyle.paddingTop > 0 || ownStyle.paddingRight > 0 || ownStyle.paddingBottom > 0 || ownStyle.paddingLeft > 0 ||
                                   ownStyle.marginTop > 0 || ownStyle.marginBottom > 0 || ownStyle.borderRadius > 0;
            if (hasBoxDecoration) {
                nodes.push({ kind: "container", tag: tag, style: ownStyle, effectiveStyle: mergedStyle, children: childNodes });
            } else {
                for (var cIdx = 0; cIdx < childNodes.length; cIdx++) nodes.push(childNodes[cIdx]);
            }
        }

        i = closeInfo.closeEnd;
    }

    flushText();

    // Unificar filas consecutivas de imágenes/badges en un mismo bloque horizontal (como badges multilínea en GitHub)
    var mergedNodes = [];
    for (var ni = 0; ni < nodes.length; ni++) {
        var curNd = nodes[ni];
        if (curNd && curNd.kind === "image_row" && mergedNodes.length > 0 &&
            mergedNodes[mergedNodes.length - 1].kind === "image_row" &&
            (mergedNodes[mergedNodes.length - 1].align || "left") === (curNd.align || "left")) {
            var prevImages = mergedNodes[mergedNodes.length - 1].images || [];
            mergedNodes[mergedNodes.length - 1].images = prevImages.concat(curNd.images || []);
        } else {
            mergedNodes.push(curNd);
        }
    }
    return mergedNodes;
}

// Extrae texto plano visible de un bloque HTML para índice/conteo de Ctrl+F
function extractVisibleText(raw, opts) {
    var nodes = parseHtmlFragment(raw, opts || {});
    var parts = [];
    function walk(list) {
        for (var i = 0; i < list.length; i++) {
            var nd = list[i];
            if (!nd) continue;
            if (nd.kind === "details") {
                if (nd.summaryRaw) parts.push(nd.summaryRaw);
                if (nd.children) walk(nd.children);
            } else if (nd.kind === "container" || nd.kind === "blockquote") {
                if (nd.children && nd.children.length > 0) walk(nd.children);
                else if (nd.raw) parts.push(nd.raw);
            } else if (nd.kind === "heading" || nd.kind === "markdown") {
                if (nd.raw) parts.push(nd.raw);
            } else if (nd.kind === "code") {
                if (nd.text) parts.push(nd.text);
            } else if (nd.kind === "list" && nd.items) {
                for (var li = 0; li < nd.items.length; li++) parts.push(nd.items[li]);
            } else if (nd.kind === "table") {
                if (nd.headers) parts.push(nd.headers.join(" "));
                if (nd.rows) {
                    for (var r = 0; r < nd.rows.length; r++) parts.push(nd.rows[r].join(" "));
                }
            }
        }
    }
    walk(nodes);
    return parts.join("\n").replace(/<[^>]+>/g, "");
}
