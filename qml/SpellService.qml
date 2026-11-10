pragma Singleton
import QtQuick
import Notas
import "SpellLogic.js" as SpellLogic
import "LangDetect.js" as LangDetect

QtObject {
    id: root

    property bool available: false
    property var installedDicts: []
    property var installedLanguages: []
    property int cacheRevision: 0

    readonly property var personalWords: (typeof SpellBackend !== "undefined") ? SpellBackend.personalWords : []

    readonly property string notasBin: (typeof Sys !== "undefined" && Sys.appExecutable) ? Sys.appExecutable : "criperto-notes"
    readonly property string dictsDir: ((typeof Sys !== "undefined" && Sys.homeDir) ? Sys.homeDir : "") + "/.local/share/criperto.notes/dictionaries"
    readonly property string dictsStampPath: dictsDir + "/.dicts_stamp"
    readonly property string personalDictPath: ((typeof Sys !== "undefined" && Sys.homeDir) ? Sys.homeDir : "") + "/.config/notas/personal.dic"

    signal personalWordAdded(string word)
    signal personalWordsCleared()

    // Vigilancia reactiva de cambios en diccionarios instalados/eliminados
    property var _dictsStampWatcher: FileView {
        id: dictsStampWatcher
        path: root.dictsStampPath
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: {
            root.refreshDicts();
        }
    }

    // ── Cache de palabras y sesión ───────────────────────────────────────
    property var _wordCache: ({})
    property var _sessionIgnored: ({})
    property bool _pendingRefresh: false
    property var _activeBatches: []
    property int _batchSeq: 0

    function cancelOwner(owner) {
        if (!owner) return;
        var remaining = [];
        for (var i = 0; i < root._activeBatches.length; i++) {
            var b = root._activeBatches[i];
            if (b && b.owner === owner) {
                b.cancelled = true;
                b.callback = null;
            } else if (b && !b.cancelled && b.callback) {
                remaining.push(b);
            }
        }
        root._activeBatches = remaining;
    }

    function cancelAll() {
        for (var i = 0; i < root._activeBatches.length; i++) {
            var b = root._activeBatches[i];
            if (b) {
                b.cancelled = true;
                b.callback = null;
            }
        }
        root._activeBatches = [];
    }

    function _isOwnerValid(owner) {
        if (!owner) return false;
        try {
            if (owner._isDestroyed) return false;
            return true;
        } catch (e) {
            return false;
        }
    }

    // ── Detección de diccionarios instalados ──────────────────────────────
    property var _listDictsProc: Process {
        id: listDictsProc
        command: [root.notasBin, "spell", "list"]
        running: false
        stdout: StdioCollector {
            id: listDictsCollector
            onStreamFinished: {
                try {
                    var data = JSON.parse(listDictsCollector.text);
                    if (Array.isArray(data)) {
                        root.installedDicts = data;
                        var langs = [];
                        for (var i = 0; i < data.length; i++) {
                            if (data[i].installed && data[i].code) {
                                langs.push(data[i].code);
                            }
                        }
                        root.installedLanguages = langs;
                        root._updateHunspellProcess();
                    }
                } catch (e) {
                    console.warn("[SpellService] Error listando diccionarios:", e);
                }
                if (root._pendingRefresh) {
                    root._pendingRefresh = false;
                    Qt.callLater(function() { root.refreshDicts(); });
                }
            }
        }
        Component.onDestruction: { running = false; }
    }

    function refreshDicts() {
        if (typeof SpellBackend !== "undefined" && typeof SpellBackend.refreshDictionaries === "function") {
            SpellBackend.refreshDictionaries();
        }
        if (listDictsProc.running) {
            root._pendingRefresh = true;
            return;
        }
        listDictsProc.running = true;
    }

    function refreshDictionaries() {
        refreshDicts();
    }

    Component.onCompleted: {
        refreshDicts();
    }

    Component.onDestruction: {
        for (var i = 0; i < hunspellWorkers.count; i++) {
            var w = hunspellWorkers.objectAt(i);
            if (w && typeof w.stopProcess === "function") {
                w.stopProcess();
            }
        }
    }

    // ── Gestión de los workers Hunspell persistentes ──────────────────────
    property var _activeEffectiveLangs: []
    property var _pendingWordQueries: []

    property var _spellConfigConn: Connections {
        target: (typeof SpellConfig !== "undefined") ? SpellConfig : null
        function onEffectiveLanguagesChanged() {
            root._updateHunspellProcess();
        }
        function onEnabledChanged() {
            root._updateHunspellProcess();
        }
        function onPrimaryLanguageChanged() {
            root._updateHunspellProcess();
        }
        function onIgnoreUppercaseChanged() {
            root.cacheRevision++;
        }
        function onIgnoreWithDigitsChanged() {
            root.cacheRevision++;
        }
    }

    function _resolveSingleDictPath(code) {
        if (!code) return "";
        for (var j = 0; j < root.installedDicts.length; j++) {
            if (root.installedDicts[j].code === code && root.installedDicts[j].installed) {
                return root.installedDicts[j].path;
            }
        }
        return root.dictsDir + "/" + code;
    }

    function _resolveDictPaths(langs) {
        if (!Array.isArray(langs) || langs.length === 0) return "";
        var paths = [];
        for (var i = 0; i < langs.length; i++) {
            paths.push(_resolveSingleDictPath(langs[i]));
        }
        return paths.join(",");
    }

    function getEffectiveLanguages() {
        var sys = (typeof SpellConfig !== "undefined" && SpellConfig.systemLocale) ? SpellConfig.systemLocale : "es_AR";
        var dis = (typeof SpellConfig !== "undefined" && SpellConfig.disabledLanguages) ? SpellConfig.disabledLanguages : "";
        var prim = (typeof SpellConfig !== "undefined" && SpellConfig.primaryLanguage) ? SpellConfig.primaryLanguage : "";
        return SpellLogic.resolveEffectiveLanguages(sys, {
            disabledLanguages: dis,
            primaryLanguage: prim
        }, root.installedLanguages);
    }

    function _updateHunspellProcess() {
        if (typeof SpellConfig !== "undefined" && !SpellConfig.enabled) {
            root._activeEffectiveLangs = [];
            root.available = false;
            return;
        }

        var langs = root.getEffectiveLanguages();
        if (JSON.stringify(root._activeEffectiveLangs) !== JSON.stringify(langs)) {
            root._activeEffectiveLangs = langs;
            root._wordCache = {};
            root.cacheRevision++;
        }
        root.available = (langs.length > 0);

        if (root.available && root._pendingWordQueries.length > 0) {
            Qt.callLater(function() {
                var pending = root._pendingWordQueries.slice();
                root._pendingWordQueries = [];
                for (var p = 0; p < pending.length; p++) {
                    root.checkWord(pending[p].word, pending[p].callback);
                }
            });
        }
    }

    function _restartWorkers() {
        root._wordCache = {};
        root.cacheRevision++;
        var savedLangs = root._activeEffectiveLangs ? root._activeEffectiveLangs.slice() : [];
        root._activeEffectiveLangs = [];
        Qt.callLater(function() {
            root._activeEffectiveLangs = savedLangs;
        });
    }

    property var _hunspellWorkers: Instantiator {
        id: hunspellWorkers
        model: root._activeEffectiveLangs
        delegate: Item {
            id: workerItem
            required property string modelData
            required property int index

            readonly property string langCode: modelData
            readonly property string dictPath: root._resolveSingleDictPath(modelData)
            property bool ready: false

            property var queue: []
            property var currentQuery: null

            function stopProcess() {
                if (proc.running) {
                    proc.running = false;
                }
            }

            Process {
                id: proc
                command: [
                    "hunspell", "-a",
                    "-d", workerItem.dictPath,
                    "-p", root.personalDictPath
                ]
                running: workerItem.dictPath !== "" && (typeof SpellConfig === "undefined" || SpellConfig.enabled)
                stdinEnabled: true

                onStarted: {
                    workerItem.ready = true;
                    workerItem.pump();
                }

                onExited: {
                    workerItem.ready = false;
                    workerItem.currentQuery = null;
                    workerWatchdog.stop();
                }

                stdout: SplitParser {
                    splitMarker: "\n\n"
                    onRead: (chunk) => {
                        if (!chunk || !workerItem.currentQuery) return;
                        var parsed = SpellLogic.parseHunspellResponse(chunk);
                        var res = parsed.length > 0 ? parsed[0] : { ok: true, suggestions: [] };
                        var q = workerItem.currentQuery;
                        workerItem.currentQuery = null;
                        workerWatchdog.stop();
                        if (q && !q.cancelled && typeof q.callback === "function") {
                            try {
                                q.callback(res);
                            } catch (e) {
                                var msg = (e && e.message) ? String(e.message) : String(e);
                                if (msg.indexOf("null") === -1 && msg.indexOf("context") === -1) {
                                    console.warn("[SpellService] Error en callback de worker:", e);
                                }
                            }
                        }
                        workerItem.pump();
                    }
                }

                stderr: SplitParser {
                    onRead: (line) => {
                        console.warn("[SpellService worker stderr]", workerItem.langCode, line);
                    }
                }
            }

            Timer {
                id: workerWatchdog
                interval: 3500
                repeat: false
                onTriggered: {
                    if (workerItem.currentQuery) {
                        console.warn("[SpellService] Watchdog timeout en worker", workerItem.langCode, workerItem.currentQuery.word);
                        var q = workerItem.currentQuery;
                        workerItem.currentQuery = null;
                        if (q && !q.cancelled && typeof q.callback === "function") {
                            try {
                                q.callback({ ok: true, suggestions: [] });
                            } catch (e) {
                                console.warn("[SpellService] Error en callback de fallback de watchdog:", e);
                            }
                        }
                    }
                    if (proc.running) {
                        proc.running = false;
                        Qt.callLater(function() {
                            if (workerItem.dictPath !== "") proc.running = true;
                        });
                    }
                }
            }

            function query(word, cb) {
                queue.push({ word: word, callback: cb });
                pump();
            }

            function pump() {
                if (!ready || !proc.running || currentQuery !== null || queue.length === 0) return;
                currentQuery = queue.shift();
                workerWatchdog.restart();
                try {
                    proc.write("^" + currentQuery.word + "\n");
                } catch (e) {
                    console.warn("[SpellService] Error al escribir en stdin de hunspell worker:", e);
                    workerWatchdog.stop();
                    currentQuery = null;
                    pump();
                }
            }

            Component.onDestruction: {
                stopProcess();
            }
        }
    }

    // ── API Pública ──────────────────────────────────────────────────────

    function checkWord(word, callback, targetLangs) {
        if (!word || typeof word !== "string") {
            if (typeof callback === "function") callback({ ok: true, suggestions: [] });
            return;
        }

        var w = word.trim();
        if (w === "" || root._sessionIgnored[w] === true) {
            if (typeof callback === "function") callback({ ok: true, suggestions: [] });
            return;
        }

        var langsToCheck = (Array.isArray(targetLangs) && targetLangs.length > 0) ? targetLangs : null;
        var langKey = langsToCheck ? langsToCheck.join(",") : "all";
        var cacheKey = langKey + ":" + w;

        if (root._wordCache[cacheKey] !== undefined) {
            if (typeof callback === "function") callback(root._wordCache[cacheKey]);
            return;
        }

        if (typeof SpellConfig !== "undefined" && !SpellConfig.enabled) {
            if (typeof callback === "function") callback({ ok: true, suggestions: [] });
            return;
        }

        var count = hunspellWorkers.count;
        if (count === 0) {
            if (listDictsProc.running) {
                root._pendingWordQueries.push({ word: w, callback: callback });
                return;
            }
            if (typeof callback === "function") callback({ ok: true, suggestions: [] });
            return;
        }

        var activeWorkers = [];
        for (var idx = 0; idx < count; idx++) {
            var workerObj = hunspellWorkers.objectAt(idx);
            if (workerObj && (!langsToCheck || langsToCheck.indexOf(workerObj.langCode) !== -1)) {
                activeWorkers.push(workerObj);
            }
        }

        // Si se filtraron diccionarios y ninguno coincide en el trabajador, fallback a todos los trabajadores
        if (activeWorkers.length === 0) {
            for (var fIdx = 0; fIdx < count; fIdx++) {
                var wObj = hunspellWorkers.objectAt(fIdx);
                if (wObj) activeWorkers.push(wObj);
            }
        }

        if (activeWorkers.length === 0) {
            if (typeof callback === "function") callback({ ok: true, suggestions: [] });
            return;
        }

        var resultsByLang = {};
        var pending = activeWorkers.length;

        var onAllFinished = function() {
            var anyOk = false;
            for (var c in resultsByLang) {
                if (resultsByLang[c] && resultsByLang[c].ok) {
                    anyOk = true;
                    break;
                }
            }

            if (anyOk) {
                root._wordCache[cacheKey] = { ok: true, suggestions: [] };
            } else {
                var sugsMap = {};
                for (var code in resultsByLang) {
                    sugsMap[code] = (resultsByLang[code] && resultsByLang[code].suggestions) ? resultsByLang[code].suggestions : [];
                }
                var primaryLang = (langsToCheck && langsToCheck.length > 0) ? langsToCheck[0] : ((root._activeEffectiveLangs && root._activeEffectiveLangs.length > 0) ? root._activeEffectiveLangs[0] : "");
                var merged = SpellLogic.mergeMultiLangSuggestions(sugsMap, w, primaryLang);
                root._wordCache[cacheKey] = { ok: false, suggestions: merged };
            }

            if (typeof callback === "function") {
                callback(root._wordCache[cacheKey]);
            }
        };

        for (var i = 0; i < activeWorkers.length; i++) {
            var worker = activeWorkers[i];
            (function(wItem) {
                wItem.query(w, function(res) {
                    resultsByLang[wItem.langCode] = res;
                    pending--;
                    if (pending <= 0) {
                        onAllFinished();
                    }
                });
            })(worker);
        }

        if (pending <= 0) {
            onAllFinished();
        }
    }

    function checkWordsBatch(words, callback, owner, options) {
        if (!Array.isArray(words) || words.length === 0) {
            if (typeof callback === "function") callback({});
            return;
        }

        var uniqueWords = [];
        for (var i = 0; i < words.length; i++) {
            var w = words[i];
            if (w && uniqueWords.indexOf(w) === -1) {
                uniqueWords.push(w);
            }
        }

        if (uniqueWords.length === 0) {
            if (typeof callback === "function") callback({});
            return;
        }

        // Resolución de idioma de destino por párrafo
        var targetLangs = null;
        var autoDetect = (typeof SpellConfig === "undefined" || SpellConfig.autoDetectParagraphLanguage !== false);
        if (options) {
            if (Array.isArray(options.langs) && options.langs.length > 0) {
                targetLangs = options.langs;
            } else if (autoDetect && options.text) {
                var detected = LangDetect.detect(options.text);
                if (detected) {
                    targetLangs = SpellLogic.filterLanguagesByDetected(detected, root._activeEffectiveLangs);
                }
            } else if (options.lang) {
                targetLangs = SpellLogic.filterLanguagesByDetected(options.lang, root._activeEffectiveLangs);
            }
        }

        var langKey = (targetLangs && targetLangs.length > 0) ? targetLangs.join(",") : "all";

        var batch = {
            id: ++root._batchSeq,
            owner: owner || null,
            callback: callback,
            cancelled: false,
            results: {},
            pendingCount: 0
        };
        root._activeBatches.push(batch);

        var checkFinished = function() {
            if (batch.cancelled || !batch.callback) return;
            if (batch.pendingCount <= 0) {
                var cb = batch.callback;
                batch.callback = null;
                var bIdx = root._activeBatches.indexOf(batch);
                if (bIdx !== -1) root._activeBatches.splice(bIdx, 1);

                if (batch.owner && !root._isOwnerValid(batch.owner)) {
                    return;
                }
                if (typeof cb === "function") {
                    try {
                        cb(batch.results);
                    } catch (err) {
                        var msg = (err && err.message) ? String(err.message) : String(err);
                        if (msg.indexOf("null") === -1 && msg.indexOf("context") === -1) {
                            console.warn("[SpellService] Error en callback de batch:", err);
                        }
                    }
                }
            }
        };

        for (var j = 0; j < uniqueWords.length; j++) {
            (function(word) {
                if (root._sessionIgnored[word] === true) {
                    batch.results[word] = { ok: true, suggestions: [] };
                    return;
                }
                var cacheKey = langKey + ":" + word;
                if (root._wordCache[cacheKey] !== undefined) {
                    batch.results[word] = root._wordCache[cacheKey];
                    return;
                }

                batch.pendingCount++;
                root.checkWord(word, function(res) {
                    batch.results[word] = res;
                    batch.pendingCount--;
                    checkFinished();
                }, targetLangs);
            })(uniqueWords[j]);
        }

        if (batch.pendingCount === 0) {
            checkFinished();
        }
    }

    function ignoreWord(word) {
        if (!word) return;
        var w = word.trim();
        root._sessionIgnored[w] = true;
        for (var k in root._wordCache) {
            if (k.endsWith(":" + w) || k === w) {
                root._wordCache[k] = { ok: true, suggestions: [] };
            }
        }
        root.cacheRevision++;
    }

    function addToDictionary(word) {
        if (!word) return;
        var w = word.trim();
        if (!w) return;
        root._sessionIgnored[w] = true;
        for (var k in root._wordCache) {
            if (k.endsWith(":" + w) || k === w) {
                root._wordCache[k] = { ok: true, suggestions: [] };
            }
        }
        if (typeof SpellBackend !== "undefined" && typeof SpellBackend.addPersonalWord === "function") {
            SpellBackend.addPersonalWord(w);
        }
        root.personalWordAdded(w);
        root._restartWorkers();
    }

    function removePersonalWord(word) {
        if (!word) return;
        var w = word.trim();
        if (!w) return;
        delete root._sessionIgnored[w];
        if (typeof SpellBackend !== "undefined" && typeof SpellBackend.removePersonalWord === "function") {
            SpellBackend.removePersonalWord(w);
        }
        root._restartWorkers();
    }

    function clearPersonalWords() {
        root._sessionIgnored = ({});
        if (typeof SpellBackend !== "undefined" && typeof SpellBackend.clearPersonalWords === "function") {
            SpellBackend.clearPersonalWords();
        }
        root.personalWordsCleared();
        root._restartWorkers();
    }
}
