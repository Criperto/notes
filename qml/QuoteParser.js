.pragma library

// QuoteParser.js — Parser puro de citas Markdown (F25)
// Soporta: `>>` sin espacio, `> >` con espacios, espacios variables,
// profundidad máxima 6 (más allá se trata como texto), encabezados `##`,
// listas dentro de citas y citas anidadas por recursión.
// Callouts estilo GitHub (F77): [!NOTE], [!TIP], [!IMPORTANT], [!WARNING], [!CAUTION]
//
// parseQuote(raw) → { depth, children } donde cada hijo es:
//   { kind: "paragraph", text }
//   { kind: "heading", level, text }
//   { kind: "list", raw, items: [{ marker, isTask, checked, text }] } (items sin ListParser: regex propia)
//   { kind: "quote", depth, children } (anidada)

var MAX_DEPTH = 6;
var CALLOUT_TYPES = ["NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"];

// Parsea un bloque de cita Markdown para determinar si es un callout estilo GitHub.
// Formato GitHub:
// > [!NOTE]
// > Información adicional...
// O con título personalizado:
// > [!NOTE] Mi título personalizado
// > Información adicional...
// Devuelve { type: "NOTE"|"TIP"|"IMPORTANT"|"WARNING"|"CAUTION", title: string, bodyRaw: string } o null.
function parseCallout(raw) {
    if (!raw || typeof raw !== "string") return null;
    var lines = raw.split("\n");
    if (lines.length === 0) return null;

    var firstLine = lines[0];
    var firstInfo = lineDepthContent(firstLine);
    if (firstInfo.depth === 0) return null;

    var content = (firstInfo.content || "").trim();
    var match = content.match(/^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]([ \t]+(.*))?$/i);
    if (!match) return null;

    var type = match[1].toUpperCase();
    var customTitle = (match[3] !== undefined && match[3] !== null) ? match[3].trim() : "";

    var bodyLines = lines.slice(1);
    var bodyRaw = bodyLines.join("\n");

    return {
        type: type,
        title: customTitle,
        bodyRaw: bodyRaw
    };
}

// Cuenta los `>` iniciales tolerando espacios/tabs entre ellos.
// "  > > texto" → { depth: 2, content: "texto" }
// ">>texto" → { depth: 2, content: "texto" }
// "> - ítem" → { depth: 1, content: "- ítem" }
// "sin marca" → { depth: 0, content: "sin marca" }
function lineDepthContent(line) {
    if (typeof line !== "string") return { depth: 0, content: "" };
    var i = 0;
    var n = line.length;
    while (i < n && (line[i] === " " || line[i] === "\t")) i++;
    var depth = 0;
    while (i < n && line[i] === ">") {
        depth++;
        i++;
        while (i < n && (line[i] === " " || line[i] === "\t")) i++;
        if (depth >= MAX_DEPTH) {
            // Más allá del máximo: el resto (incluidos `>` extra) es texto.
            break;
        }
    }
    if (depth === 0) return { depth: 0, content: line };
    if (depth > MAX_DEPTH) depth = MAX_DEPTH;
    return { depth: depth, content: line.substring(i) };
}

function headingLevelOf(text) {
    if (typeof text !== "string" || text === "") return 0;
    var m = text.match(/^(#{1,6})(?=\s|$)/);
    if (!m) return 0;
    if (text.length > m[1].length) {
        var nx = text.charAt(m[1].length);
        if (nx !== " " && nx !== "\t" && nx !== "\n") return 0;
    }
    return m[1].length;
}

function stripHeadingPrefix(text) {
    if (typeof text !== "string") return "";
    return text.replace(/^#{1,6}(?:\s+|\s*$)/, "");
}

// Detecta marcador de lista al inicio del contenido (tras quitar `>`).
// Devuelve { marker, isTask, checked, text } o null.
function matchListMarker(content) {
    if (typeof content !== "string") return null;
    var tm = content.match(/^([-*+]|\d+[.)])[ \t]*\[([ xX]?)\][ \t]*(.*)$/);
    if (tm) {
        return {
            marker: tm[1],
            isTask: true,
            checked: (tm[2].toLowerCase() === "x"),
            text: tm[3] || ""
        };
    }
    var m = content.match(/^([-*+]|\d+[.)])([ \t]+)(.*)$/);
    if (m) {
        return { marker: m[1], isTask: false, checked: false, text: m[3] || "" };
    }
    return null;
}

function _isEmptyLine(s) {
    return !s || /^\s*$/.test(s);
}

// Parsea líneas ya separadas con su {depth, content} en un nivel base dado.
// base: profundidad de este nivel (1 para la cita exterior).
function _parseLevel(lineInfos, base) {
    var children = [];
    var paraBuf = [];
    var listBuf = []; // { marker, isTask, checked, text, rawLine }

    function flushPara() {
        if (paraBuf.length > 0) {
            // Párrafo multilínea: se conserva con \n (estándar Markdown lo une,
            // pero la app conserva saltos como los párrafos normales).
            children.push({ kind: "paragraph", text: paraBuf.join("\n") });
            paraBuf = [];
        }
    }

    function flushList() {
        if (listBuf.length > 0) {
            var raws = listBuf.map(function(it) {
                var task = it.isTask ? ("[" + (it.checked ? "x" : " ") + "] ") : "";
                return it.marker + " " + task + it.text;
            });
            children.push({ kind: "list", raw: raws.join("\n"), items: listBuf.slice() });
            listBuf = [];
        }
    }

    var i = 0;
    while (i < lineInfos.length) {
        var li = lineInfos[i];
        if (li.depth > base) {
            // Bloque anidado: junta todas las líneas consecutivas con depth > base
            // y las parsea recursivamente como sub-cita.
            flushPara();
            flushList();
            var nested = [];
            while (i < lineInfos.length && lineInfos[i].depth > base) {
                nested.push(lineInfos[i]);
                i++;
            }
            // depth del nivel anidado = base + 1 (aunque haya saltos, se colapsa un nivel;
            // la profundidad visual exacta la da cada línea al aplanar).
            var sub = _parseLevel(nested, base + 1);
            children.push({ kind: "quote", depth: base + 1, children: sub });
            continue;
        }
        if (li.depth < base) {
            // No debería pasar dentro de una cita bien formada; se trata como párrafo.
            flushList();
            paraBuf.push(li.content);
            i++;
            continue;
        }
        // li.depth === base
        var c = li.content;
        if (_isEmptyLine(c)) {
            // Línea `>` vacía: corta párrafo y lista (separador).
            flushPara();
            flushList();
            i++;
            continue;
        }
        var hl = headingLevelOf(c);
        if (hl > 0) {
            flushPara();
            flushList();
            children.push({ kind: "heading", level: hl, text: stripHeadingPrefix(c) });
            i++;
            continue;
        }
        var lm = matchListMarker(c);
        if (lm) {
            flushPara();
            listBuf.push(lm);
            i++;
            continue;
        }
        // Texto normal: si venía lista, la cierra (línea no-lista corta la lista).
        flushList();
        paraBuf.push(c);
        i++;
    }
    flushPara();
    flushList();
    return children;
}

function parseQuote(raw) {
    if (!raw || typeof raw !== "string") return { depth: 1, children: [] };
    var lines = raw.split("\n");
    var infos = lines.map(function(l) { return lineDepthContent(l); });
    // Base = profundidad mínima con contenido (normalmente 1). Si hay líneas
    // sin marca (depth 0, tolerancia), se suben a base 1 para no romper el árbol.
    var base = 1;
    var norm = infos.map(function(inf) {
        if (inf.depth === 0) return { depth: base, content: inf.content };
        return inf;
    });
    return { depth: base, children: _parseLevel(norm, base) };
}

// Serialización canónica: "> " por nivel + contenido.
// Nota: normaliza `>>` → `> >` y espacios variables; por eso BlockQuote.getRaw()
// devuelve el raw original intacto cuando el usuario no editó (round-trip byte a byte).
function _serializeChildren(children, depth) {
    var out = [];
    var prefix = "";
    for (var d = 0; d < depth; d++) prefix += "> ";
    for (var i = 0; i < children.length; i++) {
        var ch = children[i];
        if (ch.kind === "paragraph") {
            var pls = (ch.text || "").split("\n");
            for (var p = 0; p < pls.length; p++) out.push(prefix + pls[p]);
        } else if (ch.kind === "heading") {
            var hp = "";
            for (var h = 0; h < (ch.level || 1); h++) hp += "#";
            out.push(prefix + hp + " " + (ch.text || ""));
        } else if (ch.kind === "list") {
            var items = ch.items || [];
            for (var l = 0; l < items.length; l++) {
                var it = items[l];
                var task = it.isTask ? ("[" + (it.checked ? "x" : " ") + "] ") : "";
                out.push(prefix + (it.marker || "-") + " " + task + (it.text || ""));
            }
        } else if (ch.kind === "quote") {
            var sub = _serializeChildren(ch.children || [], depth + 1);
            for (var s = 0; s < sub.length; s++) out.push(sub[s]);
        }
    }
    return out;
}

function serializeQuote(tree) {
    if (!tree || !tree.children) return "";
    return _serializeChildren(tree.children, tree.depth || 1).join("\n");
}

// Vista aplanada para QML (sin recursión en delegates) y para búsqueda.
// Cada entrada: { kind, depth, text?, level?, marker?, isTask?, checked?, listIndex? }
// - paragraph/heading: una entrada por bloque.
// - list: una entrada por ítem (kind "listItem").
// - quote anidada: se aplana sumando profundidad (depth = nivel visual 1..6).
function flattenQuote(tree) {
    var out = [];
    function walk(children, depth) {
        for (var i = 0; i < (children || []).length; i++) {
            var ch = children[i];
            if (ch.kind === "paragraph") {
                out.push({ kind: "paragraph", depth: depth, text: ch.text || "" });
            } else if (ch.kind === "heading") {
                out.push({ kind: "heading", depth: depth, level: ch.level || 1, text: ch.text || "" });
            } else if (ch.kind === "list") {
                var items = ch.items || [];
                for (var l = 0; l < items.length; l++) {
                    out.push({
                        kind: "listItem",
                        depth: depth,
                        marker: items[l].marker || "-",
                        isTask: !!items[l].isTask,
                        checked: !!items[l].checked,
                        text: items[l].text || "",
                        listIndex: l
                    });
                }
            } else if (ch.kind === "quote") {
                walk(ch.children || [], Math.min(MAX_DEPTH, depth + 1));
            }
        }
    }
    if (!tree) return out;
    walk(tree.children || [], tree.depth || 1);
    return out;
}

// Unidades de búsqueda que espejan exactamente lo pintado (una por Text visible).
// Cada unidad: { paintMd, isHeadingContent, isCalloutTitle?, segIndex } — paintMd es lo que va a inlineToHtml
// (para heading, sin `##`; para listItem con `##`, sin `##` igual que BlockList).
// Si es un callout (F77), excluye el marcador `[!TYPE]` y suma el título si es personalizado.
function searchUnits(raw) {
    var callout = parseCallout(raw);
    if (callout) {
        var units = [];
        if (callout.title && callout.title.trim() !== "") {
            units.push({ paintMd: callout.title.trim(), isCalloutTitle: true, segIndex: -1 });
        }
        if (callout.bodyRaw && callout.bodyRaw.trim() !== "") {
            var bodyTree = parseQuote(callout.bodyRaw);
            var bodyFlat = flattenQuote(bodyTree);
            for (var bi = 0; bi < bodyFlat.length; bi++) {
                var bs = bodyFlat[bi];
                if (bs.kind === "paragraph") {
                    units.push({ paintMd: bs.text, segIndex: bi });
                } else if (bs.kind === "heading") {
                    units.push({ paintMd: bs.text, segIndex: bi });
                } else if (bs.kind === "listItem") {
                    var bt = bs.text || "";
                    var bhm = bt.match(/^(#{1,6})[ \t]+([\s\S]*)$/);
                    if (bhm) units.push({ paintMd: bhm[2], segIndex: bi });
                    else units.push({ paintMd: bt, segIndex: bi });
                }
            }
        }
        return units;
    }

    var tree = parseQuote(raw);
    var flat = flattenQuote(tree);
    var units = [];
    for (var i = 0; i < flat.length; i++) {
        var s = flat[i];
        if (s.kind === "paragraph") {
            units.push({ paintMd: s.text, segIndex: i });
        } else if (s.kind === "heading") {
            units.push({ paintMd: s.text, segIndex: i });
        } else if (s.kind === "listItem") {
            var t = s.text || "";
            var hm = t.match(/^(#{1,6})[ \t]+([\s\S]*)$/);
            if (hm) units.push({ paintMd: hm[2], segIndex: i });
            else units.push({ paintMd: t, segIndex: i });
        }
    }
    return units;
}
