.pragma library

// HtmlTemplates.js — Plantillas predefinidas de HTML y CSS básico compatibles con GitHub README

var TEMPLATES = {
    center: "<div align=\"center\">\n\n# Título centrado\n\nTexto centrado compatible con **GitHub**\n\n</div>",
    details: "<details>\n<summary>Ver detalles</summary>\n\nContenido desplegable con **Markdown** y listas:\n\n- Elemento 1\n- Elemento 2\n\n</details>",
    card: "<div style=\"padding: 12px 16px; border-left: 4px solid var(--accent); background-color: rgba(138, 180, 248, 0.10); border-radius: 8px;\">\n\n**Bloque destacado**\n\nTexto con estilo CSS nativo.\n\n</div>",
    columns: "<table>\n  <tr>\n    <td width=\"50%\" align=\"center\">\n      <b>Columna izquierda</b><br/>Contenido o imagen\n    </td>\n    <td width=\"50%\" align=\"center\">\n      <b>Columna derecha</b><br/>Contenido o imagen\n    </td>\n  </tr>\n</table>",
    image: "<div align=\"center\">\n  <img src=\"ruta/imagen.png\" alt=\"Descripción\" width=\"360\" />\n</div>",
    color_span: "<span style=\"color: #8ab4f8;\">Texto coloreado</span>",
    sup_sub: "x<sup>2</sup> + H<sub>2</sub>O"
};

function getTemplate(key) {
    if (TEMPLATES[key]) return TEMPLATES[key];
    return TEMPLATES.center;
}

function getTemplateList() {
    return [
        { id: "center", labelKey: "notes.html.tpl.center", defaultLabel: "Bloque centrado (<div>)", icon: "align-horizontal-center" },
        { id: "details", labelKey: "notes.html.tpl.details", defaultLabel: "Desplegable (<details>)", icon: "details-collapse" },
        { id: "card", labelKey: "notes.html.tpl.card", defaultLabel: "Tarjeta con CSS (<div>)", icon: "html-block" },
        { id: "columns", labelKey: "notes.html.tpl.columns", defaultLabel: "Dos columnas (<table>)", icon: "table" },
        { id: "image", labelKey: "notes.html.tpl.image", defaultLabel: "Imagen con tamaño (<img>)", icon: "image" },
        { id: "color_span", labelKey: "notes.html.tpl.color", defaultLabel: "Texto con color (<span>)", icon: "format-color-text" },
        { id: "sup_sub", labelKey: "notes.html.tpl.sup_sub", defaultLabel: "Super / Subíndice", icon: "code" }
    ];
}

// Localiza un único contenedor envolvente de nivel superior (<center>, <div>, <p>)
// que cubra de punta a punta el string completo.
function _inspectOuterContainer(raw) {
    var trimmed = String(raw || "").trim();
    if (trimmed === "" || trimmed.charAt(0) !== "<") return null;

    var openM = trimmed.match(/^<(center|div|p)\b([^>]*)>/i);
    if (!openM) return null;

    var tag = openM[1].toLowerCase();
    var attrsStr = openM[2] || "";
    if (/\/\s*$/.test(attrsStr)) return null;

    var tagRe = new RegExp("<(\\/)?" + tag + "(?=[\\s>/])[^>]*>", "gi");
    tagRe.lastIndex = openM[0].length;
    var depth = 1;
    var m;
    var closeStart = -1;
    var closeEnd = -1;
    while ((m = tagRe.exec(trimmed)) !== null) {
        if (m[1]) {
            depth--;
            if (depth === 0) {
                closeStart = m.index;
                closeEnd = tagRe.lastIndex;
                break;
            }
        } else if (!/\/\s*>$/.test(m[0])) {
            depth++;
        }
    }
    if (closeStart === -1 || closeEnd !== trimmed.length) return null;

    var align = "";
    if (tag === "center") {
        align = "center";
    } else {
        var alAttr = attrsStr.match(/\balign\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i);
        if (alAttr) {
            var vAttr = (alAttr[1] !== undefined ? alAttr[1] : (alAttr[2] !== undefined ? alAttr[2] : alAttr[3] || "")).trim().toLowerCase();
            if (vAttr === "left" || vAttr === "center" || vAttr === "right" || vAttr === "justify") align = vAttr;
        }
        var stAttr = attrsStr.match(/\bstyle\s*=\s*(?:"([^"]*)"|'([^']*)')/i);
        if (stAttr) {
            var stBody = stAttr[1] !== undefined ? stAttr[1] : (stAttr[2] || "");
            var taM = stBody.match(/(?:^|;)\s*text-align\s*:\s*(left|center|right|justify)\b/i);
            if (taM) align = taM[1].toLowerCase();
        }
    }

    var residualAttrs = attrsStr
        .replace(/\balign\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)/gi, "")
        .replace(/\bstyle\s*=\s*(?:"([^"]*)"|'([^']*)')/gi, function(_, d1, d2) {
            var cleanedCss = (d1 !== undefined ? d1 : (d2 || ""))
                .replace(/(?:^|;)\s*text-align\s*:\s*[^;]*(?=;|$)/gi, "")
                .replace(/^\s*;\s*|\s*;\s*$/g, "")
                .trim();
            return cleanedCss ? 'style="' + cleanedCss + '"' : "";
        })
        .trim();

    return {
        tag: tag,
        attrsStr: attrsStr,
        residualAttrs: residualAttrs,
        align: align,
        isSimpleAlign: (tag === "center" || (align !== "" && residualAttrs === "")),
        inner: trimmed.substring(openM[0].length, closeStart)
    };
}

function detectAlign(raw) {
    var info = _inspectOuterContainer(raw);
    return info ? info.align : "";
}

function applyAlignContainer(raw, targetAlign) {
    var target = String(targetAlign || "").toLowerCase();
    if (target !== "left" && target !== "center" && target !== "right" && target !== "justify") {
        target = "left";
    }
    var trimmed = String(raw || "").trim();
    var info = _inspectOuterContainer(trimmed);

    if (info && info.isSimpleAlign) {
        var cleanInner = info.inner.replace(/^\n+|\n+$/g, "");
        if (target === "left" || target === info.align) {
            return { raw: cleanInner, unwrapped: true, align: "" };
        }
        return {
            raw: '<div align="' + target + '">\n\n' + cleanInner + '\n\n</div>',
            unwrapped: false,
            align: target
        };
    }

    if (info) {
        var shouldClear = (target === "left" || target === info.align);
        var nextAttrs = info.residualAttrs;
        if (!shouldClear) {
            nextAttrs = nextAttrs ? ('align="' + target + '" ' + nextAttrs) : ('align="' + target + '"');
        }
        var openNew = "<" + info.tag + (nextAttrs ? (" " + nextAttrs) : "") + ">";
        return {
            raw: openNew + info.inner + "</" + info.tag + ">",
            unwrapped: false,
            align: shouldClear ? "" : target
        };
    }

    if (target === "left") {
        return { raw: raw, unwrapped: false, align: "" };
    }
    var innerOut = trimmed === "" ? "" : trimmed;
    return {
        raw: innerOut === "" ? ('<div align="' + target + '">\n\n\n</div>') : ('<div align="' + target + '">\n\n' + innerOut + '\n\n</div>'),
        unwrapped: false,
        align: target
    };
}
