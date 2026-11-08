.pragma library

// Diff.js — Motor de Diff puro (Myers O(ND)) para líneas y palabras
// Sin dependencias externas, totalmente ejecutable en QML y Node.js.

// ── Algoritmo Myers clásico con recorte de prefijo/sufijo común ──────────
function _myers(a, b, equalsFn) {
    var n = a.length;
    var m = b.length;

    // Caso base: alguno vacío
    if (n === 0) {
        var resB = [];
        for (var bi = 0; bi < m; bi++) resB.push({ type: "add", val: b[bi], aIdx: -1, bIdx: bi });
        return resB;
    }
    if (m === 0) {
        var resA = [];
        for (var ai = 0; ai < n; ai++) resA.push({ type: "del", val: a[ai], aIdx: ai, bIdx: -1 });
        return resA;
    }

    var maxD = n + m;
    var offset = maxD;
    var v = new Int32Array(2 * maxD + 2);
    v.fill(-1);
    v[offset + 1] = 0;

    var trace = [];
    var foundD = -1;

    for (var d = 0; d <= maxD; d++) {
        var vCopy = new Int32Array(v.length);
        vCopy.set(v);
        trace.push(vCopy);

        for (var k = -d; k <= d; k += 2) {
            var kIdx = offset + k;
            var x;
            if (k === -d || (k !== d && v[kIdx - 1] < v[kIdx + 1])) {
                x = v[kIdx + 1]; // movimiento hacia abajo (add)
            } else {
                x = v[kIdx - 1] + 1; // movimiento hacia la derecha (del)
            }
            var y = x - k;

            while (x < n && y < m && equalsFn(a[x], b[y])) {
                x++;
                y++;
            }

            v[kIdx] = x;

            if (x >= n && y >= m) {
                foundD = d;
                break;
            }
        }
        if (foundD !== -1) break;
    }

    // Reconstrucción del camino en reversa
    var script = [];
    var currX = n;
    var currY = m;

    for (var dStep = trace.length - 1; dStep > 0; dStep--) {
        var prevV = trace[dStep];
        var stepK = currX - currY;
        var stepKIdx = offset + stepK;

        var prevK;
        if (stepK === -dStep || (stepK !== dStep && prevV[stepKIdx - 1] < prevV[stepKIdx + 1])) {
            prevK = stepK + 1;
        } else {
            prevK = stepK - 1;
        }

        var prevX = prevV[offset + prevK];
        var prevY = prevX - prevK;

        while (currX > prevX && currY > prevY) {
            currX--;
            currY--;
            script.push({ type: "equal", val: a[currX], aIdx: currX, bIdx: currY });
        }

        if (dStep > 0) {
            if (currX === prevX) {
                currY--;
                script.push({ type: "add", val: b[currY], aIdx: -1, bIdx: currY });
            } else if (currY === prevY) {
                currX--;
                script.push({ type: "del", val: a[currX], aIdx: currX, bIdx: -1 });
            }
        }
    }

    while (currX > 0 && currY > 0) {
        currX--;
        currY--;
        script.push({ type: "equal", val: a[currX], aIdx: currX, bIdx: currY });
    }

    script.reverse();
    return script;
}

// ── Diff de Líneas ───────────────────────────────────────────────────────
function diffLines(textA, textB) {
    if (typeof Sys !== "undefined" && typeof Sys.diffLines === "function") {
        var nativeRes = Sys.diffLines(textA, textB);
        if (nativeRes) return nativeRes;
    }

    if (textA === textB) {
        if (!textA) return [];
        var sameLines = textA.split("\n");
        var sameRes = [];
        for (var si = 0; si < sameLines.length; si++) {
            sameRes.push({ type: "equal", line: sameLines[si], aIdx: si, bIdx: si });
        }
        return sameRes;
    }

    var linesA = typeof textA === "string" ? textA.split("\n") : [];
    var linesB = typeof textB === "string" ? textB.split("\n") : [];

    // Optimización: recortar prefijo común
    var start = 0;
    var minLen = Math.min(linesA.length, linesB.length);
    while (start < minLen && linesA[start] === linesB[start]) {
        start++;
    }

    // Optimización: recortar sufijo común
    var endA = linesA.length - 1;
    var endB = linesB.length - 1;
    while (endA >= start && endB >= start && linesA[endA] === linesB[endB]) {
        endA--;
        endB--;
    }

    var res = [];
    for (var p = 0; p < start; p++) {
        res.push({ type: "equal", line: linesA[p], aIdx: p, bIdx: p });
    }

    var middleA = linesA.slice(start, endA + 1);
    var middleB = linesB.slice(start, endB + 1);

    if (middleA.length > 0 || middleB.length > 0) {
        var diffMid = _myers(middleA, middleB, function (x, y) { return x === y; });
        for (var mi = 0; mi < diffMid.length; mi++) {
            var item = diffMid[mi];
            res.push({
                type: item.type,
                line: item.val,
                aIdx: item.aIdx !== -1 ? start + item.aIdx : -1,
                bIdx: item.bIdx !== -1 ? start + item.bIdx : -1
            });
        }
    }

    for (var sA = endA + 1, sB = endB + 1; sA < linesA.length; sA++, sB++) {
        res.push({ type: "equal", line: linesA[sA], aIdx: sA, bIdx: sB });
    }

    return res;
}

// ── Diff de Palabras / Tokens dentro de una línea ────────────────────────
function _tokenizeWords(line) {
    if (!line) return [];
    var match = line.match(/[\wáéíóúÁÉÍÓÚñÑüÜ]+|\s+|[^\w\s]/g);
    return match || [line];
}

function diffWords(lineA, lineB) {
    if (typeof Sys !== "undefined" && typeof Sys.diffWords === "function") {
        var nativeWords = Sys.diffWords(lineA, lineB);
        if (nativeWords) return nativeWords;
    }

    if (lineA === lineB) {
        return [{ type: "equal", text: lineA || "" }];
    }
    var tokensA = _tokenizeWords(lineA);
    var tokensB = _tokenizeWords(lineB);

    var rawDiff = _myers(tokensA, tokensB, function (x, y) { return x === y; });

    // Compactar tokens contiguos del mismo tipo
    var merged = [];
    for (var i = 0; i < rawDiff.length; i++) {
        var cur = rawDiff[i];
        if (merged.length > 0 && merged[merged.length - 1].type === cur.type) {
            merged[merged.length - 1].text += cur.val;
        } else {
            merged.push({ type: cur.type, text: cur.val });
        }
    }
    return merged;
}

// ── Agrupación en Hunks con contexto ─────────────────────────────────────
function hunks(ops, context) {
    var ctx = typeof context === "number" ? context : 3;
    if (!ops || ops.length === 0) return [];

    var hasChanges = false;
    for (var cCheck = 0; cCheck < ops.length; cCheck++) {
        if (ops[cCheck].type !== "equal") {
            hasChanges = true;
            break;
        }
    }
    if (!hasChanges) {
        return ops;
    }

    var show = new Uint8Array(ops.length);
    for (var i = 0; i < ops.length; i++) {
        if (ops[i].type !== "equal") {
            var from = Math.max(0, i - ctx);
            var to = Math.min(ops.length - 1, i + ctx);
            for (var j = from; j <= to; j++) {
                show[j] = 1;
            }
        }
    }

    var result = [];
    var inOmitted = false;
    var omittedCount = 0;

    for (var k = 0; k < ops.length; k++) {
        if (show[k]) {
            if (inOmitted) {
                result.push({ type: "separator", count: omittedCount });
                inOmitted = false;
                omittedCount = 0;
            }
            result.push(ops[k]);
        } else {
            inOmitted = true;
            omittedCount++;
        }
    }
    if (inOmitted) {
        result.push({ type: "separator", count: omittedCount });
    }

    return result;
}

// ── Estadísticas de adiciones y supresiones ──────────────────────────────
function stats(ops) {
    var added = 0;
    var removed = 0;
    if (!ops) return { added: 0, removed: 0 };
    for (var i = 0; i < ops.length; i++) {
        if (ops[i].type === "add") added++;
        else if (ops[i].type === "del") removed++;
    }
    return { added: added, removed: removed };
}
