.pragma library

// History.js — Pila de historial de snapshots para undo/redo a nivel de documento
var MAX_HISTORY = 100;

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
