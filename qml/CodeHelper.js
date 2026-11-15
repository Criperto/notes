.pragma library

// CodeHelper.js — Utilidades puras para edición de código e inferencia de lenguaje

var _EXT_TO_LANG = {
    "lua": "lua",
    "py": "python",
    "pyw": "python",
    "rs": "rust",
    "js": "javascript",
    "mjs": "javascript",
    "cjs": "javascript",
    "jsx": "javascript",
    "ts": "typescript",
    "tsx": "typescript",
    "qml": "qml",
    "sh": "bash",
    "bash": "bash",
    "zsh": "bash",
    "fish": "bash",
    "json": "json",
    "jsonc": "json",
    "toml": "toml",
    "yaml": "yaml",
    "yml": "yaml",
    "conf": "ini",
    "ini": "ini",
    "cfg": "ini",
    "desktop": "ini",
    "service": "ini",
    "env": "ini",
    "css": "css",
    "scss": "css",
    "html": "html",
    "htm": "html",
    "xml": "html",
    "svg": "html",
    "c": "c",
    "h": "c",
    "cpp": "cpp",
    "cc": "cpp",
    "cxx": "cpp",
    "hpp": "cpp",
    "sql": "sql",
    "md": "markdown",
    "markdown": "markdown",
    "mdx": "markdown"
};

function inferLangFromFileName(fileName) {
    if (!fileName || typeof fileName !== "string") return "";
    var clean = fileName.trim();
    var slash = clean.lastIndexOf("/");
    var base = slash !== -1 ? clean.substring(slash + 1) : clean;
    var low = base.toLowerCase();
    if (low === ".bashrc" || low === ".zshrc" || low === ".profile") return "bash";
    if (low === ".env") return "ini";
    var dot = low.lastIndexOf(".");
    if (dot === -1 || dot === low.length - 1) return "";
    var ext = low.substring(dot + 1);
    return _EXT_TO_LANG[ext] || "";
}

function lineCountOf(text) {
    if (!text || typeof text !== "string" || text.length === 0) return 1;
    var count = 1;
    for (var i = 0; i < text.length; i++) {
        if (text.charCodeAt(i) === 10) count++;
    }
    return count;
}

function currentLineNumber(text, cursorPos) {
    if (!text || typeof text !== "string" || cursorPos <= 0) return 1;
    var limit = Math.min(text.length, cursorPos);
    var line = 1;
    for (var i = 0; i < limit; i++) {
        if (text.charCodeAt(i) === 10) line++;
    }
    return line;
}

// Calcula la inserción al presionar Enter/Return conservando e incrementando indentación.
// Devuelve { insertText: string, cursorOffset: number, splitPair: bool }.
function computeEnterIndent(text, cursorPos, tabWidth) {
    var src = (typeof text === "string") ? text : "";
    var pos = Math.max(0, Math.min(src.length, typeof cursorPos === "number" ? cursorPos : src.length));
    var width = (typeof tabWidth === "number" && tabWidth > 0) ? tabWidth : 4;
    var unit = "";
    for (var u = 0; u < width; u++) unit += " ";

    var lineStart = src.lastIndexOf("\n", pos - 1) + 1;
    var lineBefore = src.substring(lineStart, pos);
    var indentMatch = lineBefore.match(/^[ \t]*/);
    var baseIndent = indentMatch ? indentMatch[0] : "";

    var trimmedBefore = lineBefore.trimEnd ? lineBefore.trimEnd() : lineBefore.replace(/[ \t]+$/, "");
    var lastCh = trimmedBefore.length > 0 ? trimmedBefore[trimmedBefore.length - 1] : "";

    // Detectar expansión entre pares {} () []
    var rest = src.substring(pos);
    var nextMatch = rest.match(/^[ \t]*([}\])])/);
    var nextCh = nextMatch ? nextMatch[1] : "";
    var isPairSplit = (lastCh === "{" && nextCh === "}") ||
                      (lastCh === "(" && nextCh === ")") ||
                      (lastCh === "[" && nextCh === "]");

    if (isPairSplit) {
        var inner = "\n" + baseIndent + unit;
        return {
            insertText: inner + "\n" + baseIndent,
            cursorOffset: inner.length,
            splitPair: true
        };
    }

    var shouldIncrease = (lastCh === "{" || lastCh === "(" || lastCh === "[" || lastCh === ":");
    if (!shouldIncrease && /\b(then|do|else|repeat)\s*$/.test(trimmedBefore)) {
        shouldIncrease = true;
    }

    var nextIndent = baseIndent + (shouldIncrease ? unit : "");
    var inserted = "\n" + nextIndent;
    return {
        insertText: inserted,
        cursorOffset: inserted.length,
        splitPair: false
    };
}

// Aplica Tab o Shift+Tab sobre cursor o selección multilínea.
function applyTabIndent(text, selStart, selEnd, isShiftTab, tabWidth) {
    var src = (typeof text === "string") ? text : "";
    var s = Math.max(0, Math.min(src.length, typeof selStart === "number" ? selStart : 0));
    var e = Math.max(s, Math.min(src.length, typeof selEnd === "number" ? selEnd : s));
    var width = (typeof tabWidth === "number" && tabWidth > 0) ? tabWidth : 4;
    var unit = "";
    for (var u = 0; u < width; u++) unit += " ";

    if (s === e && !isShiftTab) {
        return {
            text: src.substring(0, s) + unit + src.substring(s),
            newSelStart: s + width,
            newSelEnd: s + width,
            rangeStart: s,
            rangeEnd: s,
            replacement: unit
        };
    }

    var lineStart = src.lastIndexOf("\n", s - 1) + 1;
    var lineEnd = src.indexOf("\n", e);
    if (lineEnd === -1) lineEnd = src.length;
    var sub = src.substring(lineStart, lineEnd);
    var lines = sub.split("\n");
    var replaced = "";
    var newS = s;
    var newE = e;

    if (!isShiftTab) {
        replaced = lines.map(function(l) { return unit + l; }).join("\n");
        newS = s + width;
        newE = e + (replaced.length - sub.length);
    } else {
        var totalCut = 0;
        var firstCut = 0;
        replaced = lines.map(function(l, idx) {
            var cut = 0;
            if (l.startsWith("\t")) {
                cut = 1;
            } else {
                while (cut < width && cut < l.length && l[cut] === " ") cut++;
            }
            totalCut += cut;
            if (idx === 0) firstCut = cut;
            return l.substring(cut);
        }).join("\n");
        newS = Math.max(lineStart, s - firstCut);
        newE = Math.max(newS, e - totalCut);
    }

    return {
        text: src.substring(0, lineStart) + replaced + src.substring(lineEnd),
        newSelStart: newS,
        newSelEnd: newE,
        rangeStart: lineStart,
        rangeEnd: lineEnd,
        replacement: replaced
    };
}
