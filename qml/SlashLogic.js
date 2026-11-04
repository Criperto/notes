.pragma library

// SlashLogic.js — Detección y filtrado de comandos '/' para editor de bloques (F78)

function detectTrigger(text, cursorPos) {
    if (typeof text !== "string" || cursorPos <= 0 || cursorPos > text.length) {
        return { triggered: false, slashIndex: -1, query: "", endIndex: -1 };
    }
    // Buscamos el '/' más cercano hacia la izquierda del cursor
    var sub = text.substring(0, cursorPos);
    var slashIdx = sub.lastIndexOf("/");
    if (slashIdx === -1) {
        return { triggered: false, slashIndex: -1, query: "", endIndex: -1 };
    }
    // Debe ser inicio de texto o precedido por espacio, tab o salto de línea
    if (slashIdx > 0) {
        var prevChar = sub.charAt(slashIdx - 1);
        if (prevChar !== " " && prevChar !== "\t" && prevChar !== "\n") {
            return { triggered: false, slashIndex: -1, query: "", endIndex: -1 };
        }
    }
    var query = sub.substring(slashIdx + 1);
    // No permitir espacios, saltos de línea ni otros slashes en la query (ej: paths o urls)
    if (/[\s\/]/.test(query) || query.length > 25) {
        return { triggered: false, slashIndex: -1, query: "", endIndex: -1 };
    }
    return {
        triggered: true,
        slashIndex: slashIdx,
        query: query,
        endIndex: cursorPos
    };
}

function normalizeText(str) {
    if (!str || typeof str !== "string") return "";
    var s = str.toLowerCase();
    try {
        if (typeof s.normalize === "function") {
            s = s.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
        }
    } catch (e) {}
    return s;
}

function filterCommands(commands, query, I18n) {
    if (!commands || !Array.isArray(commands)) return [];
    var q = normalizeText(query ? query.trim() : "");
    if (!q) {
        return commands.map(function(cmd) {
            return _formatCommandItem(cmd, I18n);
        });
    }

    var scored = [];
    for (var i = 0; i < commands.length; i++) {
        var cmd = commands[i];
        var title = (I18n && typeof I18n.t === "function") ? I18n.t(cmd.titleKey, cmd.fallbackTitle) : cmd.fallbackTitle;
        var desc = (I18n && typeof I18n.t === "function") ? I18n.t(cmd.descKey, cmd.fallbackDesc) : cmd.fallbackDesc;

        var normId = normalizeText(cmd.id);
        var normTitle = normalizeText(title);
        var normDesc = normalizeText(desc);
        var normBadge = normalizeText(cmd.badge);

        var score = 0;
        if (normBadge === "/" + q || normId === q) {
            score += 100;
        } else if (normBadge.startsWith("/" + q)) {
            score += 85;
        } else if (normTitle.startsWith(q)) {
            score += 70;
        } else if (cmd.keywords && cmd.keywords.some(function(k) { return normalizeText(k) === q; })) {
            score += 65;
        } else if (cmd.keywords && cmd.keywords.some(function(k) { return normalizeText(k).startsWith(q); })) {
            score += 50;
        } else if (normTitle.indexOf(q) !== -1) {
            score += 35;
        } else if (cmd.keywords && cmd.keywords.some(function(k) { return normalizeText(k).indexOf(q) !== -1; })) {
            score += 25;
        } else if (normDesc.indexOf(q) !== -1) {
            score += 15;
        }

        if (score > 0) {
            scored.push({
                item: _formatCommandItem(cmd, I18n),
                score: score
            });
        }
    }

    scored.sort(function(a, b) {
        return b.score - a.score;
    });

    return scored.map(function(s) {
        return s.item;
    });
}

function _formatCommandItem(cmd, I18n) {
    var title = (I18n && typeof I18n.t === "function") ? I18n.t(cmd.titleKey, cmd.fallbackTitle) : cmd.fallbackTitle;
    var desc = (I18n && typeof I18n.t === "function") ? I18n.t(cmd.descKey, cmd.fallbackDesc) : cmd.fallbackDesc;
    return {
        id: cmd.id,
        category: cmd.category,
        icon: cmd.icon,
        calloutType: cmd.calloutType || "",
        title: title,
        description: desc,
        badge: cmd.badge,
        titleKey: cmd.titleKey,
        descKey: cmd.descKey,
        fallbackTitle: cmd.fallbackTitle,
        fallbackDesc: cmd.fallbackDesc
    };
}
