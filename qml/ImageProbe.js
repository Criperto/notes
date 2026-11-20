.pragma library

// ImageProbe.js — Resolución y clasificación de rutas de imagen.
// Lógica pura y testeable: dado el `src` crudo del Markdown y la carpeta base
// de la nota, decide si es remota o local y a qué ruta de disco corresponde.
// La EXISTENCIA la resuelve NotesService (un solo find en lote + stat) y la
// expone por caché; acá no se toca disco.

function normalizePath(pathStr) {
    if (!pathStr || typeof pathStr !== "string") return "";
    var s = pathStr.trim();
    if (s === "") return "";
    var isAbs = s.startsWith("/");
    var rawParts = s.split("/");
    var stack = [];
    for (var i = 0; i < rawParts.length; i++) {
        var seg = rawParts[i];
        if (seg === "" || seg === ".") continue;
        if (seg === "..") {
            if (stack.length > 0 && stack[stack.length - 1] !== "..") {
                stack.pop();
            } else if (!isAbs) {
                stack.push("..");
            }
            continue;
        }
        stack.push(seg);
    }
    return (isAbs ? "/" : "") + stack.join("/");
}

function isRemote(src) {
    if (!src || typeof src !== "string") return false;
    return /^(https?|data):/i.test(src.trim());
}

// Ruta de disco correspondiente al src, o "" si es remota o irresoluble.
// - http(s) / data: → "" (remota o embebida, no pre-verificable)
// - file://... → ruta normalizada y decodificada (tolerante a %XX rotos)
// - /absoluta → normalizada (resuelve . / .. / // y recorta ?query/#hash)
// - relativa → normalizada sobre baseFolder ("" si no hay base)
function resolveLocal(baseFolder, src) {
    if (!src || typeof src !== "string") return "";
    var s = src.trim();
    if (s === "") return "";
    if (isRemote(s)) return "";
    // Recortar sufijos ?query / #fragment típicos de enlaces Markdown
    s = s.replace(/[?#].*$/, "");
    if (s === "") return "";
    var low = s.toLowerCase();
    if (low.startsWith("file://")) {
        var p = s.substring("file://".length);
        if (p.toLowerCase().startsWith("localhost/")) p = p.substring("localhost/".length);
        try {
            if (typeof decodeURIComponent === "function") p = decodeURIComponent(p);
        } catch (e) { /* ruta cruda igual sirve para comparar */ }
        return normalizePath(p);
    }
    if (s.indexOf("%") !== -1) {
        try {
            if (typeof decodeURIComponent === "function") s = decodeURIComponent(s);
        } catch (e) {}
    }
    if (s.startsWith("/")) return normalizePath(s);
    var base = (baseFolder && typeof baseFolder === "string") ? baseFolder.trim() : "";
    if (base === "") return "";
    if (base.endsWith("/")) base = base.substring(0, base.length - 1);
    return normalizePath(base + "/" + s);
}

// Convierte una fuente de imagen (remota, data URI, file:// o local relativa/absoluta)
// en una URL lista para Image/AnimatedImage de Qt Quick.
function toFileUrl(baseFolder, src) {
    if (!src || typeof src !== "string") return "";
    var s = src.trim();
    if (s === "") return "";
    if (/^(?:https?:\/\/|data:)/i.test(s)) return s;
    var local = resolveLocal(baseFolder || "", s);
    if (local !== "") return "file://" + encodeURI(local);
    if (s.toLowerCase().startsWith("file://")) return s;
    return "";
}
