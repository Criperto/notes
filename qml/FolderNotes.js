.pragma library

// FolderNotes.js — Identidad de notas por clave (slug + extensión).
// La clave interna es `slug + NUL + ext` (el NUL no puede aparecer en nombres
// de archivo). NUNCA se concatena una clave donde se espera un slug o una
// ruta: para eso está slugOfKey(). Funciones puras y testeadas; NotesService
// delega en ellas con wrappers del mismo nombre (cero cambios en llamadas).
// F19 extiende este archivo (isFolderNotePath, slugForPath, ...).
// F19: regla de nota-carpeta y utilidades de promoción.

// ¿La ruta relativa es de nota-carpeta? "<Nombre>/<Nombre>.(md|txt)" con la
// misma base sin distinguir mayúsculas, en cualquier profundidad ("a/b/b.md"
// sí; "Foo/Bar.md" no, es subcarpeta contenedora).
function isFolderNotePath(rel) {
    if (!rel || typeof rel !== "string") return false;
    var parts = rel.split("/");
    if (parts.length < 2) return false;
    var dirBase = parts[parts.length - 2];
    var file = parts[parts.length - 1];
    var m = file.match(/^(.+)\.(md|txt)$/i);
    if (!m) return false;
    return dirBase.toLowerCase() === m[1].toLowerCase();
}

// Slug para una ruta: nota-carpeta → solo su carpeta (estable al promover);
// resto → ruta sin extensión, como siempre.
function slugForPath(rel) {
    var s = (rel || "").toString();
    if (isFolderNotePath(s)) {
        var dir = s.substring(0, s.lastIndexOf("/"));
        return canonSlug(dir);
    }
    return canonSlug(s.replace(/\.(md|txt)$/i, ""));
}

// Directorio padre relativo ("a/b/c.md" → "a/b", "x.md" → "").
function parentDir(rel) {
    var s = (rel || "").toString();
    var i = s.lastIndexOf("/");
    return i === -1 ? "" : s.substring(0, i);
}

// Carpeta propia para promover ("Foo.md" → "Foo", "sub/n.md" → "sub/n").
function folderPathFor(rel) {
    var s = (rel || "").toString();
    var m = s.match(/^(.*\/)?(.+)\.(md|txt)$/i);
    if (!m) return s;
    return (m[1] || "") + m[2];
}

// Nombre de carpeta único ("Foo", "Foo_2"...). occupiedLower: minúsculas.
function uniqueFolderName(desired, occupiedLower) {
    var base = (desired || "").toString();
    if (!base) return "nota";
    var set = {};
    for (var i = 0; i < (occupiedLower || []).length; i++) set[String(occupiedLower[i]).toLowerCase()] = true;
    if (!set[base.toLowerCase()]) return base;
    var n = 2;
    while (set[(base + "_" + n).toLowerCase()]) n++;
    return base + "_" + n;
}

// Reescribe enlaces a assets movidos: [{from, to}] sobre ocurrencias `](from`
// (cubre `](url)` y `](url "título")`). Devuelve {body, moved}.
function rewriteAssetLinks(body, pairs) {
    var out = (body !== undefined && body !== null) ? body : "";
    var moved = 0;
    var list = pairs || [];
    for (var i = 0; i < list.length; i++) {
        var from = list[i] && list[i].from;
        var to = list[i] && list[i].to;
        if (!from || !to || from === to) continue;
        var needle = "](" + from;
        if (out.indexOf(needle) === -1) continue;
        out = out.split(needle).join("](" + to);
        moved++;
    }
    return { body: out, moved: moved };
}

function keySep() {
    return String.fromCharCode(0);
}

function canonSlug(s) {
    if (!s) return "";
    return String(s).trim().toLowerCase();
}

function canonExt(fileName) {
    return /\.txt$/i.test(fileName || "") ? "txt" : "md";
}

function dictKey(slugCanon, ext) {
    return (slugCanon || "") + keySep() + ((ext === "txt") ? "txt" : "md");
}

// Clave para un fileName tal como lo reporta el descubrimiento (%P de find:
// ruta relativa con subcarpetas). Usa slugForPath: nota-carpeta conserva slug.
function keyForFileName(fileName) {
    var fn = (fileName || "").toString();
    return dictKey(slugForPath(fn), canonExt(fn));
}

function isKey(s) {
    return !!s && String(s).indexOf(keySep()) !== -1;
}

function slugOfKey(key) {
    var k = key || "";
    var i = k.indexOf(keySep());
    return i === -1 ? k : k.substring(0, i);
}

function extOfKey(key) {
    var k = key || "";
    var i = k.indexOf(keySep());
    return (i !== -1 && k.substring(i + 1) === "txt") ? "txt" : "md";
}

// Aserción defensiva: ninguna ruta pasada a un Process puede contener
// NUL (execv la truncaría en silencio). Devuelve la primera ruta mala o "".
function firstNulPath(paths) {
    var list = paths || [];
    for (var i = 0; i < list.length; i++) {
        var p = list[i];
        if (typeof p === "string" && p.indexOf(keySep()) !== -1) return p;
    }
    return "";
}
