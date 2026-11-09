.pragma library

// ReferenceLogic.js — Detección, extracción y filtrado para Wikilinks y Anclas internas

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

function githubSlug(text) {
    if (!text || typeof text !== "string") return "";
    var s = text.trim().toLowerCase();
    s = s.replace(/[*_~`]/g, "");
    s = s.replace(/[^\p{L}\p{N}\s-]/gu, "");
    s = s.replace(/\s+/g, "-");
    s = s.replace(/-+/g, "-");
    s = s.replace(/^-+|-+$/g, "");
    return s;
}

// Detecta si la posición del cursor está dentro de un trigger de wikilink o ancla:
// - [[Texto -> mode: "note", query: "Texto"
// - [[Nota#Secc -> mode: "anchor", noteTitle: "Nota", query: "Secc"
// - [[#Secc -> mode: "anchor", noteTitle: "", isCurrentNote: true, query: "Secc"
function detectWikilinkTrigger(text, cursorPos) {
    if (typeof text !== "string" || cursorPos <= 0 || cursorPos > text.length) {
        return { triggered: false, openIndex: -1, endIndex: -1, mode: "", noteTitle: "", query: "", isCurrentNote: false };
    }

    var sub = text.substring(0, cursorPos);
    var openIdx = sub.lastIndexOf("[[");
    if (openIdx === -1) {
        return { triggered: false, openIndex: -1, endIndex: -1, mode: "", noteTitle: "", query: "", isCurrentNote: false };
    }

    // No permitir saltos de línea ni etiquetas cerradas ]] entre [[ y el cursor
    var inner = sub.substring(openIdx + 2);
    if (/[\r\n]/.test(inner) || inner.indexOf("]]") !== -1) {
        return { triggered: false, openIndex: -1, endIndex: -1, mode: "", noteTitle: "", query: "", isCurrentNote: false };
    }

    // Limitar longitud máxima de búsqueda para no mantener sugerencias abiertas indefinidamente
    if (inner.length > 80) {
        return { triggered: false, openIndex: -1, endIndex: -1, mode: "", noteTitle: "", query: "", isCurrentNote: false };
    }

    // Modo ancla: si contiene '#' después de '[['
    var hashIdx = inner.indexOf("#");
    if (hashIdx !== -1) {
        var noteTitle = inner.substring(0, hashIdx).trim();
        var secQuery = inner.substring(hashIdx + 1);
        return {
            triggered: true,
            mode: "anchor",
            openIndex: openIdx,
            endIndex: cursorPos,
            noteTitle: noteTitle,
            isCurrentNote: (noteTitle === ""),
            query: secQuery
        };
    }

    // Modo nota:
    return {
        triggered: true,
        mode: "note",
        openIndex: openIdx,
        endIndex: cursorPos,
        noteTitle: "",
        isCurrentNote: false,
        query: inner
    };
}

// Extrae los encabezados H1..H6 desde el modelo o arreglo de bloques de la nota activa
function extractHeadingsFromBlocks(blocks) {
    var headings = [];
    if (!blocks) return headings;

    var count = (typeof blocks.count === "number") ? blocks.count : (Array.isArray(blocks) ? blocks.length : 0);
    var getBlock = function(idx) {
        if (typeof blocks.get === "function") return blocks.get(idx);
        return blocks[idx];
    };

    var seenCounts = {};

    for (var i = 0; i < count; i++) {
        var b = getBlock(i);
        if (!b) continue;

        if (b.type === "heading") {
            var level = b.level || 1;
            var rawTitle = b.text || "";
            if (b.raw) {
                var m = b.raw.match(/^[ \t]*(#{1,6})[ \t]+(.*?)(?:[ \t]+#+)?$/);
                if (m) {
                    level = m[1].length;
                    rawTitle = m[2].trim();
                } else if (!rawTitle) {
                    rawTitle = b.raw.replace(/^[ \t]*#+[ \t]*/, "").trim();
                }
            }

            if (rawTitle) {
                var customMatch = rawTitle.match(/\{#([a-zA-Z0-9_-]+)\}/);
                var title = rawTitle;
                var customId = "";
                if (customMatch) {
                    customId = customMatch[1].toLowerCase();
                    title = rawTitle.replace(/\{#([a-zA-Z0-9_-]+)\}/, "").trim();
                }

                var baseSlug = customId || githubSlug(title);
                var finalSlug = baseSlug;
                if (!customId) {
                    if (seenCounts[baseSlug] !== undefined) {
                        seenCounts[baseSlug]++;
                        finalSlug = baseSlug + "-" + seenCounts[baseSlug];
                    } else {
                        seenCounts[baseSlug] = 0;
                    }
                }

                headings.push({
                    level: level,
                    tag: "H" + level,
                    title: title,
                    slug: finalSlug,
                    bid: b.bid !== undefined ? b.bid : i,
                    blockIndex: i
                });
            }
        }
    }

    return headings;
}

// Extrae encabezados H1..H6 desde un texto markdown crudo
function extractHeadingsFromMarkdown(mdText) {
    var headings = [];
    if (!mdText || typeof mdText !== "string") return headings;

    var lines = mdText.split(/\r?\n/);
    var seenCounts = {};
    var inFence = false;

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (/^[ \t]*```/.test(line)) {
            inFence = !inFence;
            continue;
        }
        if (inFence) continue;

        var m = line.match(/^[ \t]*(#{1,6})[ \t]+(.*?)(?:[ \t]+#+)?$/);
        if (m) {
            var level = m[1].length;
            var rawTitle = m[2].trim();
            var customMatch = rawTitle.match(/\{#([a-zA-Z0-9_-]+)\}/);
            var title = rawTitle;
            var customId = "";
            if (customMatch) {
                customId = customMatch[1].toLowerCase();
                title = rawTitle.replace(/\{#([a-zA-Z0-9_-]+)\}/, "").trim();
            }

            var baseSlug = customId || githubSlug(title);
            var finalSlug = baseSlug;
            if (!customId) {
                if (seenCounts[baseSlug] !== undefined) {
                    seenCounts[baseSlug]++;
                    finalSlug = baseSlug + "-" + seenCounts[baseSlug];
                } else {
                    seenCounts[baseSlug] = 0;
                }
            }

            headings.push({
                level: level,
                tag: "H" + level,
                title: title,
                slug: finalSlug,
                lineIndex: i
            });
        }
    }

    return headings;
}

// Filtra notas de la biblioteca según la consulta
function filterNotes(notesList, query, maxResults) {
    if (!notesList || !Array.isArray(notesList)) return [];
    var q = normalizeText(query ? query.trim() : "");
    var maxCount = maxResults || 15;

    var rawQ = query ? query.trim() : "";
    var scored = [];
    var hasExactMatch = false;

    for (var i = 0; i < notesList.length; i++) {
        var note = notesList[i];
        if (!note) continue;

        var title = (note.title || note.slug || note.fileName || "").trim();
        var normTitle = normalizeText(title);
        var normSlug = normalizeText(note.slug || "");

        if (!q) {
            scored.push({
                item: {
                    title: title,
                    slug: note.slug || "",
                    key: note.key || "",
                    isFolderNote: !!note.isFolderNote,
                    tags: note.tags || []
                },
                score: 10
            });
            continue;
        }

        if (normTitle === q || normSlug === q) {
            hasExactMatch = true;
        }

        var score = 0;
        if (normTitle === q) {
            score += 100;
        } else if (normTitle.startsWith(q)) {
            score += 75;
        } else if (normSlug.startsWith(q)) {
            score += 60;
        } else if (normTitle.indexOf(q) !== -1) {
            score += 40;
        } else if (normSlug.indexOf(q) !== -1) {
            score += 25;
        }

        if (score > 0) {
            scored.push({
                item: {
                    title: title,
                    slug: note.slug || "",
                    key: note.key || "",
                    isFolderNote: !!note.isFolderNote,
                    tags: note.tags || []
                },
                score: score
            });
        }
    }

    scored.sort(function(a, b) {
        return b.score - a.score;
    });

    var results = scored.slice(0, maxCount).map(function(s) {
        return s.item;
    });

    // Si el usuario escribió un término que no coincide exactamente con una nota existente,
    // ofrecemos crear la nueva nota
    if (rawQ.length > 0 && !hasExactMatch) {
        results.push({
            isCreateNew: true,
            title: rawQ,
            slug: githubSlug(rawQ)
        });
    }

    return results;
}

// Filtra encabezados según la consulta
function filterHeadings(headingsList, query, maxResults) {
    if (!headingsList || !Array.isArray(headingsList)) return [];
    var q = normalizeText(query ? query.trim() : "");
    var maxCount = maxResults || 20;

    if (!q) {
        return headingsList.slice(0, maxCount);
    }

    var scored = [];
    for (var i = 0; i < headingsList.length; i++) {
        var h = headingsList[i];
        if (!h) continue;

        var normTitle = normalizeText(h.title || "");
        var normSlug = normalizeText(h.slug || "");

        var score = 0;
        if (normTitle === q || normSlug === q) {
            score += 100;
        } else if (normTitle.startsWith(q)) {
            score += 80;
        } else if (normSlug.startsWith(q)) {
            score += 65;
        } else if (normTitle.indexOf(q) !== -1) {
            score += 40;
        } else if (normSlug.indexOf(q) !== -1) {
            score += 25;
        }

        if (score > 0) {
            scored.push({
                item: h,
                score: score
            });
        }
    }

    scored.sort(function(a, b) {
        return b.score - a.score;
    });

    return scored.slice(0, maxCount).map(function(s) {
        return s.item;
    });
}
