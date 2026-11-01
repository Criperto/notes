.pragma library

// SortLogic.js — Comparador de notas para la grilla (F17).
// Fijadas primero; luego según modo; SIEMPRE con desempate estable:
// modificación descendente y, si empatan, título ascendente. Así dos notas
// nunca abiertas (lastOpened "") no quedan en orden arbitrario.

function _str(v) {
    return (v === undefined || v === null) ? "" : String(v);
}

function _canon(s) {
    return (s || "").toString().trim().toLowerCase();
}

function openedOf(note, openedMap) {
    if (!note) return "";
    var k = _canon(note.slug || note.id);
    if (openedMap && openedMap[k]) return openedMap[k];
    return note.lastOpened || "";
}

function modifiedOf(note) {
    if (!note) return "";
    return note.fileModified || note.modified || note.created || "";
}

function compareNotes(a, b, sortBy, openedMap) {
    var pa = !!(a && a.pinned);
    var pb = !!(b && b.pinned);
    if (pa !== pb) return pa ? -1 : 1;
    var r = 0;
    if (sortBy === "title") {
        r = _canon(a.title).localeCompare(_canon(b.title));
    } else if (sortBy === "created") {
        r = _str(b.created || b.fileModified || "").localeCompare(_str(a.created || a.fileModified || ""));
    } else if (sortBy === "lastOpened") {
        r = _str(openedOf(b, openedMap)).localeCompare(_str(openedOf(a, openedMap)));
    } else { // "modified" y cualquier valor desconocido
        r = _str(modifiedOf(b)).localeCompare(_str(modifiedOf(a)));
    }
    if (r !== 0) return r < 0 ? -1 : 1;
    r = _str(modifiedOf(b)).localeCompare(_str(modifiedOf(a)));
    if (r !== 0) return r < 0 ? -1 : 1;
    r = _canon(a.title).localeCompare(_canon(b.title));
    return r < 0 ? -1 : (r > 0 ? 1 : 0);
}

// Orden estable siguiente en el ciclo del botón (F17):
// Apertura → Modificación → Creación → Título → Apertura.
function nextSort(current) {
    if (current === "lastOpened") return "modified";
    if (current === "modified") return "created";
    if (current === "created") return "title";
    return "lastOpened";
}
