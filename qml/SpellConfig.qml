pragma Singleton
import QtQuick
import Notas
import "SpellLogic.js" as SpellLogic

QtObject {
    id: root

    property bool   enabled: (typeof ConfigBackend !== "undefined") ? ConfigBackend.spellCheckEnabled : true
    property string disabledLanguages: (typeof ConfigBackend !== "undefined") ? ConfigBackend.disabledSpellLanguages : ""
    property string primaryLanguage: (typeof ConfigBackend !== "undefined") ? ConfigBackend.primarySpellLanguage : ""
    property bool   ignoreUppercase: (typeof ConfigBackend !== "undefined") ? ConfigBackend.ignoreUppercase : true
    property bool   ignoreWithDigits: (typeof ConfigBackend !== "undefined") ? ConfigBackend.ignoreWithDigits : true
    property bool   ignoreCamelCase: true
    property bool   ignoreSnakeCase: true

    onEnabledChanged: {
        if (typeof ConfigBackend !== "undefined" && ConfigBackend.spellCheckEnabled !== enabled) {
            ConfigBackend.spellCheckEnabled = enabled;
        }
    }
    onDisabledLanguagesChanged: {
        if (typeof ConfigBackend !== "undefined" && ConfigBackend.disabledSpellLanguages !== disabledLanguages) {
            ConfigBackend.disabledSpellLanguages = disabledLanguages;
        }
    }
    onPrimaryLanguageChanged: {
        if (typeof ConfigBackend !== "undefined" && ConfigBackend.primarySpellLanguage !== primaryLanguage) {
            ConfigBackend.primarySpellLanguage = primaryLanguage;
        }
    }
    onIgnoreUppercaseChanged: {
        if (typeof ConfigBackend !== "undefined" && ConfigBackend.ignoreUppercase !== ignoreUppercase) {
            ConfigBackend.ignoreUppercase = ignoreUppercase;
        }
    }
    onIgnoreWithDigitsChanged: {
        if (typeof ConfigBackend !== "undefined" && ConfigBackend.ignoreWithDigits !== ignoreWithDigits) {
            ConfigBackend.ignoreWithDigits = ignoreWithDigits;
        }
    }

    property var _cfgSync: Connections {
        target: (typeof ConfigBackend !== "undefined") ? ConfigBackend : null
        function onSpellCheckEnabledChanged() {
            if (root.enabled !== ConfigBackend.spellCheckEnabled) root.enabled = ConfigBackend.spellCheckEnabled;
        }
        function onDisabledSpellLanguagesChanged() {
            if (root.disabledLanguages !== ConfigBackend.disabledSpellLanguages) root.disabledLanguages = ConfigBackend.disabledSpellLanguages;
        }
        function onPrimarySpellLanguageChanged() {
            if (root.primaryLanguage !== ConfigBackend.primarySpellLanguage) root.primaryLanguage = ConfigBackend.primarySpellLanguage;
        }
        function onIgnoreUppercaseChanged() {
            if (root.ignoreUppercase !== ConfigBackend.ignoreUppercase) root.ignoreUppercase = ConfigBackend.ignoreUppercase;
        }
        function onIgnoreWithDigitsChanged() {
            if (root.ignoreWithDigits !== ConfigBackend.ignoreWithDigits) root.ignoreWithDigits = ConfigBackend.ignoreWithDigits;
        }
    }

    // Detección reactiva del idioma del sistema leyendo /etc/locale.conf
    property string systemLocale: "es_AR"

    property var _localeConfFile: FileView {
        id: localeConfFile
        path: "/etc/locale.conf"
        watchChanges: true
        preload: true
        printErrors: false
        onLoaded: root._parseSystemLocale(localeConfFile.text())
        onFileChanged: root._parseSystemLocale(localeConfFile.text())
    }

    Component.onCompleted: {
        if (localeConfFile.loaded) {
            root._parseSystemLocale(localeConfFile.text());
        } else if (typeof Sys !== "undefined") {
            var envLang = Sys.env("LANG", "");
            if (envLang) {
                var cleanEnv = SpellLogic.normalizeLocale(envLang);
                if (cleanEnv && root.systemLocale !== cleanEnv) {
                    root.systemLocale = cleanEnv;
                }
            }
        }
    }

    function _parseSystemLocale(txt) {
        if (!txt) return;
        var match = txt.match(/^LANG=(.+)$/m);
        if (match && match[1]) {
            var raw = match[1].trim().replace(/["']/g, "");
            var clean = SpellLogic.normalizeLocale(raw);
            if (clean && root.systemLocale !== clean) {
                root.systemLocale = clean;
            }
        }
    }

    // Lista de idiomas efectivos resueltos (multi-idioma automático simultáneo)
    readonly property var effectiveLanguages: {
        var sys = root.systemLocale || "es_AR";
        var available = (typeof SpellService !== "undefined" && SpellService.installedLanguages && SpellService.installedLanguages.length > 0)
            ? SpellService.installedLanguages
            : ["es_AR"];
        return SpellLogic.resolveEffectiveLanguages(sys, {
            disabledLanguages: root.disabledLanguages,
            primaryLanguage: root.primaryLanguage
        }, available);
    }

    function setPrimaryLanguage(code) {
        var clean = SpellLogic.normalizeLocale(code);
        if (root.primaryLanguage !== clean) {
            root.primaryLanguage = clean;
        }
    }

    function isLanguageEnabled(code) {
        var clean = SpellLogic.normalizeLocale(code);
        if (!clean) return true;
        var dis = (root.disabledLanguages || "").split(",").map(SpellLogic.normalizeLocale);
        return dis.indexOf(clean) === -1;
    }

    function toggleLanguage(code) {
        var clean = SpellLogic.normalizeLocale(code);
        if (!clean) return;
        var dis = (root.disabledLanguages || "").split(",").map(SpellLogic.normalizeLocale).filter(function(c) { return c.length > 0; });
        var idx = dis.indexOf(clean);
        if (idx !== -1) {
            dis.splice(idx, 1);
        } else {
            dis.push(clean);
        }
        root.disabledLanguages = dis.join(",");
    }
}
