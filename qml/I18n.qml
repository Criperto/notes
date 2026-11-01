pragma Singleton
import QtQuick
import "I18nCatalogs.js" as Catalogs

QtObject {
    id: root

    property string currentLanguage: "es_ar"
    readonly property var availableLanguages: Catalogs.meta.languages || []

    function setLanguage(lang) {
        if (!lang || lang === currentLanguage) return;
        currentLanguage = lang;
    }

    function _lookup(obj, parts) {
        var cur = obj;
        for (var i = 0; i < parts.length; i++) {
            if (cur === null || cur === undefined || typeof cur !== "object") return undefined;
            cur = cur[parts[i]];
        }
        return cur;
    }

    function t(path, fallback) {
        if (!path) return fallback !== undefined ? fallback : "";

        // Mapeo de claves heredadas de common
        if (path === "common.actions.cancel") {
            return t("notes._common_actions_cancel", fallback !== undefined ? fallback : "Cancelar");
        }
        if (path === "common.states.active") {
            return t("notes._common_states_active", fallback !== undefined ? fallback : "Activo");
        }

        var key = path.startsWith("notes.") ? path.substring(6) : path;
        var parts = key.split(".");

        // 1. Idioma activo
        var activeCatalog = Catalogs.catalogs[currentLanguage] || Catalogs.catalogs["es_ar"];
        var val = _lookup(activeCatalog, parts);
        if (typeof val === "string") return val;

        // 2. Fallback a inglés
        var enCatalog = Catalogs.catalogs["en"];
        if (enCatalog) {
            val = _lookup(enCatalog, parts);
            if (typeof val === "string") return val;
        }

        return fallback !== undefined ? fallback : path;
    }

    function tArr(path, fallback) {
        if (!path) return fallback !== undefined ? fallback : [];
        var key = path.startsWith("notes.") ? path.substring(6) : path;
        var parts = key.split(".");

        var activeCatalog = Catalogs.catalogs[currentLanguage] || Catalogs.catalogs["es_ar"];
        var val = _lookup(activeCatalog, parts);
        if (Array.isArray(val)) return val;

        var enCatalog = Catalogs.catalogs["en"];
        if (enCatalog) {
            val = _lookup(enCatalog, parts);
            if (Array.isArray(val)) return val;
        }

        return fallback !== undefined ? fallback : [];
    }
}
