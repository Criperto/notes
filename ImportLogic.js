.pragma library

// ImportLogic.js — Lógica pura de importación de archivos arrastrados o seleccionados.
// Decide qué hacer con cada URL, sin tocar disco ni QML.
// El ejecutor (NotesService) usa estas decisiones con Process argv y verifica.
// Testeable con node (tests/run.js).

var MAX_IMPORT_BYTES = 5 * 1024 * 1024;
var MAX_DOCX_IMPORT_BYTES = 50 * 1024 * 1024;
var MAX_PDF_IMPORT_BYTES = 100 * 1024 * 1024;

var CONVERTIBLE_CONFIG = {
    docx: { script: "docx-to-md.py", dep: "python-docx", maxBytes: 50 * 1024 * 1024 },
    pdf:  { script: "doc-to-md.py",  dep: "python-pymupdf", maxBytes: 100 * 1024 * 1024 },
    xlsx: { script: "doc-to-md.py",  dep: "python-openpyxl", maxBytes: 50 * 1024 * 1024 },
    odt:  { script: "doc-to-md.py",  dep: "", maxBytes: 50 * 1024 * 1024 },
    epub: { script: "doc-to-md.py",  dep: "", maxBytes: 50 * 1024 * 1024 },
    html: { script: "doc-to-md.py",  dep: "", maxBytes: 50 * 1024 * 1024 },
    htm:  { script: "doc-to-md.py",  dep: "", maxBytes: 50 * 1024 * 1024 },
    rtf:  { script: "doc-to-md.py",  dep: "", maxBytes: 50 * 1024 * 1024 },
    csv:  { script: "doc-to-md.py",  dep: "", maxBytes: 50 * 1024 * 1024 },
    tsv:  { script: "doc-to-md.py",  dep: "", maxBytes: 50 * 1024 * 1024 }
};

var CONVERTIBLE_EXTS = ["docx", "pdf", "xlsx", "odt", "epub", "html", "htm", "rtf", "csv", "tsv"];

// Decodifica una URL de drop ("file:///home/u/Mi%20nota%20ñ.md") a ruta local.
// Devuelve "" si no es un archivo local válido.
function decodeDropUrl(url) {
    if (url === undefined || url === null) return "";
    var s = (typeof url === "string") ? url : String(url);
    s = s.trim();
    if (s.startsWith("file://localhost/")) s = s.substring("file://localhost".length);
    else if (s.startsWith("file://")) s = s.substring("file://".length);
    else if (s.startsWith("/")) return (s.indexOf("\0") === -1) ? s : "";
    else return "";
    try {
        if (typeof decodeURIComponent === "function") s = decodeURIComponent(s);
    } catch (e) {
        return "";
    }
    if (s === "" || s.indexOf("\0") !== -1) return "";
    return s;
}

// Extensión en minúsculas del nombre base ("NOTA.MD" → "md", sin ext → "")
function getExtension(filePath) {
    if (!filePath || typeof filePath !== "string") return "";
    var base = filePath;
    var slash = Math.max(base.lastIndexOf("/"), base.lastIndexOf("\\"));
    if (slash !== -1) base = base.substring(slash + 1);
    var dot = base.lastIndexOf(".");
    if (dot <= 0 || dot === base.length - 1) return "";
    return base.substring(dot + 1).toLowerCase();
}

function isDocx(filePath) {
    return getExtension(filePath) === "docx";
}

function isConvertible(filePath) {
    var ext = getExtension(filePath);
    return Boolean(CONVERTIBLE_CONFIG[ext]);
}

function isImportable(filePath) {
    var ext = getExtension(filePath);
    return ext === "md" || ext === "txt" || Boolean(CONVERTIBLE_CONFIG[ext]);
}

function getDepForExt(ext) {
    if (!ext || typeof ext !== "string") return "";
    var cfg = CONVERTIBLE_CONFIG[ext.toLowerCase()];
    return cfg ? cfg.dep : "";
}

function getScriptForExt(ext) {
    if (!ext || typeof ext !== "string") return "doc-to-md.py";
    var cfg = CONVERTIBLE_CONFIG[ext.toLowerCase()];
    return cfg ? cfg.script : "doc-to-md.py";
}

function depsForItems(items) {
    var needed = [];
    var seen = {};
    var list = items || [];
    for (var i = 0; i < list.length; i++) {
        var item = list[i];
        var ext = (item && item.ext) ? item.ext : (item && item.localPath ? getExtension(item.localPath) : "");
        var dep = getDepForExt(ext);
        if (dep && !seen[dep]) {
            seen[dep] = true;
            needed.push(dep);
        }
    }
    return needed;
}

// Separa un array de URLs en notas normales (.md/.txt) y documentos convertibles (.docx, .pdf, .odt, etc.)
function partitionDroppedUrls(urls) {
    var normal = [];
    var convert = [];
    var docx = [];
    var list = urls || [];
    for (var i = 0; i < list.length; i++) {
        var raw = (list[i] && list[i].toString) ? list[i].toString() : String(list[i]);
        var local = decodeDropUrl(raw);
        if (!local) continue;
        var ext = getExtension(local);
        if (CONVERTIBLE_CONFIG[ext]) {
            var item = { url: list[i], localPath: local, ext: ext };
            convert.push(item);
            if (ext === "docx") docx.push(item);
        } else if (ext === "md" || ext === "txt") {
            normal.push(list[i]);
        }
    }
    return { normalUrls: normal, convertItems: convert, docxItems: docx };
}

function baseName(filePath) {
    if (!filePath || typeof filePath !== "string") return "";
    var slash = Math.max(filePath.lastIndexOf("/"), filePath.lastIndexOf("\\"));
    return slash !== -1 ? filePath.substring(slash + 1) : filePath;
}

// ¿La ruta ya está dentro de la carpeta de notas (o subcarpeta)?
function isInsideDir(filePath, dir) {
    if (!filePath || !dir) return false;
    var d = dir;
    while (d.length > 1 && (d.endsWith("/"))) d = d.substring(0, d.length - 1);
    return filePath === d || filePath.startsWith(d + "/");
}

// Nombre único estilo "nombre (2).md" sin pisar nada existente.
// existingLower: array de nombres existentes en minúsculas. Compara insensitive.
function uniqueFileName(desired, existingLower) {
    if (!desired) return "nota.md";
    var set = {};
    for (var i = 0; i < (existingLower || []).length; i++) set[String(existingLower[i]).toLowerCase()] = true;
    if (!set[String(desired).toLowerCase()]) return desired;
    var dot = desired.lastIndexOf(".");
    var stem = dot !== -1 ? desired.substring(0, dot) : desired;
    var ext = dot !== -1 ? desired.substring(dot) : "";
    var n = 2;
    while (set[(stem + " (" + n + ")" + ext).toLowerCase()]) n++;
    return stem + " (" + n + ")" + ext;
}

// Valida tamaño y tipo antes de importar. Recibe lo que reporta `stat`
// (con LC_ALL=C, %F da "regular file"). Devuelve {ok} o {ok:false, reason}.
function validateImport(fileKind, fileSize, ext) {
    if (fileKind !== "regular file" && fileKind !== "regular") return { ok: false, reason: "type" };
    if (typeof fileSize !== "number" || !(fileSize >= 0)) return { ok: false, reason: "size" };
    var cfg = ext ? CONVERTIBLE_CONFIG[ext.toLowerCase()] : null;
    var maxAllowed = cfg ? cfg.maxBytes : MAX_IMPORT_BYTES;
    if (fileSize > maxAllowed) return { ok: false, reason: "size" };
    return { ok: true };
}

// Cambia la extensión conservando el resto ("notas.txt" → "notas.md")
function replaceExtension(fileName, newExt) {
    if (!fileName || typeof fileName !== "string") return "";
    var dot = fileName.lastIndexOf(".");
    var stem = (dot > 0) ? fileName.substring(0, dot) : fileName;
    return stem + "." + newExt;
}

// Resume un lote: [{status}] donde status ∈ copied|moved|already|skipped|error
function summarizeImport(outcomes) {
    var s = { copied: 0, moved: 0, already: 0, skipped: 0, errors: 0, total: 0 };
    for (var i = 0; i < (outcomes || []).length; i++) {
        var st = outcomes[i] ? outcomes[i].status : "error";
        s.total++;
        if (st === "copied") s.copied++;
        else if (st === "moved") s.moved++;
        else if (st === "already") s.already++;
        else if (st === "skipped") s.skipped++;
        else s.errors++;
    }
    return s;
}

// Genera especificaciones de filtros para qs-helper file-picker
function getFilterSpecs(t) {
    var tr = (typeof t === "function") ? t : function(k, d) { return d; };
    var allExts = ["md", "txt", "docx", "pdf", "odt", "epub", "html", "htm", "rtf", "csv", "tsv", "xlsx"];
    var allGlob = "*." + allExts.join(":*.");
    var docGlob = "*.docx:*.pdf:*.odt:*.rtf:*.epub";
    var webGlob = "*.html:*.htm:*.csv:*.tsv:*.xlsx";
    var notesGlob = "*.md:*.txt";

    return [
        tr("notes.import.filter_all", "Todos los soportados") + ":" + allGlob,
        tr("notes.import.filter_docs", "Documentos") + ":" + docGlob,
        tr("notes.import.filter_web_data", "Web y planillas") + ":" + webGlob,
        tr("notes.import.filter_notes", "Notas de texto") + ":" + notesGlob,
        tr("notes.import.filter_any", "Todos los archivos") + ":*.*"
    ];
}
