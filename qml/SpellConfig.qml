pragma Singleton
import QtQuick
import Notas

QtObject {
    id: root

    property bool enabled: (typeof ConfigBackend !== "undefined") ? ConfigBackend.spellCheckEnabled : true
    property string mode: (typeof ConfigBackend !== "undefined") ? ConfigBackend.spellcheckMode : "auto"
    property string language: (typeof ConfigBackend !== "undefined" && ConfigBackend.primarySpellLanguage) ? ConfigBackend.primarySpellLanguage : "es"
    property bool ignoreUppercase: (typeof ConfigBackend !== "undefined") ? ConfigBackend.ignoreUppercase : true
    property bool ignoreWithDigits: (typeof ConfigBackend !== "undefined") ? ConfigBackend.ignoreWithDigits : true
    property var disabledLanguages: (typeof ConfigBackend !== "undefined") ? ConfigBackend.disabledSpellLanguages : []
}
