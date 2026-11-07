.pragma library

// SpellLogic.js — Lógica pura para corrección ortográfica en Quickshell
// Tokenización Unicode, filtros heurísticos, protocolo Hunspell y cálculo geométrico.

/**
 * Normaliza un código de idioma (ej. "es_AR.UTF-8", "es-ar", "es_ar" -> "es_AR").
 */
function normalizeLocale(loc) {
    if (!loc || typeof loc !== "string") return "";
    var clean = loc.trim().split(".")[0].split("@")[0];
    clean = clean.replace(/-/g, "_");
    var parts = clean.split("_");
    if (parts.length === 1) {
        return parts[0].toLowerCase();
    }
    return parts[0].toLowerCase() + "_" + parts[1].toUpperCase();
}

/**
 * Resuelve la lista de idiomas prioritarios en modo multi-idioma automático.
 * Valida simultáneamente palabras en el idioma principal del sistema y en
 * todos los diccionarios instalados adicionales (ej. Español e Inglés a la vez).
 *
 * @param {string} systemLocale - Ej: "es_AR.UTF-8"
 * @param {Object} config - { disabledLanguages: string|Array }
 * @param {Array<string>} availableDicts - Lista de diccionarios instalados (ej. ["es_AR", "en_US"])
 * @returns {Array<string>} Lista ordenada de códigos de idioma válidos
 */
function resolveEffectiveLanguages(systemLocale, config, availableDicts) {
    var rawAvailable = Array.isArray(availableDicts) ? availableDicts : [];
    var available = [];
    for (var a = 0; a < rawAvailable.length; a++) {
        var norm = normalizeLocale(rawAvailable[a]);
        if (norm && available.indexOf(norm) === -1) {
            available.push(norm);
        }
    }

    var cfg = config || {};
    var disabled = [];
    if (cfg.disabledLanguages) {
        var disList = Array.isArray(cfg.disabledLanguages) ? cfg.disabledLanguages : String(cfg.disabledLanguages).split(",");
        for (var d = 0; d < disList.length; d++) {
            var disNorm = normalizeLocale(disList[d]);
            if (disNorm) disabled.push(disNorm);
        }
    }

    var activeDicts = available.filter(function(code) {
        return disabled.indexOf(code) === -1;
    });

    var resolved = [];
    var sys = normalizeLocale(systemLocale);
    var primaryPref = normalizeLocale(cfg.primaryLanguage || "");

    // 1. Priorizar el idioma principal configurado explícitamente o el del sistema
    var primaryMatch = null;
    var targetPrimary = primaryPref || sys;
    if (targetPrimary) {
        // Coincidencia exacta (ej: es_AR)
        for (var i = 0; i < activeDicts.length; i++) {
            if (activeDicts[i] === targetPrimary) {
                primaryMatch = activeDicts[i];
                break;
            }
        }
        // Coincidencia por idioma base (ej: es_AR busca es_ES o es)
        if (!primaryMatch) {
            var targetBase = targetPrimary.split("_")[0];
            for (var j = 0; j < activeDicts.length; j++) {
                if (activeDicts[j].split("_")[0] === targetBase) {
                    primaryMatch = activeDicts[j];
                    break;
                }
            }
        }
    }

    if (primaryMatch) {
        resolved.push(primaryMatch);
    } else if (targetPrimary && activeDicts.length === 0) {
        resolved.push(targetPrimary);
    }

    // 2. Agregar el resto de diccionarios instalados y activos (soporte multi-idioma simultáneo)
    for (var k = 0; k < activeDicts.length; k++) {
        if (resolved.indexOf(activeDicts[k]) === -1) {
            resolved.push(activeDicts[k]);
        }
    }

    // 3. Fallback seguro
    if (resolved.length === 0) {
        resolved.push("es_AR");
    }

    return resolved;
}

/**
 * Filtra la lista de diccionarios activos según el idioma detectado en un párrafo.
 * Si el idioma es desconocido o ninguno de los diccionarios coincide, retorna activeLangs como fallback.
 * @param {string|null} detectedLang - Código ISO ("es", "en", "pt", etc.) o null
 * @param {Array<string>} activeLangs - Diccionarios activos (ej. ["es_AR", "en_US"])
 * @returns {Array<string>} Diccionarios filtrados
 */
function filterLanguagesByDetected(detectedLang, activeLangs) {
    if (!Array.isArray(activeLangs) || activeLangs.length === 0) return [];
    if (!detectedLang || typeof detectedLang !== "string") return activeLangs;

    var clean = detectedLang.toLowerCase().trim();
    var matched = [];
    for (var i = 0; i < activeLangs.length; i++) {
        var lang = activeLangs[i];
        if (!lang) continue;
        var base = lang.toLowerCase().split("_")[0];
        if (base === clean) {
            matched.push(lang);
        }
    }

    if (matched.length > 0) {
        return matched;
    }
    return activeLangs;
}

/**
 * Tokeniza un texto extrayendo palabras y sus posiciones [start, end].
 * Soporta caracteres alfabéticos Unicode y apóstrofes internos.
 * Enmascara y excluye automáticamente spans de código inline (`...`),
 * URLs, emails, rutas Unix (/path/...) y enlaces Markdown.
 *
 * @param {string} text
 * @param {Object} [options]
 * @returns {Array<{word: string, start: int, end: int}>}
 */
function tokenize(text, options) {
    if (!text || typeof text !== "string") return [];

    var opts = options || {};
    var ignoreUppercase = opts.ignoreUppercase !== false;
    var ignoreWithDigits = opts.ignoreWithDigits !== false;
    var ignoreCamelCase = opts.ignoreCamelCase !== false;
    var ignoreSnakeCase = opts.ignoreSnakeCase !== false;
    var minWordLength = typeof opts.minWordLength === "number" ? opts.minWordLength : 2;

    var ignoredRanges = [];
    var match;

    // 1. URLs y emails
    var urlEmailRegex = /(https?:\/\/[^\s]+|www\.[^\s]+|[\w.+-]+@[\w-]+\.[\w.-]+)/g;
    while ((match = urlEmailRegex.exec(text)) !== null) {
        ignoredRanges.push({ start: match.index, end: match.index + match[0].length });
    }

    // 2. Spans de código inline (`...`)
    var codeRegex = /`[^`]+`/g;
    while ((match = codeRegex.exec(text)) !== null) {
        ignoredRanges.push({ start: match.index, end: match.index + match[0].length });
    }

    // 3. Destinos de enlaces Markdown (ej. [link](https://... o relative))
    var mdLinkRegex = /\]\([^\)]+\)/g;
    while ((match = mdLinkRegex.exec(text)) !== null) {
        ignoredRanges.push({ start: match.index + 1, end: match.index + match[0].length });
    }

    // 4. Rutas Unix (ej. /mnt/ssd/..., /var/lib/..., /etc/...)
    var pathRegex = /(?:^|[\s"'\(\[])(\/[a-zA-Z0-9_.\-\/]+)/g;
    while ((match = pathRegex.exec(text)) !== null) {
        var full = match[0];
        var pathStr = match[1];
        var pStart = match.index + (full.length - pathStr.length);
        ignoredRanges.push({ start: pStart, end: pStart + pathStr.length });
    }

    // 5. Etiquetas HTML (ej. <br>, <br/>, <span>, </b>, etc., común en celdas de tabla)
    var htmlTagRegex = /<[^>]+>/g;
    while ((match = htmlTagRegex.exec(text)) !== null) {
        ignoredRanges.push({ start: match.index, end: match.index + match[0].length });
    }

    // 6. Fórmulas matemáticas en bloque ($$...$$) e inline ($...$)
    var mathRegex = /\$\$[\s\S]*?\$\$|\$(?:\\\$|[^\$])+\$/g;
    while ((match = mathRegex.exec(text)) !== null) {
        ignoredRanges.push({ start: match.index, end: match.index + match[0].length });
    }

    // Regex para palabras con apóstrofes internos compatible con Qt Quick QJSEngine/V4 y Node.js
    var wordRegex = /[a-zA-Z\u00C0-\u024F\u0400-\u04FF]+(?:['’][a-zA-Z\u00C0-\u024F\u0400-\u04FF]+)*/g;
    var tokens = [];

    while ((match = wordRegex.exec(text)) !== null) {
        var word = match[0];
        var start = match.index;
        var end = start + word.length;

        // Comprobar si solapa con cualquier rango ignorado
        var inIgnored = false;
        for (var i = 0; i < ignoredRanges.length; i++) {
            var ir = ignoredRanges[i];
            if (!(end <= ir.start || start >= ir.end)) {
                inIgnored = true;
                break;
            }
        }
        if (inIgnored) continue;

        // Verificar longitud mínima
        if (word.length < minWordLength) continue;

        // Verificar si contiene números o caracteres adyacentes a dígitos (ej: "h1", "v2")
        if (ignoreWithDigits) {
            var charBefore = start > 0 ? text.charAt(start - 1) : "";
            var charAfter = end < text.length ? text.charAt(end) : "";
            if (/\d/.test(charBefore) || /\d/.test(charAfter)) {
                continue;
            }
        }

        // Ignorar todo en MAYÚSCULAS (ej. "NASA", "HTML", "CPU")
        if (ignoreUppercase && word.length > 1 && word === word.toUpperCase() && word !== word.toLowerCase()) {
            continue;
        }

        // Ignorar snake_case si está unido por guión bajo
        if (ignoreSnakeCase) {
            var prevChar = start > 0 ? text.charAt(start - 1) : "";
            var nextChar = end < text.length ? text.charAt(end) : "";
            if (prevChar === "_" || nextChar === "_") {
                continue;
            }
        }

        // Ignorar camelCase (ej: "miVariable", "blockId")
        if (ignoreCamelCase && word.length > 2) {
            if (/[a-z\u00E0-\u00FD\u0430-\u044F][A-Z\u00C0-\u00DD\u0410-\u042F]/.test(word)) {
                continue;
            }
        }

        tokens.push({
            word: word,
            start: start,
            end: end
        });
    }

    return tokens;
}

/**
 * Parsea la respuesta del protocolo interactivo hunspell -a.
 * Protocolo hunspell:
 *   * = OK
 *   + <derivado> = OK
 *   - <compuesto> = OK
 *   & <palabra> <conteo> <offset>: <sug1>, <sug2>, ... = Error con sugerencias
 *   # <palabra> <offset> = Error sin sugerencias
 * @param {string} hunspellOutput - Salida para una o más palabras
 * @returns {Array<{word: string, ok: boolean, suggestions: Array<string>}>}
 */
function parseHunspellResponse(hunspellOutput) {
    if (!hunspellOutput || typeof hunspellOutput !== "string") return [];

    var lines = hunspellOutput.split("\n");
    var results = [];

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (line === "" || line.startsWith("@(#)")) {
            continue;
        }

        var prefix = line.charAt(0);
        if (prefix === "*" || prefix === "+" || prefix === "-") {
            results.push({
                word: "",
                ok: true,
                suggestions: []
            });
        } else if (prefix === "#") {
            var partsHash = line.split(/\s+/);
            var badWordHash = partsHash[1] || "";
            results.push({
                word: badWordHash,
                ok: false,
                suggestions: []
            });
        } else if (prefix === "&") {
            var colonIdx = line.indexOf(":");
            var header = colonIdx !== -1 ? line.substring(0, colonIdx) : line;
            var sugsStr = colonIdx !== -1 ? line.substring(colonIdx + 1) : "";

            var headerParts = header.split(/\s+/);
            var badWordAmp = headerParts[1] || "";

            var sugs = sugsStr.split(",").map(function(s) {
                return s.trim();
            }).filter(function(s) {
                return s.length > 0;
            });

            results.push({
                word: badWordAmp,
                ok: false,
                suggestions: sugs
            });
        }
    }

    return results;
}

/**
 * Calcula segmentos de línea continua para dibujar la onda ondulada debajo de una palabra.
 * Soporta palabras que se quiebran en múltiples líneas y adapta las coordenadas a la
 * escala del glifo (`rStart.height`), evitando puntos o trazos fantasma en (0, 0).
 *
 * @param {Function} positionToRectFn - Función (pos) => { x, y, width, height } de TextEdit
 * @param {int} start - Índice de inicio en el texto
 * @param {int} end - Índice de fin en el texto
 * @returns {Array<{x: real, y: real, width: real, height: real}>}
 */
function calculateWaveSegments(positionToRectFn, start, end) {
    if (typeof positionToRectFn !== "function" || start >= end || start < 0) {
        return [];
    }

    var rStart = positionToRectFn(start);
    var rEnd = positionToRectFn(end);
    if (!rStart || !rEnd) return [];

    // Validar que el layout exista y tenga altura positiva (evita renderizado prematuro en (0,0))
    var hStart = rStart.height || 0;
    var hEnd = rEnd.height || 0;
    if (hStart <= 0 || hEnd <= 0) return [];

    // Si start y end están en la misma línea
    if (Math.abs(rStart.y - rEnd.y) < 4) {
        var w = rEnd.x - rStart.x;
        if (w <= 0) return [];
        return [{
            x: rStart.x,
            y: rStart.y + hStart,
            width: w,
            height: hStart
        }];
    }

    // Si la palabra salta de línea, recorrer carácter por carácter
    var segments = [];
    var curSegment = null;

    for (var pos = start; pos <= end; pos++) {
        var r = positionToRectFn(pos);
        if (!r || (r.height || 0) <= 0) continue;

        var rH = r.height || 16;
        var rBaselineY = r.y + rH;

        if (!curSegment) {
            curSegment = {
                startX: r.x,
                endX: r.x,
                y: rBaselineY,
                height: rH
            };
        } else if (Math.abs(rBaselineY - curSegment.y) < 4) {
            curSegment.endX = r.x;
        } else {
            // Salto de línea detectado
            if (curSegment.endX > curSegment.startX) {
                segments.push({
                    x: curSegment.startX,
                    y: curSegment.y,
                    width: curSegment.endX - curSegment.startX,
                    height: curSegment.height
                });
            }
            curSegment = {
                startX: r.x,
                endX: r.x,
                y: rBaselineY,
                height: rH
            };
        }
    }

    if (curSegment && curSegment.endX > curSegment.startX) {
        segments.push({
            x: curSegment.startX,
            y: curSegment.y,
            width: curSegment.endX - curSegment.startX,
            height: curSegment.height
        });
    }

    return segments;
}

/**
 * Busca si una posición de cursor está dentro de un rango de error.
 * @param {Array<{start: int, end: int, word: string, suggestions: Array<string>}>} ranges
 * @param {int} cursorPosition
 * @returns {Object|null}
 */
function findRangeAt(ranges, cursorPosition) {
    if (!Array.isArray(ranges) || cursorPosition < 0) return null;
    for (var i = 0; i < ranges.length; i++) {
        var r = ranges[i];
        if (r && cursorPosition >= r.start && cursorPosition <= r.end) {
            return r;
        }
    }
    return null;
}

/**
 * Ajusta la capitalización de una sugerencia según la palabra original.
 * Ej: "kasa" -> "casa", pero "Kasa" -> "Casa", "KASA" -> "CASA".
 */
function matchCapitalization(original, suggestion) {
    if (!original || !suggestion) return suggestion;
    if (original === original.toUpperCase()) {
        return suggestion.toUpperCase();
    }
    var firstUpper = original.charAt(0) === original.charAt(0).toUpperCase() &&
                     original.charAt(0) !== original.charAt(0).toLowerCase();
    if (firstUpper) {
        return suggestion.charAt(0).toUpperCase() + suggestion.slice(1);
    }
    return suggestion;
}

/**
 * Remueve marcas diacríticas / acentos para comparar formas canónicas (ej: "botón" -> "boton").
 */
function stripDiacritics(str) {
    if (!str || typeof str !== "string") return "";
    return str.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

/**
 * Distancia de Levenshtein entre dos cadenas.
 */
function levenshteinDistance(a, b) {
    if (a === b) return 0;
    var la = a.length, lb = b.length;
    if (la === 0) return lb;
    if (lb === 0) return la;

    var v0 = new Array(lb + 1);
    var v1 = new Array(lb + 1);

    for (var i = 0; i <= lb; i++) v0[i] = i;

    for (var i = 0; i < la; i++) {
        v1[0] = i + 1;
        var ca = a.charCodeAt(i);
        for (var j = 0; j < lb; j++) {
            var cost = (ca === b.charCodeAt(j)) ? 0 : 1;
            v1[j + 1] = Math.min(v1[j] + 1, v0[j + 1] + 1, v0[j] + cost);
        }
        for (var k = 0; k <= lb; k++) v0[k] = v1[k];
    }
    return v1[lb];
}

/**
 * Coeficiente de similitud entre dos cadenas en [0, 1].
 */
function similarityRatio(a, b) {
    if (!a && !b) return 1.0;
    if (!a || !b) return 0.0;
    var maxLen = Math.max(a.length, b.length);
    if (maxLen === 0) return 1.0;
    var dist = levenshteinDistance(a.toLowerCase(), b.toLowerCase());
    return (maxLen - dist) / maxLen;
}

/**
 * Fusiona sugerencias de múltiples idiomas y las ordena inteligentemente por similitud léxica.
 * @param {Object} sugsMap - Mapa { "es_AR": ["botón", "boto", ...], "en_US": ["boron", "boon", ...] }
 * @param {string} originalWord - La palabra original escrita por el usuario
 * @param {string} [primaryLang] - Código del idioma principal
 * @returns {Array<{word: string, lang: string, score: number}>}
 */
function mergeMultiLangSuggestions(sugsMap, originalWord, primaryLang) {
    if (!sugsMap || typeof sugsMap !== "object") return [];

    var word = (originalWord || "").trim();
    var wordClean = word.toLowerCase();
    var wordStripped = stripDiacritics(wordClean);
    var normPrimary = normalizeLocale(primaryLang || "");

    var byLang = {};
    var langCodes = Object.keys(sugsMap);

    for (var l = 0; l < langCodes.length; l++) {
        var lang = langCodes[l];
        var list = sugsMap[lang];
        if (!Array.isArray(list)) continue;

        var isPrimary = normPrimary && (normalizeLocale(lang) === normPrimary);
        var scoredList = [];

        for (var i = 0; i < list.length; i++) {
            var sug = list[i];
            if (!sug || typeof sug !== "string") continue;
            var sugTrim = sug.trim();
            var sugClean = sugTrim.toLowerCase();
            if (sugClean === "") continue;

            var sim = similarityRatio(wordClean, sugClean);
            var sugStripped = stripDiacritics(sugClean);

            // Bonus significativo si la forma base sin tildes es idéntica (ej: "boton" vs "botón")
            if (wordStripped === sugStripped && wordStripped !== "") {
                sim += 0.35;
            }

            // Bonus por coincidencia de primera y última letra (frecuente en tipeo rápido)
            if (wordClean.length > 2 && sugClean.length > 2) {
                if (wordClean.charAt(0) === sugClean.charAt(0)) sim += 0.04;
                if (wordClean.charAt(wordClean.length - 1) === sugClean.charAt(sugClean.length - 1)) sim += 0.04;
            }

            // Bonus suave para el idioma principal
            if (isPrimary) {
                sim += 0.03;
            }

            // Penalización gradual por posición original entregada por Hunspell
            var rankPenalty = i * 0.015;
            var finalScore = sim - rankPenalty;

            scoredList.push({
                word: sugTrim,
                lang: lang,
                score: finalScore
            });
        }

        scoredList.sort(function(a, b) {
            return b.score - a.score;
        });

        byLang[lang] = scoredList;
    }

    var validLangs = Object.keys(byLang).filter(function(code) {
        return byLang[code] && byLang[code].length > 0;
    });

    if (validLangs.length === 0) return [];

    // Ordenar idiomas dando prioridad al que tenga la sugerencia con mejor puntaje
    validLangs.sort(function(a, b) {
        var topA = byLang[a][0] ? byLang[a][0].score : -999;
        var topB = byLang[b][0] ? byLang[b][0].score : -999;
        return topB - topA;
    });

    // Intercalar candidatos garantizando representación equilibrada de ambos idiomas
    var result = [];
    var seen = {};
    var maxCount = 0;
    for (var v = 0; v < validLangs.length; v++) {
        if (byLang[validLangs[v]].length > maxCount) {
            maxCount = byLang[validLangs[v]].length;
        }
    }

    for (var round = 0; round < maxCount; round++) {
        for (var idx = 0; idx < validLangs.length; idx++) {
            var cand = byLang[validLangs[idx]][round];
            if (cand) {
                var cKey = cand.word.toLowerCase();
                if (!seen[cKey]) {
                    seen[cKey] = true;
                    result.push(cand);
                    if (result.length >= 6) break;
                }
            }
        }
        if (result.length >= 6) break;
    }

    return result;
}
