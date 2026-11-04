.pragma library

// VersionPolicy.js — Políticas de creación, deduplicación y poda de versiones
// Sin dependencias externas, totalmente ejecutable en QML y Node.js.

// ── Hash FNV-1a para deduplicación rápida de contenido en memoria ────────
function fastHash(str) {
    if (!str || typeof str !== "string") return "0";
    var h1 = 0xdeadbeef;
    var h2 = 0x41c6ce57;
    for (var i = 0; i < str.length; i++) {
        var ch = str.charCodeAt(i);
        h1 = Math.imul(h1 ^ ch, 2654435761);
        h2 = Math.imul(h2 ^ ch, 1597334677);
    }
    h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
    h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);
    return (4294967296 * (2097151 & h2) + (h1 >>> 0)).toString(16);
}

// ── Generador de ID y nombre de archivo para snapshot ─────────────────────
function makeSnapshotId(date) {
    var d = date instanceof Date ? date : new Date();
    var pad = function (n) { return n < 10 ? "0" + n : "" + n; };
    return d.getFullYear() +
        pad(d.getMonth() + 1) +
        pad(d.getDate()) + "-" +
        pad(d.getHours()) +
        pad(d.getMinutes()) +
        pad(d.getSeconds());
}

// ── Condición para crear un snapshot ──────────────────────────────────────
function shouldCreateSnapshot(reason, lastSnapshot, currentText, options) {
    if (!currentText && currentText !== "") return false;
    var opts = options || {};
    var minDeltaChars = typeof opts.minDeltaChars === "number" ? opts.minDeltaChars : 20;
    var intervalMs = typeof opts.intervalMs === "number" ? opts.intervalMs : 5 * 60 * 1000; // 5 minutos

    // 1. Snapshot manual o pre-restauración siempre se crea (a menos que no haya texto)
    if (reason === "manual" || reason === "before_restore" || reason === "before_overwrite") {
        return true;
    }

    // 2. Si no hay snapshot previo, siempre se crea como base
    if (!lastSnapshot) {
        return true;
    }

    var curHash = fastHash(currentText);
    if (lastSnapshot.hash && lastSnapshot.hash === curHash) {
        return false; // Mismo contenido exacto: deduplicación O(1)
    }

    var now = Date.now();
    var lastTs = lastSnapshot.timestamp ? new Date(lastSnapshot.timestamp).getTime() : 0;
    var elapsed = now - lastTs;

    if (reason === "open_base") {
        return lastSnapshot.hash !== curHash;
    }

    if (reason === "auto_interval") {
        return elapsed >= intervalMs && lastSnapshot.hash !== curHash;
    }

    if (reason === "close_delta") {
        var lastLen = typeof lastSnapshot.length === "number" ? lastSnapshot.length : 0;
        var diffLen = Math.abs(currentText.length - lastLen);
        return diffLen >= minDeltaChars && lastSnapshot.hash !== curHash;
    }

    return false;
}

// ── Algoritmo de Poda y Retención Temporal (Gating & Tiering) ─────────────
// - Las versiones manuales (isManual: true) NUNCA se eliminan automáticamente.
// - Últimas 24 horas: se conservan todas.
// - De 24h a 30 días: se conserva como máximo una por día (la más reciente del día).
// - Más de 30 días: se conserva como máximo una por semana.
// - Si el total excede maxVersions (ej. 50), se podan las automáticas más antiguas primero.
function pruneVersions(versionsList, maxVersions) {
    var maxCount = typeof maxVersions === "number" && maxVersions >= 10 ? maxVersions : 50;
    if (!Array.isArray(versionsList) || versionsList.length === 0) {
        return { toKeep: [], toDelete: [] };
    }

    // Ordenar de más reciente a más antiguo
    var sorted = versionsList.slice().sort(function (a, b) {
        var ta = a.timestamp ? new Date(a.timestamp).getTime() : 0;
        var tb = b.timestamp ? new Date(b.timestamp).getTime() : 0;
        return tb - ta;
    });

    var now = Date.now();
    var oneDayMs = 24 * 60 * 60 * 1000;
    var thirtyDaysMs = 30 * oneDayMs;

    var toKeep = [];
    var toDelete = [];

    var dayBuckets = {};
    var weekBuckets = {};

    for (var i = 0; i < sorted.length; i++) {
        var item = sorted[i];

        // 1. Manuales nunca se eliminan automáticamente
        if (item.isManual) {
            toKeep.push(item);
            continue;
        }

        var itemTime = item.timestamp ? new Date(item.timestamp).getTime() : 0;
        var age = now - itemTime;

        if (age <= oneDayMs) {
            // Últimas 24h: mantener todas
            toKeep.push(item);
        } else if (age <= thirtyDaysMs) {
            // 1 por día
            var dObj = new Date(itemTime);
            var dayKey = dObj.getFullYear() + "-" + (dObj.getMonth() + 1) + "-" + dObj.getDate();
            if (!dayBuckets[dayKey]) {
                dayBuckets[dayKey] = true;
                toKeep.push(item);
            } else {
                toDelete.push(item);
            }
        } else {
            // 1 por semana
            var wYear = new Date(itemTime).getFullYear();
            var weekNum = Math.floor(age / (7 * oneDayMs));
            var weekKey = wYear + "-w" + weekNum;
            if (!weekBuckets[weekKey]) {
                weekBuckets[weekKey] = true;
                toKeep.push(item);
            } else {
                toDelete.push(item);
            }
        }
    }

    // Si todavía excedemos maxCount (por acumulación de días/semanas),
    // podar las automáticas más viejas que excedan el límite
    if (toKeep.length > maxCount) {
        var keptManuals = [];
        var keptAutos = [];
        for (var k = 0; k < toKeep.length; k++) {
            if (toKeep[k].isManual) keptManuals.push(toKeep[k]);
            else keptAutos.push(toKeep[k]);
        }

        var allowedAutos = Math.max(0, maxCount - keptManuals.length);
        // keptAutos ya está ordenado de más reciente a más viejo
        var prunedAutos = keptAutos.slice(0, allowedAutos);
        var discardedAutos = keptAutos.slice(allowedAutos);

        toKeep = keptManuals.concat(prunedAutos);
        toDelete = toDelete.concat(discardedAutos);
    }

    return {
        toKeep: toKeep,
        toDelete: toDelete
    };
}
