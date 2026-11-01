.pragma library

// TableParser.js — Parser y serializador de tablas Markdown con soporte de alineación y edición matricial

function splitCells(line) {
    if (!line || typeof line !== "string") return [];
    var trimmed = line.trim();
    if (trimmed.startsWith("|")) trimmed = trimmed.substring(1);
    if (trimmed.endsWith("|")) trimmed = trimmed.substring(0, trimmed.length - 1);

    var cells = [];
    var current = "";
    for (var i = 0; i < trimmed.length; i++) {
        var c = trimmed[i];
        if (c === "|" && (i === 0 || trimmed[i - 1] !== "\\")) {
            cells.push(current.trim());
            current = "";
        } else {
            current += c;
        }
    }
    cells.push(current.trim());
    return cells;
}

function parseTable(raw) {
    if (!raw || typeof raw !== "string") {
        return { headers: [], aligns: [], rows: [] };
    }

    var lines = raw.split("\n").filter(function(l) { return l.trim().length > 0; });
    if (lines.length < 2) {
        return null;
    }

    var headers = splitCells(lines[0]);
    var delimCells = splitCells(lines[1]);
    if (headers.length === 0 || delimCells.length === 0) {
        return null;
    }

    var colCount = headers.length;
    var aligns = [];
    for (var c = 0; c < colCount; c++) {
        var d = (c < delimCells.length) ? delimCells[c].trim() : "---";
        if (d.startsWith(":") && d.endsWith(":")) {
            aligns.push("center");
        } else if (d.endsWith(":")) {
            aligns.push("right");
        } else if (d.startsWith(":")) {
            aligns.push("left");
        } else {
            aligns.push("none");
        }
    }

    var rows = [];
    for (var r = 2; r < lines.length; r++) {
        var rCells = splitCells(lines[r]);
        // Asegurar que tenga tantas celdas como columnas
        while (rCells.length < colCount) rCells.push("");
        if (rCells.length > colCount) rCells = rCells.slice(0, colCount);
        rows.push(rCells);
    }

    return {
        headers: headers,
        aligns: aligns,
        rows: rows,
        rawDelimLine: lines[1].trim()
    };
}

function _escapeCell(text) {
    if (!text && text !== 0) return "";
    var s = String(text).replace(/\r?\n/g, "<br>");
    return s.replace(/(^|[^\\])\|/g, "$1\\|");
}

function serializeTable(table) {
    if (!table || !table.headers || table.headers.length === 0) return "";
    var cols = table.headers.length;

    // Fila de encabezados con escape de pipes
    var safeHeaders = table.headers.map(_escapeCell);
    var out = "| " + safeHeaders.join(" | ") + " |\n";

    // Fila delimitadora: preservar la línea original si las columnas y alineaciones no cambiaron
    if (table.rawDelimLine && !table._alignsChanged) {
        out += table.rawDelimLine + "\n";
    } else {
        var delims = [];
        for (var c = 0; c < cols; c++) {
            var a = (table.aligns && table.aligns[c]) ? table.aligns[c] : "none";
            if (a === "center") delims.push(":---:");
            else if (a === "right") delims.push("---:");
            else if (a === "left") delims.push(":---");
            else delims.push("---");
        }
        out += "| " + delims.join(" | ") + " |\n";
    }

    // Filas de datos con escape de pipes
    for (var r = 0; r < table.rows.length; r++) {
        var safeRow = table.rows[r].map(_escapeCell);
        out += "| " + safeRow.join(" | ") + " |";
        if (r < table.rows.length - 1) out += "\n";
    }

    return out;
}

function addRow(table, index) {
    if (!table || !table.rows) return table;
    var cols = table.headers.length;
    var newRow = [];
    for (var i = 0; i < cols; i++) newRow.push("");
    var idx = (typeof index === "number" && index >= 0 && index <= table.rows.length) ? index : table.rows.length;
    table.rows.splice(idx, 0, newRow);
    return table;
}

function removeRow(table, index) {
    if (!table || !table.rows || table.rows.length <= 1) return table;
    var idx = (typeof index === "number" && index >= 0 && index < table.rows.length) ? index : table.rows.length - 1;
    table.rows.splice(idx, 1);
    return table;
}

function addCol(table, index, defaultHeader) {
    if (!table || !table.headers) return table;
    table.rawDelimLine = null;
    var idx = (typeof index === "number" && index >= 0 && index <= table.headers.length) ? index : table.headers.length;
    table.headers.splice(idx, 0, defaultHeader || "Columna");
    if (table.aligns) table.aligns.splice(idx, 0, "left");
    for (var r = 0; r < table.rows.length; r++) {
        table.rows[r].splice(idx, 0, "");
    }
    return table;
}

function removeCol(table, index) {
    if (!table || !table.headers || table.headers.length <= 1) return table;
    table.rawDelimLine = null;
    var idx = (typeof index === "number" && index >= 0 && index < table.headers.length) ? index : table.headers.length - 1;
    table.headers.splice(idx, 1);
    if (table.aligns) table.aligns.splice(idx, 1);
    for (var r = 0; r < table.rows.length; r++) {
        table.rows[r].splice(idx, 1);
    }
    return table;
}

function toggleColAlign(table, colIndex) {
    if (!table || !table.headers || colIndex < 0 || colIndex >= table.headers.length) return table;
    if (!table.aligns) {
        table.aligns = [];
        for (var i = 0; i < table.headers.length; i++) table.aligns.push("none");
    }
    table._alignsChanged = true;
    var current = table.aligns[colIndex] || "none";
    var next = "left";
    if (current === "left") next = "center";
    else if (current === "center") next = "right";
    else if (current === "right") next = "none";
    else next = "left";
    table.aligns[colIndex] = next;
    return table;
}
