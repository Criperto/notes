.pragma library

// MermaidLayout.js — Motor de layout geométrico nativo para diagramas Mermaid
// Recibe un AST y una función measure(text, fontPx) -> { width, height }
// Produce un objeto de geometría pura listo para renderizar sin lógica de dibujo

function layout(parsed, measureFn, options) {
    if (!parsed || !parsed.ok || !parsed.ast) {
        return { ok: false, error: parsed ? parsed.error : { msg: "AST inválido" } };
    }

    var opts = options || {};
    var maxW = opts.maxWidth || 800;
    var baseFontPx = opts.fontSize || 13;
    var mFn = typeof measureFn === "function" ? measureFn : function(t) {
        var lines = (t || "").split("\n");
        var maxL = 0;
        for (var i = 0; i < lines.length; i++) if (lines[i].length > maxL) maxL = lines[i].length;
        return { width: Math.max(30, maxL * baseFontPx * 0.6), height: lines.length * (baseFontPx * 1.35) };
    };

    switch (parsed.type) {
        case "flowchart":
            return _layoutFlowchart(parsed.ast, mFn, opts);
        case "sequenceDiagram":
            return _layoutSequence(parsed.ast, mFn, opts);
        case "pie":
            return _layoutPie(parsed.ast, mFn, opts);
        case "stateDiagram":
            return _layoutState(parsed.ast, mFn, opts);
        case "classDiagram":
            return _layoutClassDiagram(parsed.ast, mFn, opts);
        case "erDiagram":
            return _layoutErDiagram(parsed.ast, mFn, opts);
        case "gantt":
            return _layoutGantt(parsed.ast, mFn, opts);
        case "timeline":
            return _layoutTimeline(parsed.ast, mFn, opts);
        case "mindmap":
            return _layoutMindmap(parsed.ast, mFn, opts);
        case "gitGraph":
            return _layoutGitGraph(parsed.ast, mFn, opts);
        case "quadrantChart":
            return _layoutQuadrantChart(parsed.ast, mFn, opts);
        case "journey":
            return _layoutJourney(parsed.ast, mFn, opts);
        case "xychart":
            return _layoutXyChart(parsed.ast, mFn, opts);
        case "empty":
            return { ok: true, width: 200, height: 60, empty: true };
        default:
            return { ok: false, error: { msg: "Tipo no soportado: " + parsed.type } };
    }
}

// ── 1. FLOWCHART LAYOUT (Sugiyama simplificado) ─────────────────────────────

function _layoutFlowchart(ast, measure, opts) {
    var rawNodes = ast.nodes || {};
    var rawEdges = ast.edges || [];
    var dir = ast.direction || "TD";
    var isHorizontal = (dir === "LR" || dir === "RL");
    var isReverse = (dir === "BT" || dir === "RL");
    var baseFontPx = (opts && opts.fontSize) ? opts.fontSize : 13;

    var nodeIds = Object.keys(rawNodes);
    if (nodeIds.length > 300 || rawEdges.length > 800) {
        return { ok: false, error: { msg: "Diagrama excede el límite máximo (300 nodos / 800 aristas)" } };
    }

    // A. Medir dimensiones de cada nodo
    var nodes = {};
    var padX = 36;
    var padY = 20;

    for (var i = 0; i < nodeIds.length; i++) {
        var id = nodeIds[i];
        var n = rawNodes[id];
        var textDim = measure(n.label || id, baseFontPx);
        if (n.shape === "start") {
            nodes[id] = Object.assign({}, n, { w: 22, h: 22, labelDim: { width: 0, height: 0 } });
        } else if (n.shape === "end") {
            nodes[id] = Object.assign({}, n, { w: 24, h: 24, labelDim: { width: 0, height: 0 } });
        } else if (n.shape === "circle" || n.shape === "doublecircle") {
            var d = Math.max(textDim.width, textDim.height) + 32;
            nodes[id] = Object.assign({}, n, { w: d, h: d, labelDim: textDim });
        } else if (n.shape === "diamond") {
            var dw = Math.max(88, textDim.width * 1.5 + 40);
            var dh = Math.max(52, textDim.height * 1.5 + 28);
            nodes[id] = Object.assign({}, n, { w: dw, h: dh, labelDim: textDim });
        } else if (n.shape === "cylinder") {
            nodes[id] = Object.assign({}, n, {
                w: Math.max(84, textDim.width + padX + 8),
                h: Math.max(50, textDim.height + padY + 14),
                labelDim: textDim
            });
        } else {
            nodes[id] = Object.assign({}, n, {
                w: Math.max(76, textDim.width + padX),
                h: Math.max(42, textDim.height + padY),
                labelDim: textDim
            });
        }
    }

    // Mapa nodo -> subgrafo
    var nodeToSub = {};
    var rawSubs = ast.subgraphs || [];
    for (var s = 0; s < rawSubs.length; s++) {
        var sub = rawSubs[s];
        for (var sn = 0; sn < (sub.nodeIds || []).length; sn++) {
            nodeToSub[sub.nodeIds[sn]] = sub.id;
        }
    }

    // B. Construir grafo de adyacencias
    var adj = {};
    var inDegree = {};
    for (var ni = 0; ni < nodeIds.length; ni++) {
        adj[nodeIds[ni]] = [];
        inDegree[nodeIds[ni]] = 0;
    }
    for (var ei = 0; ei < rawEdges.length; ei++) {
        var edge = rawEdges[ei];
        if (adj[edge.from] && adj[edge.to]) {
            adj[edge.from].push(edge.to);
            inDegree[edge.to] = (inDegree[edge.to] || 0) + 1;
        }
    }

    // C. Detección y rotura de ciclos (DFS Coloring: 0=blanco, 1=gris, 2=negro)
    var color = {};
    for (var ci = 0; ci < nodeIds.length; ci++) color[nodeIds[ci]] = 0;
    var treeEdges = [];
    var backEdges = [];
    function dfs(u) {
        color[u] = 1;
        var neighbors = adj[u] || [];
        for (var vi = 0; vi < neighbors.length; vi++) {
            var v = neighbors[vi];
            if (color[v] === 1) {
                backEdges.push({ from: u, to: v });
            } else if (color[v] === 0) {
                treeEdges.push({ from: u, to: v });
                dfs(v);
            }
        }
        color[u] = 2;
    }
    for (var di = 0; di < nodeIds.length; di++) {
        if (color[nodeIds[di]] === 0) dfs(nodeIds[di]);
    }

    // D. Asignación de capas (Longest path en DAG con consciencia de subgrafos)
    var layerOf = {};

    if (rawSubs.length === 0) {
        var sorted = _topologicalSort(nodeIds, treeEdges);
        for (var si = 0; si < sorted.length; si++) {
            var uNode = sorted[si];
            if (layerOf[uNode] === undefined) layerOf[uNode] = 0;
            var targets = adj[uNode] || [];
            for (var ti = 0; ti < targets.length; ti++) {
                var vNode = targets[ti];
                var isBack = false;
                for (var bi = 0; bi < backEdges.length; bi++) {
                    if (backEdges[bi].from === uNode && backEdges[bi].to === vNode) {
                        isBack = true; break;
                    }
                }
                if (!isBack) {
                    layerOf[vNode] = Math.max(layerOf[vNode] || 0, layerOf[uNode] + 1);
                }
            }
        }
    } else {
        // Metagrafo de dependencias entre subgrafos
        var subAdj = {};
        var subInDeg = {};
        var subIds = [];
        for (var s = 0; s < rawSubs.length; s++) {
            var sId = rawSubs[s].id;
            subIds.push(sId);
            subAdj[sId] = [];
            subInDeg[sId] = 0;
        }

        var subEdges = [];
        for (var te = 0; te < treeEdges.length; te++) {
            var e = treeEdges[te];
            var sFrom = nodeToSub[e.from];
            var sTo = nodeToSub[e.to];
            if (sFrom && sTo && sFrom !== sTo) {
                if (subAdj[sFrom].indexOf(sTo) === -1) {
                    subAdj[sFrom].push(sTo);
                    subInDeg[sTo] = (subInDeg[sTo] || 0) + 1;
                    subEdges.push({ from: sFrom, to: sTo });
                }
            }
        }

        var sortedSubs = _topologicalSort(subIds, subEdges);

        // Capas relativas internas dentro de cada subgrafo
        var relLayerOf = {};
        for (var s2 = 0; s2 < rawSubs.length; s2++) {
            var sub2 = rawSubs[s2];
            var sNodes = sub2.nodeIds || [];
            var subTreeEdges = [];
            for (var te2 = 0; te2 < treeEdges.length; te2++) {
                if (sNodes.indexOf(treeEdges[te2].from) !== -1 && sNodes.indexOf(treeEdges[te2].to) !== -1) {
                    subTreeEdges.push(treeEdges[te2]);
                }
            }
            var sortedSubNodes = _topologicalSort(sNodes, subTreeEdges);
            for (var sni = 0; sni < sortedSubNodes.length; sni++) {
                var u2 = sortedSubNodes[sni];
                if (relLayerOf[u2] === undefined) relLayerOf[u2] = 0;
                var targets2 = adj[u2] || [];
                for (var ti2 = 0; ti2 < targets2.length; ti2++) {
                    var v2 = targets2[ti2];
                    if (sNodes.indexOf(v2) !== -1) {
                        relLayerOf[v2] = Math.max(relLayerOf[v2] || 0, relLayerOf[u2] + 1);
                    }
                }
            }
        }

        // Asignar capas a nodos raíz no agrupados
        var sortedAll = _topologicalSort(nodeIds, treeEdges);
        for (var i3 = 0; i3 < sortedAll.length; i3++) {
            var u3 = sortedAll[i3];
            if (!nodeToSub[u3]) {
                if (layerOf[u3] === undefined) layerOf[u3] = 0;
                var targets3 = adj[u3] || [];
                for (var ti3 = 0; ti3 < targets3.length; ti3++) {
                    var v3 = targets3[ti3];
                    if (!nodeToSub[v3]) {
                        layerOf[v3] = Math.max(layerOf[v3] || 0, layerOf[u3] + 1);
                    }
                }
            }
        }

        // Asignación de baseLayer y capas por subgrafo en orden topológico
        var subBaseLayer = {};
        var subMaxLayer = {};
        for (var si2 = 0; si2 < sortedSubs.length; si2++) {
            var sId2 = sortedSubs[si2];
            var subObj = null;
            for (var sIdx = 0; sIdx < rawSubs.length; sIdx++) {
                if (rawSubs[sIdx].id === sId2) { subObj = rawSubs[sIdx]; break; }
            }
            if (!subObj) continue;
            var sNodes2 = subObj.nodeIds || [];
            if (sNodes2.length === 0) continue;

            var baseL = 0;
            // Dependencias de subgrafos predecesores
            for (var pi = 0; pi < sortedSubs.length; pi++) {
                var pId = sortedSubs[pi];
                if (subAdj[pId] && subAdj[pId].indexOf(sId2) !== -1) {
                    if (subMaxLayer[pId] !== undefined) {
                        baseL = Math.max(baseL, subMaxLayer[pId] + 1);
                    }
                }
            }

            // Aristas entrantes desde nodos externos o raíces
            for (var sni2 = 0; sni2 < sNodes2.length; sni2++) {
                var v4 = sNodes2[sni2];
                for (var te3 = 0; te3 < treeEdges.length; te3++) {
                    if (treeEdges[te3].to === v4) {
                        var u4 = treeEdges[te3].from;
                        if (layerOf[u4] !== undefined) {
                            baseL = Math.max(baseL, layerOf[u4] + 1 - (relLayerOf[v4] || 0));
                        }
                    }
                }
            }

            subBaseLayer[sId2] = baseL;
            var maxL = baseL;
            for (var sni3 = 0; sni3 < sNodes2.length; sni3++) {
                var v5 = sNodes2[sni3];
                layerOf[v5] = baseL + (relLayerOf[v5] || 0);
            }

            // Relajación interna para aristas cruzadas
            for (var sni4 = 0; sni4 < sNodes2.length; sni4++) {
                var v6 = sNodes2[sni4];
                for (var te4 = 0; te4 < treeEdges.length; te4++) {
                    if (treeEdges[te4].to === v6) {
                        var u5 = treeEdges[te4].from;
                        if (layerOf[u5] !== undefined) {
                            layerOf[v6] = Math.max(layerOf[v6], layerOf[u5] + 1);
                        }
                    }
                }
                if (layerOf[v6] > maxL) maxL = layerOf[v6];
            }
            subMaxLayer[sId2] = maxL;
        }

        // Nodos no agrupados posteriores
        for (var i4 = 0; i4 < sortedAll.length; i4++) {
            var u6 = sortedAll[i4];
            var targets4 = adj[u6] || [];
            for (var ti4 = 0; ti4 < targets4.length; ti4++) {
                var v7 = targets4[ti4];
                if (!nodeToSub[v7]) {
                    layerOf[v7] = Math.max(layerOf[v7] || 0, (layerOf[u6] !== undefined ? layerOf[u6] + 1 : 0));
                }
            }
        }
    }

    // Asegurar que estados terminales "end" queden en la última capa
    var maxAssignedLayer = 0;
    for (var lk in layerOf) {
        if (layerOf[lk] > maxAssignedLayer) maxAssignedLayer = layerOf[lk];
    }
    for (var ei2 = 0; ei2 < nodeIds.length; ei2++) {
        var eNodeId = nodeIds[ei2];
        if (rawNodes[eNodeId] && rawNodes[eNodeId].shape === "end") {
            layerOf[eNodeId] = Math.max(layerOf[eNodeId] || 0, maxAssignedLayer);
        }
    }

    // Agrupar nodos por capa
    var layers = [];
    for (var li = 0; li < nodeIds.length; li++) {
        var nId = nodeIds[li];
        var lIdx = layerOf[nId] || 0;
        while (layers.length <= lIdx) layers.push([]);
        layers[lIdx].push(nId);
    }

    // E. Ordenamiento dentro de capas (heurística de baricentro consciente de clusters)
    for (var iter = 0; iter < 12; iter++) {
        for (var lay = 1; lay < layers.length; lay++) {
            _barycenterSort(layers[lay], layers[lay - 1], rawEdges, true, nodeToSub);
        }
        for (var lay2 = layers.length - 2; lay2 >= 0; lay2--) {
            _barycenterSort(layers[lay2], layers[lay2 + 1], rawEdges, false, nodeToSub);
        }
    }

    // F. Medir etiquetas de aristas y asignar coordenadas X e Y
    var edgeLabelDims = [];
    for (var ei = 0; ei < rawEdges.length; ei++) {
        var elbl = rawEdges[ei].label || "";
        edgeLabelDims[ei] = (elbl && elbl.trim() !== "") ? measure(elbl, 11) : { width: 0, height: 0 };
    }

    var baseNodeGap = 44;
    var baseRankGap = 64;
    var interClusterGap = 64;

    // Calcular rangos de capas por subgrafo para detectar subgrafos paralelos
    var subLayerRange = {};
    for (var s = 0; s < rawSubs.length; s++) {
        var sId = rawSubs[s].id;
        var sNodes = rawSubs[s].nodeIds || [];
        var minL = Infinity, maxL = -Infinity;
        for (var sni = 0; sni < sNodes.length; sni++) {
            var lVal = layerOf[sNodes[sni]];
            if (lVal < minL) minL = lVal;
            if (lVal > maxL) maxL = lVal;
        }
        subLayerRange[sId] = { minL: minL, maxL: maxL };
    }

    // Identificar bandas de subgrafos que se solapan en capas (subgrafos paralelos)
    var bands = [];
    for (var s2 = 0; s2 < rawSubs.length; s2++) {
        var sId1 = rawSubs[s2].id;
        var r1 = subLayerRange[sId1];
        if (r1.minL === Infinity) continue;
        var foundBand = null;
        for (var b = 0; b < bands.length; b++) {
            for (var bi = 0; bi < bands[b].length; bi++) {
                var sId2 = bands[b][bi];
                var r2 = subLayerRange[sId2];
                if (Math.max(r1.minL, r2.minL) <= Math.min(r1.maxL, r2.maxL)) {
                    foundBand = bands[b];
                    break;
                }
            }
            if (foundBand) break;
        }
        if (foundBand) {
            foundBand.push(sId1);
        } else {
            bands.push([sId1]);
        }
    }

    // Para cada banda con > 1 subgrafo, asignar columnas horizontales no solapadas
    var subColumnX = {};
    var subColWidth = {};

    for (var b2 = 0; b2 < bands.length; b2++) {
        var bSubs = bands[b2];
        if (bSubs.length <= 1) continue;

        // Ordenar subgrafos horizontalmente según su aparición en las capas
        bSubs.sort(function(sA, sB) {
            for (var lk = 0; lk < layers.length; lk++) {
                var lNodes = layers[lk];
                var idxA = -1, idxB = -1;
                for (var ni = 0; ni < lNodes.length; ni++) {
                    if (nodeToSub[lNodes[ni]] === sA && idxA === -1) idxA = ni;
                    if (nodeToSub[lNodes[ni]] === sB && idxB === -1) idxB = ni;
                }
                if (idxA !== -1 && idxB !== -1) return idxA - idxB;
                if (idxA !== -1) return -1;
                if (idxB !== -1) return 1;
            }
            return 0;
        });

        var curColX = 24;
        for (var bsi = 0; bsi < bSubs.length; bsi++) {
            var subBandId = bSubs[bsi];
            var subObj = null;
            for (var soi = 0; soi < rawSubs.length; soi++) {
                if (rawSubs[soi].id === subBandId) { subObj = rawSubs[soi]; break; }
            }
            var sTitleDim = measure(subObj ? (subObj.title || subObj.id) : subBandId, 11);
            var maxSubW = (sTitleDim ? sTitleDim.width : 50) + 48;

            for (var lSub = subLayerRange[subBandId].minL; lSub <= subLayerRange[subBandId].maxL; lSub++) {
                var subLNodes = layers[lSub] || [];
                var spanW = 0;
                var countInSub = 0;
                for (var sni2 = 0; sni2 < subLNodes.length; sni2++) {
                    if (nodeToSub[subLNodes[sni2]] === subBandId) {
                        var ndItem = nodes[subLNodes[sni2]];
                        var ndW = isHorizontal ? ndItem.h : ndItem.w;
                        spanW += ndW + (countInSub > 0 ? baseNodeGap : 0);
                        countInSub++;
                    }
                }
                if (spanW > maxSubW) maxSubW = spanW;
            }
            subColWidth[subBandId] = maxSubW;
            subColumnX[subBandId] = curColX;
            curColX += maxSubW + interClusterGap;
        }
    }

    var currentY = 24;
    var maxLayerW = 0;

    for (var l = 0; l < layers.length; l++) {
        var layerNodes = layers[l];
        var layerH = 0;

        for (var nIdx = 0; nIdx < layerNodes.length; nIdx++) {
            var item = nodes[layerNodes[nIdx]];
            var nh = isHorizontal ? item.w : item.h;
            if (nh > layerH) layerH = nh;
        }

        // Agrupar nodos por subgrafo en este nivel
        var groups = {};
        var groupOrder = [];
        for (var ni = 0; ni < layerNodes.length; ni++) {
            var nid = layerNodes[ni];
            var sId = nodeToSub[nid] || "__root__";
            if (!groups[sId]) {
                groups[sId] = [];
                groupOrder.push(sId);
            }
            groups[sId].push(nid);
        }

        var layerRight = 24;
        for (var gi = 0; gi < groupOrder.length; gi++) {
            var grpSubId = groupOrder[gi];
            var gNodes = groups[grpSubId];
            var gSpan = 0;
            for (var gni = 0; gni < gNodes.length; gni++) {
                var gItem = nodes[gNodes[gni]];
                var gw = isHorizontal ? gItem.h : gItem.w;
                gSpan += gw + (gni > 0 ? baseNodeGap : 0);
            }

            if (subColumnX[grpSubId] !== undefined) {
                var cX = subColumnX[grpSubId];
                var cW = subColWidth[grpSubId];
                var startX = cX + (cW - gSpan) / 2;
                var curX = startX;
                for (var gni2 = 0; gni2 < gNodes.length; gni2++) {
                    var curItem = nodes[gNodes[gni2]];
                    var curW = isHorizontal ? curItem.h : curItem.w;
                    var curH = isHorizontal ? curItem.w : curItem.h;
                    if (!isHorizontal) {
                        curItem.x = curX;
                        curItem.y = currentY + (layerH - curH) / 2;
                    } else {
                        curItem.x = currentY + (layerH - curH) / 2;
                        curItem.y = curX;
                    }
                    curX += curW + baseNodeGap;
                }
                if (cX + cW > layerRight) layerRight = cX + cW;
            } else {
                var curX2 = layerRight;
                for (var gni3 = 0; gni3 < gNodes.length; gni3++) {
                    var curItem2 = nodes[gNodes[gni3]];
                    var curW2 = isHorizontal ? curItem2.h : curItem2.w;
                    var curH2 = isHorizontal ? curItem2.w : curItem2.h;
                    if (!isHorizontal) {
                        curItem2.x = curX2;
                        curItem2.y = currentY + (layerH - curH2) / 2;
                    } else {
                        curItem2.x = currentY + (layerH - curH2) / 2;
                        curItem2.y = curX2;
                    }
                    curX2 += curW2 + baseNodeGap;
                }
                layerRight = curX2 + (gi < groupOrder.length - 1 ? interClusterGap : 0);
            }
        }
        if (layerRight > maxLayerW) maxLayerW = layerRight;

        // Espacio hacia la siguiente capa considerando subgrafos y etiquetas de aristas
        var nextLayerGap = baseRankGap;
        if (l < layers.length - 1) {
            var hasSubTransition = false;
            for (var a = 0; a < layerNodes.length; a++) {
                for (var b = 0; b < layers[l + 1].length; b++) {
                    var subA = nodeToSub[layerNodes[a]];
                    var subB = nodeToSub[layers[l + 1][b]];
                    if (subA && subB && subA !== subB) {
                        hasSubTransition = true;
                        break;
                    }
                }
                if (hasSubTransition) break;
            }
            if (hasSubTransition) {
                nextLayerGap = Math.max(nextLayerGap, 84);
            }

            for (var rei = 0; rei < rawEdges.length; rei++) {
                var reEdge = rawEdges[rei];
                var fL = layerOf[reEdge.from];
                var tL = layerOf[reEdge.to];
                if ((fL === l && tL === l + 1) || (fL === l + 1 && tL === l)) {
                    var lDim = edgeLabelDims[rei];
                    if (lDim && lDim.height > 0) {
                        if (!isHorizontal) {
                            nextLayerGap = Math.max(nextLayerGap, lDim.height + 38);
                        } else {
                            nextLayerGap = Math.max(nextLayerGap, lDim.width + 38);
                        }
                    }
                }
            }
        }
        currentY += layerH + nextLayerGap;
    }

    // Centrar capas angostas que no están ligadas a columnas multi-subgrafo
    for (var l2 = 0; l2 < layers.length; l2++) {
        var lNodes2 = layers[l2];
        if (lNodes2.length === 0) continue;
        var isMultiCol = false;
        for (var mi = 0; mi < lNodes2.length; mi++) {
            if (subColumnX[nodeToSub[lNodes2[mi]]] !== undefined) {
                isMultiCol = true;
                break;
            }
        }
        if (!isMultiCol) {
            var first = nodes[lNodes2[0]];
            var last = nodes[lNodes2[lNodes2.length - 1]];
            var curLayerSpan = (isHorizontal ? (last.y + last.h - first.y) : (last.x + last.w - first.x));
            var shift = Math.max(0, (maxLayerW - curLayerSpan) / 2);
            for (var sIdx = 0; sIdx < lNodes2.length; sIdx++) {
                if (!isHorizontal) nodes[lNodes2[sIdx]].x += shift;
                else nodes[lNodes2[sIdx]].y += shift;
            }
        }
    }

    // G. Ruteo de aristas con curvas cúbicas suaves y canales de bypass para multi-capa
    var layoutEdges = [];
    var multiLayerCounter = 0;
    var incomingMultiCounts = {};

    for (var e = 0; e < rawEdges.length; e++) {
        var origEdge = rawEdges[e];
        var nFrom = nodes[origEdge.from];
        var nTo = nodes[origEdge.to];
        if (!nFrom || !nTo) continue;

        var fromLayer = layerOf[origEdge.from] !== undefined ? layerOf[origEdge.from] : 0;
        var toLayer = layerOf[origEdge.to] !== undefined ? layerOf[origEdge.to] : 0;
        var layerDiff = Math.abs(toLayer - fromLayer);
        var eLabelDim = edgeLabelDims[e] || { width: 0, height: 0 };

        // Caso 1: Arista multi-capa en flujo vertical (!isHorizontal && layerDiff > 1 && hacia adelante)
        // Se rutea por un canal lateral para no atravesar cajas intermedias (ej. A->C, A->D, B->D en 1.3)
        if (!isHorizontal && layerDiff > 1 && toLayer > fromLayer) {
            var minL = fromLayer;
            var maxL = toLayer;
            var maxRight = Math.max(nFrom.x + nFrom.w, nTo.x + nTo.w);
            for (var lk = minL + 1; lk < maxL; lk++) {
                var lNodesArr = layers[lk] || [];
                for (var ln = 0; ln < lNodesArr.length; ln++) {
                    var midNode = nodes[lNodesArr[ln]];
                    if (midNode && midNode.x + midNode.w > maxRight) {
                        maxRight = midNode.x + midNode.w;
                    }
                }
            }

            var halfLabelW = (eLabelDim && eLabelDim.width > 0) ? (eLabelDim.width / 2 + 14) : 0;
            var corridorX = maxRight + Math.max(26, halfLabelW + 12) + (multiLayerCounter * 20);
            multiLayerCounter++;

            var incIdx = incomingMultiCounts[origEdge.to] || 0;
            incomingMultiCounts[origEdge.to] = incIdx + 1;
            var targetFraction = Math.min(0.90, 0.68 + (incIdx * 0.12));

            var startPtMulti = { x: nFrom.x + nFrom.w * 0.76, y: nFrom.y + nFrom.h };
            var endPtMulti = { x: nTo.x + nTo.w * targetFraction, y: nTo.y };
            var midYMulti = (startPtMulti.y + endPtMulti.y) / 2;

            // Puntos de control garantizando tangentes puramente verticales en salida y llegada
            var cp1xMulti = startPtMulti.x;
            var cp1yMulti = startPtMulti.y + Math.min(36, (midYMulti - startPtMulti.y) * 0.5);
            var cp2xMulti = corridorX;
            var cp2yMulti = startPtMulti.y + Math.min(54, (midYMulti - startPtMulti.y) * 0.7);

            var cp3xMulti = corridorX;
            var cp3yMulti = endPtMulti.y - Math.min(54, (endPtMulti.y - midYMulti) * 0.7);
            var cp4xMulti = endPtMulti.x;
            var cp4yMulti = endPtMulti.y - Math.min(36, (endPtMulti.y - midYMulti) * 0.5);

            var pathStrMulti = "M " + Math.round(startPtMulti.x) + " " + Math.round(startPtMulti.y) + " " +
                               "C " + Math.round(cp1xMulti) + " " + Math.round(cp1yMulti) + ", " +
                                      Math.round(cp2xMulti) + " " + Math.round(cp2yMulti) + ", " +
                                      Math.round(corridorX) + " " + Math.round(midYMulti) + " " +
                               "C " + Math.round(cp3xMulti) + " " + Math.round(cp3yMulti) + ", " +
                                      Math.round(cp4xMulti) + " " + Math.round(cp4yMulti) + ", " +
                                      Math.round(endPtMulti.x) + " " + Math.round(endPtMulti.y);

            layoutEdges.push({
                path: pathStrMulti,
                from: origEdge.from,
                to: origEdge.to,
                type: origEdge.type,
                strokeDash: origEdge.strokeDash,
                thick: !!origEdge.thick,
                label: origEdge.label,
                labelDim: eLabelDim,
                labelX: corridorX,
                labelY: midYMulti,
                endX: endPtMulti.x,
                endY: endPtMulti.y,
                endAngle: Math.PI / 2,
                corridorX: corridorX
            });
            continue;
        }

        // Caso 2: Aristas estándar (adyacentes o horizontales)
        var fromCenterX = nFrom.x + nFrom.w / 2;
        var fromCenterY = nFrom.y + nFrom.h / 2;
        var toCenterX = nTo.x + nTo.w / 2;
        var toCenterY = nTo.y + nTo.h / 2;

        var angle = Math.atan2(toCenterY - fromCenterY, toCenterX - fromCenterX);
        var startPt = _getBoundaryPoint(nFrom, angle);
        var endPt = _getBoundaryPoint(nTo, angle + Math.PI);

        // Detectar si existe arista inversa entre los mismos dos nodos
        var hasReverse = false;
        for (var re = 0; re < rawEdges.length; re++) {
            if (rawEdges[re].from === origEdge.to && rawEdges[re].to === origEdge.from) {
                hasReverse = true;
                break;
            }
        }

        var isBackEdge = false;
        for (var be = 0; be < backEdges.length; be++) {
            if (backEdges[be].from === origEdge.from && backEdges[be].to === origEdge.to) {
                isBackEdge = true;
                break;
            }
        }

        var curveOffset = 0;
        if (hasReverse) {
            curveOffset = (origEdge.from < origEdge.to) ? 58 : -58;
        } else if (isBackEdge) {
            if (layerDiff > 1) {
                var minLeft = Math.min(nFrom.x, nTo.x);
                var lStart = Math.min(fromLayer, toLayer);
                var lEnd = Math.max(fromLayer, toLayer);
                for (var lk2 = lStart + 1; lk2 < lEnd; lk2++) {
                    var lNodes = layers[lk2] || [];
                    for (var lni = 0; lni < lNodes.length; lni++) {
                        var mnd = nodes[lNodes[lni]];
                        if (mnd && mnd.x < minLeft) minLeft = mnd.x;
                    }
                }
                var clearance = Math.max(88, (nFrom.x - minLeft) + 70 + (eLabelDim.width / 2));
                curveOffset = -clearance;
            } else {
                curveOffset = -54;
            }
        }

        var dx = endPt.x - startPt.x;
        var dy = endPt.y - startPt.y;
        var cp1x, cp1y, cp2x, cp2y;

        if (!isHorizontal) {
            cp1x = startPt.x + curveOffset;
            cp1y = startPt.y + dy * 0.45;
            cp2x = endPt.x + curveOffset;
            cp2y = endPt.y - dy * 0.45;
            if (Math.abs(dy) < 14) {
                var archY = (curveOffset !== 0 ? curveOffset : -36);
                cp1y += archY;
                cp2y += archY;
            }
        } else {
            cp1x = startPt.x + dx * 0.45;
            cp1y = startPt.y + curveOffset;
            cp2x = endPt.x - dx * 0.45;
            cp2y = endPt.y + curveOffset;
            if (Math.abs(dx) < 14) {
                var archX = (curveOffset !== 0 ? curveOffset : 36);
                cp1x += archX;
                cp2x += archX;
            }
        }

        var pathStr = "M " + Math.round(startPt.x) + " " + Math.round(startPt.y) + " " +
                      "C " + Math.round(cp1x) + " " + Math.round(cp1y) + ", " +
                             Math.round(cp2x) + " " + Math.round(cp2y) + ", " +
                             Math.round(endPt.x) + " " + Math.round(endPt.y);

        var midX, midY;
        if (hasReverse) {
            // Evaluar a t=0.33 a lo largo de cada curva: dado que fluyen en sentidos opuestos,
            // una etiqueta queda cerca del nodo superior y la otra cerca del nodo inferior,
            // logrando separación vertical completa sin colisiones.
            var tPos = 0.33;
            var mt = 1 - tPos;
            midX = mt * mt * mt * startPt.x + 3 * mt * mt * tPos * cp1x + 3 * mt * tPos * tPos * cp2x + tPos * tPos * tPos * endPt.x;
            midY = mt * mt * mt * startPt.y + 3 * mt * mt * tPos * cp1y + 3 * mt * tPos * tPos * cp2y + tPos * tPos * tPos * endPt.y;
        } else {
            midX = (startPt.x + endPt.x) / 2 + (isHorizontal ? 0 : curveOffset);
            midY = (startPt.y + endPt.y) / 2 + (isHorizontal ? curveOffset : (Math.abs(dy) < 14 ? -26 : 0));
        }

        layoutEdges.push({
            path: pathStr,
            from: origEdge.from,
            to: origEdge.to,
            type: origEdge.type,
            strokeDash: origEdge.strokeDash,
            thick: !!origEdge.thick,
            label: origEdge.label,
            labelDim: eLabelDim,
            labelX: midX,
            labelY: midY,
            endX: endPt.x,
            endY: endPt.y,
            endAngle: Math.atan2(endPt.y - cp2y, endPt.x - cp2x)
        });
    }

    // Calcular cajas delimitadoras de subgrafos con márgenes generosos
    var subgraphs = [];
    var rawSubs = ast.subgraphs || [];
    for (var s = 0; s < rawSubs.length; s++) {
        var sub = rawSubs[s];
        var sNodeIds = sub.nodeIds || [];
        var sMinX = Infinity, sMinY = Infinity, sMaxX = -Infinity, sMaxY = -Infinity;
        var foundAny = false;
        for (var sn = 0; sn < sNodeIds.length; sn++) {
            var nPos = nodes[sNodeIds[sn]];
            if (nPos) {
                foundAny = true;
                if (nPos.x < sMinX) sMinX = nPos.x;
                if (nPos.y < sMinY) sMinY = nPos.y;
                if (nPos.x + nPos.w > sMaxX) sMaxX = nPos.x + nPos.w;
                if (nPos.y + nPos.h > sMaxY) sMaxY = nPos.y + nPos.h;
            }
        }
        if (foundAny) {
            var padH = 20;
            var padTop = 36;
            var padBottom = 18;
            var subTitle = sub.title || sub.id;
            var titleDim = measure(subTitle);
            var contentW = (sMaxX - sMinX) + padH * 2;
            var minSubW = Math.max(contentW, (titleDim ? titleDim.width : 50) + 48);
            if (minSubW > contentW) {
                var diff = minSubW - contentW;
                sMinX -= diff / 2;
                sMaxX += diff / 2;
            }
            subgraphs.push({
                id: sub.id,
                title: subTitle,
                x: sMinX - padH,
                y: sMinY - padTop,
                w: (sMaxX - sMinX) + padH * 2,
                h: (sMaxY - sMinY) + padTop + padBottom
            });
        }
    }

    // Normalización de coordenadas y límites reales del bounding box abarcando todo el contenido
    var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (var k in nodes) {
        var nd = nodes[k];
        if (nd.x < minX) minX = nd.x;
        if (nd.y < minY) minY = nd.y;
        if (nd.x + nd.w > maxX) maxX = nd.x + nd.w;
        if (nd.y + nd.h > maxY) maxY = nd.y + nd.h;
    }
    for (var sIdx = 0; sIdx < subgraphs.length; sIdx++) {
        var sg = subgraphs[sIdx];
        if (sg.x < minX) minX = sg.x;
        if (sg.y < minY) minY = sg.y;
        if (sg.x + sg.w > maxX) maxX = sg.x + sg.w;
        if (sg.y + sg.h > maxY) maxY = sg.y + sg.h;
    }
    for (var eIdx = 0; eIdx < layoutEdges.length; eIdx++) {
        var le = layoutEdges[eIdx];
        if (le.label && le.label.trim() !== "") {
            var lw = (le.labelDim ? le.labelDim.width : 50) + 12;
            var lh = (le.labelDim ? le.labelDim.height : 16) + 6;
            var lx1 = le.labelX - lw / 2;
            var lx2 = le.labelX + lw / 2;
            var ly1 = le.labelY - lh / 2;
            var ly2 = le.labelY + lh / 2;
            if (lx1 < minX) minX = lx1;
            if (ly1 < minY) minY = ly1;
            if (lx2 > maxX) maxX = lx2;
            if (ly2 > maxY) maxY = ly2;
        }
        if (le.corridorX !== undefined) {
            if (le.corridorX - 16 < minX) minX = le.corridorX - 16;
            if (le.corridorX + 16 > maxX) maxX = le.corridorX + 16;
        }
    }

    var hasTitle = !!(ast.title && ast.title.trim().length > 0);
    var targetMargin = 16;
    var targetMarginTop = hasTitle ? 44 : 16;
    var shiftX = minX < targetMargin ? (targetMargin - minX) : 0;
    var shiftY = minY < targetMarginTop ? (targetMarginTop - minY) : 0;

    if (shiftX !== 0 || shiftY !== 0) {
        for (var k2 in nodes) {
            nodes[k2].x += shiftX;
            nodes[k2].y += shiftY;
        }
        for (var s2 = 0; s2 < subgraphs.length; s2++) {
            subgraphs[s2].x += shiftX;
            subgraphs[s2].y += shiftY;
        }
        for (var e2 = 0; e2 < layoutEdges.length; e2++) {
            var le2 = layoutEdges[e2];
            le2.labelX += shiftX;
            le2.labelY += shiftY;
            le2.endX += shiftX;
            le2.endY += shiftY;
            if (le2.corridorX !== undefined) le2.corridorX += shiftX;
            le2.path = _shiftSvgPath(le2.path, shiftX, shiftY);
        }
        maxX += shiftX;
        maxY += shiftY;
    }

    var totalW = Math.max(180, Math.ceil(maxX + targetMargin));
    var totalH = Math.max(100, Math.ceil(maxY + targetMargin));

    return {
        ok: true,
        type: "flowchart",
        title: ast.title || "",
        width: totalW,
        height: totalH,
        nodes: nodes,
        edges: layoutEdges,
        subgraphs: subgraphs
    };
}

function _topologicalSort(nodeIds, edges) {
    var inDeg = {};
    var adj = {};
    for (var i = 0; i < nodeIds.length; i++) {
        inDeg[nodeIds[i]] = 0;
        adj[nodeIds[i]] = [];
    }
    for (var j = 0; j < edges.length; j++) {
        adj[edges[j].from].push(edges[j].to);
        inDeg[edges[j].to] = (inDeg[edges[j].to] || 0) + 1;
    }
    var q = [];
    for (var k in inDeg) if (inDeg[k] === 0) q.push(k);
    var res = [];
    while (q.length > 0) {
        var u = q.shift();
        res.push(u);
        var nbrs = adj[u] || [];
        for (var n = 0; n < nbrs.length; n++) {
            inDeg[nbrs[n]]--;
            if (inDeg[nbrs[n]] === 0) q.push(nbrs[n]);
        }
    }
    // Si hubo nodos no ordenados por ciclos, agregarlos al final
    for (var x = 0; x < nodeIds.length; x++) {
        if (res.indexOf(nodeIds[x]) === -1) res.push(nodeIds[x]);
    }
    return res;
}

function _barycenterSort(layer, refLayer, edges, isDown, nodeToSub) {
    var posMap = {};
    for (var r = 0; r < refLayer.length; r++) posMap[refLayer[r]] = r;

    var weights = {};
    for (var l = 0; l < layer.length; l++) {
        var u = layer[l];
        var sum = 0;
        var count = 0;
        for (var e = 0; e < edges.length; e++) {
            var edge = edges[e];
            var ref = isDown ? edge.from : edge.to;
            var target = isDown ? edge.to : edge.from;
            if (target === u && posMap[ref] !== undefined) {
                sum += posMap[ref];
                count++;
            }
        }
        weights[u] = count > 0 ? (sum / count) : l;
    }

    if (!nodeToSub) {
        layer.sort(function(a, b) { return weights[a] - weights[b]; });
        return;
    }

    var groups = {};
    var groupOrder = [];
    for (var l2 = 0; l2 < layer.length; l2++) {
        var u2 = layer[l2];
        var s = nodeToSub[u2] || "__root__";
        if (!groups[s]) {
            groups[s] = [];
            groupOrder.push(s);
        }
        groups[s].push(u2);
    }

    for (var sName in groups) {
        groups[sName].sort(function(a, b) { return weights[a] - weights[b]; });
    }

    groupOrder.sort(function(sA, sB) {
        var avgA = 0, avgB = 0;
        for (var iA = 0; iA < groups[sA].length; iA++) avgA += weights[groups[sA][iA]];
        avgA /= groups[sA].length;
        for (var iB = 0; iB < groups[sB].length; iB++) avgB += weights[groups[sB][iB]];
        avgB /= groups[sB].length;
        return avgA - avgB;
    });

    var newL = [];
    for (var g = 0; g < groupOrder.length; g++) {
        var gNodes = groups[groupOrder[g]];
        for (var gn = 0; gn < gNodes.length; gn++) newL.push(gNodes[gn]);
    }
    for (var fi = 0; fi < layer.length; fi++) layer[fi] = newL[fi];
}

function _getBoundaryPoint(node, angleRad) {
    var cx = node.x + node.w / 2;
    var cy = node.y + node.h / 2;
    var halfW = node.w / 2;
    var halfH = node.h / 2;
    var cos = Math.cos(angleRad);
    var sin = Math.sin(angleRad);

    if (node.shape === "circle" || node.shape === "doublecircle" || node.shape === "start" || node.shape === "end") {
        var r = Math.min(halfW, halfH);
        return { x: cx + r * cos, y: cy + r * sin };
    }

    var tx = (cos > 0) ? (halfW / cos) : (-halfW / cos);
    var ty = (sin > 0) ? (halfH / sin) : (-halfH / sin);
    var t = Math.min(Math.abs(tx), Math.abs(ty));

    return { x: cx + t * cos, y: cy + t * sin };
}

// ── 2. SEQUENCE DIAGRAM LAYOUT ──────────────────────────────────────────────

function _layoutSequence(ast, measure, opts) {
    var participants = ast.participants || [];
    var events = ast.events || [];
    var autonumber = !!ast.autonumber;

    var pWidth = 110;
    var pHeight = 36;
    var pGap = 52;
    var startX = 28;
    var hasTitle = !!(ast.title && ast.title.trim().length > 0);
    var headerY = hasTitle ? 48 : 24;

    // Ajustar pGap si hay mensajes con texto largo para evitar solapamientos
    for (var mi = 0; mi < events.length; mi++) {
        if (events[mi].kind === "message") {
            var mDim = measure(events[mi].text, 11);
            if (mDim.width + 36 > pWidth + pGap) {
                pGap = Math.max(pGap, mDim.width + 36 - pWidth);
            }
        }
    }

    // Calcular posiciones X de cada participante
    var pLayout = {};
    var currentX = startX;

    for (var i = 0; i < participants.length; i++) {
        var p = participants[i];
        var labelDim = measure(p.label, 13);
        var w = Math.max(pWidth, labelDim.width + 24);
        pLayout[p.id] = {
            id: p.id,
            label: p.label,
            isActor: p.isActor,
            x: currentX,
            y: headerY,
            w: w,
            h: pHeight,
            centerX: currentX + w / 2
        };
        currentX += w + pGap;
    }

    var currentY = headerY + pHeight + 36;
    var layoutMessages = [];
    var layoutNotes = [];
    var msgIndex = 1;

    for (var j = 0; j < events.length; j++) {
        var ev = events[j];
        if (ev.kind === "message") {
            var fromP = pLayout[ev.from];
            var toP = pLayout[ev.to];
            if (!fromP || !toP) continue;

            var msgNum = autonumber ? (msgIndex++ + ". ") : "";
            var fullText = msgNum + ev.text;
            var textDim = measure(fullText, 12);

            var startXMsg = fromP.centerX;
            var endXMsg = toP.centerX;
            var isSelf = (ev.from === ev.to);

            layoutMessages.push({
                from: ev.from,
                to: ev.to,
                isSelf: isSelf,
                startX: startXMsg,
                endX: endXMsg,
                y: currentY,
                text: fullText,
                textDim: textDim,
                arrow: ev.arrow,
                dotted: ev.dotted
            });
            currentY += isSelf ? 54 : Math.max(46, textDim.height + 30);
        } else if (ev.kind === "note") {
            var targetP = pLayout[ev.targets[0]];
            if (targetP) {
                var noteDim = measure(ev.text, 12);
                var noteW = Math.max(80, noteDim.width + 16);
                var noteH = Math.max(28, noteDim.height + 12);
                var noteX = targetP.centerX - noteW / 2;

                layoutNotes.push({
                    x: noteX,
                    y: currentY,
                    w: noteW,
                    h: noteH,
                    text: ev.text
                });
                currentY += noteH + 20;
            }
        }
    }

    var totalW = Math.max(260, currentX + 24);
    var lifeLineEndY = currentY + 16;
    var totalH = lifeLineEndY + pHeight + 24;

    return {
        ok: true,
        type: "sequenceDiagram",
        title: ast.title || "",
        width: totalW,
        height: totalH,
        participants: pLayout,
        messages: layoutMessages,
        notes: layoutNotes,
        lifeLineEndY: lifeLineEndY
    };
}

// ── 3. PIE CHART LAYOUT ─────────────────────────────────────────────────────

function _layoutPie(ast, measure, opts) {
    var slices = ast.slices || [];
    var total = ast.total || 0;
    if (total <= 0) {
        return { ok: false, error: { msg: "Gráfico de torta sin valores válidos" } };
    }

    var chartSize = 220;
    var radius = chartSize / 2;
    var cx = radius + 24;
    var cy = radius + (ast.title ? 42 : 24);

    var currentAngle = -Math.PI / 2; // Empezar en las 12 en punto
    var layoutSlices = [];

    // Colores semánticos estándar para las porciones
    var palette = ["#33ccff", "#ff9933", "#33cc66", "#cc66ff", "#ff3366", "#ffcc00", "#00cccc", "#ff66cc"];

    for (var i = 0; i < slices.length; i++) {
        var sl = slices[i];
        var angleSpan = (sl.value / total) * 2 * Math.PI;
        var endAngle = currentAngle + angleSpan;
        var percent = Math.round((sl.value / total) * 100);

        var x1 = cx + radius * Math.cos(currentAngle);
        var y1 = cy + radius * Math.sin(currentAngle);
        var x2 = cx + radius * Math.cos(endAngle);
        var y2 = cy + radius * Math.sin(endAngle);

        var largeArc = angleSpan > Math.PI ? 1 : 0;
        var pathStr = "M " + cx + " " + cy + " L " + x1 + " " + y1 + " " +
                      "A " + radius + " " + radius + " 0 " + largeArc + " 1 " + x2 + " " + y2 + " Z";

        var midAngle = currentAngle + angleSpan / 2;
        var labelR = radius * 0.68;
        var labelX = Math.round(cx + labelR * Math.cos(midAngle));
        var labelY = Math.round(cy + labelR * Math.sin(midAngle));

        layoutSlices.push({
            label: sl.label,
            value: sl.value,
            percent: percent,
            color: palette[i % palette.length],
            path: pathStr,
            labelX: labelX,
            labelY: labelY
        });

        currentAngle = endAngle;
    }

    // Layout de leyenda al lado derecho
    var legendX = cx + radius + 32;
    var legendY = cy - radius + 10;
    var totalW = legendX + 160;
    var totalH = Math.max(cy + radius + 32, legendY + slices.length * 24 + 20);

    return {
        ok: true,
        type: "pie",
        title: ast.title || "",
        showData: !!ast.showData,
        width: totalW,
        height: totalH,
        cx: cx,
        cy: cy,
        radius: radius,
        slices: layoutSlices,
        legendX: legendX,
        legendY: legendY
    };
}

// ── 4. STATE DIAGRAM LAYOUT ─────────────────────────────────────────────────

function _layoutState(ast, measure, opts) {
    // Convierte el AST de state a un formato compatible con flowchart para reusar el layout en capas
    var flowNodes = {};
    for (var sId in ast.states) {
        var st = ast.states[sId];
        var shp = "round";
        if (st.isStart) shp = "start";
        else if (st.isEnd) shp = "end";
        else if (st.isChoice) shp = "choice";
        else if (st.isFork || st.isJoin) shp = "fork";

        flowNodes[sId] = {
            id: sId,
            label: st.label,
            shape: shp,
            classNames: [],
            style: {}
        };
    }

    var flowEdges = [];
    var trans = ast.transitions || [];
    for (var i = 0; i < trans.length; i++) {
        flowEdges.push({
            from: trans[i].from,
            to: trans[i].to,
            type: "arrow",
            label: trans[i].label,
            style: {},
            strokeDash: false
        });
    }

    var flowAst = {
        title: ast.title,
        direction: "TD",
        nodes: flowNodes,
        edges: flowEdges,
        subgraphs: []
    };

    var res = _layoutFlowchart(flowAst, measure, opts);
    if (res.ok) res.type = "stateDiagram";
    return res;
}

function _shiftSvgPath(pathStr, sx, sy) {
    if (!pathStr || (sx === 0 && sy === 0)) return pathStr;
    var res = pathStr.replace(/([MCLS])\s*([^MCLS]+)/g, function(match, cmd, coords) {
        var nums = coords.trim().split(/[\s,]+/);
        var shifted = [];
        for (var i = 0; i < nums.length; i += 2) {
            if (i + 1 < nums.length) {
                var x = parseFloat(nums[i]) + sx;
                var y = parseFloat(nums[i + 1]) + sy;
                shifted.push(Math.round(x) + " " + Math.round(y));
            }
        }
        return cmd + " " + shifted.join(" ") + " ";
    });
    return res.trim();
}

// ── 5. CLASS DIAGRAM LAYOUT (UML) ───────────────────────────────────────────

function _layoutClassDiagram(ast, measure, opts) {
    var rawClasses = ast.classes || {};
    var rawRelations = ast.relations || [];
    var rawNotes = ast.notes || [];
    var dir = ast.direction || "TB";
    var isHoriz = (dir === "LR" || dir === "RL");
    var isReverse = (dir === "BT" || dir === "RL");

    var classIds = Object.keys(rawClasses);
    if (classIds.length === 0) {
        return { ok: true, type: "classDiagram", width: 240, height: 100, nodes: {}, edges: [], notes: [] };
    }

    // A. Medir dimensiones de cada clase compartimentada
    var nodes = {};
    for (var i = 0; i < classIds.length; i++) {
        var cId = classIds[i];
        var c = rawClasses[cId];

        var nameMeas = measure(c.label || c.id, 14);
        var stereoMeas = c.stereotype ? measure("<<" + c.stereotype + ">>", 11) : { width: 0, height: 0 };
        var maxTitleW = Math.max(nameMeas.width, stereoMeas.width) + 32;

        var maxAttrW = 0;
        var attrs = c.attributes || [];
        for (var a = 0; a < attrs.length; a++) {
            var am = measure(attrs[a].visibility + " " + attrs[a].text, 12);
            if (am.width + 24 > maxAttrW) maxAttrW = am.width + 24;
        }

        var maxMethW = 0;
        var meths = c.methods || [];
        for (var m = 0; m < meths.length; m++) {
            var mm = measure(meths[m].visibility + " " + meths[m].text, 12);
            if (mm.width + 24 > maxMethW) maxMethW = mm.width + 24;
        }

        var w = Math.max(140, Math.max(maxTitleW, Math.max(maxAttrW, maxMethW)));
        var headerH = c.stereotype ? 40 : 28;
        var attrH = attrs.length > 0 ? (attrs.length * 20 + 8) : 0;
        var methH = meths.length > 0 ? (meths.length * 20 + 8) : 0;
        var h = headerH + attrH + methH + 8;

        nodes[cId] = {
            id: cId,
            label: c.label || c.id,
            stereotype: c.stereotype,
            attributes: attrs,
            methods: meths,
            headerH: headerH,
            attrH: attrH,
            methH: methH,
            w: w,
            h: h,
            x: 0,
            y: 0
        };
    }

    // B. Asignación de capas para distribución en cuadrícula
    var adj = {};
    for (var ci = 0; ci < classIds.length; ci++) adj[classIds[ci]] = [];
    for (var ri = 0; ri < rawRelations.length; ri++) {
        var rel = rawRelations[ri];
        if (adj[rel.from]) adj[rel.from].push(rel.to);
    }

    var layerOf = {};
    for (var li = 0; li < classIds.length; li++) layerOf[classIds[li]] = 0;
    for (var rk = 0; rk < rawRelations.length; rk++) {
        var rRel = rawRelations[rk];
        if (layerOf[rRel.to] !== undefined && layerOf[rRel.from] !== undefined) {
            layerOf[rRel.to] = Math.max(layerOf[rRel.to], layerOf[rRel.from] + 1);
        }
    }

    var layers = [];
    for (var cj = 0; cj < classIds.length; cj++) {
        var cid = classIds[cj];
        var lay = layerOf[cid] || 0;
        while (layers.length <= lay) layers.push([]);
        layers[lay].push(cid);
    }

    // C. Asignar coordenadas (x, y)
    var hasTitle = !!(ast.title && ast.title.trim().length > 0);
    var gapX = isHoriz ? 70 : 40;
    var gapY = isHoriz ? 36 : 60;
    var curOffset = hasTitle ? 52 : 24;
    var totalW = 0;
    var totalH = 0;

    if (!isHoriz) {
        // Vertical (TB / TD)
        for (var L = 0; L < layers.length; L++) {
            var layerNodes = layers[L];
            var maxLayerH = 0;
            var layerW = 0;
            for (var n1 = 0; n1 < layerNodes.length; n1++) {
                layerW += nodes[layerNodes[n1]].w + (n1 > 0 ? gapX : 0);
                if (nodes[layerNodes[n1]].h > maxLayerH) maxLayerH = nodes[layerNodes[n1]].h;
            }

            var startX = 24;
            for (var n2 = 0; n2 < layerNodes.length; n2++) {
                var nodeObj = nodes[layerNodes[n2]];
                nodeObj.x = startX;
                nodeObj.y = curOffset;
                startX += nodeObj.w + gapX;
            }
            if (startX > totalW) totalW = startX;
            curOffset += maxLayerH + gapY;
        }
        totalH = curOffset;
    } else {
        // Horizontal (LR)
        for (var L2 = 0; L2 < layers.length; L2++) {
            var hLayerNodes = layers[L2];
            var maxLayerW = 0;
            var hLayerH = 0;
            for (var hn1 = 0; hn1 < hLayerNodes.length; hn1++) {
                hLayerH += nodes[hLayerNodes[hn1]].h + (hn1 > 0 ? gapY : 0);
                if (nodes[hLayerNodes[hn1]].w > maxLayerW) maxLayerW = nodes[hLayerNodes[hn1]].w;
            }

            var startY = hasTitle ? 52 : 24;
            for (var hn2 = 0; hn2 < hLayerNodes.length; hn2++) {
                var hNodeObj = nodes[hLayerNodes[hn2]];
                hNodeObj.x = curOffset;
                hNodeObj.y = startY;
                startY += hNodeObj.h + gapY;
            }
            if (startY > totalH) totalH = startY;
            curOffset += maxLayerW + gapX;
        }
        totalW = curOffset;
    }

    // D. Ruteo de aristas y cálculo de etiquetas de cardinalidad
    var edges = [];
    for (var re = 0; re < rawRelations.length; re++) {
        var relItem = rawRelations[re];
        var srcNode = nodes[relItem.from];
        var dstNode = nodes[relItem.to];
        if (!srcNode || !dstNode) continue;

        var startPt = { x: 0, y: 0 };
        var endPt = { x: 0, y: 0 };
        var pathStr = "";
        var endAngle = 0;

        if (!isHoriz) {
            var isDown = dstNode.y >= srcNode.y;
            startPt.x = srcNode.x + srcNode.w / 2;
            startPt.y = isDown ? (srcNode.y + srcNode.h) : srcNode.y;
            endPt.x = dstNode.x + dstNode.w / 2;
            endPt.y = isDown ? dstNode.y : (dstNode.y + dstNode.h);
            endAngle = isDown ? (Math.PI / 2) : (-Math.PI / 2);

            var dy = Math.max(25, Math.abs(endPt.y - startPt.y) * 0.5);
            var cp1y = isDown ? (startPt.y + dy) : (startPt.y - dy);
            var cp2y = isDown ? (endPt.y - dy) : (endPt.y + dy);
            pathStr = "M " + Math.round(startPt.x) + " " + Math.round(startPt.y) +
                      " C " + Math.round(startPt.x) + " " + Math.round(cp1y) + ", " +
                      Math.round(endPt.x) + " " + Math.round(cp2y) + ", " +
                      Math.round(endPt.x) + " " + Math.round(endPt.y);
        } else {
            var isRight = dstNode.x >= srcNode.x;
            startPt.x = isRight ? (srcNode.x + srcNode.w) : srcNode.x;
            startPt.y = srcNode.y + srcNode.h / 2;
            endPt.x = isRight ? dstNode.x : (dstNode.x + dstNode.w);
            endPt.y = dstNode.y + dstNode.h / 2;
            endAngle = isRight ? 0 : Math.PI;

            var dx = Math.max(25, Math.abs(endPt.x - startPt.x) * 0.5);
            var cp1x = isRight ? (startPt.x + dx) : (startPt.x - dx);
            var cp2x = isRight ? (endPt.x - dx) : (endPt.x + dx);
            pathStr = "M " + Math.round(startPt.x) + " " + Math.round(startPt.y) +
                      " C " + Math.round(cp1x) + " " + Math.round(startPt.y) + ", " +
                      Math.round(cp2x) + " " + Math.round(endPt.y) + ", " +
                      Math.round(endPt.x) + " " + Math.round(endPt.y);
        }

        // Posiciones de etiquetas de cardinalidad
        var fromCardX = startPt.x + (isHoriz ? 12 : 12);
        var fromCardY = startPt.y + (isHoriz ? -12 : (isDown ? 12 : -12));
        var toCardX = endPt.x + (isHoriz ? -14 : 12);
        var toCardY = endPt.y + (isHoriz ? -12 : (isDown ? -14 : 14));

        var midX = (startPt.x + endPt.x) / 2;
        var midY = (startPt.y + endPt.y) / 2;

        edges.push({
            from: relItem.from,
            to: relItem.to,
            relType: relItem.relType,
            lineStyle: relItem.lineStyle,
            fromMarker: relItem.fromMarker,
            toMarker: relItem.toMarker,
            path: pathStr,
            startX: startPt.x,
            startY: startPt.y,
            endX: endPt.x,
            endY: endPt.y,
            endAngle: endAngle,
            fromCard: relItem.fromCard,
            fromCardX: fromCardX,
            fromCardY: fromCardY,
            toCard: relItem.toCard,
            toCardX: toCardX,
            toCardY: toCardY,
            label: relItem.label,
            labelX: midX,
            labelY: midY,
            strokeDash: relItem.lineStyle === "dashed"
        });
    }

    return {
        ok: true,
        type: "classDiagram",
        title: ast.title,
        nodes: nodes,
        edges: edges,
        notes: rawNotes,
        width: Math.max(300, totalW + 30),
        height: Math.max(120, totalH + 20)
    };
}

// ── 6. ER DIAGRAM LAYOUT (Entity-Relationship) ──────────────────────────────

function _layoutErDiagram(ast, measure, opts) {
    var rawEntities = ast.entities || {};
    var rawRelations = ast.relations || [];
    var entIds = Object.keys(rawEntities);

    if (entIds.length === 0) {
        return { ok: true, type: "erDiagram", width: 240, height: 100, entities: {}, relations: [] };
    }

    var entities = {};
    for (var i = 0; i < entIds.length; i++) {
        var eId = entIds[i];
        var ent = rawEntities[eId];

        var nameMeas = measure(ent.id, 14);
        var maxAttrW = 0;
        var attrs = ent.attributes || [];
        for (var a = 0; a < attrs.length; a++) {
            var at = attrs[a];
            var rowText = at.type + " " + at.name + (at.key ? (" [" + at.key + "]") : "");
            var am = measure(rowText, 12);
            if (am.width + 24 > maxAttrW) maxAttrW = am.width + 24;
        }

        var w = Math.max(140, Math.max(nameMeas.width + 30, maxAttrW + 24));
        var headerH = 30;
        var attrH = attrs.length * 22 + (attrs.length > 0 ? 8 : 0);
        var h = headerH + attrH + 8;

        entities[eId] = {
            id: eId,
            attributes: attrs,
            headerH: headerH,
            attrH: attrH,
            w: w,
            h: h,
            x: 0,
            y: 0
        };
    }

    // Distribución en capas
    var layerOf = {};
    for (var li = 0; li < entIds.length; li++) layerOf[entIds[li]] = 0;
    for (var ri = 0; ri < rawRelations.length; ri++) {
        var r = rawRelations[ri];
        if (layerOf[r.to] !== undefined && layerOf[r.from] !== undefined) {
            layerOf[r.to] = Math.max(layerOf[r.to], layerOf[r.from] + 1);
        }
    }

    var layers = [];
    for (var ei = 0; ei < entIds.length; ei++) {
        var eid = entIds[ei];
        var lay = layerOf[eid] || 0;
        while (layers.length <= lay) layers.push([]);
        layers[lay].push(eid);
    }

    var gapX = 45;
    var gapY = 55;
    var hasTitle = !!(ast.title && ast.title.trim().length > 0);
    var curY = hasTitle ? 52 : 24;
    var totalW = 0;

    for (var L = 0; L < layers.length; L++) {
        var layNodes = layers[L];
        var curX = 24;
        var maxH = 0;
        for (var n = 0; n < layNodes.length; n++) {
            var entObj = entities[layNodes[n]];
            entObj.x = curX;
            entObj.y = curY;
            curX += entObj.w + gapX;
            if (entObj.h > maxH) maxH = entObj.h;
        }
        if (curX > totalW) totalW = curX;
        curY += maxH + gapY;
    }
    var totalH = curY;

    // Ruteo de relaciones ER
    var relations = [];
    for (var re = 0; re < rawRelations.length; re++) {
        var relItem = rawRelations[re];
        var srcEnt = entities[relItem.from];
        var dstEnt = entities[relItem.to];
        if (!srcEnt || !dstEnt) continue;

        var isDown = dstEnt.y >= srcEnt.y;
        var startPt = {
            x: srcEnt.x + srcEnt.w / 2,
            y: isDown ? (srcEnt.y + srcEnt.h) : srcEnt.y
        };
        var endPt = {
            x: dstEnt.x + dstEnt.w / 2,
            y: isDown ? dstEnt.y : (dstEnt.y + dstEnt.h)
        };
        var endAngle = isDown ? (Math.PI / 2) : (-Math.PI / 2);

        var dy = Math.max(25, Math.abs(endPt.y - startPt.y) * 0.5);
        var cp1y = isDown ? (startPt.y + dy) : (startPt.y - dy);
        var cp2y = isDown ? (endPt.y - dy) : (endPt.y + dy);

        var pathStr = "M " + Math.round(startPt.x) + " " + Math.round(startPt.y) +
                      " C " + Math.round(startPt.x) + " " + Math.round(cp1y) + ", " +
                      Math.round(endPt.x) + " " + Math.round(cp2y) + ", " +
                      Math.round(endPt.x) + " " + Math.round(endPt.y);

        relations.push({
            from: relItem.from,
            to: relItem.to,
            card1: relItem.card1,
            card2: relItem.card2,
            identifying: relItem.identifying,
            fromMarker: relItem.fromMarker,
            toMarker: relItem.toMarker,
            path: pathStr,
            startX: startPt.x,
            startY: startPt.y,
            endX: endPt.x,
            endY: endPt.y,
            endAngle: endAngle,
            label: relItem.label,
            labelX: (startPt.x + endPt.x) / 2,
            labelY: (startPt.y + endPt.y) / 2,
            strokeDash: !relItem.identifying
        });
    }

    return {
        ok: true,
        type: "erDiagram",
        title: ast.title,
        entities: entities,
        relations: relations,
        width: Math.max(300, totalW + 20),
        height: Math.max(120, totalH + 20)
    };
}

// ── 7. GANTT CHART LAYOUT ───────────────────────────────────────────────────

function _layoutGantt(ast, measure, opts) {
    var title = ast.title || "";
    var sections = ast.sections || [];
    var maxW = (opts && opts.maxWidth) ? opts.maxWidth : 800;

    var allTasks = [];
    for (var s = 0; s < sections.length; s++) {
        var secTasks = sections[s].tasks || [];
        for (var t = 0; t < secTasks.length; t++) {
            allTasks.push(secTasks[t]);
        }
    }

    if (allTasks.length === 0) {
        return { ok: true, type: "gantt", width: 300, height: 100, tasks: [], sections: [], gridTicks: [] };
    }

    // Normalizar duraciones y fechas a días relativos
    var taskDays = {};
    var currentDay = 0;
    for (var i = 0; i < allTasks.length; i++) {
        var task = allTasks[i];
        var dur = 3; // default 3 días
        if (task.endOrDuration) {
            var dm = task.endOrDuration.match(/^(\d+)(d|w|h)?$/);
            if (dm) {
                var num = parseInt(dm[1], 10);
                dur = dm[2] === "w" ? (num * 7) : (dm[2] === "h" ? Math.max(1, Math.round(num / 24)) : num);
            }
        }
        if (task.isMilestone) dur = 0;

        var startD = currentDay;
        if (task.start && task.start.startsWith("after")) {
            var afterId = task.start.replace(/^after\s+/, "").trim();
            if (taskDays[afterId]) {
                startD = taskDays[afterId].end;
            }
        }

        taskDays[task.id] = { start: startD, end: startD + dur, dur: dur };
        currentDay = Math.max(currentDay, startD + dur);
    }

    var totalDays = Math.max(7, currentDay + 1);
    var labelColW = 150;
    var chartW = Math.max(280, maxW - labelColW - 40);
    var dayW = chartW / totalDays;

    var hasTitle = !!(title && title.trim().length > 0);
    var titleOffset = hasTitle ? 32 : 0;
    var tickLabelY = 12 + titleOffset;
    var gridTopY = 28 + titleOffset;
    var curY = 38 + titleOffset;
    var layoutSections = [];
    var layoutTasks = [];

    for (var s2 = 0; s2 < sections.length; s2++) {
        var sec = sections[s2];
        var secTasks2 = sec.tasks || [];
        if (secTasks2.length === 0) continue;

        var secStartY = curY;
        if (sec.name && sec.name !== "General") {
            layoutSections.push({
                name: sec.name,
                y: curY,
                h: 22
            });
            curY += 26;
        }

        for (var t2 = 0; t2 < secTasks2.length; t2++) {
            var tObj = secTasks2[t2];
            var dInfo = taskDays[tObj.id] || { start: 0, end: 1, dur: 1 };
            var taskX = labelColW + (dInfo.start * dayW);
            var taskBarW = Math.max(14, dInfo.dur * dayW);

            layoutTasks.push({
                id: tObj.id,
                name: tObj.name,
                x: Math.round(taskX),
                y: curY,
                w: Math.round(taskBarW),
                h: 20,
                isDone: tObj.isDone,
                isActive: tObj.isActive,
                isCrit: tObj.isCrit,
                isMilestone: tObj.isMilestone
            });
            curY += 28;
        }
        curY += 6;
    }

    // Ticks temporales de cuadrícula
    var gridTicks = [];
    var tickStep = Math.max(1, Math.ceil(totalDays / 8));
    for (var td = 0; td <= totalDays; td += tickStep) {
        gridTicks.push({
            x: Math.round(labelColW + td * dayW),
            label: "D" + (td + 1)
        });
    }

    return {
        ok: true,
        type: "gantt",
        title: title,
        labelColW: labelColW,
        chartW: chartW,
        sections: layoutSections,
        tasks: layoutTasks,
        gridTicks: gridTicks,
        tickLabelY: tickLabelY,
        gridTopY: gridTopY,
        width: Math.round(labelColW + chartW + 30),
        height: Math.round(curY + 20)
    };
}

// ── 8. TIMELINE LAYOUT ──────────────────────────────────────────────────────

function _layoutTimeline(ast, measure, opts) {
    var title = ast.title || "";
    var sections = ast.sections || [];

    var periods = [];
    for (var s = 0; s < sections.length; s++) {
        var secPeriods = sections[s].periods || [];
        for (var p = 0; p < secPeriods.length; p++) {
            periods.push(secPeriods[p]);
        }
    }

    if (periods.length === 0) {
        return { ok: true, type: "timeline", width: 300, height: 120, periods: [], cards: [] };
    }

    // Medir ancho requerido para eventos para asegurar que las tarjetas nunca recorten texto
    var maxEventW = 120;
    for (var pi = 0; pi < periods.length; pi++) {
        var evts = periods[pi].events || [];
        for (var ei = 0; ei < evts.length; ei++) {
            var m = measure(evts[ei], 11);
            var reqW = m.width + 12 + 24; // bullet + spacing + card padding
            if (reqW > maxEventW) maxEventW = reqW;
        }
    }

    var baseSpacing = Math.max(maxEventW + 24, 150);
    var spacing = Math.max(baseSpacing, Math.floor(((opts && opts.maxWidth ? opts.maxWidth : 750) - 60) / Math.max(1, periods.length)));
    var hasTitle = !!(title && title.trim().length > 0);
    var titleOffset = hasTitle ? 36 : 0;
    var axisY = 130 + titleOffset;
    var layoutPeriods = [];
    var layoutCards = [];

    // Asegurar que el primer período inicie con espacio suficiente para la mitad de la tarjeta + margen
    var cardW = Math.max(maxEventW, spacing - 24);
    var curX = Math.max(40, Math.ceil(cardW / 2 + 24));

    for (var i = 0; i < periods.length; i++) {
        var per = periods[i];
        var isTop = (i % 2 === 0);

        layoutPeriods.push({
            name: per.period,
            x: curX,
            y: axisY
        });

        var evs = per.events || [];
        var cardH = evs.length * 20 + 16;
        var cardY = isTop ? (axisY - 24 - cardH) : (axisY + 24);

        layoutCards.push({
            period: per.period,
            events: evs,
            x: curX - cardW / 2,
            y: cardY,
            w: cardW,
            h: cardH,
            isTop: isTop,
            stemX: curX,
            stemY1: isTop ? (cardY + cardH) : axisY,
            stemY2: isTop ? axisY : cardY
        });

        curX += spacing;
    }

    // Calcular cajas de secciones para agrupar períodos cronológicos (ej: 2024, 2025)
    var layoutSections = [];
    var pTracker = 0;
    for (var s2 = 0; s2 < sections.length; s2++) {
        var secObj = sections[s2];
        var sCount = (secObj.periods || []).length;
        if (sCount === 0) continue;
        var pStart = layoutPeriods[pTracker];
        var pEnd = layoutPeriods[pTracker + sCount - 1];
        pTracker += sCount;

        if (secObj.name && secObj.name.trim() !== "" && pStart && pEnd) {
            var sLeft = Math.min(pStart.x - cardW / 2, pStart.x - 30);
            var sRight = Math.max(pEnd.x + cardW / 2, pEnd.x + 30);
            layoutSections.push({
                name: secObj.name.trim(),
                x: sLeft,
                w: Math.max(70, sRight - sLeft),
                y: axisY - 16
            });
        }
    }

    var axisStartX = Math.min(layoutPeriods[0].x - 40, layoutCards[0].x - 16);
    var axisEndX = Math.max(layoutPeriods[layoutPeriods.length - 1].x + 40, layoutCards[layoutCards.length - 1].x + cardW + 16);

    // Normalización de coordenadas para garantizar margen positivo y evitar recortes en el borde izquierdo
    var minX = Infinity;
    var maxX = -Infinity;
    for (var ci = 0; ci < layoutCards.length; ci++) {
        if (layoutCards[ci].x < minX) minX = layoutCards[ci].x;
        if (layoutCards[ci].x + layoutCards[ci].w > maxX) maxX = layoutCards[ci].x + layoutCards[ci].w;
    }
    if (axisStartX < minX) minX = axisStartX;
    if (axisEndX > maxX) maxX = axisEndX;

    var targetMargin = 24;
    var shiftX = minX < targetMargin ? (targetMargin - minX) : 0;
    if (shiftX !== 0) {
        for (var ci2 = 0; ci2 < layoutCards.length; ci2++) {
            layoutCards[ci2].x += shiftX;
            layoutCards[ci2].stemX += shiftX;
        }
        for (var pi2 = 0; pi2 < layoutPeriods.length; pi2++) {
            layoutPeriods[pi2].x += shiftX;
        }
        for (var si2 = 0; si2 < layoutSections.length; si2++) {
            layoutSections[si2].x += shiftX;
        }
        axisStartX += shiftX;
        axisEndX += shiftX;
        maxX += shiftX;
    }

    return {
        ok: true,
        type: "timeline",
        title: title,
        axisY: axisY,
        axisStartX: axisStartX,
        axisEndX: axisEndX,
        sections: layoutSections,
        periods: layoutPeriods,
        cards: layoutCards,
        width: Math.max(300, Math.ceil(maxX + targetMargin)),
        height: Math.max(160 + titleOffset, axisY + 140)
    };
}

// ── 9. MINDMAP LAYOUT ───────────────────────────────────────────────────────

function _layoutMindmap(ast, measure, opts) {
    var title = ast.title || "";
    var root = ast.root;
    if (!root) {
        return { ok: true, type: "mindmap", width: 200, height: 100, nodes: [], edges: [] };
    }

    var nodes = [];
    var edges = [];

    // A. Medir dimensiones de cada nodo del árbol
    function measureNode(n) {
        var m = measure(n.label || "", 13);
        if (n.shape === "circle" || n.shape === "doublecircle") {
            var d = Math.max(m.width + 36, m.height + 36, 56);
            n.w = d;
            n.h = d;
        } else if (n.shape === "cloud" || n.shape === "bang") {
            n.w = Math.max(76, m.width + 40);
            n.h = Math.max(36, m.height + 16);
        } else {
            n.w = Math.max(64, m.width + 24);
            n.h = Math.max(28, m.height + 12);
        }
        var subH = 0;
        for (var c = 0; c < (n.children || []).length; c++) {
            subH += measureNode(n.children[c]);
        }
        n.subH = Math.max(n.h, subH + (n.children && n.children.length > 1 ? (n.children.length - 1) * 14 : 0));
        return n.subH;
    }
    measureNode(root);

    // B. Posicionar jerárquicamente a la derecha con ramas orgánicas
    var totalH = Math.max(120, root.subH + 40);

    function placeSubtree(node, x, yCenter, branchColorIdx) {
        node.x = Math.round(x);
        node.y = Math.round(yCenter - node.h / 2);
        node.colorIdx = branchColorIdx;

        nodes.push({
            id: node.id,
            label: node.label,
            shape: node.shape || "rect",
            x: node.x,
            y: node.y,
            w: node.w,
            h: node.h,
            colorIdx: branchColorIdx
        });

        var children = node.children || [];
        if (children.length === 0) return;

        var startY = yCenter - node.subH / 2;
        var nextX = node.x + node.w + 50;

        for (var ci = 0; ci < children.length; ci++) {
            var child = children[ci];
            var cColor = (node === root) ? ci : branchColorIdx;
            var childCenterY = startY + child.subH / 2;

            placeSubtree(child, nextX, childCenterY, cColor);

            // Curva Bézier fluida conectando el padre con el hijo
            var pRightX = node.x + node.w;
            var pRightY = node.y + node.h / 2;
            var cLeftX = child.x;
            var cLeftY = child.y + child.h / 2;
            var dx = (cLeftX - pRightX) * 0.5;

            edges.push({
                path: "M " + pRightX + " " + pRightY + " C " + (pRightX + dx) + " " + pRightY + ", " + (cLeftX - dx) + " " + cLeftY + ", " + cLeftX + " " + cLeftY,
                colorIdx: cColor
            });

            startY += child.subH + 14;
        }
    }

    var hasTitle = !!(title && title.trim().length > 0);
    var titleOffset = hasTitle ? 34 : 0;
    placeSubtree(root, 24, (totalH / 2) + titleOffset, 0);

    var maxRightX = 0;
    for (var ni = 0; ni < nodes.length; ni++) {
        if (nodes[ni].x + nodes[ni].w > maxRightX) maxRightX = nodes[ni].x + nodes[ni].w;
    }

    return {
        ok: true,
        type: "mindmap",
        title: title,
        nodes: nodes,
        edges: edges,
        width: Math.max(280, maxRightX + 30),
        height: totalH + 30 + titleOffset
    };
}

// ── 10. GIT GRAPH LAYOUT (FASE 3) ────────────────────────────────────────────

function _layoutGitGraph(ast, measure, opts) {
    var title = ast.title || "";
    var branches = ast.branches || [];
    var commits = ast.commits || [];
    var hasTitle = !!(title && title.trim().length > 0);
    var titleOffset = hasTitle ? 36 : 0;
    var topMargin = 50 + titleOffset;

    var branchY = {};
    var branchLanes = [];
    var maxBranchNameW = 50;

    for (var bi = 0; bi < branches.length; bi++) {
        var b = branches[bi];
        var y = topMargin + bi * 52;
        branchY[b.name] = y;
        var m = measure(b.name, 11);
        if (m.width > maxBranchNameW) maxBranchNameW = m.width;
    }

    var startX = maxBranchNameW + 48;
    var commitMap = {};
    var layoutCommits = [];
    var curX = startX;
    var prevReqW = 0;

    for (var ci = 0; ci < commits.length; ci++) {
        var c = commits[ci];
        var idW = measure(c.id, 10).width;
        var tagW = c.tag ? measure(c.tag, 9).width : 0;
        var reqW = Math.max(idW, tagW, 20);

        if (ci === 0) {
            curX = startX;
        } else {
            // Espaciado adaptativo para evitar cualquier solapamiento de textos entre commits adyacentes
            var deltaX = Math.max(72, Math.ceil((prevReqW + reqW) / 2 + 20));
            curX += deltaX;
        }
        prevReqW = reqW;

        var cy = branchY[c.branch] !== undefined ? branchY[c.branch] : topMargin;
        var bIdx = branches.findIndex(function(bItem) { return bItem.name === c.branch; });
        if (bIdx === -1) bIdx = 0;

        var cObj = {
            id: c.id,
            branch: c.branch,
            x: curX,
            y: cy,
            type: c.type || "NORMAL",
            tag: c.tag || "",
            parents: c.parents || [],
            mergedFrom: c.mergedFrom || "",
            colorIdx: bIdx,
            reqW: reqW,
            seq: ci
        };
        commitMap[c.id] = cObj;
        layoutCommits.push(cObj);
    }

    // Branch lanes guide lines
    var lastCommitX = layoutCommits.length > 0 ? layoutCommits[layoutCommits.length - 1].x : startX;
    for (var bi2 = 0; bi2 < branches.length; bi2++) {
        var b2 = branches[bi2];
        var bCommits = layoutCommits.filter(function(lc) { return lc.branch === b2.name; });
        var minX = startX - 20;
        var maxX = lastCommitX + 40;
        if (bCommits.length > 0) {
            maxX = Math.max(maxX, bCommits[bCommits.length - 1].x + 40);
        }
        branchLanes.push({
            name: b2.name,
            y: branchY[b2.name],
            startX: minX,
            endX: maxX,
            colorIdx: bi2
        });
    }

    // Connectors
    var connectors = [];
    for (var ci2 = 0; ci2 < layoutCommits.length; ci2++) {
        var child = layoutCommits[ci2];
        for (var pi = 0; pi < child.parents.length; pi++) {
            var parent = commitMap[child.parents[pi]];
            if (parent) {
                if (parent.y === child.y) {
                    connectors.push({
                        path: "M " + parent.x + " " + parent.y + " L " + child.x + " " + child.y,
                        colorIdx: child.colorIdx
                    });
                } else {
                    var dx = (child.x - parent.x) * 0.5;
                    var connColor = child.colorIdx;
                    if (child.mergedFrom) {
                        var mIdx = branches.findIndex(function(b) { return b.name === child.mergedFrom; });
                        if (mIdx !== -1) connColor = mIdx;
                    }
                    connectors.push({
                        path: "M " + parent.x + " " + parent.y + " C " + (parent.x + dx) + " " + parent.y + ", " + (child.x - dx) + " " + child.y + ", " + child.x + " " + child.y,
                        colorIdx: connColor
                    });
                }
            }
        }
    }

    var totalW = Math.max(340, lastCommitX + 60);
    var totalH = topMargin + branches.length * 52 + 40;

    return {
        ok: true,
        type: "gitGraph",
        title: title,
        branches: branchLanes,
        commits: layoutCommits,
        connectors: connectors,
        width: totalW,
        height: totalH
    };
}

// ── 11. QUADRANT CHART LAYOUT (FASE 3) ───────────────────────────────────────

function _layoutQuadrantChart(ast, measure, opts) {
    var title = ast.title || "";
    var xAxis = ast.xAxis || { left: "", right: "" };
    var yAxis = ast.yAxis || { bottom: "", top: "" };
    var quadrants = ast.quadrants || { q1: "", q2: "", q3: "", q4: "" };
    var points = ast.points || [];

    var hasTitle = !!(title && title.trim().length > 0);
    var titleOffset = hasTitle ? 36 : 0;
    var chartSize = Math.max(340, Math.min(440, (opts && opts.maxWidth ? opts.maxWidth - 80 : 440)));

    var left = 40;
    var top = 26 + titleOffset;
    var half = chartSize / 2;
    var cx = left + half;
    var cy = top + half;

    // Margen interior de seguridad para mantener puntos y etiquetas estrictamente dentro de la caja
    var innerPad = 38;
    var plotW = chartSize - (innerPad * 2);
    var plotH = chartSize - (innerPad * 2);

    var layoutPoints = [];
    for (var pi = 0; pi < points.length; pi++) {
        var p = points[pi];
        var px = left + innerPad + p.x * plotW;
        var py = top + innerPad + (1.0 - p.y) * plotH;
        layoutPoints.push({
            label: p.label,
            x: px,
            y: py,
            alignLeft: (p.x > 0.55)
        });
    }

    return {
        ok: true,
        type: "quadrantChart",
        title: title,
        chartSize: chartSize,
        left: left,
        top: top,
        cx: cx,
        cy: cy,
        xAxis: xAxis,
        yAxis: yAxis,
        quadrants: {
            q1: { text: quadrants.q1 || "", x: cx + 12, y: top + 16 },
            q2: { text: quadrants.q2 || "", x: left + 12, y: top + 16 },
            q3: { text: quadrants.q3 || "", x: left + 12, y: cy + 16 },
            q4: { text: quadrants.q4 || "", x: cx + 12, y: cy + 16 }
        },
        points: layoutPoints,
        width: Math.max(360, chartSize + 80),
        height: Math.max(360, chartSize + 60 + titleOffset)
    };
}

// ── 12. USER JOURNEY LAYOUT (FASE 3) ─────────────────────────────────────────

function _layoutJourney(ast, measure, opts) {
    var title = ast.title || "";
    var sections = ast.sections || [];
    var actors = ast.actors || [];
    var hasTitle = !!(title && title.trim().length > 0);
    var titleOffset = hasTitle ? 36 : 0;

    // Medir ancho dinámico de tarjetas para evitar truncados
    var maxTaskW = 110;
    for (var si0 = 0; si0 < sections.length; si0++) {
        var sTasks0 = sections[si0].tasks || [];
        for (var ti0 = 0; ti0 < sTasks0.length; ti0++) {
            var tm = measure(sTasks0[ti0].name, 11);
            if (tm.width > maxTaskW) maxTaskW = tm.width;
        }
    }
    var cardW = Math.max(160, Math.min(220, maxTaskW + 40));
    var cardH = 92;
    var curX = 24;
    var topY = 40 + titleOffset;

    // Tres zonas verticales disjuntas:
    // 1. Cabeceras de sección
    var secY = topY + 6;
    var secH = 26;

    // 2. Franja de curva de satisfacción
    var curveBandTop = secY + secH + 14;
    var curveBandH = 58;

    // 3. Tarjetas de tareas
    var taskCardY = curveBandTop + curveBandH + 14;

    var layoutSections = [];
    var layoutTasks = [];
    var splinePoints = [];

    for (var si = 0; si < sections.length; si++) {
        var sec = sections[si];
        var secStartX = curX;
        var secTasks = sec.tasks || [];

        for (var ti = 0; ti < secTasks.length; ti++) {
            var t = secTasks[ti];
            var tx = curX;
            var ty = taskCardY;

            // Score curve Y: nivel 5 arriba (curveBandTop + 6), nivel 1 abajo (curveBandTop + 50)
            var curveY = curveBandTop + 6 + (5 - t.score) * 11;
            var curveX = tx + cardW / 2;
            splinePoints.push({ x: curveX, y: curveY, score: t.score });

            layoutTasks.push({
                name: t.name,
                score: t.score,
                actors: t.actors || [],
                x: tx,
                y: ty,
                w: cardW,
                h: cardH,
                sectionIdx: si
            });

            curX += cardW + 16;
        }

        var secW = Math.max(cardW, (curX - 16) - secStartX);
        layoutSections.push({
            name: sec.name,
            x: secStartX,
            y: secY,
            w: secW,
            colorIdx: si
        });
    }

    // Build SVG trajectory path
    var trajPath = "";
    if (splinePoints.length > 0) {
        trajPath = "M " + splinePoints[0].x + " " + splinePoints[0].y;
        for (var spi = 1; spi < splinePoints.length; spi++) {
            var pPrev = splinePoints[spi - 1];
            var pCurr = splinePoints[spi];
            var midX = (pPrev.x + pCurr.x) / 2;
            trajPath += " C " + midX + " " + pPrev.y + ", " + midX + " " + pCurr.y + ", " + pCurr.x + " " + pCurr.y;
        }
    }

    // Líneas guía de benchmark de satisfacción
    var curveGuides = [
        { score: 5, label: "5", y: curveBandTop + 6 },
        { score: 3, label: "3", y: curveBandTop + 28 },
        { score: 1, label: "1", y: curveBandTop + 50 }
    ];

    var totalW = Math.max(340, curX + 20);
    var totalH = taskCardY + cardH + 24;

    return {
        ok: true,
        type: "journey",
        title: title,
        sections: layoutSections,
        tasks: layoutTasks,
        points: splinePoints,
        trajectoryPath: trajPath,
        curveGuides: curveGuides,
        curveBandTop: curveBandTop,
        curveBandH: curveBandH,
        actors: actors,
        width: totalW,
        height: totalH
    };
}

// ── 13. XY CHART LAYOUT (FASE 3) ─────────────────────────────────────────────

function _layoutXyChart(ast, measure, opts) {
    var title = ast.title || "";
    var xAxis = ast.xAxis || { title: "", categories: [] };
    var yAxis = ast.yAxis || { title: "", min: null, max: null };
    var plots = ast.plots || [];
    var hasTitle = !!(title && title.trim().length > 0);
    var titleOffset = hasTitle ? 36 : 0;

    var numPoints = Math.max(xAxis.categories.length, 1);
    for (var pi = 0; pi < plots.length; pi++) {
        if (plots[pi].values.length > numPoints) numPoints = plots[pi].values.length;
    }

    // Determine scale min/max
    var allVals = [];
    for (var pi2 = 0; pi2 < plots.length; pi2++) {
        for (var vi = 0; vi < plots[pi2].values.length; vi++) {
            allVals.push(plots[pi2].values[vi]);
        }
    }
    if (allVals.length === 0) allVals.push(0);

    var rawMin = Math.min.apply(null, allVals);
    var rawMax = Math.max.apply(null, allVals);

    var yMin = yAxis.min !== null && yAxis.min !== undefined ? yAxis.min : Math.min(0, rawMin);
    var yMax = yAxis.max !== null && yAxis.max !== undefined ? yAxis.max : (rawMax > 0 ? rawMax * 1.15 : 10);
    if (yMax <= yMin) yMax = yMin + 10;

    var plotW = Math.max(300, numPoints * 56);
    var plotH = 200;
    var plotLeft = 60;
    // Margen superior suficiente para que el título no toque el tick superior
    var plotTop = 44 + titleOffset;

    // Y ticks (5 ticks)
    var ticks = [];
    var numTicks = 5;
    for (var ti = 0; ti < numTicks; ti++) {
        var frac = ti / (numTicks - 1);
        var val = yMin + frac * (yMax - yMin);
        var tickY = plotTop + plotH - (frac * plotH);
        ticks.push({
            value: Math.round(val * 10) / 10,
            y: tickY
        });
    }

    var slotW = plotW / numPoints;
    var barW = Math.max(16, Math.min(36, slotW - 14));

    var layoutPlots = [];
    for (var pidx = 0; pidx < plots.length; pidx++) {
        var pItem = plots[pidx];
        var isBar = (pItem.type === "bar");
        var pData = [];
        var linePath = "";

        for (var vi2 = 0; vi2 < pItem.values.length; vi2++) {
            var val2 = pItem.values[vi2];
            var hFrac = (val2 - yMin) / (yMax - yMin);
            var itemH = Math.max(2, hFrac * plotH);
            var itemX = plotLeft + vi2 * slotW + (slotW - barW) / 2;
            var itemY = plotTop + plotH - itemH;
            var centerX = plotLeft + vi2 * slotW + slotW / 2;
            var centerY = plotTop + plotH - (hFrac * plotH);

            if (isBar) {
                pData.push({
                    x: itemX,
                    y: itemY,
                    w: barW,
                    h: itemH,
                    val: val2,
                    cat: xAxis.categories[vi2] || ("#" + (vi2 + 1))
                });
            } else {
                pData.push({
                    x: centerX,
                    y: centerY,
                    val: val2,
                    cat: xAxis.categories[vi2] || ("#" + (vi2 + 1))
                });
                if (vi2 === 0) {
                    linePath += "M " + centerX + " " + centerY;
                } else {
                    linePath += " L " + centerX + " " + centerY;
                }
            }
        }

        layoutPlots.push({
            type: pItem.type,
            data: pData,
            path: linePath,
            colorIdx: pidx
        });
    }

    // Categories
    var layoutCats = [];
    for (var ci = 0; ci < numPoints; ci++) {
        layoutCats.push({
            label: xAxis.categories[ci] || ("#" + (ci + 1)),
            x: plotLeft + ci * slotW + slotW / 2,
            y: plotTop + plotH + 18
        });
    }

    var totalW = Math.max(340, plotLeft + plotW + 40);
    var totalH = plotTop + plotH + 46;

    return {
        ok: true,
        type: "xychart",
        title: title,
        yAxisTitle: yAxis.title || "",
        yAxisTitleY: plotTop - 26,
        xAxisTitle: xAxis.title || "",
        plotLeft: plotLeft,
        plotTop: plotTop,
        plotW: plotW,
        plotH: plotH,
        ticks: ticks,
        categories: layoutCats,
        plots: layoutPlots,
        width: totalW,
        height: totalH
    };
}
