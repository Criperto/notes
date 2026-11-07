.pragma library

// Selection.js — Helpers puros para selección múltiple de bloques (Notion-style)

function count(selectedBids) {
    if (!selectedBids || typeof selectedBids !== "object") return 0;
    var n = 0;
    for (var k in selectedBids) {
        if (selectedBids[k] === true) n++;
    }
    return n;
}

function toMap(bids) {
    var m = {};
    if (Array.isArray(bids)) {
        for (var i = 0; i < bids.length; i++) {
            var b = bids[i];
            if (b !== undefined && b !== null && b !== -1) {
                m[b] = true;
            }
        }
    }
    return m;
}

function rangeBids(blocks, fromBid, toBid) {
    if (!Array.isArray(blocks) || blocks.length === 0) return [];
    var idx1 = -1;
    var idx2 = -1;
    for (var i = 0; i < blocks.length; i++) {
        var b = blocks[i];
        var bid = (b && typeof b === "object") ? b.bid : b;
        if (bid === fromBid) idx1 = i;
        if (bid === toBid) idx2 = i;
    }
    if (idx1 === -1 && idx2 === -1) return [];
    if (idx1 === -1) return [toBid];
    if (idx2 === -1) return [fromBid];
    var start = Math.min(idx1, idx2);
    var end = Math.max(idx1, idx2);
    var res = [];
    for (var k = start; k <= end; k++) {
        var item = blocks[k];
        res.push((item && typeof item === "object") ? item.bid : item);
    }
    return res;
}


function removeSelected(blocks, selectedBids, createFallbackBlock) {
    if (!Array.isArray(blocks)) return { blocks: [], focusIndex: -1 };
    var remaining = [];
    var firstRemovedIdx = -1;
    for (var i = 0; i < blocks.length; i++) {
        var b = blocks[i];
        if (b && selectedBids && selectedBids[b.bid] === true) {
            if (firstRemovedIdx === -1) firstRemovedIdx = i;
        } else {
            remaining.push(b);
        }
    }
    if (remaining.length === 0) {
        var fallback = (typeof createFallbackBlock === "function")
            ? createFallbackBlock()
            : { bid: 1, type: "paragraph", raw: "", sep: "\n\n" };
        remaining.push(fallback);
        return { blocks: remaining, focusIndex: 0 };
    }
    var focusIdx = (firstRemovedIdx !== -1) ? Math.min(firstRemovedIdx, remaining.length - 1) : 0;
    return { blocks: remaining, focusIndex: focusIdx };
}

function extractSelectedText(blocks, startBid, startPos, endBid, endPos) {
    if (!Array.isArray(blocks) || blocks.length === 0) return "";
    var idx1 = -1;
    var idx2 = -1;
    for (var i = 0; i < blocks.length; i++) {
        var b = blocks[i];
        if (b.bid === startBid) idx1 = i;
        if (b.bid === endBid) idx2 = i;
    }
    if (idx1 === -1 || idx2 === -1) return "";

    var sIdx = Math.min(idx1, idx2);
    var eIdx = Math.max(idx1, idx2);
    var sPos = (idx1 <= idx2) ? startPos : endPos;
    var ePos = (idx1 <= idx2) ? endPos : startPos;

    if (sIdx === eIdx) {
        var raw = blocks[sIdx].raw || "";
        var from = Math.min(sPos, ePos);
        var to = Math.max(sPos, ePos);
        return raw.substring(from, to);
    }

    var parts = [];
    for (var k = sIdx; k <= eIdx; k++) {
        var bRaw = blocks[k].raw || "";
        if (k === sIdx) {
            parts.push(bRaw.substring(sPos));
        } else if (k === eIdx) {
            parts.push(bRaw.substring(0, ePos));
        } else {
            parts.push(bRaw);
        }
    }
    return parts.join("\n\n");
}

function replaceSelectedRange(blocks, startBid, startPos, endBid, endPos, replacementText) {
    if (!Array.isArray(blocks) || blocks.length === 0) {
        return { blocks: blocks || [], cursorBid: -1, cursorPos: 0 };
    }
    var idx1 = -1;
    var idx2 = -1;
    for (var i = 0; i < blocks.length; i++) {
        var b = blocks[i];
        if (b.bid === startBid) idx1 = i;
        if (b.bid === endBid) idx2 = i;
    }
    if (idx1 === -1 || idx2 === -1) {
        return { blocks: blocks, cursorBid: -1, cursorPos: 0 };
    }

    var sIdx = Math.min(idx1, idx2);
    var eIdx = Math.max(idx1, idx2);
    var sPos = (idx1 <= idx2) ? startPos : endPos;
    var ePos = (idx1 <= idx2) ? endPos : startPos;

    var repl = (typeof replacementText === "string") ? replacementText : "";

    if (sIdx === eIdx) {
        var cur = blocks[sIdx];
        var raw = cur.raw || "";
        var from = Math.max(0, Math.min(raw.length, Math.min(sPos, ePos)));
        var to = Math.max(0, Math.min(raw.length, Math.max(sPos, ePos)));
        var newRaw = raw.substring(0, from) + repl + raw.substring(to);
        var resultBlocks = blocks.slice();
        resultBlocks[sIdx] = {
            bid: cur.bid,
            type: cur.type,
            raw: newRaw,
            sep: cur.sep !== undefined ? cur.sep : "\n\n"
        };
        return { blocks: resultBlocks, cursorBid: cur.bid, cursorPos: from + repl.length };
    }

    var startBlock = blocks[sIdx];
    var endBlock = blocks[eIdx];
    var sRaw = startBlock.raw || "";
    var eRaw = endBlock.raw || "";

    var prefix = sRaw.substring(0, Math.max(0, Math.min(sRaw.length, sPos)));
    var suffix = eRaw.substring(Math.max(0, Math.min(eRaw.length, ePos)));
    var merged = prefix + repl + suffix;

    var res = [];
    for (var j = 0; j < sIdx; j++) {
        res.push(blocks[j]);
    }
    res.push({
        bid: startBlock.bid,
        type: startBlock.type,
        raw: merged,
        sep: startBlock.sep !== undefined ? startBlock.sep : "\n\n"
    });
    for (var m = eIdx + 1; m < blocks.length; m++) {
        res.push(blocks[m]);
    }

    return { blocks: res, cursorBid: startBlock.bid, cursorPos: prefix.length + repl.length };
}
