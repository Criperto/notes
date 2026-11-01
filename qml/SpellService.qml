pragma Singleton
import QtQuick
import Notas
import "SpellLogic.js" as SpellLogic

QtObject {
    id: root

    property int cacheRevision: 0
    readonly property bool available: SpellBackend.availableDictionaries.length > 0
    readonly property var availableDictionaries: SpellBackend.availableDictionaries
    readonly property var personalWords: SpellBackend.personalWords

    // Idiomas activos
    readonly property string primaryLanguage: {
        var p = (typeof ConfigBackend !== "undefined" && ConfigBackend.primarySpellLanguage) ? ConfigBackend.primarySpellLanguage : "";
        if (!p && typeof ConfigBackend !== "undefined" && ConfigBackend.spellCheckLanguage) p = ConfigBackend.spellCheckLanguage;
        return p || "es";
    }

    readonly property var disabledLanguages: (typeof ConfigBackend !== "undefined" && ConfigBackend.disabledSpellLanguages) ? ConfigBackend.disabledSpellLanguages : []

    readonly property var activeLanguages: {
        var avail = availableDictionaries || [];
        var dis = disabledLanguages || [];
        return avail.filter(function(code) {
            return dis.indexOf(code) === -1;
        });
    }

    property var _ignoredWords: ({})

    signal personalWordAdded(string word)
    signal personalWordsCleared()

    function refreshDictionaries() {
        if (typeof SpellBackend !== "undefined" && typeof SpellBackend.refreshDictionaries === "function") {
            SpellBackend.refreshDictionaries();
        }
        root.cacheRevision++;
    }

    function checkWordsBatch(words, callback) {
        if (!words || words.length === 0 || !available) {
            if (typeof callback === "function") callback({});
            return;
        }

        var ignoreUpper = (typeof ConfigBackend !== "undefined" && ConfigBackend.ignoreUppercase);
        var ignoreDigits = (typeof ConfigBackend !== "undefined" && ConfigBackend.ignoreWithDigits);

        var wordsToCheck = [];
        var results = {};

        for (var i = 0; i < words.length; i++) {
            var w = words[i];
            if (!w) continue;

            // Filtros rápidos
            if (_ignoredWords[w.toLowerCase()]) {
                results[w] = { ok: true };
                continue;
            }
            if (ignoreUpper && w.length > 1 && w === w.toUpperCase()) {
                results[w] = { ok: true };
                continue;
            }
            if (ignoreDigits && /\d/.test(w)) {
                results[w] = { ok: true };
                continue;
            }

            wordsToCheck.push(w);
        }

        if (wordsToCheck.length === 0) {
            if (typeof callback === "function") callback(results);
            return;
        }

        var lang = primaryLanguage || "es_ES";
        var rawRes = SpellBackend.checkWords(lang, wordsToCheck);

        for (var j = 0; j < wordsToCheck.length; j++) {
            var checkW = wordsToCheck[j];
            if (rawRes && rawRes[checkW] && rawRes[checkW].valid === false) {
                results[checkW] = {
                    ok: false,
                    suggestions: rawRes[checkW].suggestions || [],
                    lang: lang
                };
            } else {
                results[checkW] = { ok: true };
            }
        }

        if (typeof callback === "function") {
            callback(results);
        }
    }

    function suggestions(word, lang, maxCount) {
        if (!word || !available) return [];
        var l = lang || primaryLanguage;
        var res = SpellBackend.checkWords(l, [word]);
        if (res && res[word] && Array.isArray(res[word].suggestions)) {
            var arr = res[word].suggestions;
            return (maxCount && maxCount > 0) ? arr.slice(0, maxCount) : arr;
        }
        return [];
    }

    function ignoreWord(word) {
        if (!word) return;
        var clean = word.trim().toLowerCase();
        if (!_ignoredWords[clean]) {
            _ignoredWords[clean] = true;
            root.cacheRevision++;
        }
    }

    function addToDictionary(word) {
        if (!word) return;
        SpellBackend.addPersonalWord(word);
        root.cacheRevision++;
        root.personalWordAdded(word);
    }

    function removePersonalWord(word) {
        if (!word) return;
        if (typeof SpellBackend.removePersonalWord === "function") {
            SpellBackend.removePersonalWord(word);
        }
        root.cacheRevision++;
    }

    function clearPersonalWords() {
        if (typeof SpellBackend.clearPersonalWords === "function") {
            SpellBackend.clearPersonalWords();
        }
        root.cacheRevision++;
        root.personalWordsCleared();
    }

    property var _spellConn: Connections {
        target: (typeof SpellBackend !== "undefined") ? SpellBackend : null
        function onAvailableDictionariesChanged() {
            root.cacheRevision++;
        }
        function onPersonalWordsChanged() {
            root.cacheRevision++;
        }
    }

    property var _cfgConn: Connections {
        target: (typeof ConfigBackend !== "undefined") ? ConfigBackend : null
        function onPrimarySpellLanguageChanged() {
            root.cacheRevision++;
        }
        function onDisabledSpellLanguagesChanged() {
            root.cacheRevision++;
        }
        function onSpellcheckModeChanged() {
            root.cacheRevision++;
        }
        function onIgnoreUppercaseChanged() {
            root.cacheRevision++;
        }
        function onIgnoreWithDigitsChanged() {
            root.cacheRevision++;
        }
    }
}
