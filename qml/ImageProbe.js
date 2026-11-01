.pragma library

// ImageProbe.js — Resolución y clasificación de rutas de imagen.
// Lógica pura y testeable: dado el `src` crudo del Markdown y la carpeta base
// de la nota, decide si es remota o local y a qué ruta de disco corresponde.
// La EXISTENCIA la resuelve NotesService (un solo find en lote + stat) y la
// expone por caché; acá no se toca disco.

function isRemote(src) {
    if (!src || typeof src !== "string") return false;
    return /^(https?):\/\//i.test(src.trim());
}

// Ruta de disco correspondiente al src, o "" si es remota o irresoluble.
// - http(s) → "" (remota, no pre-verificable)
// - file://... → ruta decodificada (tolerante a %XX rotos)
// - /absoluta → tal cual
// - relativa → baseFolder + "/" + src ("" si no hay base)
function resolveLocal(baseFolder, src) {
    if (!src || typeof src !== "string") return "";
    var s = src.trim();
    if (s === "") return "";
    if (isRemote(s)) return "";
    var low = s.toLowerCase();
    if (low.startsWith("file://")) {
        var p = s.substring("file://".length);
        if (p.toLowerCase().startsWith("localhost/")) p = p.substring("localhost/".length);
        try {
            if (typeof decodeURIComponent === "function") p = decodeURIComponent(p);
        } catch (e) { /* ruta cruda igual sirve para comparar */ }
        return p;
    }
    if (s.startsWith("/")) return s;
    var base = (baseFolder && typeof baseFolder === "string") ? baseFolder : "";
    if (base === "") return "";
    if (base.endsWith("/")) base = base.substring(0, base.length - 1);
    return base + "/" + s;
}
