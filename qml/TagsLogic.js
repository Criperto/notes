.pragma library

// TagsLogic.js — Normalización, deduplicación y sugerencias de etiquetas.
// Lógica pura y testeable. Las etiquetas viven en el front matter (tags: [...]),
// acá solo se decide forma y coincidencia, nunca se toca disco.

function _stripAccents(str) {
    if (!str || typeof str !== "string") return "";
    var out = "";
    for (var i = 0; i < str.length; i++) {
        var c = str[i];
        var n = (typeof c.normalize === "function") ? c.normalize("NFD") : c;
        out += (n.length > 0 ? n[0] : c);
    }
    return out;
}

function normKey(s) {
    return _stripAccents(s || "").toLowerCase();
}

// Normaliza una etiqueta cruda: recorta, quita # iniciales, espacios internos
// a "-", sin comas/corchetes/comillas (rompen el front matter), máx. 40.
function normalizeTag(s) {
    if (!s || typeof s !== "string") return "";
    var t = s.trim().replace(/^#+/, "").trim();
    t = t.replace(/\s+/g, "-");
    t = t.replace(/[,[\]"]/g, "");
    t = t.replace(/^-+|-+$/g, "").trim();
    if (t.length > 40) t = t.substring(0, 40).replace(/-+$/, "");
    return t;
}

function sameTag(a, b) {
    if (!a || !b) return false;
    return normKey(a) === normKey(b);
}

// Quita duplicados (insensible a mayúsculas/acentos), conserva el primero.
function dedupe(tags) {
    var out = [];
    var seen = {};
    var list = tags || [];
    for (var i = 0; i < list.length; i++) {
        var t = list[i];
        if (!t || typeof t !== "string") continue;
        var k = normKey(t);
        if (!k || seen[k]) continue;
        seen[k] = true;
        out.push(t);
    }
    return out;
}

// Agrega si normaliza a algo no vacío y no duplicado. No muta el original.
function addTag(tags, raw) {
    var clean = normalizeTag(raw);
    if (clean === "") return { tags: (tags || []).slice(), added: "", changed: false };
    var list = dedupe(tags || []);
    for (var i = 0; i < list.length; i++) {
        if (sameTag(list[i], clean)) return { tags: list, added: "", changed: false };
    }
    list.push(clean);
    return { tags: list, added: clean, changed: true };
}

// Quita por coincidencia insensible. No muta el original.
function removeTag(tags, target) {
    var list = tags || [];
    var out = [];
    var removed = false;
    for (var i = 0; i < list.length; i++) {
        if (!removed && sameTag(list[i], target)) {
            removed = true;
            continue;
        }
        out.push(list[i]);
    }
    return { tags: out, removed: removed };
}

// Sugiere desde todas las conocidas: prefijo primero, luego contenido.
// Excluye las ya puestas. Límite 6.
function suggest(allTags, query, current, limit) {
    var max = (typeof limit === "number" && limit > 0) ? limit : 6;
    var q = normKey((query || "").replace(/^#+/, "").trim());
    if (q === "") return [];
    var cur = current || [];
    var pre = [];
    var mid = [];
    var seen = {};
    var list = allTags || [];
    for (var i = 0; i < list.length; i++) {
        var t = list[i];
        if (!t || typeof t !== "string" || seen[normKey(t)]) continue;
        seen[normKey(t)] = true;
        var k = normKey(t);
        var excluded = false;
        for (var c = 0; c < cur.length; c++) {
            if (sameTag(cur[c], t)) { excluded = true; break; }
        }
        if (excluded) continue;
        if (k.indexOf(q) === 0) pre.push(t);
        else if (k.indexOf(q) !== -1) mid.push(t);
    }
    return pre.concat(mid).slice(0, max);
}
