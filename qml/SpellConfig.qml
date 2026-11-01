pragma Singleton
import QtQuick
import Notas

QtObject {
    id: root
    property bool enabled: ConfigBackend.spellCheckEnabled
    property string language: ConfigBackend.spellCheckLanguage
}
