pragma Singleton
import QtQuick
import Notas
import Qt.labs.folderlistmodel 2.16
import "."
import "MarkdownParser.js" as MD
import "ImportLogic.js" as ImportLogic
import "ImageProbe.js" as ImageProbe
import "FolderNotes.js" as FolderNotes
import "SortLogic.js" as SortLogic

Item {
    id: root
    visible: false

    // ── Estado reactivo público ───────────────────────────────────────────
    property var  notes: []
    property bool loading: false
    property string searchQuery: ""
    property var  activeNote: null
    property bool isEditing: false
    property bool _rebuildPending: false
    property bool debug: false

    onIsEditingChanged: {
        if (!isEditing && _rebuildPending) {
            _rebuildPending = false;
            _rebuildNotes();
        }
    }

    function log() {
        if (root.debug) {
            console.log.apply(console, arguments);
        }
    }

    readonly property string notesDir: NotesConfig.resolveNotesDir()

    // Estado de guardado serial: "saved" | "saving" | "dirty" | "error" | "conflict"
    property string saveState: "saved"
    property string saveErrorMessage: ""

    // Cola serial de escrituras pendientes a disco
    property var _saveQueue: []
    property bool _isWriting: false
    property var _currentWriteItem: null
    property int _writeSequenceToken: 0
    property int _currentWriteToken: 0

    // Cola serial de eliminación a papelera
    property var _trashQueue: []
    property bool _isTrashing: false

    // Hash de contenido en disco para detectar cambios externos
    property var _lastContentHash: ({})

    // Mapa de claves en proceso de escritura en disco o eco reciente: { [key]: timestampExpiry }
    property var _writingKeys: ({})

    // Mapa de última apertura de notas para ordenamiento dinámico: { [slug]: timestampISO }
    property var lastOpenedMap: ({})

    // ── Preferencias y persistencia de estado ────────────────────────
    readonly property string statePath: Quickshell.env("HOME") + "/.local/state/qs-notes/state.json"
    property string sortBy: "lastOpened" // "lastOpened" (defecto, F17), "modified", "created", "title"
    property string activeTagFilter: ""

    onSortByChanged: {
        root._persistState();
        rebuildDebounce.restart();
    }

    FileView {
        id: stateFile
        path: root.statePath
        preload: true
        watchChanges: false
        onLoaded: {
            try {
                var s = JSON.parse(text());
                if (typeof s.sortBy === "string") root.sortBy = s.sortBy;
                if (s.lastOpenedMap && typeof s.lastOpenedMap === "object") {
                    root.lastOpenedMap = s.lastOpenedMap;
                }
            } catch (e) { /* ignorar parse error */ }
        }
    }

    Timer {
        id: stateDebounceTimer
        interval: 400
        repeat: false
        onTriggered: root._persistState()
    }

    // Escritor nativo del estado: sin sh -c ni escapado manual.
    // El directorio se crea una vez al iniciar (stateDirProc).
    FileView {
        id: stateWriter
        path: root.statePath
        atomicWrites: true
        printErrors: true
    }

    Process {
        id: stateDirProc
        running: false
        Component.onDestruction: { running = false; }
    }

    function _persistState() {
        var payload = JSON.stringify({
            sortBy: root.sortBy,
            lastOpenedMap: root.lastOpenedMap || {}
        });
        stateWriter.setText(payload);
    }

    // Mapa de borradores recién creados sin tocar: { [slug]: { title, content } }
    property var _drafts: ({})

    // Mapa de escrituras fallidas pendientes de reintento: { [slug]: writeItem }
    property var _failedItems: ({})

    // Mapa de escrituras diferidas por renombrado concurrente: { [slug]: { slug, data, callback } }
    property var _deferredSaves: ({})

    Timer {
        id: writeRetryTimer
        interval: 600
        repeat: false
        onTriggered: root.retryFailedWrites()
    }

    function _isWritingSlug(slug) {
        var s = slug || "";
        if (!s || !root._writingKeys) return false;
        var expiry = root._writingKeys[s];
        if (!expiry) return false;
        if (Date.now() < expiry) return true;
        delete root._writingKeys[s];
        return false;
    }

    function _markWritingSlug(slug, durationMs) {
        var s = slug || "";
        if (!s) return;
        var dur = durationMs || 1500;
        var now = Date.now();
        var map = Object.assign({}, root._writingKeys);
        map[s] = now + dur;
        root._writingKeys = map;
        if (root.debug) console.log("[StateDebug:Echo] Marcado slug en escritura activa:", s, "expira en +" + dur + "ms");
    }

    // Claves en proceso de eliminación para evitar guardar notas que se están borrando
    property var _deletingKeys: ({})

    // Lote de eliminaciones pendientes con ventana de deshacer acumulativa
    property var _pendingDeletions: ({})
    readonly property int pendingDeleteCount: Object.keys(_pendingDeletions).length

    Timer {
        id: deleteBatchTimer
        interval: 3500
        repeat: false
        onTriggered: root.commitPendingDeletions()
    }

    signal notesRefreshed()
    // F26 (FLIP): se emite justo ANTES de reasignar `root.notes` en _rebuildNotes(),
    // para que la grilla fotografíe el "antes" (First). notesRefreshed sale después (Last).
    signal notesAboutToChange()
    signal noteSaved(var note)
    signal noteDeleted(string slug)
    signal noteImported(var note)
    signal imagePasted(string markdownTag)
    signal externalConflictDetected(string slug, string diskContent)
    signal importFinished(var summary)

    // Diccionario interno de notas indexadas por slug canónico para O(1) lookups
    property var _notesDict: ({})

    // ── Identidad de archivo con extensión ──────────────────────────
    // foo.md y foo.txt comparten slug pero son notas distintas: la clave interna
    // del dict y de los mapas (hashes, escrituras, borrados) es slug + ext.
    // Lógica pura en FolderNotes.js (testeada); acá wrappers del mismo nombre
    // para no tocar las ~40 llamadas. slugOfKey es pública para la UI.
    function _canonSlug(s) {
        return FolderNotes.canonSlug(s);
    }
    function _canonExt(fileName) {
        return FolderNotes.canonExt(fileName);
    }
    function _keySep() {
        return FolderNotes.keySep();
    }
    function _dictKey(slugCanon, ext) {
        return FolderNotes.dictKey(slugCanon, ext);
    }
    function _keyForFileName(fileName) {
        return FolderNotes.keyForFileName(fileName);
    }
    function _slugOfKey(key) {
        return FolderNotes.slugOfKey(key);
    }
    function slugOfKey(key) {
        return FolderNotes.slugOfKey(key);
    }
    function _extOfKey(key) {
        return FolderNotes.extOfKey(key);
    }

    // Garantiza devolver siempre el directorio padre de la nota y nunca la ruta al archivo .md/.txt
    function resolveNoteBaseDir(note) {
        if (!note) return root.notesDir;
        var bf = (note.baseFolder || "").trim();
        if (bf !== "" && !/\.(md|txt)$/i.test(bf)) {
            return bf;
        }
        var fp = (note.filePath || "").trim();
        if (fp !== "") {
            var slash = fp.lastIndexOf("/");
            if (slash > 0) return fp.substring(0, slash);
        }
        return root.notesDir;
    }

    // Aserción defensiva: ninguna ruta a un Process con NUL.
    // Devuelve true si es seguro spawnear; si no, loguea y NO spawnea.
    // Pública para que el modal la use en sus mkdir/cp.
    function pathsOk(label, argv) {
        var bad = FolderNotes.firstNulPath(argv);
        if (bad !== "") {
            console.error("[NotesService] NUL en argv de " + label + ", no se ejecuta");
            return false;
        }
        return true;
    }

    // Clave con resolución de colisiones (F19): el primero en el dict conserva
    // la clave plana; el recién llegado con mismo slug usa ruta completa + log.
    // (La app nunca genera colisiones: creación/importación usan nombres únicos.)
    function _noteKeyForFile(fileName, filePath) {
        var key = root._keyForFileName(fileName);
        var existing = root._notesDict[key];
        if (!existing || existing.filePath === filePath) return key;
        root.log("[NotesService] Colisión de slug para:", fileName, "- usando ruta completa");
        var fn = (fileName || "").toString();
        return root._dictKey(root._canonSlug(fn.replace(/\.(md|txt)$/i, "")), root._canonExt(fn));
    }

    // Resuelve clave de guardado: si ya es clave compuesta se usa tal cual; si es
    // slug plano se prefiere la variante existente (.md primero, luego .txt).
    function _resolveSaveKey(slug) {
        if (!slug) return "";
        if ((slug || "").indexOf(root._keySep()) !== -1) return slug;
        var canon = root._canonSlug(slug);
        var mdKey = root._dictKey(canon, "md");
        if (root._notesDict[mdKey]) return mdKey;
        var txtKey = root._dictKey(canon, "txt");
        if (root._notesDict[txtKey]) return txtKey;
        return mdKey;
    }

    // ¿La nota activa es la de esta clave? Compara por key (slug+ext); si la
    // activa aún no tiene key (objeto a medio construir), cae a comparar slug.
    function _activeIsKey(key, slug) {
        if (!root.activeNote) return false;
        if (root.activeNote.key) return root.activeNote.key === key;
        return root._canonSlug(root.activeNote.slug) === slug || root._canonSlug(root.activeNote.id) === slug;
    }

    // ── Colección de todos los tags únicos normalizados ─────────────
    readonly property var allTags: {
        var set = {};
        for (var i = 0; i < root.notes.length; i++) {
            var n = root.notes[i];
            if (n && Array.isArray(n.tags)) {
                for (var j = 0; j < n.tags.length; j++) {
                    var t = String(n.tags[j]).trim();
                    if (t) set[t] = (set[t] || 0) + 1;
                }
            }
        }
        var tags = Object.keys(set);
        tags.sort();
        return tags;
    }

    // ── Notas filtradas por búsqueda reactiva normalizada y tags ────
    readonly property var filteredNotes: {
        var q = (root.searchQuery || "").trim();
        var tagFilter = (root.activeTagFilter || "").trim().toLowerCase();

        var list = root.notes;
        if (tagFilter !== "") {
            list = list.filter(note => {
                if (!note || !Array.isArray(note.tags)) return false;
                return note.tags.some(t => String(t).trim().toLowerCase() === tagFilter);
            });
        }

        if (q === "") return list;

        var tokens = q.split(/\s+/).filter(t => t.length > 0);
        return list.filter(note => {
            var blob = note.searchBlob || MD.normalizeSearchText((note.title || "") + " " + (note.subtitle || "") + " " + (note.body || ""));
            var noteTags = Array.isArray(note.tags) ? note.tags.map(t => String(t).toLowerCase()) : [];

            return tokens.every(tok => {
                if (tok.startsWith("#") && tok.length > 1) {
                    var targetTag = tok.substring(1).toLowerCase();
                    return noteTags.indexOf(targetTag) !== -1;
                }
                var normalizedTok = MD.normalizeSearchText(tok);
                return blob.indexOf(normalizedTok) !== -1;
            });
        });
    }

    // ── Creación garantizada de directorio ────────────────────────────────
    Process {
        id: ensureDirProc
        command: ["mkdir", "-p", root.notesDir]
        running: false
        onExited: {
            if (folderModel.folder !== "file://" + root.notesDir) {
                folderModel.folder = "file://" + root.notesDir;
            }
            if (!fileScannerProc.running) {
                fileScannerProc.running = true;
            }
        }
        Component.onDestruction: { running = false; }
    }

    // ── Modelo nativo de sistema de archivos para vigilancia de carpeta ───
    FolderListModel {
        id: folderModel
        folder: "file://" + root.notesDir
        nameFilters: ["*.md", "*.txt"]
        showDirs: true // F19: que count cambie al aparecer/desaparecer carpetas
        showDotAndDotDot: false
        sortField: FolderListModel.Time
        sortReversed: true

        onStatusChanged: {
            if (status === FolderListModel.Loading) {
                root.loading = true;
            } else if (status === FolderListModel.Ready) {
                root.loading = false;
                scanDebounceTimer.restart();
            }
        }

        onCountChanged: {
            scanDebounceTimer.restart();
        }
    }

    Timer {
        id: scanDebounceTimer
        interval: 150
        repeat: false
        onTriggered: {
            if (!fileScannerProc.running && root.notesDir) {
                fileScannerProc.command = ["find", root.notesDir, "-type", "f", "(", "-name", "*.md", "-o", "-name", "*.txt", ")", "!", "-path", "*/.*/*", "-printf", "%P\t%p\t%T@\n"];
                fileScannerProc.running = true;
            }
        }
    }

    // ── Modelo de archivos descubiertos recursivamente (incluye subcarpetas) ─
    ListModel {
        id: filesModel
    }

    property var _discoveredFilesList: []

    Process {
        id: fileScannerProc
        command: ["find", root.notesDir, "-type", "f", "(", "-name", "*.md", "-o", "-name", "*.txt", ")", "!", "-path", "*/.*/*", "-printf", "%P\t%p\t%T@\n"]
        running: false

        stdout: SplitParser {
            onRead: (line) => {
                var l = line.trim();
                if (!l) return;
                var parts = l.split("\t");
                if (parts.length >= 2) {
                    var fRel = parts[0];
                    var fPath = parts[1];
                    var fSecs = parts.length >= 3 ? parseFloat(parts[2]) : Date.now() / 1000;
                    root._discoveredFilesList.push({
                        fileName: fRel,
                        filePath: fPath,
                        fileModified: new Date(fSecs * 1000)
                    });
                }
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                // No reconciliar con un scan fallido: conservar lo conocido.
                // Un wipe acá vaciaba la grilla en silencio.
                console.warn("[NotesService] find de notas falló con código:", exitCode, "dir:", root.notesDir);
                root._discoveredFilesList = [];
                return;
            }
            root._reconcileFilesModel();
        }
        Component.onDestruction: { running = false; }
    }

    property var _cachedImageDimensions: ({})

    // Proceso de indexación nativa ultrarrápida vía Rust qs-helper (<5ms)
    Process {
        id: qsIndexProc
        property string outJson: ""
        command: [
            Quickshell.shellDir.toString().replace("file://", "") + "/bin/qs-helper",
            "notes",
            "index",
            root.notesDir
        ]
        running: false
        stdout: SplitParser {
            splitMarker: ""
            onRead: chunk => {
                qsIndexProc.outJson += chunk;
            }
        }
        onExited: exitCode => {
            var raw = qsIndexProc.outJson;
            qsIndexProc.outJson = "";
            if (exitCode === 0 && raw.length > 0) {
                try {
                    var data = JSON.parse(raw);
                    if (data && data.ok) {
                        root._applyNotesIndex(data);
                        return;
                    }
                } catch (e) {
                    console.warn("[NotesService] Error parseando JSON de qs-helper index:", e);
                }
            }
            // Fallback a find tradicional si qs-helper no estuviese disponible
            if (!fileScannerProc.running && root.notesDir) {
                fileScannerProc.running = true;
            }
        }
        Component.onDestruction: { running = false; }
    }

    function _applyNotesIndex(data) {
        if (!data || !data.notes) return;
        var incomingNotes = data.notes;
        var incomingKeys = {};
        for (var i = 0; i < incomingNotes.length; i++) {
            var n = incomingNotes[i];
            var key = n.key;
            incomingKeys[key] = true;
            if (root._deletingKeys && root._deletingKeys[key]) continue;

            var existing = root._notesDict[key];
            if (existing) {
                if (root.activeNote && (root.activeNote.key === key || root.activeNote.slug === n.slug) && root.isEditing) {
                    existing.title = n.title;
                    existing.pinned = n.pinned;
                    existing.tags = n.tags;
                    existing.previewImages = n.previewImages;
                } else {
                    var curBody = existing.body;
                    Object.assign(existing, n);
                    if (curBody !== undefined && curBody !== null) existing.body = curBody;
                }
            } else {
                root._notesDict[key] = n;
            }
        }

        var allKeys = Object.keys(root._notesDict);
        for (var j = 0; j < allKeys.length; j++) {
            var k = allKeys[j];
            if (!incomingKeys[k] && !root._pendingSave && (!root.activeNote || root.activeNote.key !== k)) {
                delete root._notesDict[k];
                delete root._lastContentHash[k];
                if (root._deletingKeys) delete root._deletingKeys[k];
            }
        }

        if (data.images) {
            root._cachedImageDimensions = Object.assign(root._cachedImageDimensions || {}, data.images);
        }

        root._rebuildNotes();
    }

    function _reconcileFilesModel() {
        var discovered = root._discoveredFilesList;
        root._discoveredFilesList = [];
        root.log("[NotesService] Scan en", root.notesDir, ": descubiertos", discovered.length, "archivos");

        var discoveredPaths = {};
        for (var i = 0; i < discovered.length; i++) {
            discoveredPaths[discovered[i].filePath] = discovered[i];
        }

        // 1. Eliminar archivos que ya no existen en disco
        for (var j = filesModel.count - 1; j >= 0; j--) {
            var item = filesModel.get(j);
            if (!discoveredPaths[item.filePath]) {
                var delKey = root._keyForFileName(item.fileName);
                delete root._notesDict[delKey];
                delete root._lastContentHash[delKey];
                delete root._deletingKeys[delKey];
                filesModel.remove(j);
            }
        }

        // 2. Agregar archivos nuevos que no estaban en filesModel
        var currentPaths = {};
        for (var k = 0; k < filesModel.count; k++) {
            currentPaths[filesModel.get(k).filePath] = true;
        }

        for (var p in discoveredPaths) {
            if (!currentPaths[p]) {
                filesModel.append(discoveredPaths[p]);
            }
        }

        // Si cambió la cantidad de archivos, re-probar imágenes (llegaron o se
        // fueron archivos que pueden referenciar assets nuevos)
        if (filesModel.count !== root._lastProbeCount) {
            root._lastProbeCount = filesModel.count;
            imageProbeDebounce.restart();
        }

        rebuildDebounce.restart();
    }

    // ── Instanciador reactivo de FileView por cada archivo descubierto ─────
    Instantiator {
        id: notesInstantiator
        model: filesModel

        delegate: QtObject {
            id: noteDelegate
            required property string fileName
            required property string filePath
            required property date fileModified

            property var reloadDebounce: Timer {
                interval: 80
                repeat: false
                onTriggered: {
                    if (root.debug) console.log("[StateDebug:External] Ejecutando reload() en FileView para:", noteDelegate.fileName);
                    noteFv.reload();
                }
            }

            property var noteFv: FileView {
                path: noteDelegate.filePath
                preload: true
                watchChanges: true
                printErrors: false

                onLoaded: {
                    var lkey = root._keyForFileName(noteDelegate.fileName);
                    if (root._isWritingSlug(lkey)) {
                        if (root.debug) console.log("[StateDebug:Echo] onLoaded ignorado por escritura interna activa para:", lkey);
                        return;
                    }
                    var content = text();
                    if (root.debug) console.log("[StateDebug:FileView] onLoaded procesando contenido para:", lkey, "bytes:", content ? content.length : 0);
                    root._onNoteContentLoaded(noteDelegate.fileName, noteDelegate.filePath, false, noteDelegate.fileModified, content);
                }

                onFileChanged: {
                    var fkey = root._keyForFileName(noteDelegate.fileName);
                    if (root._isWritingSlug(fkey)) {
                        if (root.debug) console.log("[StateDebug:Echo] onFileChanged ignorado (eco de guardado propio) para:", fkey);
                        return;
                    }
                    if (root.debug) console.log("[StateDebug:External] onFileChanged detectado para:", fkey, "- programando reload()");
                    noteDelegate.reloadDebounce.restart();
                }
            }

            Component.onDestruction: {
                root._onNoteRemoved(fileName, filePath);
            }
        }
    }

    // ── Lector / Escritor atómico serial de archivos ───────────────
    FileView {
        id: noteWriter
        atomicWrites: true
        printErrors: true

        onSaved: {
            root._onWriterSaved(root._currentWriteToken);
        }

        onSaveFailed: error => {
            root._onWriterSaveFailed(error, root._currentWriteToken);
        }
    }

    Timer {
        id: writeWatchdogTimer
        interval: 10000
        repeat: false
        onTriggered: {
            if (root._isWriting && root._currentWriteItem) {
                var failedPath = root._currentWriteItem.targetPath;
                console.warn("[NotesService] Watchdog de escritura activado tras 10000ms para:", failedPath);
                root._onWriterSaveFailed("Tiempo de espera agotado al escribir en disco (timeout)", root._currentWriteToken);
            }
        }
    }

    property var _renameQueue: []

    // Proceso seguro de renombrado atómico con Process
    Process {
        id: renameProc
        property string pendingOldSlug: ""
        property string pendingNewSlug: ""
        property string pendingNewTitle: ""
        property var pendingCallback: null
        property string pendingStage: "file" // "file" | "folder1" | "folder2" | "rollback"
        property string pendingDirOld: ""
        property string pendingDirNew: ""
        property string pendingInnerOld: ""
        property string pendingInnerNew: ""
        property string pendingNewRel: ""

        onExited: exitCode => {
            var stage = renameProc.pendingStage || "file";
            if (stage !== "file") {
                root._onFolderRenameDone(exitCode, stage);
                return;
            }
            var oldKey = renameProc.pendingOldSlug;
            var newKey = renameProc.pendingNewSlug;
            var oldS = root._slugOfKey(oldKey);
            var newS = root._slugOfKey(newKey);
            var ext = root._extOfKey(oldKey);
            var newT = renameProc.pendingNewTitle;
            var cb = renameProc.pendingCallback;
            renameProc.pendingOldSlug = "";
            renameProc.pendingNewSlug = "";
            renameProc.pendingNewTitle = "";
            renameProc.pendingCallback = null;
            renameProc.pendingStage = "";
            renameProc.pendingDirOld = "";
            renameProc.pendingDirNew = "";
            renameProc.pendingInnerOld = "";
            renameProc.pendingInnerNew = "";
            renameProc.pendingNewRel = "";

            if (exitCode === 0) {
                root.log("[NotesService - renameNote] Renombrado exitoso:", oldKey, "->", newKey);
                var existing = root._notesDict[oldKey];
                if (existing) {
                    delete root._notesDict[oldKey];
                    delete root._lastContentHash[oldKey];
                    existing.id = newS;
                    existing.slug = newS;
                    existing.key = newKey;
                    var slash = existing.filePath ? existing.filePath.lastIndexOf("/") : -1;
                    var dir = slash !== -1 ? existing.filePath.substring(0, slash) : root.notesDir;
                    var baseFname = (newS.indexOf("/") !== -1 ? newS.substring(newS.lastIndexOf("/") + 1) : newS) + "." + ext;
                    // fileName relativa (conserva subcarpeta si la hay, F19)
                    var dirRel = (dir.indexOf(root.notesDir + "/") === 0) ? dir.substring(root.notesDir.length + 1) : "";
                    existing.fileName = dirRel === "" ? baseFname : (dirRel + "/" + baseFname);
                    existing.filePath = dir + "/" + baseFname;
                    if (newT) existing.title = newT;
                    root._notesDict[newKey] = existing;
                    root.filesVersion++;
                }
                if (root._activeIsKey(oldKey, oldS)) {
                    if (existing) root.activeNote = existing;
                }
                if (!fileScannerProc.running) {
                    fileScannerProc.running = true;
                }
                root._rebuildNotes();
                if (typeof cb === "function") cb(newKey, true);
            } else {
                console.warn("[NotesService - renameNote] Error al renombrar con mv código:", exitCode);
                if (typeof cb === "function") cb(oldKey, false);
            }

            root._afterRenameSettled(oldKey, newKey, exitCode);
        }

        Component.onDestruction: { running = false; }
    }

    // Cola de difusos: reencola el siguiente renombrado y reubica guardados
    // diferidos por renombrado concurrente. Compartido por renombre de archivo
    // y de carpeta (F19).
    function _afterRenameSettled(oldKey, newKey, exitCode) {
        var defItem = (root._deferredSaves && (root._deferredSaves[oldKey] || root._deferredSaves[newKey]));
        if (defItem) {
            var defSavesCopy = Object.assign({}, root._deferredSaves);
            delete defSavesCopy[oldKey];
            delete defSavesCopy[newKey];
            root._deferredSaves = defSavesCopy;
            var destKey = (exitCode === 0) ? newKey : oldKey;
            root.queueSave(destKey, defItem.data, defItem.callback);
        }

        if (root._renameQueue && root._renameQueue.length > 0) {
            var nextRename = root._renameQueue.shift();
            root.renameNote(nextRename.oldSlug, nextRename.newTitle, nextRename.callback, nextRename.extHint);
        }
    }

    // Proceso seguro de eliminación a papelera (cola serial con gio trash y fallback)
    Process {
        id: trashProc
        property string pendingSlug: ""
        property string pendingPath: ""

        onExited: exitCode => {
            var tkey = trashProc.pendingSlug;
            var path = trashProc.pendingPath;
            trashProc.pendingSlug = "";
            trashProc.pendingPath = "";

            if (exitCode === 0) {
                root.log("[NotesService - deleteNote] gio trash exitoso para:", tkey);
                root._finalizeDeletion(tkey);
                root._isTrashing = false;
                root._processTrashQueue();
            } else {
                root.log("[NotesService - deleteNote] gio trash falló, usando fallback local a .trash/");
                var ts = Date.now();
                var safeBase = root._slugOfKey(tkey).replace(/\//g, "_");
                var trashDir = root.notesDir + "/.trash";
                var fallbackDest = trashDir + "/" + safeBase + "_" + ts + "." + root._extOfKey(tkey);
                fallbackTrashProc.pendingSlug = tkey;
                var fbArgs = ["bash", "-c", 'mkdir -p "$1" && mv -n -- "$2" "$3"', "_", trashDir, path, fallbackDest];
                if (root.pathsOk("fallbackTrash", fbArgs)) {
                    fallbackTrashProc.command = fbArgs;
                    fallbackTrashProc.running = true;
                } else {
                    console.error("[NotesService - deleteNote] pathsOk falló para fallbackTrash");
                    delete root._deletingKeys[tkey];
                    root._rebuildNotes();
                    root._isTrashing = false;
                    root._processTrashQueue();
                }
            }
        }
        Component.onDestruction: { running = false; }
    }

    Process {
        id: fallbackTrashProc
        property string pendingSlug: ""
        onExited: exitCode => {
            var fkey = fallbackTrashProc.pendingSlug;
            fallbackTrashProc.pendingSlug = "";
            if (exitCode === 0) {
                root._finalizeDeletion(fkey);
            } else {
                console.error("[NotesService] Falló el borrado de respaldo de la nota:", fkey);
                delete root._deletingKeys[fkey];
                root._rebuildNotes();
            }
            root._isTrashing = false;
            root._processTrashQueue();
        }
        Component.onDestruction: { running = false; }
    }

    // Cierre diferido del pegado (ver pasteImgProc.onExited).
    Timer {
        id: pasteFinishTimer
        interval: 150
        repeat: false
        onTriggered: pasteImgProc._finish(pasteImgProc.pendingExitCode)
    }

    // ── Subproceso directo de captura de imagen del portapapeles ──────────
    Process {
        id: pasteImgProc
        property var pendingCallback: null
        property string pendingBase: ""
        property string pendingKey: ""
        property string savedRelTag: ""
        running: false

        stdout: SplitParser {
            onRead: (line) => {
                var l = line.trim();
                console.log("[PasteImg] stdout: '" + l + "'");
                if (l !== "") {
                    pasteImgProc.savedRelTag = l;
                }
            }
        }

        // El stdout puede llegar DESPUÉS de onExited (la imagen se guardaba pero se
        // reportaba "no hay imagen"). Se difiere el cierre para que se vacíe el pipe.
        property int pendingExitCode: -1
        stderr: SplitParser {
            onRead: (line) => console.log("[PasteImg] stderr: " + line)
        }
        onExited: exitCode => {
            console.log("[PasteImg] proceso terminó: exitCode=" + exitCode + " tag='" + pasteImgProc.savedRelTag + "'");
            pasteImgProc.pendingExitCode = exitCode;
            if (exitCode === 0 && pasteImgProc.savedRelTag === "") pasteFinishTimer.restart();
            else pasteImgProc._finish(exitCode);
        }
        function _finish(exitCode) {
            var tag = pasteImgProc.savedRelTag;
            console.log("[PasteImg] _finish: exitCode=" + exitCode + " tag='" + tag + "' tieneCallback=" + (typeof pasteImgProc.pendingCallback === "function"));
            var pkey = pasteImgProc.pendingKey;
            if (exitCode === 0 && tag !== "") {
                if (pasteImgProc.pendingBase !== "") {
                    root.registerImagePath(pasteImgProc.pendingBase + "/" + tag);
                }
                pasteImgProc.pendingBase = "";
                pasteImgProc.pendingKey = "";
                root.imagePasted(tag);
                if (typeof pasteImgProc.pendingCallback === "function") {
                    pasteImgProc.pendingCallback(tag, null, pkey);
                    pasteImgProc.pendingCallback = null;
                }
            } else {
                pasteImgProc.pendingBase = "";
                pasteImgProc.pendingKey = "";
                root.log("[NotesService] No se encontró imagen en portapapeles o error (wl-paste código " + exitCode + ")");
                if (typeof pasteImgProc.pendingCallback === "function") {
                    pasteImgProc.pendingCallback(null, "no_image");
                    pasteImgProc.pendingCallback = null;
                }
            }
            pasteImgProc.savedRelTag = "";
        }

        Component.onDestruction: {
            running = false;
        }
    }

    function _contentHash(str) {
        if (!str) return "0";
        if (typeof Qt !== "undefined" && typeof Qt.md5 === "function") {
            return Qt.md5(str);
        }
        var h1 = 0xdeadbeef, h2 = 0x41c6ce57;
        for (var i = 0; i < str.length; i++) {
            var ch = str.charCodeAt(i);
            h1 = Math.imul(h1 ^ ch, 2654435761);
            h2 = Math.imul(h2 ^ ch, 1597334677);
        }
        h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
        h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);
        return (4294967296 * (2097151 & h2) + (h1 >>> 0)).toString(16);
    }

    // ── Manejo interno de eventos de archivo ────────────────────────
    function _onNoteContentLoaded(fileName, filePath, fileIsDir, fileModified, content) {
        if (!fileName) return;
        var key = root._noteKeyForFile(fileName, filePath);
        var slug = root._slugOfKey(key);
        if (root._deletingKeys[key]) return;

        var contentHash = _contentHash(content);
        var lastKnownHash = root._lastContentHash[key];

        if (root.debug) console.log("[StateDebug:ContentLoaded] key:", key, "hash:", contentHash, "lastKnown:", lastKnownHash);

        // Si ya conocemos el hash y coincide con lo que ya guardamos, es eco y no hacemos nada
        if (lastKnownHash !== undefined && contentHash === lastKnownHash) {
            if (root.debug) console.log("[StateDebug:Echo] Hash idéntico al último guardado, ignorando recarga para:", key);
            return;
        }

        var parsed = MD.parseNote(fileName, filePath, false, content);
        parsed.slug = slug;
        parsed.id = slug;
        parsed.key = key;
        parsed.isFolderNote = FolderNotes.isFolderNotePath(fileName);
        parsed.baseFolder = root.resolveNoteBaseDir(parsed);
        if (fileModified) {
            var mIso = (fileModified instanceof Date) ? fileModified.toISOString().replace("T", " ").substring(0, 19) : (typeof fileModified === "string" ? fileModified : new Date(fileModified).toISOString().replace("T", " ").substring(0, 19));
            parsed.fileModified = mIso;
            if (!parsed.modified) {
                parsed.modified = mIso;
            }
        }
        root._notesDict[key] = parsed;
        root._lastContentHash[key] = contentHash;

        if (root._activeIsKey(key, slug)) {
            if (root.isEditing) {
                if (root.saveState === "dirty") {
                    if (root.debug) console.warn("[StateDebug:Conflict] Conflicto externo detectado en nota abierta con cambios locales:", slug);
                    root.saveState = "conflict";
                    root.externalConflictDetected(slug, content);
                } else {
                    if (root.debug) console.log("[StateDebug:External] Actualizando activeNote con cambio externo (sin cambios locales):", slug);
                    root.activeNote = parsed;
                }
            } else {
                root.activeNote = parsed;
            }
        }

        rebuildDebounce.restart();
    }

    function _onNoteRemoved(fileName, filePath) {
        if (filePath) {
            // Por ruta exacta: si la clave ya apunta a otra ruta (nota recién
            // promovida/renombrada), no borrar nada (F19).
            for (var k in root._notesDict) {
                var e = root._notesDict[k];
                if (e && e.filePath === filePath) {
                    delete root._notesDict[k];
                }
            }
        } else if (fileName) {
            var key = (fileName.indexOf(root._keySep()) !== -1) ? fileName : root._keyForFileName(fileName);
            delete root._notesDict[key];
        }
        rebuildDebounce.restart();
    }

    Timer {
        id: rebuildDebounce
        interval: 35
        repeat: false
        onTriggered: {
            if (root.isEditing) {
                root._rebuildPending = true;
            } else {
                root._rebuildNotes();
            }
        }
    }

    function _rebuildNotes() {
        var arr = [];
        var seenKeys = {};
        for (var k in root._notesDict) {
            if (root._deletingKeys && root._deletingKeys[k]) continue;
            if (seenKeys[k]) continue;
            seenKeys[k] = true;
            arr.push(root._notesDict[k]);
        }

        // Ordenar con comparador puro y desempate estable (F17)
        arr.sort(function(a, b) {
            return SortLogic.compareNotes(a, b, root.sortBy, root.lastOpenedMap);
        });

        // F26: avisar ANTES de que los bindings reaccionen (First del FLIP).
        root.notesAboutToChange();
        root.notes = arr;
        root.loading = false;
        root.log("[NotesService] Notas en memoria:", arr.length, "dir:", root.notesDir);
        if (root.debug) console.log("[StateDebug:Grid] Lista de notas reconstruida en memoria (total:", arr.length, ")");
        // Abrir importación pendiente de un solo archivo: solo en grilla,
        // nunca sacando al usuario del editor
        if (root._pendingImportOpen !== "" && !root.isEditing) {
            var ps = root._pendingImportOpen;
            var found = root._notesDict[ps] || null;
            if (found) {
                root._pendingImportOpen = "";
                root.openNote(found);
            }
        }
        root.notesRefreshed();
    }

    // ── Métodos públicos CRUD ─────────────────────────────────────────────
    function refresh() {
        root.log("[NotesService - refresh] Refrescando directorio de notas:", root.notesDir);
        if (root.notesDir) {
            qsIndexProc.command = [
                Quickshell.shellDir.toString().replace("file://", "") + "/bin/qs-helper",
                "notes",
                "index",
                root.notesDir
            ];
            qsIndexProc.outJson = "";
            qsIndexProc.running = true;
        } else if (!fileScannerProc.running) {
            fileScannerProc.running = true;
        }
        imageProbeDebounce.restart();
    }

    // ── Generación de slug único garantizado sin colisiones ───────
    // La unicidad se chequea por clave (slug+ext): foo.md y foo.txt coexisten.
    function _uniqueSlug(base, excludeId, ext) {
        var slug = root._canonSlug(base) || "nota";
        var e = (ext === "txt") ? "txt" : "md";
        var excludeCanon = root._canonSlug(excludeId);
        if (root._notesDict[root._dictKey(slug, e)] && slug !== excludeCanon) {
            var counter = 2;
            while (root._notesDict[root._dictKey(slug + "_" + counter, e)] && (slug + "_" + counter) !== excludeCanon) {
                counter++;
            }
            return slug + "_" + counter;
        }
        return slug;
    }

    // ── Cola serial de escritura a disco ───────────────────────────
    function _purgeQueuedSavesFor(key) {
        if (!key) return;
        if (root._saveQueue && root._saveQueue.length > 0) {
            root._saveQueue = root._saveQueue.filter(function(it) {
                return it && it.key !== key && it.slug !== key;
            });
        }
        if (root._deferredSaves && root._deferredSaves[key]) {
            var defCopy = Object.assign({}, root._deferredSaves);
            delete defCopy[key];
            root._deferredSaves = defCopy;
        }
        root._dropFailedFor(key);
        if (root._pendingSlug === key) {
            root._pendingSave = null;
            root._pendingSlug = "";
            root._pendingCallback = null;
            saveDebounceTimer.stop();
        }
    }

    function _enqueueWrite(item) {
        if (!item) return;

        // Si ya hay una escritura pendiente para la misma nota en la cola, actualizarla con el contenido más reciente
        var found = false;
        for (var i = 0; i < root._saveQueue.length; i++) {
            if (root._saveQueue[i].key === item.key) {
                var prevCb = root._saveQueue[i].callback;
                var newCb = item.callback;
                root._saveQueue[i] = item;
                if (typeof prevCb === "function" || typeof newCb === "function") {
                    root._saveQueue[i].callback = function(saved) {
                        if (typeof prevCb === "function") prevCb(saved);
                        if (typeof newCb === "function") newCb(saved);
                    };
                }
                found = true;
                break;
            }
        }
        if (!found) {
            root._saveQueue.push(item);
        }

        if (!root._isWriting) {
            root._processNextWrite();
        }
    }

    function _processNextWrite() {
        if (root._saveQueue.length === 0) {
            root._isWriting = false;
            root._currentWriteItem = null;
            root._currentWriteToken = 0;
            writeWatchdogTimer.stop();
            if (root.saveState === "saving") {
                root.saveState = "saved";
                if (root.debug) console.log("[StateDebug:Save] saveState -> saved (cola de escrituras vacía)");
            }
            return;
        }

        root._isWriting = true;
        root.saveState = "saving";
        root._currentWriteItem = root._saveQueue.shift();
        root._writeSequenceToken++;
        var writeToken = root._writeSequenceToken;
        root._currentWriteToken = writeToken;
        root._currentWriteItem.token = writeToken;

        var targetSlug = root._currentWriteItem.slug;
        var targetKey = root._currentWriteItem.key || root._dictKey(root._canonSlug(targetSlug), root._canonExt(root._currentWriteItem.targetPath));

        if (root._deletingKeys && root._deletingKeys[targetKey]) {
            if (root.debug) console.log("[StateDebug:Save] Descartando escritura para nota en eliminación:", targetKey);
            var delCb = root._currentWriteItem.callback;
            if (typeof delCb === "function") {
                try { delCb(null); } catch (e) {}
            }
            root._currentWriteItem = null;
            root._currentWriteToken = 0;
            _processNextWrite();
            return;
        }

        var serialized = root._currentWriteItem.serialized;
        var targetPath = root._currentWriteItem.targetPath;

        root._markWritingSlug(targetKey, 2000);
        root._lastContentHash[targetKey] = _contentHash(serialized);

        if (root.debug) console.log("[StateDebug:Save] saveState -> saving (token: " + writeToken + ") para:", targetSlug, "ruta:", targetPath);

        // Si noteWriter ya tiene exactamente este archivo y contenido idéntico,
        // FileView no emitirá onSaved. Completamos inmediatamente para no bloquear la cola.
        if (noteWriter.path === targetPath && typeof noteWriter.text === "function" && noteWriter.text() === serialized) {
            if (root.debug) console.log("[StateDebug:Save] Contenido idéntico ya presente en FileView para:", targetPath, "- completando inmediato");
            Qt.callLater(() => {
                root._onWriterSaved(writeToken);
            });
            return;
        }

        writeWatchdogTimer.restart();
        noteWriter.path = targetPath;
        noteWriter.setText(serialized);
    }

    function _onWriterSaved(token) {
        if (token !== undefined && token !== 0 && token !== root._currentWriteToken) {
            root.log("[NotesService] Ignorando onSaved con token obsoleto:", token, "actual:", root._currentWriteToken);
            return;
        }
        writeWatchdogTimer.stop();
        var item = root._currentWriteItem;
        if (root.debug) console.log("[StateDebug:Save] Escritura completada exitosamente:", item ? item.targetPath : "");
        if (item) {
            var itemKey = item.key || root._dictKey(root._canonSlug(item.slug), root._canonExt(item.targetPath));
            root._markWritingSlug(itemKey, 1200);
            root._lastContentHash[itemKey] = _contentHash(item.serialized);
            if (root._failedItems && root._failedItems[itemKey]) {
                var failedCopy = Object.assign({}, root._failedItems);
                delete failedCopy[itemKey];
                root._failedItems = failedCopy;
            }
            try {
                if (typeof item.callback === "function") {
                    item.callback(item.parsed);
                }
                root.noteSaved(item.parsed);
            } catch (err) {
                console.error("[NotesService] Error en callback tras guardar:", err);
            }
        }
        var hasFailed = root._failedItems && Object.keys(root._failedItems).length > 0;
        if (root._saveQueue.length === 0) {
            if (!hasFailed) {
                root.saveState = "saved";
                root.saveErrorMessage = "";
                if (root.debug) console.log("[StateDebug:Save] saveState -> saved para slug:", item ? item.slug : "");
            } else {
                root.saveState = "error";
            }
        }
        _processNextWrite();
    }

    function _onWriterSaveFailed(error, token) {
        if (token !== undefined && token !== 0 && token !== root._currentWriteToken) {
            root.log("[NotesService] Ignorando onSaveFailed con token obsoleto:", token, "actual:", root._currentWriteToken);
            return;
        }
        writeWatchdogTimer.stop();
        var item = root._currentWriteItem;
        console.error("[StateDebug:Save] saveState -> error al guardar archivo en disco:", item ? item.targetPath : "", "error:", error);
        root.saveState = "error";
        root.saveErrorMessage = "Error al guardar: " + error;
        if (item) {
            var failKey = item.key || root._dictKey(root._canonSlug(item.slug), root._canonExt(item.targetPath));
            root._markWritingSlug(failKey, 100);
            item.retryCount = (item.retryCount || 0) + 1;
            var failedMap = Object.assign({}, root._failedItems);
            failedMap[failKey] = item;
            root._failedItems = failedMap;

            if (item.retryCount <= 3) {
                writeRetryTimer.interval = Math.min(2500, 500 * item.retryCount);
                writeRetryTimer.restart();
            }

            if (typeof item.callback === "function") {
                try {
                    item.callback(null, error);
                } catch (err) {
                    console.error("[NotesService] Error en callback tras fallo:", err);
                }
            }
        }
        _processNextWrite();
    }

    function retryFailedWrites() {
        if (!root._failedItems) return;
        var keys = Object.keys(root._failedItems);
        if (keys.length === 0) return;
        var failedCopy = Object.assign({}, root._failedItems);
        for (var i = 0; i < keys.length; i++) {
            var slug = keys[i];
            var it = failedCopy[slug];
            delete failedCopy[slug];
            if (it) {
                root._saveQueue.push(it);
            }
        }
        root._failedItems = failedCopy;
        _processNextWrite();
    }

    function saveNote(noteData, callback) {
        if (!noteData) return;
        if (noteData.readOnly) {
            root.log("[NotesService - saveNote] Ignorando guardado para nota en solo lectura:", noteData.filePath || noteData.title);
            if (typeof callback === "function") callback(false);
            return;
        }

        if (noteData.isExternal) {
            var extPath = noteData.filePath;
            if (!extPath) {
                if (typeof callback === "function") callback(false);
                return;
            }
            var extBody = (noteData.body !== undefined && noteData.body !== null) ? noteData.body : (noteData.content || "");
            var extSerialized = MD.serializeNote(noteData, extBody);
            var extKey = noteData.key || ("__external__:" + extPath);
            root._markWritingSlug(extKey, 2000);
            root._lastContentHash[extKey] = _contentHash(extSerialized);

            var extParsed = MD.parseNote(noteData.fileName || extPath.substring(extPath.lastIndexOf("/") + 1), extPath, false, extSerialized);
            extParsed.isExternal = true;
            extParsed.readOnly = false;
            extParsed.hadFrontmatter = noteData.hadFrontmatter;
            extParsed.key = extKey;
            extParsed.baseFolder = root.resolveNoteBaseDir(extParsed);

            if (root.activeNote && (root.activeNote.key === extKey || root.activeNote.filePath === extPath)) {
                Object.assign(root.activeNote, extParsed);
            }

            _enqueueWrite({
                slug: extKey,
                key: extKey,
                targetPath: extPath,
                serialized: extSerialized,
                parsed: extParsed,
                callback: function(savedParsed) {
                    if (typeof callback === "function") callback(savedParsed);
                }
            });
            return;
        }

        var slug = root._canonSlug(noteData.slug || noteData.id || "nota");

        var targetPath = noteData.filePath;
        var fileName = noteData.fileName;
        // La extensión se conserva: la del archivo existente o .md al crear
        var ext = root._canonExt(targetPath || fileName || (noteData.format === "txt" ? "x.txt" : "x.md"));
        var key = root._dictKey(slug, ext);

        if (root._deletingKeys[key]) {
            root.log("[NotesService - saveNote] Ignorando guardado para nota en eliminación:", key);
            return;
        }

        if (!targetPath) {
            slug = _uniqueSlug(slug, null, ext);
            key = root._dictKey(slug, ext);
            fileName = slug + "." + ext;
            targetPath = root.notesDir + "/" + fileName;
            noteData.slug = slug;
            noteData.id = slug;
            noteData.fileName = fileName;
            noteData.filePath = targetPath;
        }

        var isFolder = !!noteData.isFolderNote || FolderNotes.isFolderNotePath(fileName);
        var body = (noteData.body !== undefined && noteData.body !== null) ? noteData.body : (noteData.content || "");
        var serialized = MD.serializeNote(noteData, body);

        // targetPath es siempre un archivo (.md/.txt), nunca un directorio -> pasar false
        var parsed = MD.parseNote(fileName, targetPath, false, serialized);
        parsed.slug = slug;
        parsed.id = slug;
        parsed.key = key;
        parsed.isFolderNote = isFolder;
        parsed.baseFolder = root.resolveNoteBaseDir(parsed);
        var nowStr = new Date().toISOString().replace("T", " ").substring(0, 19);
        parsed.fileModified = nowStr;
        if (!parsed.modified) parsed.modified = nowStr;

        // Pre-registrar hash y marcar escritura activa para evitar ecos en FileView
        root._markWritingSlug(key, 2000);
        root._lastContentHash[key] = _contentHash(serialized);

        root._notesDict[key] = parsed;

        if (root._activeIsKey(key, slug)) {
            Object.assign(root.activeNote, parsed);
        }

        if (root.isEditing) {
            root._rebuildPending = true;
        } else {
            root._rebuildNotes();
        }

        if (root.debug) console.log("[StateDebug:Save] saveNote encolando:", targetPath, "hash:", root._lastContentHash[key]);
        _enqueueWrite({
            slug: slug,
            key: key,
            targetPath: targetPath,
            serialized: serialized,
            parsed: parsed,
            callback: function(savedParsed) {
                if (typeof callback === "function") callback(savedParsed);
            }
        });
    }

    // ── Guardado en cola en segundo plano con persistencia garantizada ────
    property var _pendingSave: null
    property string _pendingSlug: ""
    property var _pendingCallback: null

    Timer {
        id: saveDebounceTimer
        interval: 200
        repeat: false
        onTriggered: root.flushPendingSave()
    }

    function queueSave(slug, data, callback) {
        var key = root._resolveSaveKey(slug);
        var canon = root._slugOfKey(key);
        if (!canon || !data || root._deletingKeys[key]) return;
        if (renameProc.running && (renameProc.pendingOldSlug === key || renameProc.pendingNewSlug === key)) {
            var defCopy = Object.assign({}, root._deferredSaves);
            defCopy[key] = { slug: key, data: data, callback: callback };
            root._deferredSaves = defCopy;
            return;
        }
        var existing = root._notesDict[key] || root.activeNote || {};
        var updated = Object.assign({}, existing, data);
        updated.slug = canon;
        updated.id = canon;
        updated.key = key;

        if (data.title !== undefined) updated.title = data.title;
        if (data.subtitle !== undefined) updated.subtitle = data.subtitle;
        if (data.content !== undefined) {
            updated.content = data.content;
            updated.body = data.content;
            updated.preview = MD.getCleanPreview(data.content);
        }
        if (data.pinned !== undefined) updated.pinned = data.pinned;
        updated.modified = new Date().toISOString().replace("T", " ").substring(0, 19);

        if (root._drafts && root._drafts[key]) {
            var draftInfo = root._drafts[key];
            var curT = (data.title !== undefined ? data.title : updated.title || "").trim();
            var curB = (data.content !== undefined ? data.content : updated.content || "").trim();
            if (curT !== (draftInfo.title || "").trim() || curB !== (draftInfo.content || "").trim()) {
                root.clearDraft(key);
            }
        }

        root._notesDict[key] = updated;

        if (root._activeIsKey(key, canon)) {
            Object.assign(root.activeNote, updated);
        }

        if (root.saveState !== "saving") {
            root.saveState = "dirty";
        }
        if (root.debug) console.log("[StateDebug:Save] queueSave -> saveState dirty para:", key);

        root._pendingSlug = key;
        root._pendingSave = updated;
        if (typeof callback === "function") root._pendingCallback = callback;
        saveDebounceTimer.restart();
    }

    function flushPendingSave() {
        saveDebounceTimer.stop();
        if (!root._pendingSave || !root._pendingSlug) return;
        var toSave = root._pendingSave;
        var cb = root._pendingCallback;
        root._pendingSave = null;
        root._pendingSlug = "";
        root._pendingCallback = null;

        if (root.debug) console.log("[StateDebug:Save] flushPendingSave ejecutando saveNote para:", toSave.slug);
        root.saveNote(toSave, cb);
    }

    // oldSlug puede ser clave compuesta (slug+ext) o slug plano (+extHint).
    // Los callbacks siempre reciben CLAVES. La extensión se conserva.
    function renameNote(oldSlug, newTitle, callback, extHint) {
        if (!oldSlug || !newTitle) return;
        if (String(oldSlug).startsWith("__external__:") || (root.activeNote && root.activeNote.isExternal)) {
            root.log("[NotesService - renameNote] Bloqueando renombrado en disco de nota externa:", oldSlug);
            if (typeof callback === "function") callback(oldSlug, false);
            return;
        }
        var oldKey = ((oldSlug || "").indexOf(root._keySep()) !== -1) ? oldSlug : null;
        var oldCanon = oldKey ? root._slugOfKey(oldKey) : root._canonSlug(oldSlug);
        if (!oldCanon) {
            if (typeof callback === "function") callback(oldSlug, false);
            return;
        }
        var ext = oldKey ? root._extOfKey(oldKey) : (extHint === "txt" ? "txt" : "");
        if (!ext) {
            var mdK = root._dictKey(oldCanon, "md");
            var txK = root._dictKey(oldCanon, "txt");
            ext = (root._notesDict[txK] && !root._notesDict[mdK]) ? "txt" : "md";
        }
        oldKey = root._dictKey(oldCanon, ext);

        root.flushPendingSave();

        if (renameProc.running) {
            root._renameQueue.push({ oldSlug: oldKey, newTitle: newTitle, callback: callback, extHint: ext });
            return;
        }

        var subfolder = oldCanon.indexOf("/") !== -1 ? oldCanon.substring(0, oldCanon.lastIndexOf("/") + 1) : "";
        var baseTitle = newTitle.indexOf("/") !== -1 ? newTitle.substring(newTitle.lastIndexOf("/") + 1) : newTitle;
        var titleSlug = MD.slugify(baseTitle);
        var baseTargetSlug = _uniqueSlug(titleSlug, oldCanon.substring(subfolder.length), ext);
        var targetSlug = subfolder + baseTargetSlug;
        var targetKey = root._dictKey(targetSlug, ext);

        if (targetKey === oldKey) {
            var existingNote = root._notesDict[oldKey];
            if (existingNote) {
                existingNote.title = newTitle;
                // saveNote informa el objeto guardado; el contrato de renameNote
                // es (key, success): adaptar acá
                root.saveNote(existingNote, function() {
                    if (typeof callback === "function") callback(oldKey, true);
                });
            } else if (typeof callback === "function") {
                callback(oldKey, false);
            }
            return;
        }

        var existingNote = root._notesDict[oldKey];
        // Nota-carpeta: renombrar carpeta + interior con rollback (F19)
        if (existingNote && existingNote.isFolderNote) {
            root._renameFolder(oldKey, targetSlug, targetKey, ext, newTitle, callback);
            return;
        }
        var parentDir = root.notesDir;
        if (existingNote && existingNote.filePath) {
            var lastSlash = existingNote.filePath.lastIndexOf("/");
            if (lastSlash !== -1) {
                parentDir = existingNote.filePath.substring(0, lastSlash);
            }
        }
        var oldPath = (existingNote && existingNote.filePath) ? existingNote.filePath : (root.notesDir + "/" + oldCanon + "." + ext);
        var newFileName = (targetSlug.indexOf("/") !== -1 ? targetSlug.substring(targetSlug.lastIndexOf("/") + 1) : targetSlug) + "." + ext;
        var newPath = parentDir + "/" + newFileName;

        renameProc.pendingOldSlug = oldKey;
        renameProc.pendingNewSlug = targetKey;
        renameProc.pendingNewTitle = newTitle;
        renameProc.pendingCallback = callback;
        renameProc.pendingStage = "file";
        var rnArgs = ["sh", "-c", '[ ! -e "$2" ] && mv -- "$1" "$2"', "_", oldPath, newPath];
        var rnArgs = ["sh", "-c", '[ ! -e "$2" ] && mv -- "$1" "$2"', "_", oldPath, newPath];
        if (root.pathsOk("rename", rnArgs)) {
            renameProc.command = rnArgs;
            renameProc.running = true;
        }
    }

    // Renombre de nota-carpeta en dos pasos con rollback (F19): primero la
    // carpeta, después el interior. Los enlaces relativos no cambian.
    function _renameFolder(oldKey, targetSlug, targetKey, ext, newTitle, callback) {
        var cb = (typeof callback === "function") ? callback : null;
        var existingNote = root._notesDict[oldKey];
        if (!existingNote || !existingNote.fileName) {
            if (cb) cb(oldKey, false);
            return;
        }
        var oldRel = existingNote.fileName; // "Foo/Foo.md", relativa
        var oldDirRel = FolderNotes.parentDir(oldRel); // "Foo"
        var newBase = targetSlug.indexOf("/") !== -1 ? targetSlug.substring(targetSlug.lastIndexOf("/") + 1) : targetSlug;
        var newParent = FolderNotes.parentDir(oldDirRel);
        var newDirRel = newParent === "" ? newBase : (newParent + "/" + newBase);
        var newFileRel = newDirRel + "/" + newBase + "." + ext;
        var oldDirAbs = root.notesDir + "/" + oldDirRel;
        var newDirAbs = root.notesDir + "/" + newDirRel;
        var oldBase = oldRel.indexOf("/") !== -1 ? oldRel.substring(oldRel.lastIndexOf("/") + 1) : oldRel;
        var oldInnerAbs = oldDirAbs + "/" + oldBase;
        var newInnerAbs = newDirAbs + "/" + newBase + "." + ext;
        renameProc.pendingStage = "folder1";
        renameProc.pendingOldSlug = oldKey;
        renameProc.pendingNewSlug = targetKey;
        renameProc.pendingNewTitle = newTitle;
        renameProc.pendingCallback = cb;
        renameProc.pendingDirOld = oldDirAbs;
        renameProc.pendingDirNew = newDirAbs;
        renameProc.pendingInnerOld = oldInnerAbs;
        renameProc.pendingInnerNew = newInnerAbs;
        renameProc.pendingNewRel = newFileRel;
        var args1 = ["sh", "-c", '[ ! -e "$2" ] && mv -- "$1" "$2"', "_", oldDirAbs, newDirAbs];
        if (root.pathsOk("renameFolder1", args1)) {
            renameProc.command = args1;
            renameProc.running = true;
        } else if (cb) {
            cb(oldKey, false);
        }
    }

    function _onFolderRenameDone(exitCode, stage) {
        var oldKey = renameProc.pendingOldSlug;
        var newKey = renameProc.pendingNewSlug;
        var newT = renameProc.pendingNewTitle;
        var cb = renameProc.pendingCallback;
        if (stage === "folder1") {
            if (exitCode !== 0) {
                console.warn("[NotesService] Renombre de carpeta falló (dir), código:", exitCode);
                root._clearRenamePending();
                if (typeof cb === "function") cb(oldKey, false);
                root._afterRenameSettled(oldKey, newKey, exitCode);
                return;
            }
            var args2 = ["sh", "-c", '[ ! -e "$2" ] && mv -- "$1" "$2"', "_", renameProc.pendingInnerOld, renameProc.pendingInnerNew];
            renameProc.pendingStage = "folder2";
            if (root.pathsOk("renameFolder2", args2)) {
                renameProc.command = args2;
                renameProc.running = true;
            } else {
                root._rollbackFolderRename();
            }
            return;
        }
        if (stage === "folder2") {
            if (exitCode !== 0) {
                console.warn("[NotesService] Renombre de interior falló, revirtiendo carpeta");
                root._rollbackFolderRename();
                return;
            }
            var newS = root._slugOfKey(newKey);
            var existing = root._notesDict[oldKey];
            if (existing) {
                var h = root._lastContentHash[oldKey];
                delete root._notesDict[oldKey];
                delete root._lastContentHash[oldKey];
                root._dropFailedFor(oldKey);
                existing.id = newS;
                existing.slug = newS;
                existing.key = newKey;
                existing.fileName = renameProc.pendingNewRel;
                existing.filePath = renameProc.pendingInnerNew;
                existing.baseFolder = renameProc.pendingDirNew;
                existing.isFolderNote = true;
                if (newT) existing.title = newT;
                root._notesDict[newKey] = existing;
                if (h !== undefined) root._lastContentHash[newKey] = h;
            }
            if (root._activeIsKey(oldKey, root._slugOfKey(oldKey))) {
                if (existing) root.activeNote = existing;
            }
            root._clearRenamePending();
            root._markWritingSlug(newKey, 1200);
            root.filesVersion++;
            if (!fileScannerProc.running) fileScannerProc.running = true;
            root._rebuildNotes();
            if (typeof cb === "function") cb(newKey, true);
            root._afterRenameSettled(oldKey, newKey, 0);
            return;
        }
        // rollback terminado (cualquier código): informar fallo y redescubrir
        if (exitCode !== 0) {
            console.warn("[NotesService] Reversión de carpeta falló: revisar en disco");
        }
        root._clearRenamePending();
        if (typeof cb === "function") cb(oldKey, false);
        root._afterRenameSettled(oldKey, newKey, 1);
        if (!fileScannerProc.running) fileScannerProc.running = true;
        root._rebuildNotes();
    }

    function _rollbackFolderRename() {
        var rbArgs = ["sh", "-c", 'mv -- "$1" "$2"', "_", renameProc.pendingDirNew, renameProc.pendingDirOld];
        renameProc.pendingStage = "rollback";
        if (root.pathsOk("renameRollback", rbArgs)) {
            renameProc.command = rbArgs;
            renameProc.running = true;
        } else {
            var oldKey = renameProc.pendingOldSlug;
            var newKey = renameProc.pendingNewSlug;
            var cb = renameProc.pendingCallback;
            root._clearRenamePending();
            if (typeof cb === "function") cb(oldKey, false);
            root._afterRenameSettled(oldKey, newKey, 1);
        }
    }

    function _clearRenamePending() {
        renameProc.pendingOldSlug = "";
        renameProc.pendingNewSlug = "";
        renameProc.pendingNewTitle = "";
        renameProc.pendingCallback = null;
        renameProc.pendingStage = "";
        renameProc.pendingDirOld = "";
        renameProc.pendingDirNew = "";
        renameProc.pendingInnerOld = "";
        renameProc.pendingInnerNew = "";
        renameProc.pendingNewRel = "";
    }

    // Acepta clave compuesta (directo) o slug plano (.md primero, luego .txt).
    // Se mantiene por compatibilidad (wikilinks); el resto usa claves.
    function getNote(slug) {
        if (!slug) return null;
        if ((slug || "").indexOf(root._keySep()) !== -1) return root._notesDict[slug] || null;
        var cs = root._canonSlug(slug);
        return root._notesDict[root._dictKey(cs, "md")] || root._notesDict[root._dictKey(cs, "txt")] || null;
    }

    // Helper local de traducción: I18n y NotesConfig son singletons
    // importados; si falta uno es un error de instalación que debe verse.
    function _t(key, fallback) {
        return I18n.t(key, fallback);
    }

    function createNote(type, initialTitle) {
        var t = type || "text";
        var defaultTextTitle = root._t("notes.new_note", "Nueva nota");
        var title = initialTitle || defaultTextTitle;
        var subtitle = "";
        var content = "";

        var baseSlug = MD.slugify(title);
        var slug = _uniqueSlug(baseSlug, null, "md");
        var key = root._dictKey(root._canonSlug(slug), "md");
        if (root._deletingKeys[key]) delete root._deletingKeys[key];

        var targetFile = root.notesDir + "/" + slug + ".md";
        root.log("[NotesService - createNote] Creando nueva nota tipo:", t, "slug:", slug, "ruta:", targetFile);

        var nowStr = new Date().toISOString().replace("T", " ").substring(0, 19);
        var noteObj = {
            "id": slug,
            "slug": slug,
            "fileName": slug + ".md",
            "filePath": targetFile,
            "baseFolder": root.notesDir,
            "isFolderNote": false,
            "title": title,
            "subtitle": subtitle,
            "type": t,
            "pinned": false,
            "created": nowStr,
            "modified": nowStr,
            "content": content,
            "body": content
        };

        var draftsCopy = Object.assign({}, root._drafts);
        draftsCopy[key] = { title: title, content: content };
        root._drafts = draftsCopy;

        saveNote(noteObj, function(saved) {
            root.log("[NotesService - createNote] Nota persistida, abriendo editor para:", slug);
            openNote(saved || noteObj);
        });
    }

    function isUntouchedDraft(slug) {
        var key = ((slug || "").indexOf(root._keySep()) !== -1) ? slug : root._resolveSaveKey(slug);
        if (!key || !root._drafts || !root._drafts[key]) return false;
        var draft = root._drafts[key];
        var current = root.getNote(key);
        if (!current) return false;
        var curTitle = (current.title || "").trim();
        var curBody = (current.content || current.body || "").trim();
        var draftTitle = (draft.title || "").trim();
        var draftBody = (draft.content || "").trim();
        return (curTitle === draftTitle && curBody === draftBody);
    }

    function clearDraft(slug) {
        var key = ((slug || "").indexOf(root._keySep()) !== -1) ? slug : root._resolveSaveKey(slug);
        if (key && root._drafts && root._drafts[key]) {
            var draftsCopy = Object.assign({}, root._drafts);
            delete draftsCopy[key];
            root._drafts = draftsCopy;
        }
    }

    // slug puede ser clave compuesta o slug plano (se resuelve md primero)
    function deleteNote(slug) {
        if (!slug) return;
        if (String(slug).startsWith("__external__:") || (root.activeNote && root.activeNote.isExternal && (root.activeNote.slug === slug || root.activeNote.key === slug))) {
            root.log("[NotesService - deleteNote] Ignorando borrado para nota externa:", slug);
            return;
        }
        var key = root._resolveSaveKey(slug);
        var canon = root._slugOfKey(key);
        if (!canon) return;

        // Resolver la clave real: puede venir solo por filesModel (nota aún no
        // parseada) o con otra extensión que la resuelta por defecto
        var note = root._notesDict[key];
        if (!note) {
            for (var m = 0; m < filesModel.count; m++) {
                var it = filesModel.get(m);
                if (root._slugOfKey(root._keyForFileName(it.fileName)) === canon) {
                    key = root._keyForFileName(it.fileName);
                    note = { filePath: it.filePath, fileName: it.fileName, isFolderNote: false };
                    break;
                }
            }
        }
        if (!note) return;
        root.log("[NotesService - deleteNote] Solicitud para borrar nota:", key);

        root._deletingKeys[key] = true;
        root._purgeQueuedSavesFor(key);

        if (root._activeIsKey(key, canon)) {
            root.log("[NotesService - deleteNote] Cerrando editor antes de borrar");
            root.activeNote = null;
            root.isEditing = false;
        }

        delete root._notesDict[key];
        root._rebuildNotes();

        if (!note) {
            return;
        }

        var targetPath = note.isFolderNote ? note.baseFolder : note.filePath;
        root.log("[NotesService - deleteNote] Eliminando archivo a papelera:", targetPath);

        if (note.isFolderNote && targetPath) {
            // Salvaguarda F19: listar la carpeta; si hay más que lo propio
            // (el .md + assets/), solo va el .md. Nunca borrar de más.
            var ownBase = note.fileName && note.fileName.indexOf("/") !== -1
                ? note.fileName.substring(note.fileName.lastIndexOf("/") + 1) : note.fileName;
            dirListProc.pendingKey = key;
            dirListProc.pendingDir = targetPath;
            dirListProc.pendingFile = note.filePath;
            dirListProc.pendingOwnMd = ownBase || "";
            dirListProc.outText = "";
            var listArgs = ["find", targetPath, "-type", "f", "-printf", "%P\n"];
            if (root.pathsOk("dirList", listArgs)) {
                dirListProc.command = listArgs;
                dirListProc.running = true;
            } else {
                root._doTrashTarget(key, note.filePath || targetPath);
            }
            return;
        }
        root._doTrashTarget(key, targetPath);
    }

    function _doTrashTarget(key, targetPath) {
        if (!key || !targetPath) return;
        var q = root._trashQueue.slice();
        q.push({ key: key, targetPath: targetPath });
        root._trashQueue = q;
        root._processTrashQueue();
    }

    function _processTrashQueue() {
        if (root._isTrashing || !root._trashQueue || root._trashQueue.length === 0) return;
        var q = root._trashQueue.slice();
        var item = q.shift();
        root._trashQueue = q;
        if (!item || !item.key || !item.targetPath) {
            root._processTrashQueue();
            return;
        }
        if (!root._deletingKeys || !root._deletingKeys[item.key]) {
            root._processTrashQueue();
            return;
        }
        root._isTrashing = true;
        trashProc.pendingSlug = item.key;
        trashProc.pendingPath = item.targetPath;
        var trashArgs = ["gio", "trash", item.targetPath];
        if (root.pathsOk("trash", trashArgs)) {
            trashProc.command = trashArgs;
            trashProc.running = true;
        } else {
            console.error("[NotesService - deleteNote] pathsOk falló para:", item.targetPath);
            root._isTrashing = false;
            root._processTrashQueue();
        }
    }

    signal deletePartial(string slug)

    function _onDirListDone(exitCode) {
        var key = dirListProc.pendingKey;
        var dir = dirListProc.pendingDir;
        var ownFile = dirListProc.pendingFile;
        var ownMd = dirListProc.pendingOwnMd;
        dirListProc.pendingKey = "";
        dirListProc.pendingDir = "";
        dirListProc.pendingFile = "";
        dirListProc.pendingOwnMd = "";
        var ok = false;
        if (exitCode === 0 && dir) {
            ok = true;
            var lines = (dirListProc.outText || "").split("\n");
            for (var i = 0; i < lines.length; i++) {
                var rel = lines[i].trim();
                if (rel === "" || rel === ownMd) continue;
                if (rel.indexOf("assets/") === 0) continue;
                ok = false;
                break;
            }
        }
        if (ok) {
            root.log("[NotesService] Borrando carpeta entera:", dir);
            root._doTrashTarget(key, dir);
        } else {
            // Ante la duda (o contenido ajeno): solo el .md + aviso
            console.warn("[NotesService] Carpeta con contenido ajeno o ilegible, solo el .md:", dir);
            if (ownFile) {
                root._doTrashTarget(key, ownFile);
            }
            root.deletePartial(root._slugOfKey(key));
        }
    }

    // Reciben clave compuesta (la UI ya trabaja con keys); aceptan slug plano.
    // Con rebuild=false no reconstruye: para animar primero y rebuildar una
    // sola vez al final (F18).
    function markPendingDelete(slug, rebuild) {
        var key = root._resolveSaveKey(slug);
        if (!key) return;
        root._purgeQueuedSavesFor(key);
        var delKeysCopy = Object.assign({}, root._deletingKeys);
        delKeysCopy[key] = true;
        root._deletingKeys = delKeysCopy;
        if (rebuild !== false) root._rebuildNotes();
    }

    function cancelPendingDelete(slug) {
        var key = root._resolveSaveKey(slug);
        if (!key) return;
        var delKeysCopy = Object.assign({}, root._deletingKeys);
        delete delKeysCopy[key];
        root._deletingKeys = delKeysCopy;
        root._rebuildNotes();
    }

    // ── Gestión de lote de eliminaciones pendientes con ventana de deshacer ───
    function queueDelete(slug, noteData) {
        if (!slug) return;
        if (String(slug).startsWith("__external__:") || (noteData && (noteData.isExternal || noteData.readOnly))) {
            root.log("[NotesService - queueDelete] Ignorando borrado para nota externa o solo lectura:", slug);
            return;
        }
        var key = root._resolveSaveKey(slug);
        if (!key) return;

        // Cancelar cualquier guardado pendiente para esta nota (evita resurrección)
        root._purgeQueuedSavesFor(key);

        // Si está siendo editada, cerrar editor
        var canon = root._slugOfKey(key);
        if (root._activeIsKey(key, canon)) {
            root.activeNote = null;
            root.isEditing = false;
        }

        // Excluir inmediatamente de listas y búsquedas
        var delKeysCopy = Object.assign({}, root._deletingKeys);
        delKeysCopy[key] = true;
        root._deletingKeys = delKeysCopy;

        // Registrar en el lote acumulativo
        var pendingCopy = Object.assign({}, root._pendingDeletions);
        pendingCopy[key] = {
            key: key,
            noteData: noteData || root.getNote(key),
            queuedAt: Date.now()
        };
        root._pendingDeletions = pendingCopy;

        // Reconstruir lista para reflejar la eliminación inmediatamente en la UI
        root._rebuildNotes();

        // Reiniciar el temporizador de confirmación del lote
        deleteBatchTimer.restart();
    }

    function commitPendingDeletions() {
        deleteBatchTimer.stop();
        var batch = root._pendingDeletions;
        var keys = Object.keys(batch);
        if (keys.length === 0) return;
        root._pendingDeletions = ({});
        for (var i = 0; i < keys.length; i++) {
            root.deleteNote(keys[i]);
        }
    }

    function undoPendingDeletions() {
        deleteBatchTimer.stop();
        var batch = root._pendingDeletions;
        var keys = Object.keys(batch);
        if (keys.length === 0) return;
        var delKeysCopy = Object.assign({}, root._deletingKeys);
        for (var i = 0; i < keys.length; i++) {
            delete delKeysCopy[keys[i]];
        }
        root._deletingKeys = delKeysCopy;
        root._pendingDeletions = ({});
        root._rebuildNotes();
    }

    function isPendingDelete(slug) {
        var key = root._resolveSaveKey(slug);
        return !!(key && root._deletingKeys && root._deletingKeys[key]);
    }

    function _finalizeDeletion(slug) {
        var key = ((slug || "").indexOf(root._keySep()) !== -1) ? slug : root._resolveSaveKey(slug);
        delete root._notesDict[key];
        delete root._deletingKeys[key];
        delete root._lastContentHash[key];

        for (var j = filesModel.count - 1; j >= 0; j--) {
            var item = filesModel.get(j);
            if (root._keyForFileName(item.fileName) === key) {
                filesModel.remove(j);
            }
        }

        root._rebuildNotes();
        root.noteDeleted(root._slugOfKey(key));
        if (!fileScannerProc.running) {
            fileScannerProc.running = true;
        }
        root.log("[NotesService - deleteNote] Nota eliminada con éxito:", key);
    }

    function prepareToQuit() {
        flushPendingSave();

        // Si quedan elementos en la cola serial de escritura, vaciarlos de forma síncrona
        while (root._saveQueue && root._saveQueue.length > 0) {
            var nextItem = root._saveQueue.shift();
            if (nextItem && nextItem.targetPath && nextItem.serialized) {
                noteWriter.path = nextItem.targetPath;
                noteWriter.setText(nextItem.serialized);
                if (noteWriter.waitForJob) {
                    noteWriter.waitForJob();
                }
            }
        }

        if (root.pendingDeleteCount > 0) {
            var pendingKeys = Object.keys(root._pendingDeletions);
            for (var p = 0; p < pendingKeys.length; p++) {
                var pItem = root._pendingDeletions[pendingKeys[p]];
                if (pItem && pItem.targetPath) {
                    Quickshell.execDetached(["gio", "trash", pItem.targetPath]);
                }
            }
            root._pendingDeletions = ({});
            deleteBatchTimer.stop();
        }
        if (trashProc.running && trashProc.pendingPath) {
            Quickshell.execDetached(["gio", "trash", trashProc.pendingPath]);
        }
        if (root._trashQueue && root._trashQueue.length > 0) {
            for (var i = 0; i < root._trashQueue.length; i++) {
                var it = root._trashQueue[i];
                if (it && it.targetPath) {
                    Quickshell.execDetached(["gio", "trash", it.targetPath]);
                }
            }
            root._trashQueue = [];
        }
        if (noteWriter.waitForJob) {
            noteWriter.waitForJob();
        }
    }

    function togglePin(note) {
        if (!note || note.readOnly || note.isExternal) return;
        root.log("[NotesService - togglePin] Alternando pin para:", note.slug, "nuevo estado:", !note.pinned);
        var updated = Object.assign({}, note, {
            pinned: !note.pinned,
            body: note.content || note.body || ""
        });
        saveNote(updated);
    }

    // Compat: el modal usa attachImage; queda como alias al portapapeles.
    function pasteImage(slug, callback) {
        root.attachImage(slug, "clipboard", callback);
    }

    // Detecta si el portapapeles actual en Wayland tiene imagen (o archivo de imagen)
    // ignorando texto viejo en caché de Quickshell.clipboardText.
    Process {
        id: clipCheckProc
        property var pendingOnImage: null
        property var pendingOnText: null
        property string outTypes: ""
        running: false
        stdout: SplitParser {
            onRead: (line) => { clipCheckProc.outTypes += line.trim() + "\n"; }
        }
        onExited: (exitCode) => {
            var types = clipCheckProc.outTypes;
            var onImg = clipCheckProc.pendingOnImage;
            var onTxt = clipCheckProc.pendingOnText;
            clipCheckProc.outTypes = "";
            clipCheckProc.pendingOnImage = null;
            clipCheckProc.pendingOnText = null;

            var hasImgMime = /^image\/(png|jpe?g|webp|gif|svg\+xml|bmp|x-bmp|x-ms-bmp)/im.test(types);
            var hasUriList = /^text\/uri-list$/im.test(types);
            var hasPlain = /^text\/plain/im.test(types) || /^UTF8_STRING$/im.test(types);

            // Si hay un MIME de imagen real, o uri-list sin texto plano, tratar como imagen
            if (exitCode === 0 && (hasImgMime || (hasUriList && !hasPlain))) {
                if (typeof onImg === "function") onImg();
            } else {
                if (typeof onTxt === "function") onTxt();
            }
        }
        Component.onDestruction: { running = false; }
    }

    function checkClipboardForImage(onImage, onText) {
        if (clipCheckProc.running) {
            if (typeof onText === "function") onText();
            return;
        }
        clipCheckProc.outTypes = "";
        clipCheckProc.pendingOnImage = onImage;
        clipCheckProc.pendingOnText = onText;
        clipCheckProc.command = ["wl-paste", "-l"];
        clipCheckProc.running = true;
    }

    function _pasteToNote(key, cb) {
        console.log("[PasteImg] _pasteToNote: key=" + key + " procRunning=" + pasteImgProc.running
            + " finishTimer=" + pasteFinishTimer.running + " folderNote=" + !!(root._notesDict[key] && root._notesDict[key].isFolderNote));
        if (pasteImgProc.running || pasteFinishTimer.running) {
            if (typeof cb === "function") cb(null, "busy");
            return;
        }
        var note = root._notesDict[key];
        if (!note) {
            if (typeof cb === "function") cb(null, "invalid_note");
            return;
        }
        if (!note.isFolderNote && !FolderNotes.isFolderNotePath(note.fileName)) {
            root._doPromoteNote(key, function(okKey, ok) {
                if (!ok) {
                    if (cb) cb(null, "promote_failed");
                    return;
                }
                root._pasteToNote(okKey, cb);
            });
            return;
        }
        note.isFolderNote = true;
        var baseDir = root.resolveNoteBaseDir(note);
        note.baseFolder = baseDir;
        var assetsDir = baseDir + "/assets";
        var baseName = "img_clip_" + Date.now();
        var relPrefix = "assets/";

        pasteImgProc.pendingCallback = cb || null;
        pasteImgProc.pendingBase = baseDir;
        pasteImgProc.pendingKey = key;
        pasteImgProc.savedRelTag = "";
        var qsHelperBin = Quickshell.shellDir.toString().replace("file://", "") + "/bin/qs-helper";
        var pasteArgs = [
            qsHelperBin,
            "notes",
            "paste-image",
            assetsDir,
            baseName,
            relPrefix
        ];
        console.log("[PasteImg] lanzando qs-helper: assetsDir=" + assetsDir + " baseName=" + baseName);
        if (root.pathsOk("pasteImage", pasteArgs)) {
            pasteImgProc.command = pasteArgs;
            pasteImgProc.running = true;
        }
    }

    // ── Importación de .md arrastrados ────────────────────────────────
    // Un archivo por vez, con argv (sin shell): stat → cp/mv -n → stat verify.
    property var _importQueue: []
    property bool _importRunning: false
    property var _importOutcomes: []
    property var _importKnownNames: ({})
    property string _pendingImportOpen: ""

    Process {
        id: importStatProc
        property string pendingStage: "check" // "check" | "verify"
        property string pendingSrc: ""
        property string pendingDst: ""
        property string pendingMode: "copy"
        property int pendingSrcSize: 0
        property string outText: ""
        running: false
        stdout: SplitParser {
            onRead: (line) => { importStatProc.outText += line + "\n"; }
        }
        onExited: exitCode => root._onImportStatDone(exitCode)
        Component.onDestruction: { running = false; }
    }

    Process {
        id: importFileProc
        property string pendingSrc: ""
        property string pendingDst: ""
        property string pendingMode: "copy"
        property int pendingSrcSize: 0
        running: false
        onExited: exitCode => root._onImportFileDone(exitCode)
        Component.onDestruction: { running = false; }
    }

    property var _directReadQueue: []

    // Proceso para lectura asíncrona pero casi instantánea (<3ms) de archivos externos o directos
    Process {
        id: directFileReadProc
        property var pendingCallback: null
        property string accumulatedText: ""
        running: false

        stdout: SplitParser {
            splitMarker: ""
            onRead: chunk => {
                directFileReadProc.accumulatedText += chunk;
            }
        }

        onExited: exitCode => {
            var cb = directFileReadProc.pendingCallback;
            var text = directFileReadProc.accumulatedText;
            directFileReadProc.pendingCallback = null;
            directFileReadProc.accumulatedText = "";
            if (typeof cb === "function") {
                cb(exitCode === 0, text);
            }
            root._processNextDirectRead();
        }

        Component.onDestruction: { running = false; }
    }

    function _readDiskFile(filePath, callback) {
        if (!filePath) {
            if (typeof callback === "function") callback(false, "");
            return;
        }
        root._directReadQueue.push({ filePath: filePath, callback: callback });
        root._processNextDirectRead();
    }

    function _processNextDirectRead() {
        if (directFileReadProc.running || !root._directReadQueue || root._directReadQueue.length === 0) return;
        var req = root._directReadQueue.shift();
        if (!req) return;
        directFileReadProc.pendingCallback = req.callback;
        directFileReadProc.accumulatedText = "";
        directFileReadProc.exec(["cat", "--", req.filePath]);
    }

    // Proceso aislado para importación in-place a la biblioteca
    Process {
        id: directImportProc
        property var pendingCallback: null
        property string pendingDst: ""
        running: false
        onExited: exitCode => {
            var cb = directImportProc.pendingCallback;
            var dst = directImportProc.pendingDst;
            directImportProc.pendingCallback = null;
            directImportProc.pendingDst = "";
            if (typeof cb === "function") cb(exitCode === 0, dst);
        }
        Component.onDestruction: { running = false; }
    }

    function openExternalFile(absPath, previewOnly, callback) {
        if (!absPath) {
            if (typeof callback === "function") callback(null);
            return null;
        }
        var p = absPath.toString().replace(/^file:\/\//, "");
        try {
            p = decodeURIComponent(p);
        } catch (e) {}

        root.log("[NotesService - openExternalFile] Abriendo archivo externo:", p, "previewOnly:", previewOnly);
        var slash = p.lastIndexOf("/");
        var fileName = slash !== -1 ? p.substring(slash + 1) : p;
        var baseFolder = slash !== -1 ? p.substring(0, slash) : "";

        _readDiskFile(p, function(success, raw) {
            if (!success) {
                console.error("[NotesService] Error leyendo archivo externo:", p);
                if (typeof callback === "function") callback(null);
                return;
            }

            var noteObj = MD.parseNote(fileName, p, false, raw);
            noteObj.isExternal = true;
            noteObj.readOnly = (previewOnly !== false);
            noteObj.hadFrontmatter = Boolean(noteObj._frontmatterEntries && noteObj._frontmatterEntries.length > 0);
            noteObj.key = "__external__:" + p;
            noteObj.slug = "__external__:" + fileName;
            noteObj.baseFolder = baseFolder;

            if (typeof root.probeExternalImages === "function") {
                root.probeExternalImages(noteObj.baseFolder);
            }

            if (typeof callback === "function") {
                callback(noteObj);
            } else {
                root.openNote(noteObj);
            }
        });
        return null;
    }

    function unlockExternalInPlace() {
        if (!root.activeNote || !root.activeNote.isExternal) return;
        root.log("[NotesService - unlockExternalInPlace] Desbloqueando edición in-place para:", root.activeNote.filePath);
        var clone = Object.assign({}, root.activeNote);
        clone.readOnly = false;
        root.activeNote = clone;
    }

    function importExternalAndEdit(callback) {
        if (!root.activeNote || !root.activeNote.isExternal) {
            if (typeof callback === "function") callback(false);
            return;
        }
        var src = root.activeNote.filePath;
        if (!src) {
            if (typeof callback === "function") callback(false);
            return;
        }
        var slash = src.lastIndexOf("/");
        var rawName = slash !== -1 ? src.substring(slash + 1) : "nota.md";
        var existingNames = [];
        for (var k in root._notesDict) {
            if (root._notesDict[k] && root._notesDict[k].fileName) {
                existingNames.push(root._notesDict[k].fileName);
            }
        }
        var targetFileName = ImportLogic.uniqueFileName(rawName, existingNames);
        var targetPath = root.notesDir + "/" + targetFileName;
        var mode = NotesConfig.effectiveImportMode();
        var cmd = (mode === "move") ? "mv" : "cp";

        root.log("[NotesService - importExternalAndEdit] Importando:", src, "->", targetPath, "modo:", mode);
        directImportProc.pendingCallback = function(success, dst) {
            if (success) {
                _readDiskFile(targetPath, function(readOk, raw) {
                    var parsed = MD.parseNote(targetFileName, targetPath, false, readOk ? raw : "");
                    var slug = root._canonSlug(parsed.slug || parsed.id || targetFileName.replace(/\.(md|txt)$/i, ""));
                    var ext = root._canonExt(targetFileName);
                    var key = root._dictKey(slug, ext);
                    parsed.slug = slug;
                    parsed.id = slug;
                    parsed.key = key;
                    parsed.isExternal = false;
                    parsed.readOnly = false;
                    parsed.baseFolder = root.resolveNoteBaseDir(parsed);
                    root._notesDict[key] = parsed;
                    root._rebuildNotes();
                    root.openNote(parsed);
                    root.noteImported(parsed);
                    if (typeof callback === "function") callback(true, parsed);
                });
            } else {
                console.error("[NotesService - importExternalAndEdit] Falló importación de", src);
                if (typeof callback === "function") callback(false);
            }
        };
        directImportProc.pendingDst = targetPath;
        directImportProc.exec(["env", "LC_ALL=C", cmd, "--", src, targetPath]);
    }

    function openPath(absPath, previewOnly, callback) {
        if (!absPath) {
            if (typeof callback === "function") callback(null);
            return null;
        }
        var p = absPath.toString().replace(/^file:\/\//, "");
        try {
            p = decodeURIComponent(p);
        } catch (e) {}

        if (ImportLogic.isInsideDir(p, root.notesDir)) {
            for (var k in root._notesDict) {
                var n = root._notesDict[k];
                if (n && n.filePath === p) {
                    root.openNote(n);
                    if (typeof callback === "function") callback(n);
                    return n;
                }
            }
            _readDiskFile(p, function(success, raw) {
                if (success) {
                    var slash = p.lastIndexOf("/");
                    var fileName = slash !== -1 ? p.substring(slash + 1) : p;
                    var parsed = MD.parseNote(fileName, p, false, raw);
                    var slug = root._canonSlug(parsed.slug || parsed.id || fileName.replace(/\.(md|txt)$/i, ""));
                    var ext = root._canonExt(fileName);
                    var key = root._dictKey(slug, ext);
                    parsed.slug = slug;
                    parsed.id = slug;
                    parsed.key = key;
                    parsed.isExternal = false;
                    parsed.readOnly = false;
                    parsed.baseFolder = root.resolveNoteBaseDir(parsed);
                    root._notesDict[key] = parsed;
                    if (typeof callback === "function") {
                        callback(parsed);
                    } else {
                        root.openNote(parsed);
                    }
                } else {
                    if (typeof callback === "function") callback(null);
                }
            });
            return null;
        }
        return root.openExternalFile(p, previewOnly !== false, callback);
    }

    function importDroppedUrls(urls) {
        if (!urls) return;
        var mode = NotesConfig.effectiveImportMode();
        var pushed = 0;
        for (var i = 0; i < urls.length; i++) {
            var u = urls[i];
            var raw = (u && typeof u.toString === "function") ? u.toString() : String(u);
            var local = ImportLogic.decodeDropUrl(raw);
            if (!local) continue;
            // .md y .txt (el watcher descubre ambas)
            var iext = ImportLogic.getExtension(local);
            if (iext !== "md" && iext !== "txt") continue;
            root._importQueue.push({ src: local, mode: mode });
            pushed++;
        }
        if (pushed > 0 && !root._importRunning) {
            root._importRunning = true;
            root._processNextImport();
        }
    }

    function _importExistingLower() {
        var arr = [];
        for (var i = 0; i < filesModel.count; i++) {
            var it = filesModel.get(i);
            if (it && it.fileName) arr.push(String(it.fileName).toLowerCase());
        }
        // F19: los nombres de nota-carpeta también ocupan (Foo/ choca con Foo.md)
        for (var j = 0; j < filesModel.count; j++) {
            var jt = filesModel.get(j);
            if (jt && jt.filePath && jt.filePath.indexOf(root.notesDir + "/") === 0) {
                var rel = jt.filePath.substring(root.notesDir.length + 1);
                var slash = rel.indexOf("/");
                if (slash !== -1) {
                    var top = rel.substring(0, slash).toLowerCase();
                    if (arr.indexOf(top) === -1) arr.push(top);
                }
            }
        }
        for (var k in root._importKnownNames) arr.push(k);
        return arr;
    }

    function _processNextImport() {
        if (root._importQueue.length === 0) {
            root._finishImport();
            return;
        }
        var item = root._importQueue.shift();
        var src = item.src;
        // Ya está dentro de la carpeta: no copiar ni mover, solo abrir (en grilla).
        // Clave con ruta relativa para que valga también en subcarpetas.
        if (ImportLogic.isInsideDir(src, root.notesDir)) {
            var rel = src;
            var prefix = root.notesDir + "/";
            if (rel.indexOf(prefix) === 0) rel = rel.substring(prefix.length);
            var akey = root._keyForFileName(rel);
            var known = root.getNote(akey);
            var opened = false;
            if (!root.isEditing) {
                if (known) {
                    root.openNote(known);
                    opened = true;
                } else {
                    root._pendingImportOpen = akey;
                    if (!fileScannerProc.running) fileScannerProc.running = true;
                    opened = true;
                }
            }
            root._importOutcomes.push({ status: "already", name: ImportLogic.baseName(src), opened: opened });
            root._processNextImport();
            return;
        }
        importStatProc.pendingStage = "check";
        importStatProc.pendingSrc = src;
        importStatProc.pendingMode = item.mode;
        importStatProc.outText = "";
        var statArgs = ["env", "LC_ALL=C", "stat", "-c", "%F\t%s", "--", src];
        if (root.pathsOk("importStat", statArgs)) {
            importStatProc.command = statArgs;
            importStatProc.running = true;
        } else {
            root._importOutcomes.push({ status: "skipped", name: ImportLogic.baseName(src), reason: "type", opened: false });
            root._processNextImport();
        }
    }

    function _onImportStatDone(exitCode) {
        var stage = importStatProc.pendingStage;
        if (stage === "verify") {
            root._onImportVerifyDone(exitCode);
            return;
        }
        var src = importStatProc.pendingSrc;
        var mode = importStatProc.pendingMode;
        var kind = "";
        var size = -1;
        if (exitCode !== 0) {
            console.warn("[NotesService] stat de importación falló para:", src, "código:", exitCode);
        }
        if (exitCode === 0) {
            var parts = (importStatProc.outText || "").split("\n")[0].split("\t");
            if (parts.length >= 2) {
                kind = parts[0].trim();
                size = parseInt(parts[1].trim(), 10);
            }
        }
        var v = ImportLogic.validateImport(kind, size);
        if (!v.ok) {
            root._importOutcomes.push({ status: "skipped", name: ImportLogic.baseName(src), reason: v.reason, opened: false });
            root._processNextImport();
            return;
        }
        // Nombre único, nunca sobrescribir (cp/mv -n como segunda barrera)
        var unique = ImportLogic.uniqueFileName(ImportLogic.baseName(src), root._importExistingLower());
        var dst = root.notesDir + "/" + unique;
        var known = Object.assign({}, root._importKnownNames);
        known[unique.toLowerCase()] = true;
        root._importKnownNames = known;
        importFileProc.pendingSrc = src;
        importFileProc.pendingDst = dst;
        importFileProc.pendingMode = mode;
        importFileProc.pendingSrcSize = size;
        var fileArgs = mode === "move" ? ["mv", "-n", "--", src, dst] : ["cp", "-n", "--", src, dst];
        if (root.pathsOk("importFile", fileArgs)) {
            importFileProc.command = fileArgs;
            importFileProc.running = true;
        } else {
            root._importOutcomes.push({ status: "error", name: ImportLogic.baseName(src), opened: false });
            root._processNextImport();
        }
    }

    function _onImportFileDone(exitCode) {
        var src = importFileProc.pendingSrc;
        var dst = importFileProc.pendingDst;
        // Verificar destino con el mismo tamaño ANTES de dar por bueno el
        // movimiento (mv entre filesystems copia y borra; si el borrado falla
        // por solo-lectura, igual quedó copiado: no es error total)
        importStatProc.pendingStage = "verify";
        importStatProc.pendingSrc = src;
        importStatProc.pendingDst = dst;
        importStatProc.pendingMode = importFileProc.pendingMode;
        importStatProc.pendingSrcSize = importFileProc.pendingSrcSize;
        importStatProc.outText = "";
        var verifyArgs = ["env", "LC_ALL=C", "stat", "-c", "%n\t%s", "--", dst, src];
        if (root.pathsOk("importVerify", verifyArgs)) {
            importStatProc.command = verifyArgs;
            importStatProc.running = true;
        } else {
            root._importOutcomes.push({ status: "error", name: ImportLogic.baseName(dst), opened: false });
            root._processNextImport();
        }
    }

    function _onImportVerifyDone(exitCode) {
        var src = importStatProc.pendingSrc;
        var dst = importStatProc.pendingDst;
        var mode = importStatProc.pendingMode;
        var wantSize = importStatProc.pendingSrcSize;
        var dstOk = false;
        var srcRemains = true;
        if (exitCode === 0) {
            var lines = (importStatProc.outText || "").split("\n");
            for (var i = 0; i < lines.length; i++) {
                var parts = lines[i].split("\t");
                if (parts.length < 2) continue;
                var p = parts[0];
                var sz = parseInt((parts[1] || "").trim(), 10);
                if (p === dst && sz === wantSize) dstOk = true;
                if (p === src) srcRemains = true;
                else if (p !== dst) { /* línea desconocida, ignorar */ }
            }
            // stat lista solo lo que existe: si src no aparece, ya no está
            if ((importStatProc.outText || "").indexOf(src) === -1) srcRemains = false;
        }
        var name = ImportLogic.baseName(dst);
        if (!dstOk) {
            root._importOutcomes.push({ status: "error", name: name, opened: false });
        } else if (mode === "move") {
            root._importOutcomes.push({ status: "moved", name: name, srcKept: srcRemains, opened: false });
            root._afterImportSuccess(dst);
        } else {
            root._importOutcomes.push({ status: "copied", name: name, opened: false });
            root._afterImportSuccess(dst);
        }
        root._processNextImport();
    }

    function _afterImportSuccess(dst) {
        // Solo abrir automáticamente si fue UN solo archivo y estamos en grilla
        var single = root._importOutcomes.length === 1 && root._importQueue.length === 0 && root._importOutcomes.filter(function(o) { return o.status === "copied" || o.status === "moved"; }).length === 1;
        if (!single || root.isEditing) return;
        var skey = root._keyForFileName(ImportLogic.baseName(dst));
        var known = root.getNote(skey);
        var idx = root._importOutcomes.length - 1;
        if (known) {
            root.openNote(known);
            root._importOutcomes[idx].opened = true;
        } else {
            root._pendingImportOpen = skey;
            root._importOutcomes[idx].opened = true; // se abrirá al refrescar
            if (!fileScannerProc.running) fileScannerProc.running = true;
        }
    }

    function _finishImport() {
        root._importRunning = false;
        var summary = ImportLogic.summarizeImport(root._importOutcomes);
        var opened = false;
        var kept = 0;
        var issueName = "";
        var issueReason = "";
        for (var i = 0; i < root._importOutcomes.length; i++) {
            var o = root._importOutcomes[i];
            if (o.opened) opened = true;
            if (o.srcKept) kept++;
            if (!issueName && (o.status === "error" || o.status === "skipped")) {
                issueName = o.name || "";
                issueReason = o.reason || "";
            }
        }
        summary.opened = opened;
        summary.srcKept = kept;
        summary.issueName = issueName;
        summary.issueReason = issueReason;
        root._importOutcomes = [];
        root._importKnownNames = {};
        root.refresh();
        root.importFinished(summary);
    }

    // ── Existencia de imágenes locales ───────────────────────────────
    // Un solo find sobre el árbol + un stat en lote para absolutas externas.
    // Los delegates no setean source hasta saber que existe ("yes") o que es
    // remota: así no hay warnings "Cannot open". La caché se invalida con
    // refresh/rescan-con-cambios y se registra al agregar imágenes desde la app.
    property var _imageExists: ({})
    property bool imageProbeReady: false
    property int imageProbeSeq: 0
    property int _lastProbeCount: -1

    // "yes" | "no" | "remote" | "unknown" (sin probe aún: no setear source)
    function imageStateFor(src, baseFolder) {
        var abs = ImageProbe.resolveLocal(baseFolder || "", src || "");
        if (!abs) {
            if ((src || "").trim() === "") return "no";
            return "remote";
        }
        if (root._imageExists && root._imageExists[abs]) return "yes";
        if (!root.imageProbeReady) return "unknown";
        return "no";
    }

    function imageExistsCached(absPath) {
        return !!(absPath && root._imageExists && root._imageExists[absPath]);
    }

    function registerImagePath(absPath) {
        if (!absPath) return;
        var m = Object.assign({}, root._imageExists);
        m[absPath] = true;
        root._imageExists = m;
        root.imageProbeReady = true;
        root.imageProbeSeq++;
    }

    Process {
        id: externalImageProbeProc
        property string pendingFolder: ""
        running: false
        command: ["find", pendingFolder, "-maxdepth", "3", "-type", "f", "(",
            "-name", "*.png", "-o", "-name", "*.jpg", "-o", "-name", "*.jpeg", "-o",
            "-name", "*.webp", "-o", "-name", "*.gif", "-o", "-name", "*.svg", "-o",
            "-name", "*.bmp", ")"]
        stdout: SplitParser {
            onRead: (line) => {
                var p = line.trim();
                if (p) root.registerImagePath(p);
            }
        }
        function scan(folder) {
            if (!folder || running) return;
            pendingFolder = folder;
            command = ["find", folder, "-maxdepth", "3", "-type", "f", "(",
                "-name", "*.png", "-o", "-name", "*.jpg", "-o", "-name", "*.jpeg", "-o",
                "-name", "*.webp", "-o", "-name", "*.gif", "-o", "-name", "*.svg", "-o",
                "-name", "*.bmp", ")"];
            running = true;
        }
        Component.onDestruction: { running = false; }
    }

    function probeExternalImages(baseFolder) {
        if (!baseFolder || typeof baseFolder !== "string" || baseFolder.trim() === "") return;
        externalImageProbeProc.scan(baseFolder.trim());
    }

    Process {
        id: imageProbeProc
        property string stage: "assets" // "assets" | "absolutes"
        property string outText: ""
        property var pendingFound: ({})
        running: false
        stdout: SplitParser {
            onRead: (line) => { imageProbeProc.outText += line + "\n"; }
        }
        onExited: exitCode => root._onImageProbeDone(exitCode)
        Component.onDestruction: { running = false; }
    }

    Timer {
        id: imageProbeDebounce
        interval: 1200
        repeat: false
        onTriggered: root.runImageProbe()
    }

    function _sameImageSet(a, b) {
        var ka = Object.keys(a || {});
        var kb = Object.keys(b || {});
        if (ka.length !== kb.length) return false;
        for (var i = 0; i < ka.length; i++) {
            if (!b[ka[i]]) return false;
        }
        return true;
    }

    function runImageProbe() {
        if (imageProbeProc.running || !root.notesDir) return;
        // No invalidar lo conocido al re-sondear: solo la primera vez se
        // muestra placeholder. Al terminar se actualiza si cambió.
        if (Object.keys(root._imageExists).length === 0) {
            root.imageProbeReady = false;
        }
        imageProbeProc.stage = "assets";
        imageProbeProc.outText = "";
        imageProbeProc.command = ["find", root.notesDir, "-type", "f", "(", "-iname", "*.png", "-o", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.webp", "-o", "-iname", "*.gif", "-o", "-iname", "*.bmp", "-o", "-iname", "*.svg", ")"];
        imageProbeProc.running = true;
    }

    function _publishImageSet(found) {
        // Publicar una sola vez y solo si cambió: sin parpadeo
        if (!_sameImageSet(root._imageExists, found)) {
            root._imageExists = found;
            root.imageProbeSeq++;
        }
        root.imageProbeReady = true;
    }

    function _onImageProbeDone(exitCode) {
        if (imageProbeProc.stage === "absolutes") {
            if (exitCode !== 0) {
                console.warn("[NotesService] stat de imágenes falló, código:", exitCode);
            } else {
                var doneLines = (imageProbeProc.outText || "").split("\n");
                var doneMap = Object.assign({}, imageProbeProc.pendingFound);
                for (var i = 0; i < doneLines.length; i++) {
                    var dp = doneLines[i].trim();
                    if (dp) doneMap[dp] = true;
                }
                imageProbeProc.pendingFound = {};
                root._publishImageSet(doneMap);
                return;
            }
            root.imageProbeReady = true;
            return;
        }
        var found = {};
        if (exitCode !== 0) {
            console.warn("[NotesService] find de imágenes falló, código:", exitCode);
        } else {
            var lines = (imageProbeProc.outText || "").split("\n");
            for (var j = 0; j < lines.length; j++) {
                var lp = lines[j].trim();
                if (lp) found[lp] = true;
            }
        }
        // Referencias absolutas o file:// fuera del árbol: un stat en lote.
        // Solo se publica si el conjunto cambió (sin parpadeo, F15.3).
        var abs = [];
        var seen = {};
        for (var k in root._notesDict) {
            var note = root._notesDict[k];
            if (!note) continue;
            var base = note.baseFolder || root.notesDir;
            var assets = note.assets || [];
            for (var a = 0; a < assets.length && abs.length < 200; a++) {
                var ap = ImageProbe.resolveLocal(base, assets[a] || "");
                if (ap && !found[ap] && !seen[ap]) {
                    seen[ap] = true;
                    abs.push(ap);
                }
            }
        }
        if (abs.length === 0) {
            root._publishImageSet(found);
            return;
        }
        imageProbeProc.pendingFound = found;
        imageProbeProc.stage = "absolutes";
        imageProbeProc.outText = "";
        imageProbeProc.command = ["env", "LC_ALL=C", "stat", "-c", "%n", "--"].concat(abs);
        imageProbeProc.running = true;
    }

    function openNote(note) {
        root.flushPendingSave();
        root.log("[NotesService - openNote] Abriendo nota en editor:", note ? (note.slug || note.title) : "null");
        if (note) {
            var nkey = note.key || root._resolveSaveKey(note.slug || note.id);
            // No robar una importación pendiente si el usuario abrió otra nota
            if (root._pendingImportOpen !== "" && nkey !== root._pendingImportOpen) {
                root._pendingImportOpen = "";
            }
            if (!note.isExternal) {
                var cs = root._canonSlug(note.slug || note.id);
                var nowStr = new Date().toISOString().replace("T", " ").substring(0, 19);
                note.lastOpened = nowStr;
                if (root._notesDict && root._notesDict[nkey]) {
                    root._notesDict[nkey].lastOpened = nowStr;
                }
                var lom = Object.assign({}, root.lastOpenedMap);
                lom[cs] = nowStr;
                root.lastOpenedMap = lom;
                root._persistState();
            }
        }
        if (note && note.filePath && (note.body === undefined || note.body === null)) {
            root._readDiskFile(note.filePath, function(ok, text) {
                if (ok && note) {
                    var parsed = MD.parseNote(note.fileName, note.filePath, false, text);
                    note.body = parsed.body;
                    note.blocks = parsed.blocks;
                    if (root.activeNote && root.activeNote.key === note.key) {
                        root.activeNote = Object.assign({}, note);
                    }
                }
            });
        }
        root.activeNote = note;
        root.isEditing = true;
    }

    function closeNote() {
        root.log("[NotesService - closeNote] Cerrando editor de notas");
        root.flushPendingSave();
        var wasExternal = root.activeNote && root.activeNote.isExternal;
        root.activeNote = null;
        root.isEditing = false;
        if (!wasExternal) {
            root._rebuildNotes();
        }
    }

    // Suelta reintentos pendientes de una ruta vieja (el contenido vive en el
    // dict; reintentar escribiría a una ruta muerta y la recrearía).
    function _dropFailedFor(oldKey) {
        if (root._failedItems && root._failedItems[oldKey]) {
            var fc = Object.assign({}, root._failedItems);
            delete fc[oldKey];
            root._failedItems = fc;
        }
    }

    // Versión de archivos: se incrementa en promote/rename/convert para que los
    // bindings a fileName se refresquen aunque el objeto no cambie (F19).
    property int filesVersion: 0

    // ── Promoción a nota-carpeta + attach de imágenes (F19) ────────────────
    // Punto único de entrada para agregar imágenes (F15.2): files y portapapeles.
    // ¿Hay trabajo de archivos en vuelo que un attach/promote no debe pisar?
    function _attachBusy() {
        return root._isWriting || root._saveQueue.length > 0
            || renameProc.running || convertProc.running || promoteProc.running
            || assetMoveProc.running || imageCopyProc.running
            || root._isTrashing || (root._trashQueue && root._trashQueue.length > 0);
    }

    Timer {
        id: promoteWaitTimer
        interval: 150
        repeat: false
        property var waitQueue: []
        onTriggered: {
            var q = promoteWaitTimer.waitQueue;
            if (q.length === 0) return;
            if (root._attachBusy()) {
                promoteWaitTimer.restart();
                return;
            }
            var item = q.shift();
            promoteWaitTimer.waitQueue = q;
            root._doAttachImage(item.key, item.source, item.cb);
        }
    }

    Process {
        id: promoteProc
        property string pendingStage: "list" // "list" | "move"
        property string pendingKey: ""
        property string pendingFolderRel: ""
        property string pendingNewRel: ""
        property string pendingNewPath: ""
        property string outText: ""
        property var pendingCallback: null
        running: false
        stdout: SplitParser {
            onRead: (line) => { promoteProc.outText += line + "\n"; }
        }
        onExited: exitCode => root._onPromoteDone(exitCode)
        Component.onDestruction: { running = false; }
    }

    Process {
        id: assetMoveProc
        property var pendingMoves: []
        property int pendingIndex: 0
        property string pendingKey: ""
        property string pendingBody: ""
        property var pendingRewrites: []
        property var pendingDoneCb: null
        running: false
        onExited: exitCode => root._onAssetMoveDone(exitCode)
        Component.onDestruction: { running = false; }
    }

    Process {
        id: imageCopyProc
        property string pendingKey: ""
        property string pendingRelTag: ""
        property var pendingCb: null
        running: false
        onExited: exitCode => root._onImageCopyDone(exitCode)
        Component.onDestruction: { running = false; }
    }

    Process {
        id: dirListProc
        property string pendingKey: ""
        property string pendingDir: ""
        property string pendingFile: ""
        property string pendingOwnMd: ""
        property string outText: ""
        running: false
        stdout: SplitParser {
            onRead: (line) => { dirListProc.outText += line + "\n"; }
        }
        onExited: exitCode => root._onDirListDone(exitCode)
        Component.onDestruction: { running = false; }
    }

    function _updateFilesModelPath(oldAbs, newRel, newAbs) {
        for (var i = 0; i < filesModel.count; i++) {
            var it = filesModel.get(i);
            if (it && it.filePath === oldAbs) {
                filesModel.setProperty(i, "fileName", newRel);
                filesModel.setProperty(i, "filePath", newAbs);
                break;
            }
        }
    }

    function attachImage(key, source, callback) {
        var k = root._resolveSaveKey(key);
        console.log("[PasteImg] attachImage: key=" + key + " resolved=" + k + " source=" + source
            + " existe=" + !!root._notesDict[k] + " busy=" + root._attachBusy());
        var cb = (typeof callback === "function") ? callback : null;
        var note = root._notesDict[k];
        if (!note || root._deletingKeys[k]) {
            if (cb) cb(null, "invalid_note");
            return;
        }
        if ((note.format || "md") === "txt") {
            if (cb) cb(null, "txt");
            return;
        }
        if (source !== "clipboard" && !source) {
            if (cb) cb(null, "invalid_source");
            return;
        }
        root.flushPendingSave();
        if (root._attachBusy()) {
            var q = promoteWaitTimer.waitQueue || [];
            q.push({ key: k, source: source, cb: cb });
            promoteWaitTimer.waitQueue = q;
            promoteWaitTimer.restart();
            return;
        }
        root._doAttachImage(k, source, cb);
    }

    function _doAttachImage(key, source, cb) {
        var note = root._notesDict[key];
        if (!note) {
            if (cb) cb(null, "invalid_note");
            return;
        }
        if (source === "clipboard") {
            root._pasteToNote(key, cb);
            return;
        }
        if (note.isFolderNote) {
            root._copyImageToNote(key, source, cb);
            return;
        }
        root._doPromoteNote(key, function(okKey, ok) {
            if (!ok) {
                if (cb) cb(null, "promote_failed");
                return;
            }
            root._copyImageToNote(okKey, source, cb);
        });
    }

    function _doPromoteNote(key, callback) {
        var cb = (typeof callback === "function") ? callback : null;
        var note = root._notesDict[key];
        if (!note) {
            if (cb) cb(key, false);
            return;
        }
        if (note.isFolderNote || FolderNotes.isFolderNotePath(note.fileName)) {
            note.isFolderNote = true;
            note.baseFolder = root.resolveNoteBaseDir(note);
            if (root.activeNote && (root.activeNote.key === key || root._canonSlug(root.activeNote.slug) === note.slug)) {
                root.activeNote.isFolderNote = true;
                root.activeNote.baseFolder = note.baseFolder;
            }
            if (cb) cb(key, true);
            return;
        }
        var rel = note.fileName;
        var folderRel = FolderNotes.folderPathFor(rel);
        var base = rel.indexOf("/") !== -1 ? rel.substring(rel.lastIndexOf("/") + 1) : rel;
        var newRel = folderRel + "/" + base;
        var parentRel = FolderNotes.parentDir(folderRel);
        var parentAbs = parentRel === "" ? root.notesDir : (root.notesDir + "/" + parentRel);
        promoteProc.pendingStage = "list";
        promoteProc.pendingKey = key;
        promoteProc.pendingFolderRel = folderRel;
        promoteProc.pendingNewRel = newRel;
        promoteProc.pendingNewPath = root.notesDir + "/" + newRel;
        promoteProc.pendingCallback = cb;
        promoteProc.outText = "";
        promoteProc.command = ["find", parentAbs, "-mindepth", "1", "-maxdepth", "1", "-printf", "%f\n"];
        if (root.pathsOk("promoteList", promoteProc.command)) {
            promoteProc.running = true;
        } else if (cb) {
            cb(key, false);
        }
    }

    function _onPromoteDone(exitCode) {
        if (promoteProc.pendingStage === "list") {
            var names = [];
            if (exitCode === 0) {
                var rawLines = (promoteProc.outText || "").split("\n");
                for (var i = 0; i < rawLines.length; i++) {
                    var nm = rawLines[i].trim();
                    if (nm) names.push(nm);
                }
            }
            var folderRel = promoteProc.pendingFolderRel;
            var segs = folderRel.split("/");
            var folderBase = segs[segs.length - 1];
            var parentRel = FolderNotes.parentDir(folderRel);
            var uniqueBase = FolderNotes.uniqueFolderName(folderBase, names);
            var finalFolderRel = parentRel === "" ? uniqueBase : (parentRel + "/" + uniqueBase);
            // Nombre interno: misma base que la carpeta (regla de nota-carpeta)
            var fileBase = uniqueBase;
            var dot = promoteProc.pendingNewRel.lastIndexOf(".");
            var ext = dot !== -1 ? promoteProc.pendingNewRel.substring(dot) : ".md";
            var finalRel = finalFolderRel + "/" + fileBase + ext;
            var folderDir = root.notesDir + "/" + finalFolderRel;
            promoteProc.pendingFolderRel = finalFolderRel;
            promoteProc.pendingNewRel = finalRel;
            promoteProc.pendingNewPath = root.notesDir + "/" + finalRel;
            promoteProc.pendingStage = "move";
            var oldAbs = root._notesDict[promoteProc.pendingKey]
                ? root._notesDict[promoteProc.pendingKey].filePath : "";
            var mvArgs = ["sh", "-c", 'mkdir -p "$3/assets" && [ ! -e "$2" ] && mv -- "$1" "$2" && [ -f "$2" ]', "_", oldAbs, promoteProc.pendingNewPath, folderDir];
            if (root.pathsOk("promoteMove", mvArgs)) {
                promoteProc.command = mvArgs;
                promoteProc.running = true;
            } else {
                var cb0 = promoteProc.pendingCallback;
                promoteProc.pendingCallback = null;
                if (cb0) cb0(promoteProc.pendingKey, false);
            }
            return;
        }
        var key = promoteProc.pendingKey;
        var cbDone = promoteProc.pendingCallback;
        var newRel = promoteProc.pendingNewRel;
        var newPath = promoteProc.pendingNewPath;
        var folderDirDone = newPath.substring(0, newPath.lastIndexOf("/"));
        promoteProc.pendingKey = "";
        promoteProc.pendingCallback = null;
        if (exitCode !== 0) {
            console.warn("[NotesService] Promoción falló para:", key);
            if (cbDone) cbDone(key, false);
            return;
        }
        var existing = root._notesDict[key];
        if (!existing) {
            if (cbDone) cbDone(key, false);
            return;
        }
        var oldAbs = existing.filePath;
        var oldBase = oldAbs.indexOf("/") !== -1 ? oldAbs.substring(0, oldAbs.lastIndexOf("/")) : root.notesDir;
        var newSlug = FolderNotes.slugForPath(newRel);
        var newKey = root._dictKey(newSlug, root._canonExt(newRel));
        existing.fileName = newRel;
        existing.filePath = newPath;
        existing.baseFolder = folderDirDone;
        existing.isFolderNote = true;
        // El contenido no cambió con el mv: portar el hash para el anti-eco
        var carriedHash = root._lastContentHash[key];
        if (newKey !== key) {
            existing.slug = newSlug;
            existing.id = newSlug;
            existing.key = newKey;
            delete root._notesDict[key];
            delete root._lastContentHash[key];
            root._dropFailedFor(key);
        }
        root._notesDict[newKey] = existing;
        if (carriedHash !== undefined) {
            root._lastContentHash[newKey] = carriedHash;
        }
        if (root.activeNote && (root.activeNote.key === key || root.activeNote.key === newKey || root._canonSlug(root.activeNote.slug) === newSlug)) {
            root.activeNote = Object.assign({}, root.activeNote, existing);
            root._notesDict[newKey] = root.activeNote;
        }
        root._updateFilesModelPath(oldAbs, newRel, newPath);
        root._markWritingSlug(newKey, 1500);
        root.filesVersion++;
        if (!fileScannerProc.running) fileScannerProc.running = true;
        root._rebuildNotes();
        root._moveLegacyAssets(newKey, oldBase, function() {
            if (cbDone) cbDone(newKey, true);
        });
    }

    // Mueve/copia solo los assets heredados referenciados (copia si otra nota
    // los comparte) y reescribe los enlaces por el pipeline normal de guardado.
    // oldBase es la base ANTERIOR (la resolución que veía el pintor); así valen
    // layouts viejos de raíz y de subcarpeta. Lo no resoluble se deja como está.
    function _moveLegacyAssets(key, oldBase, done) {
        var note = root._notesDict[key];
        var finish = (typeof done === "function") ? done : null;
        if (!note) {
            if (finish) finish();
            return;
        }
        var body = (note.body !== undefined && note.body !== null) ? note.body : (note.content || "");
        var refs = note.assets || [];
        var moves = [];
        var seen = {};
        var usedNew = {};
        for (var i = 0; i < refs.length; i++) {
            var ref = refs[i] || "";
            if (seen[ref]) continue;
            seen[ref] = true;
            var oldAbs = ImageProbe.resolveLocal(oldBase, ref);
            // Solo assets locales bajo notesDir (no remotos ni absolutos externos)
            if (!oldAbs || oldAbs.indexOf(root.notesDir + "/") !== 0) continue;
            var fileBase = oldAbs.indexOf("/") !== -1 ? oldAbs.substring(oldAbs.lastIndexOf("/") + 1) : oldAbs;
            var newRel = "assets/" + fileBase;
            if (usedNew[newRel]) {
                var dotAt = fileBase.lastIndexOf(".");
                var stem = dotAt !== -1 ? fileBase.substring(0, dotAt) : fileBase;
                var ext = dotAt !== -1 ? fileBase.substring(dotAt) : "";
                var n = 2;
                while (usedNew["assets/" + stem + "_" + n + ext]) n++;
                newRel = "assets/" + stem + "_" + n + ext;
            }
            usedNew[newRel] = true;
            var newAbs = note.baseFolder + "/" + newRel;
            if (oldAbs === newAbs) continue;
            var shared = false;
            for (var k in root._notesDict) {
                if (k === key) continue;
                var other = root._notesDict[k];
                var oa = (other && other.assets) || [];
                var obase = (other && other.baseFolder) || root.notesDir;
                for (var o = 0; o < oa.length; o++) {
                    if (ImageProbe.resolveLocal(obase, oa[o] || "") === oldAbs) { shared = true; break; }
                }
                if (shared) break;
            }
            moves.push({ src: oldAbs, dst: newAbs, ref: ref, newRel: newRel, shared: shared });
        }
        if (moves.length === 0) {
            if (finish) finish();
            return;
        }
        assetMoveProc.pendingMoves = moves;
        assetMoveProc.pendingIndex = 0;
        assetMoveProc.pendingKey = key;
        assetMoveProc.pendingBody = body;
        assetMoveProc.pendingRewrites = [];
        assetMoveProc.pendingDoneCb = finish;
        root._runNextAssetMove();
    }

    function _runNextAssetMove() {
        var moves = assetMoveProc.pendingMoves || [];
        var idx = assetMoveProc.pendingIndex;
        if (idx >= moves.length) {
            var key = assetMoveProc.pendingKey;
            var rewrites = assetMoveProc.pendingRewrites || [];
            var body = assetMoveProc.pendingBody || "";
            assetMoveProc.pendingMoves = [];
            assetMoveProc.pendingRewrites = [];
            if (rewrites.length > 0) {
                var res = FolderNotes.rewriteAssetLinks(body, rewrites);
                if (res.moved > 0) {
                    root.queueSave(key, { content: res.body });
                    root.flushPendingSave();
                }
            }
            var doneCb = assetMoveProc.pendingDoneCb;
            assetMoveProc.pendingDoneCb = null;
            if (typeof doneCb === "function") doneCb();
            return;
        }
        var m = moves[idx];
        assetMoveProc.pendingIndex = idx + 1;
        var mvArgs = m.shared ? ["cp", "-n", "--", m.src, m.dst] : ["mv", "-n", "--", m.src, m.dst];
        if (!root.pathsOk("assetMove", mvArgs)) {
            root._runNextAssetMove();
            return;
        }
        assetMoveProc.command = mvArgs;
        assetMoveProc.running = true;
    }

    function _onAssetMoveDone(exitCode) {
        var moves = assetMoveProc.pendingMoves || [];
        var idx = assetMoveProc.pendingIndex - 1;
        var m = (idx >= 0 && idx < moves.length) ? moves[idx] : null;
        if (m && exitCode === 0) {
            var rw = assetMoveProc.pendingRewrites || [];
            rw.push({ from: m.ref, to: m.newRel });
            assetMoveProc.pendingRewrites = rw;
        }
        root._runNextAssetMove();
    }

    // Copia un archivo local a assets/ de la nota (ya promovida) con nombre
    // único img_fecha[_n].ext (nunca pisa) y lo registra en la caché.
    function _uniqueImageName(dirAbs, ext) {
        var d = new Date();
        var pad = function(n) { return n < 10 ? "0" + n : "" + n; };
        var cleanExt = String(ext || "png").replace(/[^a-z0-9]/gi, "") || "png";
        var base = "img_" + d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate()) + "_" + pad(d.getHours()) + pad(d.getMinutes()) + pad(d.getSeconds());
        var cand = base + "." + cleanExt;
        if (!root.imageExistsCached(dirAbs + "/" + cand)) return cand;
        for (var i = 2; i < 50; i++) {
            var c = base + "_" + i + "." + cleanExt;
            if (!root.imageExistsCached(dirAbs + "/" + c)) return c;
        }
        return base + "_" + Date.now() + "." + cleanExt;
    }

    function _copyImageToNote(key, srcFile, cb) {
        var note = root._notesDict[key];
        var callback = (typeof cb === "function") ? cb : null;
        if (!note || !srcFile) {
            if (callback) callback(null, "invalid_note");
            return;
        }
        var baseDir = root.resolveNoteBaseDir(note);
        note.baseFolder = baseDir;
        var dirAbs = baseDir + "/assets";
        var dot = srcFile.lastIndexOf(".");
        var ext = dot !== -1 ? srcFile.substring(dot + 1) : "png";
        var imgName = root._uniqueImageName(dirAbs, ext);
        var dstAbs = dirAbs + "/" + imgName;
        var relTag = "assets/" + imgName;
        imageCopyProc.pendingKey = key;
        imageCopyProc.pendingRelTag = relTag;
        imageCopyProc.pendingCb = callback;
        var cpArgs = ["sh", "-c", 'mkdir -p "$1" && cp -- "$2" "$3"', "_", dirAbs, srcFile, dstAbs];
        if (root.pathsOk("imageCopy", cpArgs)) {
            imageCopyProc.command = cpArgs;
            imageCopyProc.running = true;
        } else if (callback) {
            callback(null, "invalid_source");
        }
    }

    function _onImageCopyDone(exitCode) {
        var key = imageCopyProc.pendingKey;
        var tag = imageCopyProc.pendingRelTag;
        var cb = imageCopyProc.pendingCb;
        imageCopyProc.pendingKey = "";
        imageCopyProc.pendingRelTag = "";
        imageCopyProc.pendingCb = null;
        if (exitCode !== 0 || !tag) {
            console.warn("[NotesService] Copia de imagen falló para:", key);
            if (typeof cb === "function") cb(null, "copy_failed");
            return;
        }
        var note = root._notesDict[key];
        if (note) {
            root.registerImagePath(root.resolveNoteBaseDir(note) + "/" + tag);
        }
        if (typeof cb === "function") cb(tag, null, key);
    }

    function openNoteBySlug(slug) {
        // Acepta clave o slug plano (.md primero, luego .txt). Se mantiene por
        // compatibilidad (wikilinks en BlockEditor).
        var found = root.getNote(slug);
        if (found) {
            openNote(found);
            return;
        }
        var cs = root._canonSlug(slug);
        for (var i = 0; i < root.notes.length; i++) {
            if (root._canonSlug(root.notes[i].slug) === cs || root._canonSlug(root.notes[i].id) === cs) {
                openNote(root.notes[i]);
                return;
            }
        }
    }

    // ── Conversión .txt → .md ──────────────────────────────────────────
    // Mueve el archivo conservando el contenido tal cual, por el pipeline propio
    // (no un mv suelto): actualiza dict, hashes, watchers y la nota activa EN EL
    // LUGAR (mismo objeto) para que el editor no recargue y conserve cursor.
    Timer {
        id: convertWaitTimer
        interval: 150
        repeat: false
        property string pendingKey: ""
        property var pendingCb: null
        onTriggered: {
            if (root._isWriting || root._saveQueue.length > 0 || renameProc.running) {
                convertWaitTimer.restart();
                return;
            }
            var k = convertWaitTimer.pendingKey;
            var cb = convertWaitTimer.pendingCb;
            convertWaitTimer.pendingKey = "";
            convertWaitTimer.pendingCb = null;
            root._doConvertTxtToMd(k, cb);
        }
    }

    Process {
        id: convertProc
        property string pendingOldKey: ""
        property string pendingNewKey: ""
        property string pendingNewFileName: ""
        property string pendingNewPath: ""
        property var pendingCallback: null
        running: false
        onExited: exitCode => root._onConvertDone(exitCode)
        Component.onDestruction: { running = false; }
    }

    function convertTxtToMd(slug, callback) {
        var key = root._resolveSaveKey(slug);
        root.flushPendingSave();
        // Esperar escrituras y renombrados en vuelo: el mv no debe correr con
        // un guardado a la ruta vieja pendiente (recrearía el .txt)
        if (root._isWriting || root._saveQueue.length > 0 || renameProc.running) {
            convertWaitTimer.pendingKey = key;
            convertWaitTimer.pendingCb = (typeof callback === "function") ? callback : null;
            convertWaitTimer.restart();
            return;
        }
        root._doConvertTxtToMd(key, callback);
    }

    function _doConvertTxtToMd(key, callback) {
        key = root._resolveSaveKey(key);
        if (root._extOfKey(key) !== "txt") {
            if (typeof callback === "function") callback(key, false);
            return;
        }
        if (convertProc.running) {
            if (typeof callback === "function") callback(key, false);
            return;
        }
        var note = root._notesDict[key];
        if (!note || !note.filePath) {
            if (typeof callback === "function") callback(key, false);
            return;
        }
        var body = (note.body !== undefined && note.body !== null) ? note.body : (note.content || "");
        var slash = note.filePath.lastIndexOf("/");
        var dir = slash !== -1 ? note.filePath.substring(0, slash) : root.notesDir;
        // Nombre relativo único dentro de su carpeta (F19: vale en subcarpetas)
        var oldBase = note.fileName.indexOf("/") !== -1 ? note.fileName.substring(note.fileName.lastIndexOf("/") + 1) : note.fileName;
        var dirRel = FolderNotes.parentDir(note.fileName);
        var candBase = ImportLogic.replaceExtension(oldBase, "md");
        var candRel = dirRel === "" ? candBase : (dirRel + "/" + candBase);
        var uniqueRel = ImportLogic.uniqueFileName(candRel, root._importExistingLower());
        var newFileName = uniqueRel.indexOf("/") !== -1 ? uniqueRel.substring(uniqueRel.lastIndexOf("/") + 1) : uniqueRel;
        var newPath = dir + "/" + newFileName;
        var newKey = root._dictKey(FolderNotes.slugForPath(uniqueRel), "md");
        convertProc.pendingOldKey = key;
        convertProc.pendingNewKey = newKey;
        convertProc.pendingNewFileName = uniqueRel;
        convertProc.pendingNewPath = newPath;
        convertProc.pendingCallback = (typeof callback === "function") ? callback : null;
        // El contenido ya está guardado (flush) y verificado en dict: mv -n directo
        var cvArgs = ["sh", "-c", '[ ! -e "$2" ] && mv -- "$1" "$2"', "_", note.filePath, newPath];
        if (root.pathsOk("convert", cvArgs)) {
            convertProc.command = cvArgs;
            convertProc.running = true;
        } else if (typeof callback === "function") {
            callback(key, false);
        }
    }

    function _onConvertDone(exitCode) {
        var oldKey = convertProc.pendingOldKey;
        var newKey = convertProc.pendingNewKey;
        var newFileName = convertProc.pendingNewFileName;
        var newPath = convertProc.pendingNewPath;
        var cb = convertProc.pendingCallback;
        convertProc.pendingOldKey = "";
        convertProc.pendingNewKey = "";
        convertProc.pendingNewFileName = "";
        convertProc.pendingNewPath = "";
        convertProc.pendingCallback = null;
        if (exitCode !== 0) {
            console.warn("[NotesService - convertTxtToMd] Falló la conversión, código:", exitCode);
            if (typeof cb === "function") cb(oldKey, false);
            return;
        }
        var existing = root._notesDict[oldKey];
        if (!existing || !newFileName) {
            if (typeof cb === "function") cb(oldKey, false);
            return;
        }
        var body = (existing.body !== undefined && existing.body !== null) ? existing.body : (existing.content || "");
        var newSlug = root._slugOfKey(newKey);
        // Reparsear como .md con el mismo contenido (sin inyectar frontmatter)
        var rebuilt = MD.parseNote(newFileName, newPath, false, body);
        rebuilt.slug = newSlug;
        rebuilt.id = newSlug;
        rebuilt.key = newKey;
        rebuilt.isFolderNote = FolderNotes.isFolderNotePath(newFileName);
        rebuilt.baseFolder = root.resolveNoteBaseDir(rebuilt);
        rebuilt.title = existing.title;
        rebuilt.pinned = !!existing.pinned;
        rebuilt.created = existing.created || rebuilt.created;
        rebuilt.fileModified = new Date().toISOString().replace("T", " ").substring(0, 19);
        if (!rebuilt.modified) rebuilt.modified = rebuilt.fileModified;
        delete root._notesDict[oldKey];
        delete root._lastContentHash[oldKey];
        delete root._deletingKeys[oldKey];
        root._dropFailedFor(oldKey);
        root._notesDict[newKey] = rebuilt;
        root._lastContentHash[newKey] = _contentHash(MD.serializeNote(rebuilt, body));
        root._markWritingSlug(newKey, 1200);
        if (root.activeNote && (root.activeNote.key === oldKey || (!root.activeNote.key && root._canonSlug(root.activeNote.slug) === root._slugOfKey(oldKey)))) {
            // Solo identidad: el cuerpo del editor se conserva tal cual (el .txt
            // puede empezar con "---" y el parse md lo recortaría de la vista).
            // El dict ya tiene la entrada parseada para grilla/búsqueda.
            var updatedActive = Object.assign({}, root.activeNote);
            updatedActive.key = newKey;
            updatedActive.slug = newSlug;
            updatedActive.id = newSlug;
            updatedActive.format = "md";
            updatedActive.fileName = newFileName;
            updatedActive.filePath = newPath;
            root.activeNote = updatedActive;
            root._notesDict[newKey] = updatedActive;
        }
        root.filesVersion++;
        if (!fileScannerProc.running) fileScannerProc.running = true;
        root._rebuildNotes();
        if (typeof cb === "function") cb(newKey, true);
    }

    // ── Chequeo y gestión de dependencias ──────────────────────────────
    property bool depsChecked: false
    property bool docxDepsOk: false
    property var missingDeps: []
    property bool depsInstalling: false
    property string depsInstallError: ""
    signal depsCheckedFinished(bool ok)
    signal depsInstalled(bool success)

    Process {
        id: depsCheckProc
        running: false
        property string outText: ""
        command: [
            "python3", "-B", "-c",
            "import sys; sys.dont_write_bytecode=True; missing=[];\n" +
            "try:\n    import docx\nexcept Exception:\n    missing.append('python-docx')\n" +
            "try:\n    import fitz\nexcept Exception:\n    missing.append('python-pymupdf')\n" +
            "try:\n    import openpyxl\nexcept Exception:\n    missing.append('python-openpyxl')\n" +
            "print('MISSING:' + ','.join(missing))"
        ]
        stdout: SplitParser {
            onRead: (line) => {
                var l = line.trim();
                if (l.startsWith("MISSING:")) {
                    depsCheckProc.outText = l.substring(8).trim();
                }
            }
        }
        onExited: (exitCode) => {
            root.depsChecked = true;
            if (exitCode !== 0) {
                root.docxDepsOk = false;
                root.missingDeps = ["python-docx", "python-pymupdf", "python-openpyxl"];
            } else {
                var miss = depsCheckProc.outText ? depsCheckProc.outText.split(",") : [];
                root.missingDeps = miss.filter(function(x) { return x.trim() !== ""; });
                root.docxDepsOk = (root.missingDeps.indexOf("python-docx") === -1);
            }
            root.depsCheckedFinished(root.docxDepsOk);
        }
        Component.onDestruction: { running = false; }
    }

    function checkDeps() {
        if (depsCheckProc.running) return;
        depsCheckProc.outText = "";
        depsCheckProc.running = true;
    }

    function missingDepsFor(items) {
        var needed = ImportLogic.depsForItems(items);
        var missing = [];
        for (var i = 0; i < needed.length; i++) {
            if (root.missingDeps.indexOf(needed[i]) !== -1) {
                missing.push(needed[i]);
            }
        }
        return missing;
    }

    function hasDepForExt(ext) {
        var dep = ImportLogic.getDepForExt(ext);
        if (!dep) return true;
        return root.missingDeps.indexOf(dep) === -1;
    }

    Process {
        id: depsInstallProc
        running: false
        onExited: (exitCode) => {
            root.depsInstalling = false;
            if (exitCode === 0) {
                root.depsInstallError = "";
                root.checkDeps();
                root.depsInstalled(true);
            } else {
                root.depsInstallError = "Falló la instalación (código " + exitCode + ")";
                root.depsInstalled(false);
            }
        }
        Component.onDestruction: { running = false; }
    }

    function installMissingDeps(pkgs) {
        if (root.depsInstalling) return;
        root.depsInstalling = true;
        root.depsInstallError = "";
        var toInstall = (pkgs && pkgs.length > 0) ? pkgs : root.missingDeps;
        if (!toInstall || toInstall.length === 0) toInstall = ["python-docx"];
        var pkArgs = ["pkexec", "pacman", "-S", "--needed", "--noconfirm"].concat(toInstall);
        depsInstallProc.command = pkArgs;
        depsInstallProc.running = true;
    }

    // ── Conversor universal de documentos a .md ────────────────────────
    property bool docxConverting: false
    property real docxConversionProgress: 0.0
    property string docxCurrentFile: ""
    property string _docxLastResult: ""
    property var _docxQueue: []
    property var _docxCurrentItem: null
    property var _docxCallback: null
    property string _docxMode: "copy"
    signal docxConverted(string filePath, bool success)

    function _resolveConverterScript(scriptName) {
        var sName = scriptName || "doc-to-md.py";
        var sd = Quickshell.shellDir ? Quickshell.shellDir.toString().replace("file://", "") : "";
        if (sd.endsWith("/notes")) return sd + "/scripts/" + sName;
        if (sd !== "") return sd + "/notes/scripts/" + sName;
        return (Quickshell.env("HOME") || "") + "/.config/quickshell/notes/scripts/" + sName;
    }

    function _resolveDocxScriptPath() {
        return _resolveConverterScript("docx-to-md.py");
    }

    Process {
        id: docxConvertProc
        running: false
        property string missingDepError: ""
        stdout: SplitParser {
            onRead: (line) => {
                var l = line.trim();
                if (l.startsWith("PROGRESS:")) {
                    var p = parseFloat(l.substring(9));
                    if (!isNaN(p)) root.docxConversionProgress = Math.max(0, Math.min(1, p));
                } else if (l.startsWith("RESULT:")) {
                    root._docxLastResult = l.substring(7).trim();
                }
            }
        }
        stderr: SplitParser {
            onRead: (line) => {
                var l = line.trim();
                if (l.startsWith("MISSING_DEP:")) {
                    docxConvertProc.missingDepError = l.substring(12).trim();
                }
            }
        }
        onExited: (exitCode) => {
            var res = root._docxLastResult;
            var cb = root._docxCallback;
            var ok = (exitCode === 0 && res !== "");

            if (ok) {
                root.runImageProbe();
                if (!fileScannerProc.running) fileScannerProc.running = true;
                root.docxConverted(res, true);
            } else {
                console.warn("[NotesService] Conversión de documento falló con código:", exitCode, docxConvertProc.missingDepError);
                root.docxConverted("", false);
            }

            if (root._docxQueue.length > 0) {
                root._processNextDocx();
            } else {
                root.docxConverting = false;
                root.docxConversionProgress = 1.0;
                root.docxCurrentFile = "";
                root._docxCurrentItem = null;
                root._docxCallback = null;
                if (typeof cb === "function") cb(res, ok);
            }
        }
        Component.onDestruction: { running = false; }
    }

    function convertDocuments(items, mode, callback) {
        if (!items || items.length === 0) return;
        root._docxMode = mode || NotesConfig.effectiveImportMode();
        root._docxQueue = items.slice(0);
        root._docxCallback = (typeof callback === "function") ? callback : null;
        root.docxConverting = true;
        root.docxConversionProgress = 0.0;
        root._processNextDocx();
    }

    function convertDocx(docxItems, mode, callback) {
        convertDocuments(docxItems, mode, callback);
    }

    function _processNextDocx() {
        if (root._docxQueue.length === 0) return;
        var item = root._docxQueue.shift();
        root._docxCurrentItem = item;
        root._docxLastResult = "";
        docxConvertProc.missingDepError = "";
        root.docxConversionProgress = 0.0;
        root.docxCurrentFile = ImportLogic.baseName(item.localPath);

        var ext = item.ext || ImportLogic.getExtension(item.localPath);
        var scriptName = ImportLogic.getScriptForExt(ext);

        var args = [
            "python3", "-B",
            root._resolveConverterScript(scriptName),
            "--input", item.localPath,
            "--notes-dir", root.notesDir,
            "--mode", root._docxMode
        ];
        docxConvertProc.command = args;
        docxConvertProc.running = true;
    }

    // ── Conexión reactiva a configuración ─────────────────────────────────
    Connections {
        target: NotesConfig
        function onNotesDirChanged() {
            ensureDirProc.running = true;
        }
    }

    Component.onCompleted: {
        ensureDirProc.running = true;
        stateDirProc.command = ["mkdir", "-p", root.statePath.substring(0, root.statePath.lastIndexOf("/"))];
        stateDirProc.running = true;
        imageProbeDebounce.restart();
    }

    Component.onDestruction: {
        root.prepareToQuit();
    }
}
