.pragma library

// History.js — Pila de historial de snapshots para undo/redo a nivel de documento
var MAX_HISTORY = 100;
var MAX_BYTES = 2 * 1024 * 1024; // 2 MB límite por nota

function createHistory(initial) {
    var firstState = (typeof initial === "object" && initial !== null) ? initial : {
        md: (typeof initial === "string") ? initial : "",
        activeBid: -1,
        cursorPos: 0,
        contentY: 0
    };
    return {
        stack: [firstState],
        index: 0
    };
}

function pushState(hist, state) {
    if (!hist || state === undefined || state === null) return;
    var st = (typeof state === "string") ? { md: state, activeBid: -1, cursorPos: 0, contentY: 0 } : state;
    var current = hist.stack[hist.index];
    var currentMd = (current && typeof current === "object") ? current.md : current;
    if (currentMd === st.md) return;
    hist.stack = hist.stack.slice(0, hist.index + 1);
    hist.stack.push(st);
    if (hist.stack.length > MAX_HISTORY) {
        hist.stack.shift();
    }
    hist.index = hist.stack.length - 1;
}

function canUndo(hist) {
    return !!(hist && hist.index > 0);
}

function canRedo(hist) {
    return !!(hist && hist.index < hist.stack.length - 1);
}

function undo(hist) {
    if (!canUndo(hist)) return null;
    hist.index--;
    return hist.stack[hist.index];
}

function redo(hist) {
    if (!canRedo(hist)) return null;
    hist.index++;
    return hist.stack[hist.index];
}

// ── Capa A: Serialización persistente de pila de undo/redo ──────────────────
function serialize(hist, maxBytes) {
    if (!hist || !Array.isArray(hist.stack) || hist.stack.length === 0) {
        return "";
    }
    var limit = typeof maxBytes === "number" && maxBytes > 0 ? maxBytes : MAX_BYTES;

    // Clonar para no mutar la pila en vivo si hay que recortar por bytes
    var safeStack = hist.stack.slice();
    var safeIndex = hist.index;

    var payload = {
        version: 1,
        index: safeIndex,
        stack: safeStack
    };

    var json = JSON.stringify(payload);
    // Si excede el tope de bytes, recortar los estados más antiguos del fondo
    while (json.length > limit && safeStack.length > 1) {
        safeStack.shift();
        if (safeIndex > 0) safeIndex--;
        payload.index = safeIndex;
        payload.stack = safeStack;
        json = JSON.stringify(payload);
    }

    return json;
}

// ── Capa A: Restauración con validación estricta de coherencia ───────────────
function restore(hist, savedData, currentMd) {
    if (!hist) return false;
    if (!savedData) return false;

    var data = savedData;
    if (typeof savedData === "string") {
        try {
            data = JSON.parse(savedData);
        } catch (e) {
            return false;
        }
    }

    if (!data || !Array.isArray(data.stack) || data.stack.length === 0) {
        return false;
    }
    var idx = typeof data.index === "number" ? data.index : -1;
    if (idx < 0 || idx >= data.stack.length) {
        return false;
    }

    var savedActive = data.stack[idx];
    var savedMd = (savedActive && typeof savedActive === "object") ? savedActive.md : savedActive;

    // Validación estricta: solo se acepta si el markdown en el tope coincide
    // con el markdown actual del documento en disco. Si cambió externamente, se descarta.
    if (typeof currentMd === "string" && savedMd !== currentMd) {
        return false;
    }

    hist.stack = data.stack.slice();
    hist.index = idx;
    return true;
}

if (typeof module !== "undefined" && typeof exports !== "undefined") {
    module.exports = {
        MAX_HISTORY: MAX_HISTORY,
        MAX_BYTES: MAX_BYTES,
        createHistory: createHistory,
        pushState: pushState,
        canUndo: canUndo,
        canRedo: canRedo,
        undo: undo,
        redo: redo,
        serialize: serialize,
        restore: restore
    };
}
