.pragma library

// MermaidParser.js — Parser nativo ligero para sintaxis estándar de Mermaid
// Soporta Fase 1: flowchart/graph, sequenceDiagram, pie, stateDiagram-v2
// Detecta con elegancia formatos Fase 2/3 devolviendo { supported: false }

function _stripFences(src) {
    if (!src || typeof src !== "string") return "";
    var lines = src.split(/\r?\n/);
    if (lines.length >= 2 && /^[ \t]*(`{3,}|~{3,})/.test(lines[0])) {
        lines.shift();
        if (lines.length > 0 && /^[ \t]*(`{3,}|~{3,})[ \t]*$/.test(lines[lines.length - 1])) {
            lines.pop();
        }
    }
    return lines.join("\n");
}

function detect(src) {
    if (!src || typeof src !== "string") return { type: "unknown", supported: false };
    var unfenced = _stripFences(src);
    var cleaned = _cleanDirectivesAndComments(unfenced).trim();
    if (cleaned === "") return { type: "empty", supported: true };

    var firstLine = cleaned.split("\n")[0].trim();

    // 1. Flowchart / Graph
    if (/^(flowchart|graph)\b/i.test(firstLine)) {
        return { type: "flowchart", supported: true };
    }
    // 2. Sequence Diagram
    if (/^sequenceDiagram\b/i.test(firstLine)) {
        return { type: "sequenceDiagram", supported: true };
    }
    // 3. Pie Chart
    if (/^pie\b/i.test(firstLine)) {
        return { type: "pie", supported: true };
    }
    // 4. State Diagram
    if (/^stateDiagram(-v2)?\b/i.test(firstLine)) {
        return { type: "stateDiagram", supported: true };
    }
    // 5. Class Diagram (Fase 2)
    if (/^classDiagram(-v2)?\b/i.test(firstLine)) {
        return { type: "classDiagram", supported: true };
    }
    // 6. ER Diagram (Fase 2)
    if (/^erDiagram\b/i.test(firstLine)) {
        return { type: "erDiagram", supported: true };
    }
    // 7. Gantt Chart (Fase 2)
    if (/^gantt\b/i.test(firstLine)) {
        return { type: "gantt", supported: true };
    }
    // 8. Mindmap (Fase 2)
    if (/^mindmap\b/i.test(firstLine)) {
        return { type: "mindmap", supported: true };
    }
    // 9. Timeline (Fase 2)
    if (/^timeline\b/i.test(firstLine)) {
        return { type: "timeline", supported: true };
    }

    // Fase 3 (Soportada):
    if (/^gitGraph\b/i.test(firstLine)) {
        return { type: "gitGraph", supported: true };
    }
    if (/^quadrantChart\b/i.test(firstLine)) {
        return { type: "quadrantChart", supported: true };
    }
    if (/^journey\b/i.test(firstLine)) {
        return { type: "journey", supported: true };
    }
    if (/^xychart(-beta)?\b/i.test(firstLine)) {
        return { type: "xychart", supported: true };
    }

    return { type: "unknown", supported: false };
}

function parse(src) {
    if (!src || typeof src !== "string") {
        return { ok: false, type: "empty", error: { line: 1, msg: "Diagrama vacío" } };
    }

    src = _stripFences(src);

    // Extraer título de frontmatter YAML (--- title: ... ---) si existe
    var title = "";
    var content = src;
    var fmMatch = src.match(/^[ \t]*---\r?\n([\s\S]*?)\r?\n---[ \t]*\r?\n?/);
    if (fmMatch) {
        var fmBody = fmMatch[1];
        var titleMatch = fmBody.match(/^[ \t]*title:[ \t]*(.+)$/m);
        if (titleMatch) title = titleMatch[1].trim().replace(/^["']|["']$/g, "");
        content = src.substring(fmMatch[0].length);
    }

    var d = detect(content);
    if (!d.supported) {
        return {
            ok: false,
            type: d.type,
            unsupported: true,
            phase: d.phase || 0,
            error: { line: 1, msg: "Tipo de diagrama no soportado en esta versión: " + d.type }
        };
    }

    var lines = _splitLines(content);

    try {
        switch (d.type) {
            case "flowchart":
                return _parseFlowchart(content, lines, title);
            case "sequenceDiagram":
                return _parseSequence(content, lines, title);
            case "pie":
                return _parsePie(content, lines, title);
            case "stateDiagram":
                return _parseState(content, lines, title);
            case "classDiagram":
                return _parseClassDiagram(content, lines, title);
            case "erDiagram":
                return _parseErDiagram(content, lines, title);
            case "gantt":
                return _parseGantt(content, lines, title);
            case "timeline":
                return _parseTimeline(content, lines, title);
            case "mindmap":
                return _parseMindmap(content, lines, title);
            case "gitGraph":
                return _parseGitGraph(content, lines, title);
            case "quadrantChart":
                return _parseQuadrantChart(content, lines, title);
            case "journey":
                return _parseJourney(content, lines, title);
            case "xychart":
                return _parseXyChart(content, lines, title);
            case "empty":
                return { ok: true, type: "empty", ast: { title: title, empty: true } };
            default:
                return { ok: false, type: "unknown", error: { line: 1, msg: "Diagrama no reconocido" } };
        }
    } catch (e) {
        return { ok: false, type: d.type, error: { line: 1, msg: e.message || "Error al parsear diagrama" } };
    }
}

// ── Sanitización y utilidades de texto ────────────────────────────────────────

function _cleanDirectivesAndComments(src) {
    return src
        .replace(/^[ \t]*%%[\s\S]*?$/gm, "") // comentarios de línea %%
        .replace(/^[ \t]*---\r?\n[\s\S]*?\r?\n---[ \t]*\r?\n?/g, ""); // frontmatter
}

function _splitLines(src) {
    var rawLines = src.split(/\r?\n/);
    var res = [];
    for (var i = 0; i < rawLines.length; i++) {
        var l = rawLines[i];
        var c = l.replace(/%%.*$/, "").trim(); // Quitar comentarios
        if (c.length > 0) {
            res.push({ text: c, orig: l, lineNum: i + 1 });
        }
    }
    return res;
}

function sanitizeLabel(text) {
    if (!text || typeof text !== "string") return "";
    var s = text.trim();
    // Quitar comillas envolventes si las tiene
    if ((s.startsWith('"') && s.endsWith('"')) || (s.startsWith("'") && s.endsWith("'"))) {
        s = s.substring(1, s.length - 1);
    }
    // Entidades HTML comunes de Mermaid
    s = s.replace(/#quot;/gi, '"')
         .replace(/&quot;/gi, '"')
         .replace(/&lt;/gi, '<')
         .replace(/&gt;/gi, '>')
         .replace(/&amp;/gi, '&')
         .replace(/#38;/gi, '&')
         .replace(/#9829;/gi, '♥');

    // Saltos de línea HTML y escapados
    s = s.replace(/<br\s*\/?>/gi, "\n")
         .replace(/\\n/g, "\n");

    // Eliminar etiquetas script/style y atributos peligrosos
    s = s.replace(/<\/?(script|style|iframe|object|embed)[^>]*>/gi, "");
    s = s.replace(/\s*on\w+\s*=\s*(["'][^"']*["']|[^\s>]+)/gi, "");

    return s;
}

// ── PARSER 1: Flowchart / Graph ─────────────────────────────────────────────

function _parseFlowchart(raw, lines, title) {
    if (lines.length === 0) {
        return { ok: false, type: "flowchart", error: { line: 1, msg: "Diagrama de flujo vacío" } };
    }

    var header = lines[0].text;
    var dirMatch = header.match(/^(?:flowchart|graph)[ \t]+(TB|TD|BT|LR|RL)\b/i);
    var direction = dirMatch ? dirMatch[1].toUpperCase() : "TD";
    if (direction === "TB") direction = "TD";

    var nodes = {};        // id -> { id, label, shape, classNames, style }
    var edges = [];        // [{ from, to, type, label, style, strokeDash }]
    var subgraphs = [];    // [{ id, title, nodeIds: [] }]
    var currentSub = null;
    var classes = {};      // name -> style object
    var lineIndex = 1;

    for (var i = 1; i < lines.length; i++) {
        var lineObj = lines[i];
        var line = lineObj.text;
        lineIndex = lineObj.lineNum;

        // Subgraph start: subgraph id [title], subgraph id[title] o subgraph title
        var subStart = line.match(/^subgraph[ \t]+([a-zA-Z0-9_-]+)[ \t]*(?:\[(.*)\])?[ \t]*$/i);
        if (subStart && subStart[1]) {
            var subId = subStart[1];
            var subTitle = subStart[2] ? subStart[2].trim() : subId;
            var newSub = { id: subId, title: sanitizeLabel(subTitle), nodeIds: [] };
            subgraphs.push(newSub);
            currentSub = newSub;
            continue;
        }
        var subStartFallback = line.match(/^subgraph[ \t]+(?:"([^"]+)"|'([^']+)'|([^[\]\r\n]+))[ \t]*$/i);
        if (subStartFallback) {
            var rawTitle = subStartFallback[1] || subStartFallback[2] || subStartFallback[3] || ("sub_" + subgraphs.length);
            rawTitle = rawTitle.trim();
            var fallbackId = rawTitle.replace(/[^a-zA-Z0-9_-]/g, "_").toLowerCase();
            var newSub2 = { id: fallbackId, title: sanitizeLabel(rawTitle), nodeIds: [] };
            subgraphs.push(newSub2);
            currentSub = newSub2;
            continue;
        }

        // Subgraph end
        if (/^end\b/i.test(line)) {
            currentSub = null;
            continue;
        }

        // classDef
        var classDefMatch = line.match(/^classDef[ \t]+([a-zA-Z0-9_-]+)[ \t]+(.*)$/i);
        if (classDefMatch) {
            classes[classDefMatch[1]] = _parseStyleString(classDefMatch[2]);
            continue;
        }

        // class aplicador: class A,B className
        var classApplyMatch = line.match(/^class[ \t]+([a-zA-Z0-9_,-]+)[ \t]+([a-zA-Z0-9_-]+)$/i);
        if (classApplyMatch) {
            var targetIds = classApplyMatch[1].split(",");
            var cName = classApplyMatch[2];
            for (var cIdx = 0; cIdx < targetIds.length; cIdx++) {
                var tid = targetIds[cIdx].trim();
                _ensureNode(nodes, tid, currentSub);
                nodes[tid].classNames.push(cName);
            }
            continue;
        }

        // style individual: style A fill:#f9f,stroke:#333
        var styleMatch = line.match(/^style[ \t]+([a-zA-Z0-9_-]+)[ \t]+(.*)$/i);
        if (styleMatch) {
            var sId = styleMatch[1];
            _ensureNode(nodes, sId, currentSub);
            var parsedSt = _parseStyleString(styleMatch[2]);
            Object.assign(nodes[sId].style, parsedSt);
            continue;
        }

        // linkStyle: linkStyle 0 stroke:#ff3
        var linkStyleMatch = line.match(/^linkStyle[ \t]+(\d+)[ \t]+(.*)$/i);
        if (linkStyleMatch) {
            var edgeIdx = parseInt(linkStyleMatch[1], 10);
            if (edgeIdx >= 0 && edgeIdx < edges.length) {
                Object.assign(edges[edgeIdx].style, _parseStyleString(linkStyleMatch[2]));
            }
            continue;
        }

        // Procesar declaraciones de nodos y conexiones en la línea
        _parseFlowchartStatement(line, nodes, edges, currentSub, classes);
    }

    return {
        ok: true,
        type: "flowchart",
        ast: {
            title: title,
            direction: direction,
            nodes: nodes,
            edges: edges,
            subgraphs: subgraphs,
            classes: classes
        }
    };
}

function _parseStyleString(str) {
    var res = {};
    if (!str) return res;
    var parts = str.split(",");
    for (var i = 0; i < parts.length; i++) {
        var p = parts[i].split(":");
        if (p.length === 2) {
            var k = p[0].trim().toLowerCase();
            var v = p[1].trim();
            res[k] = v;
        }
    }
    return res;
}

function _ensureNode(nodes, id, currentSub) {
    if (!nodes[id]) {
        nodes[id] = {
            id: id,
            label: id,
            shape: "rect",
            classNames: [],
            style: {}
        };
        if (currentSub && currentSub.nodeIds.indexOf(id) === -1) {
            currentSub.nodeIds.push(id);
        }
    }
}

// Tokenizador de statement en flowchart: A["label"] -->|txt| B & C
function _parseFlowchartStatement(line, nodes, edges, currentSub, classes) {
    // Regex para operadores de flecha Mermaid, con posible etiqueta pipe |texto|
    // Orden prioritario: expresiones con etiqueta inline primero, seguidas de flechas compuestas y simples
    var edgeRegex = /(--[ \t]*[^\->\s|].*?[ \t]*-->|==[ \t]*[^\=>\s|].*?[ \t]*==>|-\.[ \t]*[^\.\s|].*?[ \t]*\.->|--[ \t]*[^\->\s|].*?[ \t]*---|==[ \t]*[^\=>\s|].*?[ \t]*===|-\.[ \t]*[^\.\s|].*?[ \t]*\.-\.|<-->|o--o|x--x|--o|--x|==+>|==+|-\.->|-\.-+|--+>|--+)(?:\|([^|]+)\|)?/g;

    var parts = [];
    var lastIdx = 0;
    var match;
    var edgeTokens = [];

    while ((match = edgeRegex.exec(line)) !== null) {
        var before = line.substring(lastIdx, match.index).trim();
        if (before) parts.push(before);
        edgeTokens.push({
            arrow: match[1],
            pipeLabel: match[2] || ""
        });
        lastIdx = edgeRegex.lastIndex;
    }
    var remaining = line.substring(lastIdx).trim();
    if (remaining) parts.push(remaining);

    // Si no hay flechas, es solo declaración de nodo o nodos separados por &
    if (edgeTokens.length === 0) {
        if (parts.length > 0) {
            _parseNodeSegment(parts[0], nodes, currentSub, classes);
        }
        return;
    }

    // Si hay flechas encadenadas: P0 E0 P1 E1 P2 ...
    for (var i = 0; i < edgeTokens.length; i++) {
        var fromSeg = parts[i];
        var toSeg = parts[i + 1];
        var edgeToken = edgeTokens[i];

        if (!fromSeg || !toSeg) continue;

        var fromNodes = _parseNodeSegment(fromSeg, nodes, currentSub, classes);
        var toNodes = _parseNodeSegment(toSeg, nodes, currentSub, classes);
        var edgeInfo = _extractEdgeInfo(edgeToken.arrow);
        if (edgeToken.pipeLabel) {
            edgeInfo.label = sanitizeLabel(edgeToken.pipeLabel);
        }

        // Múltiples nodos: A & B --> C & D
        for (var f = 0; f < fromNodes.length; f++) {
            for (var t = 0; t < toNodes.length; t++) {
                edges.push({
                    from: fromNodes[f].id,
                    to: toNodes[t].id,
                    type: edgeInfo.type,
                    label: edgeInfo.label,
                    style: {},
                    strokeDash: edgeInfo.strokeDash,
                    thick: edgeInfo.thick
                });
            }
        }
    }
}

function _extractEdgeInfo(edgeStr) {
    var label = "";
    var type = "arrow"; // arrow | open | circle | cross | double_arrow
    var strokeDash = false;
    var thick = false;

    // Detectar etiqueta inline: -- texto -->, == texto ==>, -. texto .->
    var inlineLbl = edgeStr.match(/^(?:--|-\.|\=\=)[ \t]*(.+?)[ \t]*(?:-->|\.->|==>|---|===|-\.-)$/);
    if (inlineLbl) {
        label = sanitizeLabel(inlineLbl[1]);
    }

    if (edgeStr.indexOf("-.") !== -1) strokeDash = true;
    if (edgeStr.indexOf("==") !== -1) thick = true;

    if (edgeStr.indexOf("<-->") !== -1 || edgeStr.indexOf("o--o") !== -1 || edgeStr.indexOf("x--x") !== -1) {
        type = "bidirectional";
    } else if (edgeStr.indexOf("--o") !== -1) {
        type = "circle";
    } else if (edgeStr.indexOf("--x") !== -1) {
        type = "cross";
    } else if (edgeStr.endsWith(">")) {
        type = "arrow";
    } else {
        type = "open";
    }

    return {
        type: type,
        label: label,
        strokeDash: strokeDash,
        thick: thick
    };
}

function _splitAmpersand(seg) {
    var parts = [];
    var cur = "";
    var inQuotes = false;
    var bracketDepth = 0;
    for (var i = 0; i < seg.length; i++) {
        var ch = seg[i];
        if (ch === '"' && (i === 0 || seg[i - 1] !== '\\')) {
            inQuotes = !inQuotes;
        } else if (!inQuotes) {
            if (ch === '[' || ch === '(' || ch === '{') bracketDepth++;
            else if (ch === ']' || ch === ')' || ch === '}') bracketDepth--;
            else if (ch === '&' && bracketDepth === 0) {
                parts.push(cur.trim());
                cur = "";
                continue;
            }
        }
        cur += ch;
    }
    if (cur.trim()) parts.push(cur.trim());
    return parts;
}

// Parsea un segmento de nodos: A["Hola"] & B(("Mundo")):::myClass
function _parseNodeSegment(seg, nodes, currentSub, classes) {
    var rawItems = _splitAmpersand(seg);
    var res = [];

    for (var i = 0; i < rawItems.length; i++) {
        var itemStr = rawItems[i].trim();
        if (!itemStr) continue;

        // Separar posible clase adjunta: id:::className
        var classPart = "";
        var colCol = itemStr.indexOf(":::");
        if (colCol !== -1) {
            classPart = itemStr.substring(colCol + 3).trim();
            itemStr = itemStr.substring(0, colCol).trim();
        }

        // Sintaxis v11+: id@{ shape: rect, label: "hola" }
        var v11Match = itemStr.match(/^([a-zA-Z0-9_-]+)@\{[\s\S]*\}$/);
        if (v11Match) {
            var nId = v11Match[1];
            var shapeM = itemStr.match(/shape:\s*([a-zA-Z0-9_-]+)/);
            var labelM = itemStr.match(/label:\s*["']([^"']*)["']/);
            var nodeObj = {
                id: nId,
                label: labelM ? sanitizeLabel(labelM[1]) : nId,
                shape: shapeM ? shapeM[1].toLowerCase() : "rect",
                classNames: classPart ? [classPart] : [],
                style: {}
            };
            nodes[nId] = nodeObj;
            if (currentSub && currentSub.nodeIds.indexOf(nId) === -1) currentSub.nodeIds.push(nId);
            res.push(nodeObj);
            continue;
        }

        // Detección de formas clásicas con delimitadores
        var parsed = _parseNodeShape(itemStr);
        if (parsed) {
            if (classPart) parsed.classNames.push(classPart);
            nodes[parsed.id] = parsed;
            if (currentSub && currentSub.nodeIds.indexOf(parsed.id) === -1) currentSub.nodeIds.push(parsed.id);
            res.push(parsed);
        } else {
            // Nodo simple sin delimitadores: A
            var simpleId = itemStr;
            _ensureNode(nodes, simpleId, currentSub);
            if (classPart) nodes[simpleId].classNames.push(classPart);
            res.push(nodes[simpleId]);
        }
    }
    return res;
}

function _parseNodeShape(str) {
    var m;
    // Doble círculo: A(((label)))
    if ((m = str.match(/^([a-zA-Z0-9_-]+)\(\(\(([\s\S]*?)\)\)\)$/))) {
        return { id: m[1], label: sanitizeLabel(m[2]), shape: "doublecircle", classNames: [], style: {} };
    }
    // Subrutina: A[[label]]
    if ((m = str.match(/^([a-zA-Z0-9_-]+)\[\[([\s\S]*?)\]\]$/))) {
        return { id: m[1], label: sanitizeLabel(m[2]), shape: "subroutine", classNames: [], style: {} };
    }
    // Cilindro: A[(label)]
    if ((m = str.match(/^([a-zA-Z0-9_-]+)\[\(([\s\S]*?)\)\]$/))) {
        return { id: m[1], label: sanitizeLabel(m[2]), shape: "cylinder", classNames: [], style: {} };
    }
    // Estadio: A([label])
    if ((m = str.match(/^([a-zA-Z0-9_-]+)\(\[([\s\S]*?)\]\)$/))) {
        return { id: m[1], label: sanitizeLabel(m[2]), shape: "stadium", classNames: [], style: {} };
    }
    // Círculo: A((label))
    if ((m = str.match(/^([a-zA-Z0-9_-]+)\(\(([\s\S]*?)\)\)$/))) {
        return { id: m[1], label: sanitizeLabel(m[2]), shape: "circle", classNames: [], style: {} };
    }
    // Hexágono: A{{label}}
    if ((m = str.match(/^([a-zA-Z0-9_-]+)\{\{([\s\S]*?)\}\}$/))) {
        return { id: m[1], label: sanitizeLabel(m[2]), shape: "hexagon", classNames: [], style: {} };
    }
    // Rombo / Decisión: A{label}
    if ((m = str.match(/^([a-zA-Z0-9_-]+)\{([\s\S]*?)\}$/))) {
        return { id: m[1], label: sanitizeLabel(m[2]), shape: "diamond", classNames: [], style: {} };
    }
    // Paralelogramo: A[/label/] o A[\label\]
    if ((m = str.match(/^([a-zA-Z0-9_-]+)\[\/([\s\S]*?)\/\]$/))) {
        return { id: m[1], label: sanitizeLabel(m[2]), shape: "parallelogram", classNames: [], style: {} };
    }
    if ((m = str.match(/^([a-zA-Z0-9_-]+)\[\\([\s\S]*?)\\\]$/))) {
        return { id: m[1], label: sanitizeLabel(m[2]), shape: "parallelogram_alt", classNames: [], style: {} };
    }
    // Trapecio: A[/label\] o A[\label/]
    if ((m = str.match(/^([a-zA-Z0-9_-]+)\[\/([\s\S]*?)\\\]$/))) {
        return { id: m[1], label: sanitizeLabel(m[2]), shape: "trapezoid", classNames: [], style: {} };
    }
    if ((m = str.match(/^([a-zA-Z0-9_-]+)\[\\([\s\S]*?)\/\]$/))) {
        return { id: m[1], label: sanitizeLabel(m[2]), shape: "trapezoid_alt", classNames: [], style: {} };
    }
    // Asimétrico: A>label]
    if ((m = str.match(/^([a-zA-Z0-9_-]+)>([\s\S]*?)\]$/))) {
        return { id: m[1], label: sanitizeLabel(m[2]), shape: "asym", classNames: [], style: {} };
    }
    // Redondeado: A(label)
    if ((m = str.match(/^([a-zA-Z0-9_-]+)\(([\s\S]*?)\)$/))) {
        return { id: m[1], label: sanitizeLabel(m[2]), shape: "round", classNames: [], style: {} };
    }
    // Rectángulo estándar: A[label]
    if ((m = str.match(/^([a-zA-Z0-9_-]+)\[([\s\S]*?)\]$/))) {
        return { id: m[1], label: sanitizeLabel(m[2]), shape: "rect", classNames: [], style: {} };
    }
    return null;
}

// ── PARSER 2: Sequence Diagram ──────────────────────────────────────────────

function _parseSequence(raw, lines, title) {
    var participants = []; // [{ id, label, isActor }]
    var pMap = {};
    var events = [];       // [{ kind: "message"|"note"|"activate"|"deactivate"|"block_start"|"block_end", ... }]
    var autonumber = false;

    function ensureParticipant(id, label, isActor) {
        if (!pMap[id]) {
            var p = { id: id, label: label || id, isActor: !!isActor };
            participants.push(p);
            pMap[id] = p;
        }
    }

    for (var i = 1; i < lines.length; i++) {
        var line = lines[i].text;

        if (/^autonumber\b/i.test(line)) {
            autonumber = true;
            continue;
        }

        // participant A as Alice o actor A as Alice
        var pMatch = line.match(/^(participant|actor)[ \t]+([a-zA-Z0-9_-]+)(?:[ \t]+as[ \t]+(["']?)(.*?)\3)?$/i);
        if (pMatch) {
            var pType = pMatch[1].toLowerCase();
            var pId = pMatch[2];
            var pLbl = pMatch[4] ? sanitizeLabel(pMatch[4]) : pId;
            ensureParticipant(pId, pLbl, pType === "actor");
            continue;
        }

        // activate A / deactivate A
        var actMatch = line.match(/^(activate|deactivate)[ \t]+([a-zA-Z0-9_-]+)$/i);
        if (actMatch) {
            var aKind = actMatch[1].toLowerCase();
            var aId = actMatch[2];
            ensureParticipant(aId);
            events.push({ kind: aKind, target: aId });
            continue;
        }

        // Note [left of|right of|over] A[,B]: Note text
        var noteMatch = line.match(/^Note[ \t]+(left of|right of|over)[ \t]+([a-zA-Z0-9_,-]+)[ \t]*:[ \t]*(.*)$/i);
        if (noteMatch) {
            var nPos = noteMatch[1].toLowerCase();
            var nTargets = noteMatch[2].split(",").map(function(s) { return s.trim(); });
            for (var nt = 0; nt < nTargets.length; nt++) ensureParticipant(nTargets[nt]);
            events.push({
                kind: "note",
                position: nPos,
                targets: nTargets,
                text: sanitizeLabel(noteMatch[3])
            });
            continue;
        }

        // Bloques de control: loop, alt, else, opt, par, and, critical, end, break
        var blockMatch = line.match(/^(loop|alt|else|opt|par|and|critical|option|break)\b[ \t]*(.*)$/i);
        if (blockMatch) {
            var bType = blockMatch[1].toLowerCase();
            var bLbl = sanitizeLabel(blockMatch[2]);
            events.push({ kind: "control", controlType: bType, label: bLbl });
            continue;
        }
        if (/^end\b/i.test(line)) {
            events.push({ kind: "control", controlType: "end", label: "" });
            continue;
        }

        // Mensajes: A->>+B: Hola o A-->>-B: Chau
        // Flechas soportadas: ->>, -->>, ->, -->, -x, --x, -), --)
        var msgMatch = line.match(/^([a-zA-Z0-9_]+)[ \t]*(-->>|->>|-->|->|--x|-x|--\)|-\))[ \t]*([+-]?)([a-zA-Z0-9_]+)[ \t]*:[ \t]*(.*)$/);
        if (msgMatch) {
            var from = msgMatch[1];
            var arrow = msgMatch[2];
            var modifier = msgMatch[3]; // + activa, - desactiva
            var to = msgMatch[4];
            var msgText = sanitizeLabel(msgMatch[5]);

            ensureParticipant(from);
            ensureParticipant(to);

            var isDotted = arrow.indexOf("--") !== -1;
            var arrowKind = "arrow";
            if (arrow.indexOf("x") !== -1) arrowKind = "cross";
            else if (arrow.indexOf(")") !== -1) arrowKind = "open";

            events.push({
                kind: "message",
                from: from,
                to: to,
                arrow: arrowKind,
                dotted: isDotted,
                text: msgText,
                modifier: modifier
            });
            continue;
        }
    }

    return {
        ok: true,
        type: "sequenceDiagram",
        ast: {
            title: title,
            autonumber: autonumber,
            participants: participants,
            events: events
        }
    };
}

// ── PARSER 3: Pie Chart ─────────────────────────────────────────────────────

function _parsePie(raw, lines, title) {
    var showData = false;
    var pieTitle = title;
    var slices = []; // [{ label, value }]
    var total = 0;

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].text;
        if (i === 0) {
            if (/showData\b/i.test(line)) showData = true;
            var tMatch = line.match(/title[ \t]+(["']?)(.*?)\1$/i);
            if (tMatch && !pieTitle) pieTitle = sanitizeLabel(tMatch[2]);
            continue;
        }

        // Título en línea separada
        var titleLine = line.match(/^title[ \t]+(["']?)(.*?)\1$/i);
        if (titleLine) {
            pieTitle = sanitizeLabel(titleLine[2]);
            continue;
        }

        // Slice: "Etiqueta" : 45.5 o Etiqueta : 45.5
        var sliceMatch = line.match(/^(?:["'](.*?)["']|([^:]+?))[ \t]*:[ \t]*([0-9]+(?:\.[0-9]+)?)$/);
        if (sliceMatch) {
            var lbl = sanitizeLabel(sliceMatch[1] || sliceMatch[2]);
            var val = parseFloat(sliceMatch[3]);
            if (!isNaN(val) && val > 0) {
                slices.push({ label: lbl, value: val });
                total += val;
            }
        }
    }

    return {
        ok: true,
        type: "pie",
        ast: {
            title: pieTitle,
            showData: showData,
            slices: slices,
            total: total
        }
    };
}

// ── PARSER 4: State Diagram (stateDiagram / stateDiagram-v2) ─────────────────

function _parseState(raw, lines, title) {
    var states = {};      // id -> { id, label, isStart, isEnd, isComposite, isChoice, isFork, isJoin }
    var transitions = []; // [{ from, to, label }]
    var notes = [];

    function ensureState(id, label) {
        if (!states[id]) {
            states[id] = {
                id: id,
                label: label || id,
                isStart: id === "[*]",
                isEnd: false,
                isChoice: false,
                isFork: false,
                isJoin: false
            };
        }
    }

    for (var i = 1; i < lines.length; i++) {
        var line = lines[i].text;

        // state "Desc" as id
        var asMatch = line.match(/^state[ \t]+["'](.*?)["'][ \t]+as[ \t]+([a-zA-Z0-9_*-]+)$/i);
        if (asMatch) {
            ensureState(asMatch[2], sanitizeLabel(asMatch[1]));
            continue;
        }

        // id: Desc
        var colonMatch = line.match(/^([a-zA-Z0-9_*-]+)[ \t]*:[ \t]*(.*)$/);
        if (colonMatch && line.indexOf("-->") === -1) {
            ensureState(colonMatch[1], sanitizeLabel(colonMatch[2]));
            continue;
        }

        // <<choice>>, <<fork>>, <<join>>
        var stereoMatch = line.match(/^state[ \t]+([a-zA-Z0-9_*-]+)[ \t]+<<(choice|fork|join)>>$/i);
        if (stereoMatch) {
            var stId = stereoMatch[1];
            var kind = stereoMatch[2].toLowerCase();
            ensureState(stId);
            if (kind === "choice") states[stId].isChoice = true;
            if (kind === "fork") states[stId].isFork = true;
            if (kind === "join") states[stId].isJoin = true;
            continue;
        }

        // Transición: A --> B: label o [*] --> A
        var transMatch = line.match(/^([a-zA-Z0-9_*-]+|\[\*\])[ \t]*-->[ \t]*([a-zA-Z0-9_*-]+|\[\*\])(?:[ \t]*:[ \t]*(.*))?$/);
        if (transMatch) {
            var from = transMatch[1];
            var to = transMatch[2];
            var lbl = transMatch[3] ? sanitizeLabel(transMatch[3]) : "";

            var actualFrom = from;
            var actualTo = to;

            // Manejo de [*] como inicio y fin
            if (from === "[*]") {
                actualFrom = "start_" + transitions.length;
                states[actualFrom] = { id: actualFrom, label: "", isStart: true };
            }
            if (to === "[*]") {
                actualTo = "end_" + transitions.length;
                states[actualTo] = { id: actualTo, label: "", isEnd: true };
            }

            ensureState(actualFrom);
            ensureState(actualTo);

            transitions.push({
                from: actualFrom,
                to: actualTo,
                label: lbl
            });
            continue;
        }
    }

    return {
        ok: true,
        type: "stateDiagram",
        ast: {
            title: title,
            states: states,
            transitions: transitions
        }
    };
}

// ── 5. PARSER DE DIAGRAMAS DE CLASES (UML) ───────────────────────────────────

function _parseClassDiagram(content, lines, title) {
    var classes = {};
    var relations = [];
    var notes = [];
    var direction = "TB";

    function ensureClass(id, label) {
        if (!classes[id]) {
            classes[id] = {
                id: id,
                label: label || id,
                stereotype: "",
                attributes: [],
                methods: []
            };
        } else if (label && classes[id].label === id) {
            classes[id].label = label;
        }
        return classes[id];
    }

    var i = 0;
    while (i < lines.length) {
        var item = lines[i];
        var line = item.text.trim();
        i++;

        if (/^classDiagram(-v2)?\b/i.test(line)) continue;
        if (/^direction\s+(TB|TD|BT|LR|RL)\b/i.test(line)) {
            var dm = line.match(/^direction\s+(TB|TD|BT|LR|RL)\b/i);
            if (dm) direction = dm[1].toUpperCase();
            continue;
        }

        // Note: note "..." or note for Class "..."
        var noteForMatch = line.match(/^note\s+for\s+([a-zA-Z0-9_*-]+)\s+["\x27]([\s\S]*?)["\x27]$/i);
        if (noteForMatch) {
            notes.push({ forClass: noteForMatch[1], text: sanitizeLabel(noteForMatch[2]) });
            continue;
        }
        var noteMatch = line.match(/^note\s+["\x27]([\s\S]*?)["\x27]$/i);
        if (noteMatch) {
            notes.push({ forClass: "", text: sanitizeLabel(noteMatch[1]) });
            continue;
        }

        // Estereotipo standalone: <<interface>> ClassName
        var stMatch = line.match(/^<<([a-zA-Z0-9_*-]+)>>\s+([a-zA-Z0-9_*-]+)$/i);
        if (stMatch) {
            var c = ensureClass(stMatch[2]);
            c.stereotype = stMatch[1];
            continue;
        }

        // Bloque de clase: class ClassName [ "label" ] { ... }
        var classBlockMatch = line.match(/^class\s+([a-zA-Z0-9_*-]+)(?:\["([^"]+)"\])?\s*\{?$/i);
        if (classBlockMatch && (line.endsWith("{") || (i < lines.length && lines[i].text.trim() === "{"))) {
            var cId = classBlockMatch[1];
            var cLbl = classBlockMatch[2] || cId;
            var cls = ensureClass(cId, cLbl);
            if (!line.endsWith("{") && i < lines.length && lines[i].text.trim() === "{") i++;

            while (i < lines.length) {
                var innerLine = lines[i].text.trim();
                i++;
                if (innerLine === "}") break;
                if (!innerLine) continue;

                var innerStMatch = innerLine.match(/^<<([a-zA-Z0-9_*-]+)>>$/);
                if (innerStMatch) {
                    cls.stereotype = innerStMatch[1];
                    continue;
                }

                _parseClassMember(cls, innerLine);
            }
            continue;
        }

        // Declaración simple: class ClassName
        var classSimpleMatch = line.match(/^class\s+([a-zA-Z0-9_*-]+)(?:\["([^"]+)"\])?$/i);
        if (classSimpleMatch) {
            ensureClass(classSimpleMatch[1], classSimpleMatch[2] || classSimpleMatch[1]);
            continue;
        }

        // Miembro simple en línea: ClassName : +int age o ClassName : +swim()
        var singleMemberMatch = line.match(/^([a-zA-Z0-9_*-]+)\s*:\s*([\s\S]+)$/);
        if (singleMemberMatch && !line.includes("-->") && !line.includes("--|") && !line.includes("<|--") && !line.includes("*--") && !line.includes("o--")) {
            var sc = ensureClass(singleMemberMatch[1]);
            _parseClassMember(sc, singleMemberMatch[2]);
            continue;
        }

        // Relaciones: ClassA "card1" <rel> "card2" ClassB : label
        var relRegex = /^([a-zA-Z0-9_*-]+)(?:\s+"([^"]*)")?\s*([<*o]?\|?--\|?[>*o]?|[<*o]?\|?\.\.\|?[>*o]?)(?:\s+"([^"]*)")?\s*([a-zA-Z0-9_*-]+)(?:\s*:\s*(.*))?$/;
        var rm = line.match(relRegex);
        if (rm) {
            var fromId = rm[1];
            var fromCard = rm[2] || "";
            var conn = rm[3];
            var toCard = rm[4] || "";
            var toId = rm[5];
            var rLabel = rm[6] ? sanitizeLabel(rm[6]) : "";

            ensureClass(fromId);
            ensureClass(toId);

            var relInfo = _analyzeClassConnector(conn);
            relations.push({
                from: fromId,
                to: toId,
                fromCard: fromCard,
                toCard: toCard,
                relType: relInfo.type,
                lineStyle: relInfo.lineStyle,
                fromMarker: relInfo.fromMarker,
                toMarker: relInfo.toMarker,
                label: rLabel
            });
            continue;
        }
    }

    return {
        ok: true,
        type: "classDiagram",
        ast: {
            title: title,
            direction: direction,
            classes: classes,
            relations: relations,
            notes: notes
        }
    };
}

function _parseClassMember(cls, text) {
    var raw = text.trim();
    if (!raw) return;

    var vis = "";
    if (/^[+\-#~]/.test(raw)) {
        vis = raw[0];
        raw = raw.substring(1).trim();
    }

    var isStatic = false;
    var isAbstract = false;
    if (raw.endsWith("$")) {
        isStatic = true;
        raw = raw.substring(0, raw.length - 1).trim();
    } else if (raw.endsWith("*")) {
        isAbstract = true;
        raw = raw.substring(0, raw.length - 1).trim();
    }

    var isMethod = raw.includes("(") && raw.includes(")");
    var member = {
        visibility: vis,
        text: raw,
        isStatic: isStatic,
        isAbstract: isAbstract
    };

    if (isMethod) {
        cls.methods.push(member);
    } else {
        cls.attributes.push(member);
    }
}

function _analyzeClassConnector(conn) {
    var lineStyle = conn.includes("..") ? "dashed" : "solid";
    var fromMarker = "";
    var toMarker = "";
    var type = "association";

    if (conn.startsWith("<|")) {
        fromMarker = "triangle";
        type = "inheritance";
    } else if (conn.startsWith("*")) {
        fromMarker = "diamond_filled";
        type = "composition";
    } else if (conn.startsWith("o")) {
        fromMarker = "diamond_hollow";
        type = "aggregation";
    } else if (conn.startsWith("<")) {
        fromMarker = "open_arrow";
    }

    if (conn.endsWith("|>")) {
        toMarker = "triangle";
        type = "inheritance";
    } else if (conn.endsWith("*")) {
        toMarker = "diamond_filled";
        type = "composition";
    } else if (conn.endsWith("o")) {
        toMarker = "diamond_hollow";
        type = "aggregation";
    } else if (conn.endsWith(">")) {
        toMarker = (type === "inheritance" || type === "composition" || type === "aggregation") ? toMarker : "open_arrow";
    }

    return {
        type: type,
        lineStyle: lineStyle,
        fromMarker: fromMarker,
        toMarker: toMarker
    };
}

// ── 6. PARSER DE DIAGRAMAS ENTIDAD-RELACIÓN (ER) ─────────────────────────────

function _parseErDiagram(content, lines, title) {
    var entities = {};
    var relations = [];

    function ensureEntity(id) {
        if (!entities[id]) {
            entities[id] = { id: id, attributes: [] };
        }
        return entities[id];
    }

    var i = 0;
    while (i < lines.length) {
        var item = lines[i];
        var line = item.text.trim();
        i++;

        if (/^erDiagram\b/i.test(line)) continue;

        // Entidad con atributos: ENTITY { ... }
        var entityBlockMatch = line.match(/^([a-zA-Z0-9_*-]+)\s*\{?$/);
        if (entityBlockMatch && (line.endsWith("{") || (i < lines.length && lines[i].text.trim() === "{"))) {
            var entId = entityBlockMatch[1];
            var ent = ensureEntity(entId);
            if (!line.endsWith("{") && i < lines.length && lines[i].text.trim() === "{") i++;

            while (i < lines.length) {
                var innerLine = lines[i].text.trim();
                i++;
                if (innerLine === "}") break;
                if (!innerLine) continue;

                var attrMatch = innerLine.match(/^([a-zA-Z0-9_<>[\]]+)\s+([a-zA-Z0-9_*-]+)(?:\s+(PK|FK|UK))?(?:\s+["\x27](.*?)["\x27])?/i);
                if (attrMatch) {
                    ent.attributes.push({
                        type: attrMatch[1],
                        name: attrMatch[2],
                        key: (attrMatch[3] || "").toUpperCase(),
                        comment: attrMatch[4] || ""
                    });
                }
            }
            continue;
        }

        // Relación: ENT1 <card1><conn><card2> ENT2 : label
        var relMatch = line.match(/^([a-zA-Z0-9_*-]+)\s+([|o}{]+)(--|\.\.)([|o}{]+)\s+([a-zA-Z0-9_*-]+)\s*:\s*["\x27]?(.*?)["\x27]?$/);
        if (relMatch) {
            var e1 = relMatch[1];
            var c1 = relMatch[2];
            var conn = relMatch[3];
            var c2 = relMatch[4];
            var e2 = relMatch[5];
            var lbl = relMatch[6] ? relMatch[6].trim() : "";

            ensureEntity(e1);
            ensureEntity(e2);

            relations.push({
                from: e1,
                to: e2,
                card1: c1,
                connector: conn,
                card2: c2,
                label: lbl,
                identifying: conn === "--",
                fromMarker: _cardToMarker(c1),
                toMarker: _cardToMarker(c2)
            });
            continue;
        }
    }

    return {
        ok: true,
        type: "erDiagram",
        ast: {
            title: title,
            entities: entities,
            relations: relations
        }
    };
}

function _cardToMarker(card) {
    if (card === "||") return "crows_foot_one";
    if (card === "|o" || card === "o|") return "crows_foot_zero_or_one";
    if (card === "}|" || card === "|{") return "crows_foot_many";
    if (card === "}o" || card === "o{") return "crows_foot_zero_or_many";
    return "crows_foot_one";
}

// ── 7. PARSER DE DIAGRAMAS DE GANTT ──────────────────────────────────────────

function _parseGantt(content, lines, title) {
    var chartTitle = title || "";
    var dateFormat = "YYYY-MM-DD";
    var axisFormat = "";
    var sections = [];
    var curSection = { name: "General", tasks: [] };
    sections.push(curSection);

    var taskOrder = 0;

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].text.trim();
        if (/^gantt\b/i.test(line)) continue;

        var titleMatch = line.match(/^title\s+(.*)$/i);
        if (titleMatch) {
            chartTitle = titleMatch[1].trim();
            continue;
        }
        var dfMatch = line.match(/^dateFormat\s+(.*)$/i);
        if (dfMatch) {
            dateFormat = dfMatch[1].trim();
            continue;
        }
        var afMatch = line.match(/^axisFormat\s+(.*)$/i);
        if (afMatch) {
            axisFormat = afMatch[1].trim();
            continue;
        }

        var secMatch = line.match(/^section\s+(.*)$/i);
        if (secMatch) {
            curSection = { name: secMatch[1].trim(), tasks: [] };
            sections.push(curSection);
            continue;
        }

        var colonIdx = line.indexOf(":");
        if (colonIdx !== -1) {
            var tName = line.substring(0, colonIdx).trim();
            var metaPart = line.substring(colonIdx + 1).trim();
            var tokens = metaPart.split(",").map(function(t) { return t.trim(); }).filter(Boolean);

            var tags = [];
            var id = "";
            var start = "";
            var endOrDuration = "";

            for (var k = 0; k < tokens.length; k++) {
                var tok = tokens[k];
                var low = tok.toLowerCase();
                if (low === "done" || low === "active" || low === "crit" || low === "milestone") {
                    tags.push(low);
                } else if (!id && /^[a-zA-Z0-9_*-]+$/.test(tok) && !/^\d{4}/.test(tok) && !tok.startsWith("after") && !tok.endsWith("d") && !tok.endsWith("w")) {
                    id = tok;
                } else if (!start) {
                    start = tok;
                } else if (!endOrDuration) {
                    endOrDuration = tok;
                }
            }

            if (!id) id = "task_" + (++taskOrder);
            if (!endOrDuration && start && (start.endsWith("d") || start.endsWith("w") || start.endsWith("h"))) {
                endOrDuration = start;
                start = "";
            }

            curSection.tasks.push({
                name: tName,
                id: id,
                tags: tags,
                start: start,
                endOrDuration: endOrDuration,
                isDone: tags.indexOf("done") !== -1,
                isActive: tags.indexOf("active") !== -1,
                isCrit: tags.indexOf("crit") !== -1,
                isMilestone: tags.indexOf("milestone") !== -1 || endOrDuration === "0d"
            });
        }
    }

    sections = sections.filter(function(s) { return s.tasks.length > 0 || s.name !== "General"; });

    return {
        ok: true,
        type: "gantt",
        ast: {
            title: chartTitle,
            dateFormat: dateFormat,
            axisFormat: axisFormat,
            sections: sections
        }
    };
}

// ── 8. PARSER DE DIAGRAMAS DE TIMELINE ───────────────────────────────────────

function _parseTimeline(content, lines, title) {
    var timelineTitle = title || "";
    var sections = [];
    var curSection = { name: "", periods: [] };
    sections.push(curSection);

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].text.trim();
        if (/^timeline\b/i.test(line)) continue;

        var tMatch = line.match(/^title\s+(.*)$/i);
        if (tMatch) {
            timelineTitle = tMatch[1].trim();
            continue;
        }

        var secMatch = line.match(/^section\s+(.*)$/i);
        if (secMatch) {
            curSection = { name: secMatch[1].trim(), periods: [] };
            sections.push(curSection);
            continue;
        }

        var parts = line.split(":").map(function(p) { return p.trim(); }).filter(Boolean);
        if (parts.length >= 2) {
            var periodName = parts[0];
            var events = parts.slice(1);
            curSection.periods.push({
                period: periodName,
                events: events
            });
        } else if (parts.length === 1 && curSection.periods.length > 0) {
            var lastP = curSection.periods[curSection.periods.length - 1];
            lastP.events.push(parts[0]);
        }
    }

    sections = sections.filter(function(s) { return s.periods.length > 0; });

    return {
        ok: true,
        type: "timeline",
        ast: {
            title: timelineTitle,
            sections: sections
        }
    };
}

// ── 9. PARSER DE DIAGRAMAS DE MINDMAP ────────────────────────────────────────

function _parseMindmap(content, lines, title) {
    var nodes = [];
    for (var i = 0; i < lines.length; i++) {
        var orig = lines[i].orig;
        var trimmed = lines[i].text.trim();
        if (/^mindmap\b/i.test(trimmed)) continue;
        if (!trimmed) continue;

        var indentMatch = orig.match(/^([ \t]*)/);
        var indentLen = indentMatch ? indentMatch[1].replace(/\t/g, "  ").length : 0;

        var shape = "rect";
        var label = trimmed;
        var id = "";

        var idMatch = trimmed.match(/^([a-zA-Z0-9_*-]+)?(\(\(|\(|\[|\)\)|\))([\s\S]*?)(\)\)|\)|\]|\(\(|\()$/);
        if (idMatch) {
            id = idMatch[1] || "";
            var openB = idMatch[2];
            var innerC = idMatch[3].trim();
            var closeB = idMatch[4];
            label = innerC;

            if (openB === "((" && closeB === "))") shape = "circle";
            else if (openB === "(" && closeB === ")") shape = "round";
            else if (openB === "[" && closeB === "]") shape = "rect";
            else if (openB === ")" && closeB === "(") shape = "cloud";
            else if (openB === "))" && closeB === "((") shape = "bang";
        }

        nodes.push({
            indent: indentLen,
            label: label,
            id: id,
            shape: shape
        });
    }

    if (nodes.length === 0) {
        return { ok: true, type: "mindmap", ast: { root: null, title: title } };
    }

    var rootNode = { label: nodes[0].label, id: nodes[0].id || "root", shape: nodes[0].shape, children: [] };
    var stack = [{ node: rootNode, indent: nodes[0].indent }];

    for (var j = 1; j < nodes.length; j++) {
        var curr = nodes[j];
        var itemNode = { label: curr.label, id: curr.id || ("node_" + j), shape: curr.shape, children: [] };

        while (stack.length > 1 && stack[stack.length - 1].indent >= curr.indent) {
            stack.pop();
        }

        var parentNode = stack[stack.length - 1].node;
        parentNode.children.push(itemNode);
        stack.push({ node: itemNode, indent: curr.indent });
    }

    return {
        ok: true,
        type: "mindmap",
        ast: {
            title: title,
            root: rootNode
        }
    };
}

// ── 10. PARSER DE GIT GRAPH (FASE 3) ─────────────────────────────────────────

function _parseGitGraph(content, lines, title) {
    var dir = "LR";
    var chartTitle = title || "";
    var branches = {};
    var branchList = [];
    var activeBranch = "main";
    var commits = [];
    var headOfBranch = {};

    function ensureBranch(bName, order) {
        if (!branches[bName]) {
            var bObj = { name: bName, order: order !== undefined ? order : branchList.length };
            branches[bName] = bObj;
            branchList.push(bObj);
            headOfBranch[bName] = null;
        }
        return branches[bName];
    }

    ensureBranch("main", 0);

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].text.trim();
        if (/^gitGraph\b/i.test(line)) {
            var dirMatch = line.match(/^gitGraph\s*:\s*(LR|TB|BT|RL)/i) || line.match(/^gitGraph\s+(LR|TB|BT|RL)/i);
            if (dirMatch) dir = dirMatch[1].toUpperCase();
            continue;
        }
        var tMatch = line.match(/^title\s+(.*)$/i);
        if (tMatch) {
            chartTitle = tMatch[1].trim();
            continue;
        }

        var bMatch = line.match(/^branch\s+([a-zA-Z0-9_\-\.\/]+)(?:\s+order:\s*(\d+))?/i);
        if (bMatch) {
            var bName = bMatch[1];
            var ord = bMatch[2] ? parseInt(bMatch[2], 10) : undefined;
            ensureBranch(bName, ord);
            headOfBranch[bName] = headOfBranch[activeBranch];
            continue;
        }

        var coMatch = line.match(/^checkout\s+([a-zA-Z0-9_\-\.\/]+)/i);
        if (coMatch) {
            var targetB = coMatch[1];
            ensureBranch(targetB);
            activeBranch = targetB;
            continue;
        }

        var commitMatch = line.match(/^commit\b(.*)$/i);
        if (commitMatch) {
            var rest = commitMatch[1];
            var idMatch = rest.match(/id:\s*"([^"]+)"/) || rest.match(/id:\s*([^\s]+)/);
            var tagMatch = rest.match(/tag:\s*"([^"]+)"/) || rest.match(/tag:\s*([^\s]+)/);
            var typeMatch = rest.match(/type:\s*([A-Z_]+)/i);

            var cId = idMatch ? idMatch[1] : ("c" + commits.length);
            var cTag = tagMatch ? tagMatch[1] : "";
            var cType = typeMatch ? typeMatch[1].toUpperCase() : "NORMAL";

            var parents = [];
            if (headOfBranch[activeBranch]) {
                parents.push(headOfBranch[activeBranch]);
            }

            var commitObj = {
                id: cId,
                branch: activeBranch,
                parents: parents,
                tag: cTag,
                type: cType,
                seq: commits.length
            };
            commits.push(commitObj);
            headOfBranch[activeBranch] = cId;
            continue;
        }

        var mergeMatch = line.match(/^merge\s+([a-zA-Z0-9_\-\.\/]+)(.*)$/i);
        if (mergeMatch) {
            var mBranch = mergeMatch[1];
            var mRest = mergeMatch[2] || "";
            var mIdMatch = mRest.match(/id:\s*"([^"]+)"/) || mRest.match(/id:\s*([^\s]+)/);
            var mTagMatch = mRest.match(/tag:\s*"([^"]+)"/) || mRest.match(/tag:\s*([^\s]+)/);
            var mTypeMatch = mRest.match(/type:\s*([A-Z_]+)/i);

            var mId = mIdMatch ? mIdMatch[1] : ("merge_" + commits.length);
            var mTag = mTagMatch ? mTagMatch[1] : "";
            var mType = mTypeMatch ? mTypeMatch[1].toUpperCase() : "NORMAL";

            var mParents = [];
            if (headOfBranch[activeBranch]) mParents.push(headOfBranch[activeBranch]);
            if (headOfBranch[mBranch]) mParents.push(headOfBranch[mBranch]);

            var mergeObj = {
                id: mId,
                branch: activeBranch,
                parents: mParents,
                mergedFrom: mBranch,
                tag: mTag,
                type: mType,
                seq: commits.length
            };
            commits.push(mergeObj);
            headOfBranch[activeBranch] = mId;
            continue;
        }

        var cpMatch = line.match(/^cherry-pick\s+id:\s*"([^"]+)"/i) || line.match(/^cherry-pick\s+id:\s*([^\s]+)/i);
        if (cpMatch) {
            var cpId = cpMatch[1];
            var cpParents = [];
            if (headOfBranch[activeBranch]) cpParents.push(headOfBranch[activeBranch]);
            var cpObj = {
                id: "cp_" + cpId,
                branch: activeBranch,
                parents: cpParents,
                cherryPickedFrom: cpId,
                tag: "",
                type: "NORMAL",
                seq: commits.length
            };
            commits.push(cpObj);
            headOfBranch[activeBranch] = cpObj.id;
            continue;
        }
    }

    branchList.sort(function(a, b) { return a.order - b.order; });

    return {
        ok: true,
        type: "gitGraph",
        ast: {
            title: chartTitle,
            direction: dir,
            branches: branchList,
            commits: commits
        }
    };
}

// ── 11. PARSER DE QUADRANT CHART (FASE 3) ────────────────────────────────────

function _parseQuadrantChart(content, lines, title) {
    var chartTitle = title || "";
    var xAxis = { left: "", right: "" };
    var yAxis = { bottom: "", top: "" };
    var quadrants = { q1: "", q2: "", q3: "", q4: "" };
    var points = [];

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].text.trim();
        if (/^quadrantChart\b/i.test(line)) continue;

        var tMatch = line.match(/^title\s+(.*)$/i);
        if (tMatch) {
            chartTitle = tMatch[1].trim();
            continue;
        }

        var xMatch = line.match(/^x-axis\s+(.*?)(?:\s+-->\s+(.*))?$/i);
        if (xMatch) {
            xAxis.left = xMatch[1].trim();
            xAxis.right = xMatch[2] ? xMatch[2].trim() : "";
            continue;
        }

        var yMatch = line.match(/^y-axis\s+(.*?)(?:\s+-->\s+(.*))?$/i);
        if (yMatch) {
            yAxis.bottom = yMatch[1].trim();
            yAxis.top = yMatch[2] ? yMatch[2].trim() : "";
            continue;
        }

        var qMatch = line.match(/^quadrant-([1-4])\s+(.*)$/i);
        if (qMatch) {
            quadrants["q" + qMatch[1]] = qMatch[2].trim();
            continue;
        }

        var pMatch = line.match(/^([^:]+):\s*\[\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\]/);
        if (pMatch) {
            points.push({
                label: pMatch[1].trim().replace(/^["']|["']$/g, ""),
                x: Math.max(0, Math.min(1, parseFloat(pMatch[2]))),
                y: Math.max(0, Math.min(1, parseFloat(pMatch[3])))
            });
            continue;
        }
    }

    return {
        ok: true,
        type: "quadrantChart",
        ast: {
            title: chartTitle,
            xAxis: xAxis,
            yAxis: yAxis,
            quadrants: quadrants,
            points: points
        }
    };
}

// ── 12. PARSER DE USER JOURNEY (FASE 3) ──────────────────────────────────────

function _parseJourney(content, lines, title) {
    var journeyTitle = title || "";
    var sections = [];
    var curSection = { name: "General", tasks: [] };
    sections.push(curSection);
    var actorSet = {};

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].text.trim();
        if (/^journey\b/i.test(line)) continue;

        var tMatch = line.match(/^title\s+(.*)$/i);
        if (tMatch) {
            journeyTitle = tMatch[1].trim();
            continue;
        }

        var sMatch = line.match(/^section\s+(.*)$/i);
        if (sMatch) {
            curSection = { name: sMatch[1].trim(), tasks: [] };
            sections.push(curSection);
            continue;
        }

        var parts = line.split(":");
        if (parts.length >= 2) {
            var taskName = parts[0].trim();
            var score = parseInt(parts[1].trim(), 10);
            if (isNaN(score)) score = 3;
            score = Math.max(1, Math.min(5, score));

            var actors = [];
            if (parts.length >= 3) {
                actors = parts[2].split(",").map(function(a) { return a.trim(); }).filter(Boolean);
                for (var ai = 0; ai < actors.length; ai++) actorSet[actors[ai]] = true;
            }

            curSection.tasks.push({
                name: taskName,
                score: score,
                actors: actors
            });
        }
    }

    sections = sections.filter(function(s) { return s.tasks.length > 0; });
    if (sections.length === 0) sections.push({ name: "General", tasks: [] });

    return {
        ok: true,
        type: "journey",
        ast: {
            title: journeyTitle,
            sections: sections,
            actors: Object.keys(actorSet)
        }
    };
}

// ── 13. PARSER DE XY CHART (FASE 3) ──────────────────────────────────────────

function _parseXyChart(content, lines, title) {
    var chartTitle = title || "";
    var xAxis = { title: "", categories: [], min: null, max: null };
    var yAxis = { title: "", min: null, max: null };
    var plots = [];

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].text.trim();
        if (/^xychart(-beta)?\b/i.test(line)) continue;

        var tMatch = line.match(/^title\s+(?:"([^"]+)"|(.*))$/i);
        if (tMatch) {
            chartTitle = (tMatch[1] || tMatch[2] || "").trim();
            continue;
        }

        var xMatch = line.match(/^x-axis\s+(.*)$/i);
        if (xMatch) {
            var xBody = xMatch[1].trim();
            var titleInX = xBody.match(/^"([^"]+)"\s*(.*)$/);
            if (titleInX) {
                xAxis.title = titleInX[1].trim();
                xBody = titleInX[2].trim();
            }
            var arrMatch = xBody.match(/\[(.*?)\]/);
            if (arrMatch) {
                xAxis.categories = arrMatch[1].split(",").map(function(s) {
                    return s.trim().replace(/^["']|["']$/g, "");
                }).filter(Boolean);
            } else {
                var rangeMatch = xBody.match(/([0-9.-]+)\s*-->\s*([0-9.-]+)/);
                if (rangeMatch) {
                    xAxis.min = parseFloat(rangeMatch[1]);
                    xAxis.max = parseFloat(rangeMatch[2]);
                }
            }
            continue;
        }

        var yMatch = line.match(/^y-axis\s+(.*)$/i);
        if (yMatch) {
            var yBody = yMatch[1].trim();
            var titleInY = yBody.match(/^"([^"]+)"\s*(.*)$/);
            if (titleInY) {
                yAxis.title = titleInY[1].trim();
                yBody = titleInY[2].trim();
            }
            var yRangeMatch = yBody.match(/([0-9.-]+)\s*-->\s*([0-9.-]+)/);
            if (yRangeMatch) {
                yAxis.min = parseFloat(yRangeMatch[1]);
                yAxis.max = parseFloat(yRangeMatch[2]);
            }
            continue;
        }

        var barMatch = line.match(/^bar\s*\[(.*?)\]/i);
        if (barMatch) {
            var bVals = barMatch[1].split(",").map(function(s) { return parseFloat(s.trim()); }).filter(function(v) { return !isNaN(v); });
            plots.push({ type: "bar", values: bVals });
            continue;
        }

        var linePlotMatch = line.match(/^line\s*\[(.*?)\]/i);
        if (linePlotMatch) {
            var lVals = linePlotMatch[1].split(",").map(function(s) { return parseFloat(s.trim()); }).filter(function(v) { return !isNaN(v); });
            plots.push({ type: "line", values: lVals });
            continue;
        }
    }

    return {
        ok: true,
        type: "xychart",
        ast: {
            title: chartTitle,
            xAxis: xAxis,
            yAxis: yAxis,
            plots: plots
        }
    };
}
