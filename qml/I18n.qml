pragma Singleton
import QtQuick
import Notas
import "I18nCatalogs.js" as Catalogs

QtObject {
    id: root

    function _resolveCatalogCode(raw) {
        if (!raw || typeof raw !== "string") return "es_ar";
        var norm = raw.trim().split(".")[0].split("@")[0].toLowerCase().replace("-", "_");
        if (!norm || norm === "auto") return "";
        if (Catalogs.catalogs[norm]) return norm;
        var base = norm.split("_")[0];
        if (base === "es") return "es_ar";
        if (Catalogs.catalogs[base]) return base;
        return "es_ar";
    }

    readonly property string configuredLanguage: (typeof ConfigBackend !== "undefined" && ConfigBackend.language) ? ConfigBackend.language : "auto"

    readonly property string currentLanguage: {
        if (configuredLanguage && configuredLanguage !== "auto") {
            var explicit = _resolveCatalogCode(configuredLanguage);
            if (explicit) return explicit;
        }
        var sys = (typeof SpellConfig !== "undefined" && SpellConfig.systemLocale)
            ? SpellConfig.systemLocale
            : ((typeof Sys !== "undefined") ? Sys.env("LANG", "es_AR") : "es_AR");
        var resolved = _resolveCatalogCode(sys);
        return resolved || "es_ar";
    }

    readonly property var availableLanguages: Catalogs.meta.languages || []

    function setLanguage(lang) {
        if (typeof ConfigBackend !== "undefined") {
            var next = lang || "auto";
            if (ConfigBackend.language !== next) {
                ConfigBackend.language = next;
            }
        }
    }

    function _lookup(obj, parts) {
        var cur = obj;
        for (var i = 0; i < parts.length; i++) {
            if (cur === null || cur === undefined || typeof cur !== "object") return undefined;
            cur = cur[parts[i]];
        }
        return cur;
    }

    function _resolveInCatalog(cat, path, key, parts, pathParts) {
        if (!cat || typeof cat !== "object") return undefined;
        var val = _lookup(cat, parts);
        if (typeof val === "string") return val;
        val = _lookup(cat, pathParts);
        if (typeof val === "string") return val;
        if (typeof cat[path] === "string") return cat[path];
        if (typeof cat[key] === "string") return cat[key];
        return undefined;
    }

    function _resolveArrayInCatalog(cat, path, key, parts, pathParts) {
        if (!cat || typeof cat !== "object") return undefined;
        var val = _lookup(cat, parts);
        if (Array.isArray(val)) return val;
        val = _lookup(cat, pathParts);
        if (Array.isArray(val)) return val;
        if (Array.isArray(cat[path])) return cat[path];
        if (Array.isArray(cat[key])) return cat[key];
        return undefined;
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
        var pathParts = path.split(".");

        // 1. Idioma activo
        var activeCatalog = Catalogs.catalogs[currentLanguage] || Catalogs.catalogs["es_ar"];
        var res = _resolveInCatalog(activeCatalog, path, key, parts, pathParts);
        if (typeof res === "string") return res;

        // 2. Fallback a inglés
        var enCatalog = Catalogs.catalogs["en"];
        if (enCatalog && currentLanguage !== "en") {
            res = _resolveInCatalog(enCatalog, path, key, parts, pathParts);
            if (typeof res === "string") return res;
        }

        // 3. Fallback a español si el idioma no es español ni inglés
        var esCatalog = Catalogs.catalogs["es_ar"];
        if (esCatalog && currentLanguage !== "es_ar" && currentLanguage !== "es_es") {
            res = _resolveInCatalog(esCatalog, path, key, parts, pathParts);
            if (typeof res === "string") return res;
        }

        return fallback !== undefined ? fallback : path;
    }

    function tArr(path, fallback) {
        if (!path) return fallback !== undefined ? fallback : [];
        var key = path.startsWith("notes.") ? path.substring(6) : path;
        var parts = key.split(".");
        var pathParts = path.split(".");

        var activeCatalog = Catalogs.catalogs[currentLanguage] || Catalogs.catalogs["es_ar"];
        var res = _resolveArrayInCatalog(activeCatalog, path, key, parts, pathParts);
        if (Array.isArray(res)) return res;

        var enCatalog = Catalogs.catalogs["en"];
        if (enCatalog && currentLanguage !== "en") {
            res = _resolveArrayInCatalog(enCatalog, path, key, parts, pathParts);
            if (Array.isArray(res)) return res;
        }

        return fallback !== undefined ? fallback : [];
    }
}
