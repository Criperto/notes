pragma Singleton
import QtQuick
import Notas
import "SpellLogic.js" as SpellLogic

QtObject {
    id: root

    readonly property bool available: SpellBackend.availableDictionaries.length > 0
    readonly property var availableDictionaries: SpellBackend.availableDictionaries
    readonly property var personalWords: SpellBackend.personalWords

    signal personalWordAdded(string word)
    signal personalWordsCleared()

    function check(words, lang) {
        var l = lang || ConfigBackend.spellCheckLanguage;
        return SpellBackend.checkWords(l, words);
    }

    function addPersonalWord(word) {
        SpellBackend.addPersonalWord(word);
        personalWordAdded(word);
    }
}
