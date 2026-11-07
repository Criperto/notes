// NoteEditorModal.qml — Vista y editor de notas basado en bloques
import "."
import Notas
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Controls
import "MarkdownParser.js" as MD
import "Inline.js" as Inline
import "SearchLogic.js" as SearchLogic
import "TagsLogic.js" as TagsLogic
import "ImportLogic.js" as ImportLogic
import "EditorActions.js" as EA
import "ListParser.js" as LP
import "TableParser.js" as TP
import "QuoteParser.js" as QP
import "MermaidTemplates.js" as MermaidTemplates
import "MathTemplates.js" as MathTemplates

Item {
    id: root
    focus: true

    property var noteData: null
    readonly property bool isPreviewMode: Boolean(noteData && noteData.readOnly)
    readonly property bool isExternalNote: Boolean(noteData && noteData.isExternal)
    property string loadedSlug: ""
    property bool isPinned: false
    // Las .txt se editan como texto plano (sin Markdown) en modo fuente forzado.
    // Propiedad plana (no binding a noteData): el servicio muta la nota activa en
    // el lugar en varios flujos y los bindings a objetos JS mutados no avisan.
    property bool isTxt: false
    // El modelo de bloques se carga al terminar el morph de apertura
    // (los ~65 delegates no pagan instanciación durante la animación).
    property bool morphReady: true
    property string _pendingBody: ""
    property bool isSettingsOpen: false

    // Carga diferida pendiente (llamado por toggle/foco/guardado/búsqueda).
    function _flushPendingBody() {
        if (root._pendingBody === "") return;
        var pb = root._pendingBody;
        root._pendingBody = "";
        blockEditor.loadMarkdown(pb);
        blockEditor.contentY = 0;
        var noteFilePath = (root.noteData && root.noteData.filePath) ? root.noteData.filePath : (root.noteData && root.noteData.fullPath ? root.noteData.fullPath : "");
        if (noteFilePath && NotesConfig.persistUndo && blockEditor) {
            blockEditor.loadPersistedUndoHistory(noteFilePath, pb);
        }
        if (noteFilePath && NotesConfig.versionHistoryEnabled) {
            NotesService.checkAutoSnapshot(noteFilePath, pb, "open_base");
        }
        if (root.isFindActive) findRecalcTimer.restart();
    }

    onMorphReadyChanged: {
        if (root.morphReady) {
            root._flushPendingBody();
            if (!root.isTxt && !root.isSourceMode && !root.isPreviewMode) {
                if (typeof blockEditor !== "undefined" && blockEditor) {
                    blockEditor.forceActiveFocus();
                }
            }
        }
    }
    // Etiquetas del front matter (edición local hasta guardar)
    property var editTags: []
    property var _originalTags: []
    property var tagSuggestions: []
    property int tagSuggIndex: -1
    property bool dirty: false
    property bool isLoading: false
    property bool isSaving: false
    property bool isExpanded: true
    property bool isClosing: false

    property string _originalTitle: ""
    property string _originalBody: ""
    property string _currentBody: ""
    property bool _originalPinned: false
    property bool hasConflict: false
    property string conflictContent: ""

    property bool isSourceMode: false
    property bool isFindActive: false
    property string findQuery: ""
    property int findMatchIndex: 0
    property int findTotalMatches: 0
    property var _findMatchesList: []
    property bool _matchEverNavigated: false

    signal closeRequested()
    signal noteKeyChanged(string oldKey, string newKey)
    signal saveRequested(var data, var callback)
    signal deleteRequested(string slug)
    signal pasteImageRequested(string slug, var callback)
    onPasteImageRequested: (slug, callback) => {
        NotesService.pasteImage(slug, callback);
    }

    // ── Guardado desacoplado en segundo plano (NotesService) ──────────────
    Timer {
        id: autoSaveTimer
        interval: 500 // 500ms después de escribir para respuesta ágil
        repeat: false
        onTriggered: {
            if (root.dirty && root.loadedSlug) {
                if (NotesService.debug) console.log("[NoteEditorModal] Auto-guardado de 500ms ejecutándose:", root.loadedSlug);
                root.performSave();
            }
        }
    }

    function markDirty() {
        if (root.isLoading || !root.loadedSlug) return;
        var curTitle = (typeof titleInput !== "undefined" && titleInput) ? titleInput.text.trim() : root._originalTitle;
        var curMd = root.isSourceMode ? (sourceCodeEditor ? sourceCodeEditor.text : root._currentBody) : (blockEditor ? blockEditor.getMarkdown() : root._currentBody);
        var tagsNow = (root.editTags || []).join("\n");
        var tagsOrig = (root._originalTags || []).join("\n");
        var hasChanges = (curMd !== root._originalBody || curTitle !== root._originalTitle || root.isPinned !== root._originalPinned || tagsNow !== tagsOrig);
        if (!hasChanges) {
            root.dirty = false;
            autoSaveTimer.stop();
            return;
        }
        root.dirty = true;
        autoSaveTimer.restart();
    }

    Component.onDestruction: {
        if (root.loadedSlug) {
            if (root.isSourceMode) {
                root._currentBody = sourceCodeEditor ? sourceCodeEditor.text : root._currentBody;
            } else {
                if (blockEditor.activeBlockBid !== -1) {
                    blockEditor.confirmActiveBlock();
                }
                root._currentBody = blockEditor.getMarkdown();
            }
            if (root.hasConflict) {
                root.resolveConflictKeepBoth();
                return;
            }
            var newTitle = titleInput.text.trim() || I18n.t("notes.card.untitled", "Sin título");
            if (root.dirty || root._currentBody !== root._originalBody || newTitle !== root._originalTitle) {
                root.performSave();
            } else {
                NotesService.flushPendingSave();
            }
        }
    }

    onVisibleChanged: {
        if (!visible && root.loadedSlug) {
            var newTitle = titleInput.text.trim() || I18n.t("notes.card.untitled", "Sin título");
            var hasPending = root.dirty || (blockEditor && blockEditor.hasPendingChanges) || (newTitle !== root._originalTitle);
            if (!hasPending) return;

            if (root.isSourceMode) {
                root._currentBody = sourceCodeEditor ? sourceCodeEditor.text : root._currentBody;
            } else {
                if (blockEditor && blockEditor.activeBlockBid !== -1) {
                    blockEditor.confirmActiveBlock();
                }
                root._currentBody = blockEditor ? blockEditor.getMarkdown() : root._currentBody;
            }
            if (root.hasConflict) {
                root.resolveConflictKeepBoth();
                return;
            }
            if (root.dirty || root._currentBody !== root._originalBody || newTitle !== root._originalTitle) {
                root.performSave();
            }
        }
    }

    function clearClosedNote() {
        root.isClosing = false;
        root.loadedSlug = "";
        root._originalBody = "";
        root._originalTitle = "";
        root._currentBody = "";
        root.dirty = false;
        if (sourceFlickable) sourceFlickable.contentY = 0;
        if (blockEditor) {
            blockEditor.clearEditor();
            blockEditor.contentY = 0;
        }
    }

    // ── Sincronización al cambiar la nota activa ───────────────────────────
    onNoteDataChanged: {
        root.isClosing = false;
        if (!root.noteData) {
            root.loadedSlug = "";
            return;
        }

        // loadedSlug es la CLAVE (slug+ext) desde F6; las notas del dict siempre
        // traen .key (los objetos a medio construir se resuelven por slug)
        var incomingSlug = root.noteData.key || NotesService._resolveSaveKey(root.noteData.slug || root.noteData.id || "");

        // Si es la misma nota ya cargada en este editor
        if (root.loadedSlug && root.loadedSlug === incomingSlug) {
            // Con carga diferida pendiente, cargarla ya para comparar bien
            // (si no, el modelo vacío parece cambio local y dispara conflicto)
            root._flushPendingBody();
            var incomingClean = MD.getCleanBody(root.noteData);
            if (incomingClean !== root._originalBody) {
                var currentEditorMd = root.isSourceMode
                    ? (sourceCodeEditor ? sourceCodeEditor.text : root._currentBody)
                    : (blockEditor ? blockEditor.getMarkdown() : root._currentBody);

                // Si el texto entrante coincide con lo que el usuario ya tiene en pantalla,
                // solo sincronizamos metadata sin resetear el editor ni perder foco/cursor
                if (incomingClean === currentEditorMd) {
                    if (NotesService.debug) console.log("[StateDebug:Editor] incomingClean coincide con el editor actual, sincronizando sin recargar bloques:", incomingSlug);
                    root._originalBody = incomingClean;
                    root._originalTitle = root.noteData.title || "";
                    if (titleInput.text !== root._originalTitle) titleInput.text = root._originalTitle;
                    root.isPinned = !!root.noteData.pinned;
                    return;
                }

                var hasLocalChanges = root.dirty || (currentEditorMd !== root._originalBody);
                if (!hasLocalChanges) {
                    if (NotesService.debug) console.log("[StateDebug:Editor] Recarga externa aceptada (sin cambios locales) para:", incomingSlug);
                    var savedContentY = blockEditor ? blockEditor.contentY : 0;
                    var savedBid = blockEditor ? blockEditor.activeBlockBid : -1;
                    root._originalBody = incomingClean;
                    root._currentBody = incomingClean;
                    root._originalTitle = root.noteData.title || "";
                    titleInput.text = root._originalTitle;
                    root.isPinned = !!root.noteData.pinned;
                    if (root.isSourceMode && sourceCodeEditor) {
                        sourceCodeEditor.text = incomingClean;
                    } else if (blockEditor) {
                        blockEditor.loadMarkdown(incomingClean);
                        Qt.callLater(() => {
                            if (blockEditor) {
                                blockEditor.contentY = savedContentY;
                                if (savedBid !== -1) blockEditor.activeBlockBid = savedBid;
                            }
                        });
                    }
                } else {
                    if (NotesService.debug) console.warn("[StateDebug:Editor] Conflicto de contenido detectado para:", incomingSlug);
                    root.hasConflict = true;
                    root.conflictContent = root.noteData.content || root.noteData.body || incomingClean;
                    NotesService.saveState = "conflict";
                }
            } else {
                var newT = root.noteData.title || "";
                if (newT !== root._originalTitle) {
                    root._originalTitle = newT;
                    if (titleInput.text !== newT) titleInput.text = newT;
                }
                root.isPinned = !!root.noteData.pinned;
                // Adoptar etiquetas externas solo sin ediciones locales
                if (!root.dirty) {
                    var extTags = root.noteData.tags || [];
                    root.editTags = extTags.slice();
                    root._originalTags = extTags.slice();
                }
            }
            return;
        }

        if (root.loadedSlug && root.dirty) {
            if (NotesService.debug) console.log("[StateDebug:Editor] Persistiendo nota previa antes de abrir nueva:", root.loadedSlug);
            root.performSave();
        }

        if (NotesService.debug) console.log("[StateDebug:Editor] Abriendo nueva nota:", incomingSlug, "Título:", root.noteData.title);
        root.loadedSlug = incomingSlug;
        root.isLoading = true;

        var titleStr = root.noteData.title || "";
        titleInput.text = titleStr;

        var cleanBody = MD.getCleanBody(root.noteData);
        root._originalTitle = titleStr;
        root._originalBody = cleanBody;
        root._currentBody = cleanBody;
        root.isPinned = !!root.noteData.pinned;
        root._originalPinned = root.isPinned;
        var noteTags = root.noteData.tags || [];
        root.editTags = noteTags.slice();
        root._originalTags = noteTags.slice();
        root.tagSuggestions = [];
        root.tagSuggIndex = -1;
        root.dirty = false;
        root.isLoading = false;
        // Las .txt abren directo en modo fuente (texto plano, sin Markdown)
        root.isTxt = root.noteData.format === "txt";
        root.isSourceMode = root.isTxt;
        root.closeFind();
        if (sourceFlickable) sourceFlickable.contentY = 0;
        if (blockEditor) {
            blockEditor.contentY = 0;
            if (blockEditor.scrollAnim && blockEditor.scrollAnim.running) {
                blockEditor.scrollAnim.stop();
            }
        }
        if (root.isTxt) {
            root._pendingBody = "";
            if (sourceCodeEditor) sourceCodeEditor.text = cleanBody;
        } else if (!root.morphReady) {
            // Morph en curso, los bloques esperan (título/meta ya visibles).
            // Se limpia el modelo anterior para no mostrar la nota previa.
            blockEditor.loadMarkdown("");
            root._pendingBody = cleanBody;
        } else {
            root._pendingBody = "";
            blockEditor.loadMarkdown(cleanBody);
            var noteFilePath = (root.noteData && root.noteData.filePath) ? root.noteData.filePath : (root.noteData && root.noteData.fullPath ? root.noteData.fullPath : "");
            if (noteFilePath && NotesConfig.persistUndo && blockEditor) {
                blockEditor.loadPersistedUndoHistory(noteFilePath, cleanBody);
            }
            if (noteFilePath && NotesConfig.versionHistoryEnabled) {
                NotesService.checkAutoSnapshot(noteFilePath, cleanBody, "open_base");
            }
        }
    }

    function focusTitleInput() {
        if (titleInput && !root.isPreviewMode) {
            titleInput.forceActiveFocus();
            titleInput.cursorPosition = titleInput.text.length;
        }
    }

    function _confirmTitleRename() {
        if (!root.loadedSlug || root.isLoading) return;
        var newTitle = titleInput.text.trim();
        if (newTitle === "" || newTitle === root._originalTitle) return;

        NotesService.renameNote(root.loadedSlug, newTitle, function(newSlug, success) {
            if (success) {
                var oldK = root.loadedSlug;
                root.loadedSlug = newSlug;
                root._originalTitle = newTitle;
                root.noteKeyChanged(oldK, newSlug);
            } else {
                titleInput.text = root._originalTitle;
                console.warn("[NoteEditorModal] Falló renombrado; restaurando título:", root._originalTitle);
            }
        });
    }

    function performSave(callback, force) {
        if (!root.loadedSlug) {
            if (typeof callback === "function") callback();
            return;
        }

        // Nunca guardar el modelo vacío pendiente de carga diferida
        root._flushPendingBody();

        if (!force && root.hasConflict) {
            if (typeof callback === "function") callback();
            return;
        }

        var newTitle = titleInput.text.trim() || I18n.t("notes.card.untitled", "Sin título");
        var tagsNow = (root.editTags || []).join("\n");
        var tagsOrig = (root._originalTags || []).join("\n");
        var metaChanged = (newTitle !== root._originalTitle || root.isPinned !== root._originalPinned || tagsNow !== tagsOrig);

        // Si no hay cambios forzados ni pendientes y los metadatos son iguales, salir en O(1)
        if (!force && !root.dirty && !metaChanged && (!blockEditor || !blockEditor.hasPendingChanges)) {
            if (typeof callback === "function") callback();
            return;
        }

        if (root.isSourceMode) {
            root._currentBody = sourceCodeEditor ? sourceCodeEditor.text : root._currentBody;
        } else {
            root._currentBody = blockEditor ? blockEditor.getMarkdown() : root._currentBody;
        }

        var bodyText = root._currentBody;
        var hasChanges = (bodyText !== root._originalBody || metaChanged);
        if (!force && !hasChanges) {
            root.dirty = false;
            if (typeof callback === "function") callback();
            return;
        }

        root.isSaving = true;
        var currentData = {
            title: newTitle,
            content: bodyText,
            body: bodyText,
            pinned: root.isPinned,
            tags: (root.editTags || []).slice()
        };

        if (newTitle !== root._originalTitle && root.loadedSlug && !root.isLoading) {
            NotesService.renameNote(root.loadedSlug, newTitle, function(newSlug, success) {
                if (success) {
                    var oldKey = root.loadedSlug;
                    root.loadedSlug = newSlug;
                    root._originalTitle = newTitle;
                    root.noteKeyChanged(oldKey, newSlug);
                    NotesService.queueSave(newSlug, currentData);
                    NotesService.flushPendingSave();
                } else {
                    titleInput.text = root._originalTitle;
                    console.warn("[NoteEditorModal] Falló renombrado; restaurando título:", root._originalTitle);
                }
                root._originalBody = bodyText;
                root._originalPinned = root.isPinned;
                root._originalTags = (root.editTags || []).slice();
                root.dirty = false;
                root.isSaving = false;
                if (typeof callback === "function") callback();
            });
            return;
        }

        if (NotesService.debug) console.log("[StateDebug:Editor] performSave enviando a NotesService:", root.loadedSlug, "caracteres:", bodyText.length);
        NotesService.queueSave(root.loadedSlug, currentData);
        NotesService.flushPendingSave();

        var noteFilePath = (root.noteData && root.noteData.filePath) ? root.noteData.filePath : (root.noteData && root.noteData.fullPath ? root.noteData.fullPath : "");
        if (noteFilePath && NotesConfig.persistUndo && blockEditor) {
            blockEditor.persistUndoHistory(noteFilePath);
        }
        if (noteFilePath && NotesConfig.versionHistoryEnabled) {
            NotesService.checkAutoSnapshot(noteFilePath, bodyText, "save");
        }

        root._originalTitle = newTitle;
        root._originalBody = bodyText;
        root._originalPinned = root.isPinned;
        root._originalTags = (root.editTags || []).slice();
        root.dirty = false;
        root.isSaving = false;
        if (typeof callback === "function") callback();
    }

    function resolveConflictKeepBoth(callback) {
        var now = new Date();
        var pad = n => n < 10 ? "0" + n : "" + n;
        var dateStr = now.getFullYear() + "" + pad(now.getMonth() + 1) + pad(now.getDate()) + "_" + pad(now.getHours()) + pad(now.getMinutes()) + pad(now.getSeconds());
        // loadedSlug es clave (slug+NUL+ext): extraer el slug para el nombre
        var conflictSlug = NotesService.slugOfKey(root.loadedSlug) + ".conflict-" + dateStr;
        var conflictTitle = (root.noteData ? root.noteData.title : "Nota") + " (Conflicto " + dateStr + ")";
        NotesService.saveNote({
            slug: conflictSlug,
            title: conflictTitle,
            content: root.conflictContent,
            body: root.conflictContent
        }, function() {
            root.hasConflict = false;
            root.dirty = true;
            root.performSave(callback, true);
        });
    }

    function requestClose() {
        if (root.isClosing) return;
        root.isClosing = true;

        try {
            EditorMetrics.flushZoom();
            autoSaveTimer.stop();
        } catch(e) {
            console.warn("[NoteEditorModal] Error flushing zoom/timer:", e);
        }

        if (root.isPreviewMode) {
            root.closeRequested();
            return;
        }

        try {
            if (!root.isSourceMode && blockEditor && blockEditor.activeBlockBid !== -1) {
                blockEditor.confirmActiveBlock();
            }
        } catch(e) {
            console.warn("[NoteEditorModal] Error confirming active block:", e);
        }

        try {
            var noteFilePath = (root.noteData && root.noteData.filePath) ? root.noteData.filePath : (root.noteData && root.noteData.fullPath ? root.noteData.fullPath : "");
            if (noteFilePath && NotesConfig.persistUndo && blockEditor) {
                blockEditor.persistUndoHistory(noteFilePath);
            }
        } catch(e) {
            console.warn("[NoteEditorModal] Error persisting undo history:", e);
        }

        if (root.hasConflict) {
            root.resolveConflictKeepBoth(function() {
                root.closeRequested();
            });
            return;
        }

        root.closeRequested();
    }

    // ── Etiquetas del front matter ────────────────────────────────────
    // editTags vive en el editor hasta guardar (performSave → queueSave →
    // serializeNote actualiza el front matter). Backspace en vacío NO borra.
    function addTagText(raw) {
        var res = TagsLogic.addTag(root.editTags, raw);
        if (!res.changed) return false;
        root.editTags = res.tags;
        root.markDirty();
        root.updateTagSuggestions();
        return true;
    }

    function removeTagAt(idx) {
        if (idx < 0 || idx >= root.editTags.length) return;
        var res = TagsLogic.removeTag(root.editTags, root.editTags[idx]);
        if (!res.removed) return;
        root.editTags = res.tags;
        root.markDirty();
        root.updateTagSuggestions();
    }

    function updateTagSuggestions() {
        if (typeof tagInput === "undefined" || !tagInput) return;
        root.tagSuggestions = TagsLogic.suggest(NotesService.allTags, tagInput.text, root.editTags, 6);
        root.tagSuggIndex = -1;
        root.placeTagSuggestions();
    }

    function hideTagSuggestions() {
        root.tagSuggestions = [];
        root.tagSuggIndex = -1;
    }

    function placeTagSuggestions() {
        if (typeof tagSuggPopup === "undefined" || !tagSuggPopup) return;
        if (typeof tagInputBox === "undefined" || !tagInputBox) return;
        var p = tagInputBox.mapToItem(modalContainer, 0, tagInputBox.height + 4);
        tagSuggPopup.x = Math.max(8, Math.min(p.x, modalContainer.width - tagSuggPopup.width - 8));
        tagSuggPopup.y = p.y;
    }

    function pickTagSuggestion(idx) {
        if (idx < 0 || idx >= root.tagSuggestions.length) return;
        if (root.addTagText(root.tagSuggestions[idx]) && typeof tagInput !== "undefined" && tagInput) {
            tagInput.text = "";
            tagInput.forceActiveFocus();
        }
        root.hideTagSuggestions();
    }

    function confirmTagInput() {
        if (typeof tagInput === "undefined" || !tagInput) return;
        if (root.tagSuggestions.length > 0 && root.tagSuggIndex >= 0 && root.tagSuggIndex < root.tagSuggestions.length) {
            root.pickTagSuggestion(root.tagSuggIndex);
            return;
        }
        if (root.addTagText(tagInput.text)) {
            tagInput.text = "";
        }
        root.hideTagSuggestions();
    }

    function moveTagSugg(delta) {
        if (root.tagSuggestions.length === 0) return;
        var n = root.tagSuggestions.length;
        var cur = root.tagSuggIndex < 0 ? (delta > 0 ? -1 : 0) : root.tagSuggIndex;
        root.tagSuggIndex = (cur + delta + n) % n;
    }

    // ── Convertir .txt → .md ──────────────────────────
    // Guarda lo pendiente, convierte por el pipeline del servicio (la nota activa
    // se muta en el lugar) y entra a modo bloques conservando cursor y scroll
    // con la lógica existente de toggleSourceMode.
    function convertToMarkdown() {
        if (!root.isTxt || !root.loadedSlug || root.isLoading) return;
        autoSaveTimer.stop();
        root._currentBody = sourceCodeEditor ? sourceCodeEditor.text : root._currentBody;
        root.performSave(function() {
            NotesService.flushPendingSave();
            NotesService.convertTxtToMd(root.loadedSlug, function(newKey, ok) {
                if (!ok || !newKey) {
                    root.showToast(I18n.t("notes.import.failed", "No se pudo importar"));
                    return;
                }
                var oldKey = root.loadedSlug;
                root.loadedSlug = newKey;
                root.isTxt = false;
                root._originalBody = root._currentBody;
                root.noteKeyChanged(oldKey, newKey);
                // Entrar a bloques con mapa de cursor/scroll (toggleSourceMode)
                root.toggleSourceMode();
            });
        });
    }

    // ── Manejo de imágenes (Portal y Copia) ──────────────────────────────────
    // En .txt están bloqueadas: ni picker, ni pegado, ni drop, ni URL
    function _openImagePicker() {
        if (root.isTxt) return;
        imagePickerProc.running = true;
    }

    // Maneja un drop de URLs quedándose solo con imágenes. Devuelve true
    // si manejó al menos una (decodifica %20/acentos, antes se rompía).
    // En .txt no maneja nada.
    function _handleImageDrop(urls) {
        if (root.isTxt) return false;
        var handled = false;
        if (!urls) return false;
        for (var u = 0; u < urls.length; u++) {
            var raw = (urls[u] && urls[u].toString) ? urls[u].toString() : String(urls[u]);
            var cleanUrl = ImportLogic.decodeDropUrl(raw);
            if (!cleanUrl) continue;
            var lower = cleanUrl.toLowerCase();
            if (lower.endsWith(".png") || lower.endsWith(".jpg") || lower.endsWith(".jpeg") ||
                lower.endsWith(".webp") || lower.endsWith(".gif") || lower.endsWith(".svg") || lower.endsWith(".bmp")) {
                root._attachImageFile(cleanUrl);
                handled = true;
            }
        }
        return handled;
    }

    // Inserta la imagen copiada/pegada según el modo (F19: vía attachImage del
    // servicio, punto único que promueve a nota-carpeta si hace falta).
    function _insertAttachedImage(relTag, alt) {
        if (!relTag) return;
        if (root.isSourceMode) {
            root._insertImageTagInSource(relTag, alt || "imagen");
        } else {
            blockEditor.insertImageBlock(relTag, alt || "imagen");
        }
    }

    function _attachImageFile(src) {
        if (!src || root.isTxt || !root.loadedSlug) return;
        var alt = src.indexOf("/") !== -1 ? src.substring(src.lastIndexOf("/") + 1) : src;
        NotesService.attachImage(root.loadedSlug, src, function(relTag, err, newKey) {
            if (!relTag) {
                if (err === "txt") {
                    root.showToast(I18n.t("notes.editor.txt_no_format", "No disponible en .txt — convertí a .md para usar formato"));
                }
                return;
            }
            // La promoción pudo cambiar la clave (carpeta con nombre único)
            if (newKey && newKey !== root.loadedSlug) root.loadedSlug = newKey;
            root._insertAttachedImage(relTag, alt);
        });
    }

    function _insertImageTagInSource(src, alt) {
        if (!sourceCodeEditor) return;
        var tag = "![" + (alt || "imagen") + "](" + src + ")";
        var pos = sourceCodeEditor.cursorPosition;
        var txt = sourceCodeEditor.text;
        var needLeadingNl = (pos > 0 && txt[pos - 1] !== "\n");
        var needTrailingNl = (pos < txt.length && txt[pos] !== "\n");
        var inserted = (needLeadingNl ? "\n\n" : "") + tag + (needTrailingNl ? "\n\n" : "\n");
        sourceCodeEditor.insert(pos, inserted);
        sourceCodeEditor.cursorPosition = pos + inserted.length;
        sourceCodeEditor.forceActiveFocus();
        root.markDirty();
    }

    function pasteClipboardImage() {
        console.log("[PasteImg] Modal.pasteClipboardImage: isTxt=" + root.isTxt + " loadedSlug=" + root.loadedSlug
            + " sourceMode=" + root.isSourceMode);
        if (root.isTxt) {
            root.showToast(I18n.t("notes.editor.txt_no_format", "No disponible en .txt — convertí a .md para usar formato"));
            return;
        }
        var slug = root.loadedSlug || (root.noteData ? (root.noteData.slug || root.noteData.id) : "");
        console.log("[PasteImg] Modal: slug resuelto='" + slug + "'");
        if (!slug) { console.log("[PasteImg] Modal: sin slug, abortando"); return; }
        NotesService.attachImage(slug, "clipboard", function(relTag, errReason, newKey) {
            console.log("[PasteImg] Modal callback: relTag=" + relTag + " err=" + errReason + " newKey=" + newKey);
            if (relTag) {
                if (newKey && newKey !== root.loadedSlug) root.loadedSlug = newKey;
                root._insertAttachedImage(relTag, "imagen");
            } else if (errReason === "txt") {
                root.showToast(I18n.t("notes.editor.txt_no_format", "No disponible en .txt — convertí a .md para usar formato"));
            } else if (errReason !== "busy") {
                root.showToast(I18n.t("notes.paste_img.none", "No hay imagen en el portapapeles"));
            }
        });
    }

    function _confirmWebImageUrl() {
        if (root.isTxt) return;
        var url = webUrlInput.text.trim();
        if (url.startsWith("http://") || url.startsWith("https://")) {
            if (root.isSourceMode) {
                root._insertImageTagInSource(url, "imagen");
            } else {
                blockEditor.insertImageBlock(url, "imagen");
            }
            webUrlBar.visible = false;
            webUrlInput.text = "";
        }
    }

    // ── Modo Código Fuente con preservación de cursor y scroll ───────────
    // En .txt el modo fuente está forzado (no aplica alternar)
    function toggleSourceMode() {
        if (root.isTxt) return;
        root._flushPendingBody();
        if (!root.isSourceMode) {
            var activeBid = blockEditor ? blockEditor.activeBlockBid : -1;
            var activeCursorPos = 0;
            if (activeBid !== -1) {
                var te = blockEditor._getTextEditForBid(activeBid);
                if (te) activeCursorPos = te.cursorPosition;
                blockEditor.confirmActiveBlock();
            }
            var fullMd = blockEditor.getMarkdown();

            var targetCursor = 0;
            if (activeBid !== -1) {
                targetCursor = (blockEditor.documentLead || "").length;
                for (var i = 0; i < blockEditor.blocksCount; i++) {
                    var b = blockEditor.getBlockAt(i);
                    if (b && b.bid === activeBid) {
                        targetCursor += activeCursorPos;
                        break;
                    }
                    if (b) {
                        targetCursor += (b.raw ? b.raw.length : 0) + (b.sep ? b.sep.length : 2);
                    }
                }
            }

            var scrollRatio = blockEditor.contentHeight > 0 ? (blockEditor.contentY / blockEditor.contentHeight) : 0;
            sourceCodeEditor.text = fullMd;
            root._currentBody = fullMd;
            root.isSourceMode = true;
            Qt.callLater(() => {
                sourceCodeEditor.cursorPosition = Math.min(sourceCodeEditor.text.length, targetCursor);
                if (sourceFlickable && sourceFlickable.contentHeight > 0) {
                    sourceFlickable.contentY = scrollRatio * sourceFlickable.contentHeight;
                }
                sourceCodeEditor.forceActiveFocus();
            });
        } else {
            var currentText = sourceCodeEditor.text;
            var sourceCursor = sourceCodeEditor.cursorPosition;
            var sourceRatio = sourceFlickable.contentHeight > 0 ? (sourceFlickable.contentY / sourceFlickable.contentHeight) : 0;

            blockEditor.loadMarkdown(currentText);
            root._currentBody = currentText;
            root.markDirty();
            root.isSourceMode = false;

            Qt.callLater(() => {
                var running = (blockEditor.documentLead || "").length;
                var foundBid = -1;
                var foundInnerPos = 0;
                for (var j = 0; j < blockEditor.blocksCount; j++) {
                    var blk = blockEditor.getBlockAt(j);
                    if (blk) {
                        var blkLen = blk.raw ? blk.raw.length : 0;
                        var sepLen = blk.sep ? blk.sep.length : 2;
                        if (sourceCursor <= running + blkLen + sepLen) {
                            foundBid = blk.bid;
                            foundInnerPos = Math.max(0, Math.min(blkLen, sourceCursor - running));
                            break;
                        }
                        running += blkLen + sepLen;
                    }
                }
                if (foundBid !== -1) {
                    blockEditor.activeBlockBid = foundBid;
                    blockEditor.safeFocusDelegate(foundBid, foundInnerPos);
                    blockEditor.scrollToBid(foundBid);
                } else {
                    if (blockEditor.contentHeight > 0) {
                        blockEditor.contentY = sourceRatio * blockEditor.contentHeight;
                    }
                    blockEditor.forceActiveFocus();
                }
            });
        }
    }

    function restoreContentFromHistory(restoredContent) {
        if (restoredContent === undefined || restoredContent === null) return;
        if (root.isSourceMode && sourceCodeEditor) {
            sourceCodeEditor.text = restoredContent;
        } else if (blockEditor) {
            blockEditor.restoreMarkdown(restoredContent);
        }
        root._currentBody = restoredContent;
        root.markDirty();
        importToast.showText("Versión restaurada (Ctrl+Z para deshacer)");
    }

    function _applySourceInlineFormat(marker) {
        if (!sourceCodeEditor) return;
        var s = sourceCodeEditor.selectionStart;
        var e = sourceCodeEditor.selectionEnd;
        var txt = sourceCodeEditor.text;
        var res = Inline.toggleWrap(txt, s, e, marker);
        if (res && res.text !== txt) {
            sourceCodeEditor.text = res.text;
            sourceCodeEditor.select(res.newSelStart, res.newSelEnd);
            sourceCodeEditor.cursorPosition = res.newSelEnd;
            sourceCodeEditor.forceActiveFocus();
            root.markDirty();
        }
    }

    function _toggleSourceLinePrefix(action) {
        if (!sourceCodeEditor) return;
        var s = sourceCodeEditor.selectionStart;
        var e = sourceCodeEditor.selectionEnd;
        var txt = sourceCodeEditor.text;

        var lineStart = Math.min(s, e);
        while (lineStart > 0 && txt[lineStart - 1] !== "\n") lineStart--;
        var lineEnd = Math.max(s, e);
        while (lineEnd < txt.length && txt[lineEnd] !== "\n") lineEnd++;

        var selectedBlock = txt.substring(lineStart, lineEnd);
        var lines = selectedBlock.split("\n");

        var targetPrefix = "";
        var isHeading = false;
        if (action === "h1") { targetPrefix = "# "; isHeading = true; }
        else if (action === "h2") { targetPrefix = "## "; isHeading = true; }
        else if (action === "h3") { targetPrefix = "### "; isHeading = true; }
        else if (action === "bullet_list") targetPrefix = "- ";
        else if (action === "ordered_list") targetPrefix = "1. ";
        else if (action === "task_list") targetPrefix = "- [ ] ";
        else if (action === "quote") targetPrefix = "> ";

        var allHavePrefix = true;
        for (var i = 0; i < lines.length; i++) {
            var l = lines[i];
            if (isHeading) {
                var reH = new RegExp("^" + targetPrefix.trim() + " ");
                if (!reH.test(l)) { allHavePrefix = false; break; }
            } else if (action === "bullet_list") {
                if (!/^\s*[-*+] (?!\[[ xX]\])/.test(l)) { allHavePrefix = false; break; }
            } else if (action === "ordered_list") {
                if (!/^\s*\d+[\.\)] /.test(l)) { allHavePrefix = false; break; }
            } else if (action === "task_list") {
                if (!/^\s*[-*+]\s*\[[ xX]\] /.test(l)) { allHavePrefix = false; break; }
            } else if (action === "quote") {
                if (!/^\s*> /.test(l)) { allHavePrefix = false; break; }
            }
        }

        var newLines = [];
        for (var j = 0; j < lines.length; j++) {
            var line = lines[j];
            if (allHavePrefix) {
                if (isHeading) newLines.push(line.replace(/^#{1,6}\s*/, ""));
                else if (action === "bullet_list") newLines.push(line.replace(/^\s*[-*+]\s+/, ""));
                else if (action === "ordered_list") newLines.push(line.replace(/^\s*\d+[\.\)]\s+/, ""));
                else if (action === "task_list") newLines.push(line.replace(/^\s*[-*+]\s*\[[ xX]\]\s+/, ""));
                else if (action === "quote") newLines.push(line.replace(/^\s*>\s?/, ""));
            } else {
                var cleanLine = line;
                if (isHeading) {
                    cleanLine = cleanLine.replace(/^#{1,6}\s*/, "");
                    newLines.push(targetPrefix + cleanLine);
                } else if (action === "ordered_list") {
                    cleanLine = cleanLine.replace(/^\s*([-*+](\s*\[[ xX]\])?|\d+[\.\)])\s+/, "");
                    newLines.push((j + 1) + ". " + cleanLine);
                } else if (action === "bullet_list") {
                    cleanLine = cleanLine.replace(/^\s*([-*+](\s*\[[ xX]\])?|\d+[\.\)])\s+/, "");
                    newLines.push("- " + cleanLine);
                } else if (action === "task_list") {
                    cleanLine = cleanLine.replace(/^\s*([-*+](\s*\[[ xX]\])?|\d+[\.\)])\s+/, "");
                    newLines.push("- [ ] " + cleanLine);
                } else if (action === "quote") {
                    cleanLine = cleanLine.replace(/^\s*>\s?/, "");
                    newLines.push("> " + cleanLine);
                }
            }
        }

        var replacement = newLines.join("\n");
        sourceCodeEditor.remove(lineStart, lineEnd);
        sourceCodeEditor.insert(lineStart, replacement);
        sourceCodeEditor.select(lineStart, lineStart + replacement.length);
        sourceCodeEditor.forceActiveFocus();
        root.markDirty();
    }

    function applyFormatOrAction(action) {
        // En .txt no hay formato: todo inerte salvo Buscar (que no pasa por acá)
        if (root.isTxt) return;
        if (root.isSourceMode) {
            if (action === "bold") _applySourceInlineFormat("**");
            else if (action === "italic") _applySourceInlineFormat("*");
            else if (action === "underline") _applySourceInlineFormat("<u>");
            else if (action === "strike") _applySourceInlineFormat("~~");
            else if (action === "highlight") _applySourceInlineFormat("==");
            else if (action === "inline_code") _applySourceInlineFormat("`");
            else if (action === "h1" || action === "h2" || action === "h3" ||
                     action === "bullet_list" || action === "ordered_list" ||
                     action === "task_list" || action === "quote") {
                _toggleSourceLinePrefix(action);
            }
            else if (action === "code_block") {
                _applySourceInlineFormat("```\n");
            }
            else if (action === "hr") {
                var hrPos = sourceCodeEditor.cursorPosition;
                sourceCodeEditor.insert(hrPos, "\n\n---\n\n");
                sourceCodeEditor.cursorPosition = hrPos + 7;
                sourceCodeEditor.forceActiveFocus();
                root.markDirty();
            }
            else if (action === "table") {
                var tPos = sourceCodeEditor.cursorPosition;
                sourceCodeEditor.insert(tPos, "\n| Columna 1 | Columna 2 |\n| --- | --- |\n|  |  |\n");
                sourceCodeEditor.cursorPosition = tPos + 48;
                sourceCodeEditor.forceActiveFocus();
                root.markDirty();
            }
            else if (action === "mermaid" || (typeof action === "string" && action.startsWith("mermaid"))) {
                var mPos = sourceCodeEditor.cursorPosition;
                var tpl = "```mermaid\nflowchart TD\n    A[Inicio] --> B[Fin]\n```\n";
                if (action.startsWith("mermaid:")) {
                    var tKey = action.substring(8);
                    tpl = MermaidTemplates.getTemplate(tKey) + "\n";
                }
                sourceCodeEditor.insert(mPos, "\n" + tpl);
                sourceCodeEditor.cursorPosition = mPos + tpl.length + 1;
                sourceCodeEditor.forceActiveFocus();
                root.markDirty();
            }
            else if (action === "math" || (typeof action === "string" && action.startsWith("math"))) {
                var mathPos = sourceCodeEditor.cursorPosition;
                var mathTpl = "$$\n\\frac{a}{b}\n$$\n";
                if (action.startsWith("math:")) {
                    var mathKey = action.substring(5);
                    mathTpl = MathTemplates.getTemplate(mathKey) + "\n";
                }
                sourceCodeEditor.insert(mathPos, "\n" + mathTpl);
                sourceCodeEditor.cursorPosition = mathPos + mathTpl.length + 1;
                sourceCodeEditor.forceActiveFocus();
                root.markDirty();
            }
            else if (action === "link") {
                var sel = sourceCodeEditor.selectedText;
                if (sel) {
                    var s = sourceCodeEditor.selectionStart;
                    var e = sourceCodeEditor.selectionEnd;
                    sourceCodeEditor.remove(s, e);
                    sourceCodeEditor.insert(s, "[" + sel + "](url)");
                    sourceCodeEditor.cursorPosition = s + sel.length + 3;
                } else {
                    var p = sourceCodeEditor.cursorPosition;
                    sourceCodeEditor.insert(p, "[texto](url)");
                    sourceCodeEditor.select(p + 1, p + 6);
                }
                sourceCodeEditor.forceActiveFocus();
                root.markDirty();
            }
        } else {
            blockEditor.applyAction(action);
        }
    }

    property int sourceFormatSeq: 0

    function isFormatActive(actionId) {
        if (root.readOnly || root.isPreviewMode) return false;
        if (root.isSourceMode) {
            var _ = root.sourceFormatSeq;
            if (!sourceCodeEditor) return false;
            var txt = sourceCodeEditor.text || "";
            var s = sourceCodeEditor.selectionStart;
            var e = sourceCodeEditor.selectionEnd;
            var cur = sourceCodeEditor.cursorPosition;

            // Formatos inline
            if (actionId === "bold" || actionId === "italic" || actionId === "underline" || actionId === "strike" || actionId === "highlight" || actionId === "inline_code" || actionId === "link") {
                var det = Inline.detectFormats(txt, s, e, cur);
                return !!det[actionId];
            }

            // Formatos de bloque / línea
            var pos = cur;
            var lineStart = pos;
            while (lineStart > 0 && txt[lineStart - 1] !== "\n") lineStart--;
            var lineEnd = pos;
            while (lineEnd < txt.length && txt[lineEnd] !== "\n") lineEnd++;
            var line = txt.substring(lineStart, lineEnd);

            // F22: en modo fuente la línea puede ser "- ## texto" (lista + encabezado).
            // Se detecta el encabezado tras quitar el marcador de lista/tarea/ordenada.
            // Así viñeta y H2 pueden estar activos a la vez, igual que en modo bloques.
            var listStripped = line.replace(/^\s*([-*+](\s*\[[ xX]\])?|\d+[.\)])\s+/, "");
            if (actionId === "h1") return /^# [^\n]*/.test(line) || /^# [^\n]*/.test(listStripped);
            if (actionId === "h2") return /^## [^\n]*/.test(line) || /^## [^\n]*/.test(listStripped);
            if (actionId === "h3") return /^### [^\n]*/.test(line) || /^### [^\n]*/.test(listStripped);
            if (actionId === "bullet_list") return /^\s*[-*+] (?!\[[ xX]\])/.test(line);
            if (actionId === "ordered_list") return /^\s*\d+[\.\)] /.test(line);
            if (actionId === "task_list") return /^\s*[-*+]\s*\[[ xX]\] /.test(line);
            if (actionId === "quote") return /^\s*> /.test(line);
            if (actionId === "code_block") {
                var beforeCursor = txt.substring(0, pos);
                var fenceCount = (beforeCursor.match(/^```/gm) || []).length;
                return (fenceCount % 2) === 1;
            }
            return false;
        }

        if (blockEditor && typeof blockEditor.isFormatActive === "function") {
            return blockEditor.isFormatActive(actionId);
        }
        return false;
    }

    // ── Buscar en la nota (Ctrl+F, F2) ──────────────────────────────────────
    // La lista de coincidencias se construye sobre las UNIDADES VISIBLES que
    // pinta cada delegate (el mismo texto que Inline.highlightInHtml resalta).
    // Orden canónico: bloques en orden; dentro del bloque, unidades en orden de
    // pintado (ítems de lista; celdas: encabezados y luego filas); matches por pos.
    // Cada entrada: {bid, type, unit, local, cursor, item, row, col}
    // cursor = posición en el texto editable del delegate, justo al final del
    // match. item/row/col solo aplican a list/table.
    property var _findSrcMatchesList: []

    Timer {
        id: findRecalcTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (root.isFindActive && root.findQuery.trim() !== "") root._updateFindMatches(true);
        }
    }

    function openFind() {
        root.isFindActive = true;
        root._matchEverNavigated = false;
        Qt.callLater(() => {
            findInput.forceActiveFocus();
            findInput.selectAll();
            root._updateFindMatches();
        });
    }

    function closeFind() {
        root.isFindActive = false;
        root._matchEverNavigated = false;
        root.findQuery = "";
        root._findMatchesList = [];
        root._findSrcMatchesList = [];
        root.findTotalMatches = 0;
        root.findMatchIndex = 0;
        if (root.isSourceMode) {
            sourceCodeEditor.forceActiveFocus();
        } else {
            if (blockEditor && blockEditor.activeBlockBid !== -1) {
                blockEditor.safeFocusDelegate(blockEditor.activeBlockBid);
            } else if (blockEditor) {
                blockEditor.forceActiveFocus();
            }
        }
    }

    // Unidades visibles de un bloque para búsqueda (espeja lo que pinta cada
    // Block*.qml). image/hr no pintan texto buscable → contribuyen 0 (antes se
    // contaban desde el raw y el N no coincidía con lo visible).
    function _searchUnitsForBlock(b) {
        if (!b || !b.raw) return [];
        var raw = b.raw;
        var type = b.type || "paragraph";
        if (type === "paragraph") {
            return [{ unit: 0, paintMd: raw, plainCount: false, base: 0, item: -1, row: -2, col: -2 }];
        }
        if (type === "raw") {
            // BlockRaw pinta texto plano (escapeHtml + highlight, como BlockCode)
            return [{ unit: 0, paintMd: raw, plainCount: true, base: 0, item: -1, row: -2, col: -2 }];
        }
        if (type === "heading") {
            // BlockHeading pinta cleanHeadingText (sin prefijo "## ")
            var pre = SearchLogic.headingPrefixLen(raw);
            return [{ unit: 0, paintMd: raw.substring(pre), plainCount: false, base: pre, item: -1, row: -2, col: -2 }];
        }
        if (type === "quote") {
            // F25: la vista segmentada pinta un Text por segmento (párrafo /
            // encabezado / ítem de lista, anidadas aplanadas). Las unidades
            // espejan ese orden para que el contador N coincida con lo pintado.
            // paintMd ya viene sin `##` (igual que BlockList con headingSizes).
            try {
                var qUnits = QP.searchUnits(raw);
                var qOut = [];
                for (var qi = 0; qi < qUnits.length; qi++) {
                    qOut.push({ unit: qi, paintMd: qUnits[qi].paintMd || "", plainCount: false, base: 0, item: -1, row: -2, col: -2 });
                }
                if (qOut.length > 0) return qOut;
            } catch (e) {}
            // Fallback: comportamiento anterior (una sola unidad).
            var qm = SearchLogic.quoteCleanMap(raw);
            return [{ unit: 0, paintMd: qm.clean, plainCount: false, base: 0, item: -1, row: -2, col: -2 }];
        }
        if (type === "list") {
            // BlockList pinta un Text por ítem, en orden (índice = unidad)
            var items = LP.parseList(raw);
            var units = [];
            for (var li = 0; li < items.length; li++) {
                var t = items[li].text || "";
                // inlineToHtml con headingSizes consume "## " inicial (ver T31)
                var hm = t.match(/^(#{1,6})[ \t]+([\s\S]*)$/);
                if (hm) units.push({ unit: li, paintMd: hm[2], plainCount: false, base: t.length - hm[2].length, item: li, row: -2, col: -2 });
                else units.push({ unit: li, paintMd: t, plainCount: false, base: 0, item: li, row: -2, col: -2 });
            }
            return units;
        }
        if (type === "table") {
            // BlockTable pinta encabezados y luego filas, celda por celda. La fila
            // delimitadora (| --- |) no se pinta → no se cuenta.
            var tbl = TP.parseTable(raw);
            if (!tbl || !tbl.headers) return [];
            var tunits = [];
            var u = 0;
            var C = tbl.headers.length;
            for (var c = 0; c < C; c++) tunits.push({ unit: u++, paintMd: tbl.headers[c] || "", plainCount: false, base: 0, item: -1, row: -1, col: c });
            for (var r = 0; r < tbl.rows.length; r++)
                for (var c2 = 0; c2 < C; c2++)
                    tunits.push({ unit: u++, paintMd: (tbl.rows[r][c2] || ""), plainCount: false, base: 0, item: -1, row: r, col: c2 });
            return tunits;
        }
        if (type === "code") {
            // BlockCode pinta pureCodeText (sin fences) con escapeHtml + highlight
            var pr = SearchLogic.codePureRange(raw);
            return [{ unit: 0, paintMd: raw.substring(pr.start, pr.start + pr.length), plainCount: true, base: pr.start, item: -1, row: -2, col: -2 }];
        }
        return [];
    }

    function _updateFindMatches(keepIndex) {
        var q = (root.findQuery || "").trim();
        var blockMatches = [];
        var srcMatches = [];
        if (q !== "") {
            // Modo fuente: texto crudo completo (la selección ES el marcador)
            if (sourceCodeEditor) {
                var srcFound = SearchLogic.findAll(sourceCodeEditor.text || "", q);
                for (var s = 0; s < srcFound.length; s++) srcMatches.push(srcFound[s]);
            }
            // Modo bloques: unidades visibles (N = spans que se van a pintar)
            var count = blockEditor ? blockEditor.blocksCount : 0;
            for (var i = 0; i < count; i++) {
                var b = blockEditor.getBlockAt(i);
                if (!b) continue;
                var units = root._searchUnitsForBlock(b);
                for (var u = 0; u < units.length; u++) {
                    var un = units[u];
                    // Mismo HTML que pinta el delegate (listas: sin imágenes,
                    // van como Image reales aparte; resto: skipMissing igual).
                    var isListUnit = (un.item !== undefined && un.item >= 0);
                    var countSrc = isListUnit ? Inline.stripImages(un.paintMd) : un.paintMd;
                    var countOpts = {};
                    if (!isListUnit && !un.plainCount) {
                        countOpts = {
                            baseFolder: (NotesService.activeNote && NotesService.activeNote.baseFolder) ? NotesService.activeNote.baseFolder : NotesService.notesDir,
                            imageSkipMissing: true,
                            imageExists: function(abs) { return NotesService.imageExistsCached(abs); }
                        };
                    }
                    var html = un.plainCount ? Inline.escapeHtml(countSrc) : Inline.inlineToHtml(countSrc, countOpts);
                    var painted = SearchLogic.countInHtml(html, q);
                    if (painted === 0) continue;
                    var stripped = SearchLogic.stripForSearch(un.paintMd);
                    var found = SearchLogic.findAll(stripped.text, q);
                    for (var f = 0; f < painted; f++) {
                        var cursor = un.base + un.paintMd.length; // fallback: fin de la unidad
                        if (f < found.length) {
                            var lastV = found[f].pos + found[f].len - 1;
                            if (lastV >= 0 && lastV < stripped.map.length) {
                                cursor = un.base + stripped.map[lastV] + 1;
                            } else if (found[f].pos < stripped.map.length) {
                                cursor = un.base + stripped.map[found[f].pos] + found[f].len;
                            }
                        }
                        blockMatches.push({ bid: b.bid, type: b.type, unit: un.unit, local: f, cursor: cursor, item: un.item, row: un.row, col: un.col });
                    }
                }
            }
        }
        root._findMatchesList = blockMatches;
        root._findSrcMatchesList = srcMatches;
        root.findTotalMatches = root.isSourceMode ? srcMatches.length : blockMatches.length;
        if (keepIndex !== true) {
            root.findMatchIndex = 0;
            // La coincidencia 1 ya queda activa al escribir (se hace scroll hasta
            // ella sin mover cursor, robar foco ni disparar guardado).
            root._matchEverNavigated = root.findTotalMatches > 0;
        }
        if (root.findMatchIndex >= root.findTotalMatches) root.findMatchIndex = 0;
    }

    function _findNext() {
        var total = root.isSourceMode ? root._findSrcMatchesList.length : root._findMatchesList.length;
        if (total === 0) return;
        if (!root._matchEverNavigated) {
            root._matchEverNavigated = true;
        } else {
            root.findMatchIndex = (root.findMatchIndex + 1) % total;
        }
        root._scrollToCurrentMatch();
    }

    function _findPrev() {
        var total = root.isSourceMode ? root._findSrcMatchesList.length : root._findMatchesList.length;
        if (total === 0) return;
        if (!root._matchEverNavigated) {
            root._matchEverNavigated = true;
            root.findMatchIndex = total - 1;
        } else {
            root.findMatchIndex = (root.findMatchIndex - 1 + total) % total;
        }
        root._scrollToCurrentMatch();
    }

    // Navegación = mover el marcador activo + scroll. En modo bloques NO toca
    // selección ni cursor (la activa se distingue por pintado); en modo fuente
    // la selección ES el marcador (persistentSelection) y el foco sigue en el campo.
    function _scrollToCurrentMatch() {
        if (root.findTotalMatches === 0) return;
        if (root.isSourceMode) {
            var sm = root._findSrcMatchesList[root.findMatchIndex];
            if (!sm || !sourceCodeEditor || !sourceFlickable) return;
            sourceCodeEditor.select(sm.pos, sm.pos + sm.len);
            var rect = sourceCodeEditor.positionToRectangle(sm.pos);
            var maxY = Math.max(0, sourceFlickable.contentHeight - sourceFlickable.height);
            sourceFlickable.contentY = Math.max(0, Math.min(maxY, rect.y - sourceFlickable.height / 3));
        } else {
            var m = root._findMatchesList[root.findMatchIndex];
            if (!m) return;
            if (blockEditor && typeof blockEditor.scrollToBid === "function") {
                blockEditor.scrollToBid(m.bid);
            }
        }
    }

    // Enter en el campo = confirmar la coincidencia activa: activar el bloque y
    // dejar el cursor justo al final de la palabra, sin selección residual. La
    // barra queda abierta (Escape la cierra).
    function _confirmActiveMatch() {
        if (root.findTotalMatches === 0) return;
        if (root.isSourceMode) {
            var sm = root._findSrcMatchesList[root.findMatchIndex];
            if (!sm || !sourceCodeEditor) return;
            sourceCodeEditor.cursorPosition = sm.pos + sm.len;
            sourceCodeEditor.forceActiveFocus();
            return;
        }
        var m = root._findMatchesList[root.findMatchIndex];
        if (!m || !blockEditor) return;
        // Si el modelo aún no cargó (morph en curso), cargarlo ya
        root._flushPendingBody();
        blockEditor.requestEditBlock(m.bid);
        Qt.callLater(() => {
            if (!blockEditor) return;
            var loader = blockEditor._getDelegateItemForBid(m.bid);
            var del = (loader && loader.item) ? loader.item : null;
            if (!del) return;
            if (m.type === "list" && typeof del.focusSearchMatch === "function") {
                del.focusSearchMatch(m.item, m.cursor);
            } else if (m.type === "table" && typeof del.focusCell === "function") {
                del.focusCell(m.row, m.col, m.cursor);
            } else if (typeof del.focusInput === "function") {
                del.focusInput(m.cursor);
            }
        });
    }

    // ── Atajos de teclado en el editor (Fase 1: tabla unificada de atajos) ─────
    Keys.onPressed: (event) => {
        var isCtrl = !!(event.modifiers & Qt.ControlModifier);
        var isShift = !!(event.modifiers & Qt.ShiftModifier);
        var isAlt = !!(event.modifiers & Qt.AltModifier);

        if (event.key === Qt.Key_F3 || (isCtrl && event.key === Qt.Key_G)) {
            if (root.isFindActive) {
                if (isShift) root._findPrev();
                else root._findNext();
            } else {
                root.openFind();
            }
            event.accepted = true;
            return;
        }

        // Escape: Si el popup de imagen está abierto, lo cierra; si la barra de búsqueda está activa, la cierra; si hay bloque en edición, confirma; si no, cierra la nota
        if (event.key === Qt.Key_F7) {
            blockEditor.toggleSpellCheck();
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_F10) {
            for (var bi = 0; bi < toolbarRow.children.length; bi++) {
                var tbBtn = toolbarRow.children[bi];
                if (tbBtn && tbBtn.activeFocusOnTab && !tbBtn.disabled) {
                    tbBtn.forceActiveFocus();
                    event.accepted = true;
                    return;
                }
            }
        }

        if (event.key === Qt.Key_Escape) {
            event.accepted = true;
            if (imageMenuPopup.isOpen) {
                imageMenuPopup.isOpen = false;
            } else if (mermaidMenuPopup.isOpen) {
                mermaidMenuPopup.isOpen = false;
            } else if (mathMenuPopup.isOpen) {
                mathMenuPopup.isOpen = false;
            } else if (root.isFindActive) {
                root.closeFind();
            } else {
                if (!root.isSourceMode && blockEditor && blockEditor.activeBlockBid !== -1) {
                    blockEditor.confirmActiveBlock();
                }
                root.requestClose();
            }
            return;
        }

        // Atajos con Ctrl + Shift
        if (isCtrl && isShift && !isAlt) {
            if (event.key === Qt.Key_Plus) {
                EditorMetrics.zoomIn();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Z) {
                if (root.isSourceMode && sourceCodeEditor) sourceCodeEditor.redo();
                else blockEditor.redo();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_X) {
                root.applyFormatOrAction("strike");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_8) {
                root.applyFormatOrAction("bullet_list");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_7 && event.text !== "/") {
                root.applyFormatOrAction("ordered_list");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_9) {
                root.applyFormatOrAction("task_list");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Q) {
                root.applyFormatOrAction("quote");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_E) {
                root.applyFormatOrAction("code_block");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_T) {
                root.applyFormatOrAction("table");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_M) {
                root.applyFormatOrAction("mermaid");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_H) {
                root.applyFormatOrAction("hr");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_I) {
                root._openImagePicker();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_V) {
                root.pasteClipboardImage();
                event.accepted = true;
                return;
            }
        }

        // Atajos con Ctrl + Alt
        if (isCtrl && isAlt && !isShift) {
            if (event.key === Qt.Key_1) {
                root.applyFormatOrAction("h1");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_2) {
                root.applyFormatOrAction("h2");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_3) {
                root.applyFormatOrAction("h3");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_4) {
                root.applyFormatOrAction("h4");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_5) {
                root.applyFormatOrAction("h5");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_6) {
                root.applyFormatOrAction("h6");
                event.accepted = true;
                return;
            }
        }

        // Atajos con Ctrl solo
        if (isCtrl && !isShift && !isAlt) {
            if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
                EditorMetrics.zoomIn();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Minus) {
                EditorMetrics.zoomOut();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_0) {
                EditorMetrics.zoomReset();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_S) {
                event.accepted = true;
                root.performSave(null, true);
                return;
            }
            if (event.key === Qt.Key_W) {
                event.accepted = true;
                root.requestClose();
                return;
            }
            if (event.key === Qt.Key_F) {
                event.accepted = true;
                root.openFind();
                return;
            }
            if (event.key === Qt.Key_Z) {
                if (root.isSourceMode && sourceCodeEditor) sourceCodeEditor.undo();
                else blockEditor.undo();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Y) {
                if (root.isSourceMode && sourceCodeEditor) sourceCodeEditor.redo();
                else blockEditor.redo();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_B) {
                root.applyFormatOrAction("bold");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_I) {
                root.applyFormatOrAction("italic");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_U) {
                root.applyFormatOrAction("underline");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_H) {
                root.applyFormatOrAction("highlight");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_K) {
                root.applyFormatOrAction("link");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_E || event.key === Qt.Key_QuoteLeft) {
                root.applyFormatOrAction("inline_code");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_V) {
                // F23: el título nunca pega imágenes.
                if (titleInput && titleInput.activeFocus) return;
                var activeInput = null;
                if (root.isSourceMode && sourceCodeEditor && sourceCodeEditor.activeFocus) {
                    activeInput = sourceCodeEditor;
                } else if (blockEditor && blockEditor.activeBlockBid !== -1) {
                    activeInput = blockEditor._getTextEditForBid(blockEditor.activeBlockBid);
                }
                console.log("[PasteImg] Ctrl+V modal: activeInput=" + !!activeInput + " canPaste=" + (activeInput ? activeInput.canPaste : "n/a"));
                if (!activeInput || !activeInput.canPaste) {
                    root.pasteClipboardImage();
                    event.accepted = true;
                    return;
                }
            }
            // F23: Shift+Insert sin bloque activo se trata igual que Ctrl+V (salvo título).
            if ((event.modifiers & Qt.ShiftModifier) && !(event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Insert) {
                if (titleInput && titleInput.activeFocus) return;
                var activeInput2 = null;
                if (root.isSourceMode && sourceCodeEditor && sourceCodeEditor.activeFocus) {
                    activeInput2 = sourceCodeEditor;
                } else if (blockEditor && blockEditor.activeBlockBid !== -1) {
                    activeInput2 = blockEditor._getTextEditForBid(blockEditor.activeBlockBid);
                }
                if (!activeInput2 || !activeInput2.canPaste) {
                    root.pasteClipboardImage();
                    event.accepted = true;
                    return;
                }
            }
        }
    }

    // ── Contenedor principal de la nota ──────────────────────────────────────
    Item {
        id: modalContainer
        anchors.fill: parent

        ColumnLayout {
            id: mainColumn
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            // ── Barra superior (Volver, Título, Subtítulo, Fijar, Borrar, Guardado) ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // Botón volver / cerrar
                Rectangle {
                    id: backBtnRect
                    width: 34
                    height: 34
                    radius: 10
                    color: backBtnMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12) : "transparent"
                    opacity: root.isExpanded ? 1.0 : 0.0
                    visible: opacity > 0.0

                    Behavior on opacity {
                        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }

                    Behavior on color {
                        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                        ColorAnimation { duration: 140 }
                    }

                    Image {
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        source: Theme.iconsPath + "close.svg"
                        sourceSize: Qt.size(18, 18)
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: backBtnMa.containsMouse ? Theme.text : Theme.muted
                            Behavior on colorizationColor {
                                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                ColorAnimation { duration: 140 }
                            }
                        }
                    }

                    MouseArea {
                        id: backBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: tooltipLayer.showTooltip(parent, I18n.t("notes.editor.action.close", "Cerrar editor"), "Esc")
                        onExited: tooltipLayer.hideTooltip()
                        onClicked: {
                            tooltipLayer.hideTooltip();
                            root.requestClose();
                        }
                    }
                }

                // Título y nombre de archivo .md
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    TextInput {
                        id: titleInput
                        Layout.fillWidth: true
                        color: Theme.text
                        font.family: Theme.fontFamilyDisplay
                        font.pixelSize: Theme.fontSizeTitleLarge
                        font.bold: true
                        selectByMouse: true
                        readOnly: root.isPreviewMode
                        CustomTextCursor {}

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.t("notes.editor.title_placeholder", "Título de la nota...")
                            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.3)
                            font: parent.font
                            visible: !parent.text && !parent.activeFocus
                        }

                        onTextChanged: {
                            if (!root.isLoading && root.loadedSlug !== "") {
                                if (titleInput.text.trim() !== root._originalTitle) {
                                    root.markDirty();
                                }
                            }
                        }

                        onAccepted: root._confirmTitleRename()
                        onActiveFocusChanged: if (!activeFocus) root._confirmTitleRename()

                        Keys.onDownPressed: (event) => {
                            root._confirmTitleRename();
                            if (blockEditor && blockEditor.blocksModel.count > 0) {
                                blockEditor.requestEditBlock(blockEditor.blocksModel.get(0).bid, 0);
                                event.accepted = true;
                            }
                        }

                        Keys.onReturnPressed: (event) => {
                            root._confirmTitleRename();
                            if (blockEditor && blockEditor.blocksModel.count > 0) {
                                blockEditor.requestEditBlock(blockEditor.blocksModel.get(0).bid, 0);
                                event.accepted = true;
                            }
                        }

                        Keys.onEnterPressed: (event) => Keys.onReturnPressed(event)

                        Keys.onTabPressed: (event) => {
                            if (tagsRow.visible && tagInputBox.visible && tagInput) {
                                tagInput.forceActiveFocus();
                                event.accepted = true;
                            } else if (blockEditor && blockEditor.blocksModel.count > 0) {
                                blockEditor.requestEditBlock(blockEditor.blocksModel.get(0).bid, 0);
                                event.accepted = true;
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) {
                                    titleInput.forceActiveFocus();
                                    editorContextMenu.open(parent);
                                }
                            }
                        }
                    }

                    Item {
                        id: fileNameContainer
                        Layout.fillWidth: true
                        Layout.preferredHeight: fileNameLabel.implicitHeight
                        opacity: root.isExpanded ? 0.75 : 0.0
                        visible: opacity > 0.0 && fileNameLabel.text.length > 0

                        Text {
                            id: fileNameLabel
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            // Nombre real del archivo (con su extensión .md/.txt).
                            // Se resuelve por clave: loadedSlug cambia en rename/convert.
                            text: {
                                if (root.isExternalNote) {
                                    var home = (Quickshell.env("HOME") || "");
                                    var fp = (root.noteData && root.noteData.filePath) ? root.noteData.filePath : "";
                                    return (home !== "" && fp.startsWith(home + "/")) ? "~/" + fp.substring(home.length + 1) : fp;
                                }
                                // Dependencia reactiva: promote/rename/convert mutan la
                                // nota en el lugar (sin señal) y hay que repintar igual.
                                NotesService.filesVersion;
                                var n = NotesService.getNote(root.loadedSlug);
                                return (n && n.fileName) ? n.fileName : "";
                            }
                            color: fileClickMa.containsMouse ? Theme.text : Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeCaption
                            font.underline: fileClickMa.containsMouse
                            elide: Text.ElideRight

                            Behavior on color {
                                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                ColorAnimation { duration: 120 }
                            }
                        }

                        MouseArea {
                            id: fileClickMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var n = NotesService.getNote(root.loadedSlug);
                                var path = (n && n.filePath) ? n.filePath : ((root.noteData && root.noteData.filePath) ? root.noteData.filePath : "");
                                if (path) {
                                    Quickshell.clipboardText = path;
                                    root.showToast(I18n.t("notes.toast.path_copied", "Ruta copiada al portapapeles"));
                                }
                            }
                        }
                    }
                }

                // Botón Fijar
                Rectangle {
                    width: 34
                    height: 34
                    radius: 10
                    opacity: root.isExpanded ? 1.0 : 0.0
                    visible: opacity > 0.0 && !root.isPreviewMode
                    color: root.isPinned
                        ? Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.22)
                        : (pinBtnMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12) : "transparent")

                    Behavior on color {
                        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                        ColorAnimation { duration: 140 }
                    }

                    Image {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        source: Theme.iconsPath + "push-pin.svg"
                        sourceSize: Qt.size(16, 16)
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: root.isPinned
                                ? Theme.accent
                                : (pinBtnMa.containsMouse ? Theme.accent : Theme.muted)
                        }
                    }

                    MouseArea {
                        id: pinBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: tooltipLayer.showTooltip(parent, root.isPinned ? I18n.t("notes.editor.action.unpin", "Desfijar nota") : I18n.t("notes.editor.action.pin", "Fijar nota"), "")
                        onExited: tooltipLayer.hideTooltip()
                        onClicked: {
                            tooltipLayer.hideTooltip();
                            root.isPinned = !root.isPinned;
                            root.performSave(null, true);
                        }
                    }
                }

                // Botón Borrar
                Rectangle {
                    width: 34
                    height: 34
                    radius: 10
                    opacity: root.isExpanded ? 1.0 : 0.0
                    visible: opacity > 0.0 && !root.isPreviewMode
                    color: delBtnMa.containsMouse ? Qt.rgba(1, 0.2, 0.2, 0.22) : "transparent"

                    Behavior on color {
                        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                        ColorAnimation { duration: 140 }
                    }

                    Image {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        source: Theme.iconsPath + "delete.svg"
                        sourceSize: Qt.size(16, 16)
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: delBtnMa.containsMouse ? Theme.danger : Theme.muted
                        }
                    }

                    MouseArea {
                        id: delBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: tooltipLayer.showTooltip(parent, I18n.t("notes.editor.action.delete", "Eliminar nota"), "")
                        onExited: tooltipLayer.hideTooltip()
                        onClicked: {
                            tooltipLayer.hideTooltip();
                            var slugToDelete = root.loadedSlug || (root.noteData ? (root.noteData.slug || root.noteData.id) : "");
                            if (NotesService._pendingSlug === slugToDelete) {
                                NotesService._pendingSave = null;
                                NotesService._pendingSlug = "";
                            }
                            root.dirty = false;
                            root.deleteRequested(slugToDelete);
                        }
                    }
                }

                // Botón "Importar a Notas" (cuando se edita un archivo externo directamente)
                Rectangle {
                    height: 30
                    radius: 8
                    color: importEditMa.containsMouse ? Qt.darker(Theme.accent, 1.15) : Theme.accent
                    Layout.preferredWidth: importEditRow.implicitWidth + 20
                    opacity: root.isExpanded ? 1.0 : 0.0
                    visible: opacity > 0.0 && root.isExternalNote && !root.isPreviewMode

                    Behavior on color {
                        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                        ColorAnimation { duration: 140 }
                    }

                    RowLayout {
                        id: importEditRow
                        anchors.centerIn: parent
                        spacing: 6

                        Image {
                            width: 14
                            height: 14
                            source: Theme.iconsPath + "download.svg"
                            sourceSize: Qt.size(14, 14)
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: Theme.textOn(Theme.accent)
                            }
                        }

                        Text {
                            text: I18n.t("notes.preview.action_import", "Importar a Notas")
                            color: Theme.textOn(Theme.accent)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }
                    }

                    MouseArea {
                        id: importEditMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: tooltipLayer.showTooltip(parent, I18n.t("notes.preview.action_import_desc", "Importar esta nota externa a tu carpeta de notas"), "")
                        onExited: tooltipLayer.hideTooltip()
                        onClicked: {
                            tooltipLayer.hideTooltip();
                            NotesService.importExternalAndEdit();
                        }
                    }
                }

                // Indicador de estado de guardado
                Rectangle {
                    height: 30
                    radius: 15
                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)
                    Layout.preferredWidth: saveStatusRow.implicitWidth + 20
                    opacity: root.isExpanded ? 1.0 : 0.0
                    visible: opacity > 0.0

                    RowLayout {
                        id: saveStatusRow
                        anchors.centerIn: parent
                        spacing: 6

                        Rectangle {
                            width: 6
                            height: 6
                            radius: 3
                            color: {
                                if (root.isPreviewMode) return Theme.accent;
                                if (NotesService.saveState === "error") return Theme.danger;
                                if (NotesService.saveState === "conflict" || root.hasConflict) return Theme.warning;
                                if (NotesService.saveState === "saving") return Theme.accent;
                                if (root.dirty) return Theme.warning;
                                return Theme.success;
                            }
                        }

                        Text {
                            text: {
                                if (root.isPreviewMode) return I18n.t("notes.preview.badge", "Vista previa · Solo lectura");
                                if (NotesService.saveState === "error") return I18n.t("notes.editor.error", "Error al guardar");
                                if (NotesService.saveState === "conflict" || root.hasConflict) return I18n.t("notes.editor.conflict", "Conflicto");
                                if (NotesService.saveState === "saving") return I18n.t("notes.editor.saving", "Guardando...");
                                if (root.dirty) return I18n.t("notes.editor.editing", "Sin guardar");
                                return I18n.t("notes.editor.saved", "Guardado");
                            }
                            color: {
                                if (root.isPreviewMode) return Theme.text;
                                if (NotesService.saveState === "error") return Theme.danger;
                                if (NotesService.saveState === "conflict" || root.hasConflict) return Theme.warning;
                                return Theme.muted;
                            }
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeCaption
                        }
                    }

                    MouseArea {
                        id: saveStatusMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            if (NotesService.saveState === "error") {
                                tooltipLayer.showTooltip(parent, NotesService.saveErrorMessage || I18n.t("notes.editor.retry", "Reintentar guardado"), "");
                            } else {
                                tooltipLayer.showTooltip(parent, I18n.t("notes.editor.action.save", "Guardar nota"), "Ctrl+S");
                            }
                        }
                        onExited: tooltipLayer.hideTooltip()
                        onClicked: {
                            tooltipLayer.hideTooltip();
                            if (NotesService.saveState === "error") {
                                NotesService.retryFailedWrites();
                                root.performSave(null, true);
                            } else {
                                root.performSave(null, true);
                            }
                        }
                    }
                }
            }

            // ── Fila de etiquetas del front matter ────────────────────
            // Oculta en .txt (sin front matter). Chips con × + campo con
            // autocompletado desde NotesService.allTags.
            RowLayout {
                id: tagsRow
                Layout.fillWidth: true
                Layout.preferredHeight: root.isTxt ? 0 : 30
                visible: !root.isTxt && root.isExpanded && (!root.isPreviewMode || (root.editTags && root.editTags.length > 0))
                opacity: root.isExpanded ? 1.0 : 0.0
                spacing: 6
                clip: true

                Behavior on opacity {
                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }

                Repeater {
                    model: root.editTags
                    Rectangle {
                        Layout.preferredHeight: 22
                        Layout.preferredWidth: tagChipLabel.implicitWidth + (root.isPreviewMode ? 16 : 30)
                        radius: 11
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3)
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: root.isPreviewMode ? 8 : 6
                            spacing: 4

                            Text {
                                id: tagChipLabel
                                Layout.fillWidth: true
                                text: "#" + modelData
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeCaption - 1
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                text: "×"
                                visible: !root.isPreviewMode
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody - 1

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.removeTagAt(index)
                                }
                            }
                        }
                    }
                }

                // Campo para agregar (Enter o coma; Backspace en vacío no borra)
                Rectangle {
                    id: tagInputBox
                    visible: !root.isPreviewMode
                    Layout.preferredHeight: 26
                    Layout.preferredWidth: 150
                    radius: 8
                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05)
                    border.color: tagInput.activeFocus ? Theme.accent : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.15)
                    border.width: 1

                    TextInput {
                        id: tagInput
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeCaption
                        selectByMouse: true
                        maximumLength: 44
                        clip: true
                        CustomTextCursor {}

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: I18n.t("notes.editor.tags_add", "Agregar etiqueta")
                            color: Theme.muted
                            font: tagInput.font
                            visible: !tagInput.text && !tagInput.activeFocus
                            elide: Text.ElideRight
                        }

                        onTextChanged: {
                            var ci = text.indexOf(",");
                            if (ci !== -1) {
                                var left = text.substring(0, ci);
                                text = text.substring(ci + 1);
                                root.addTagText(left);
                            }
                            root.updateTagSuggestions();
                        }

                        Keys.onReturnPressed: (event) => {
                            if (tagInput.text.trim() === "") {
                                if (blockEditor && blockEditor.blocksModel.count > 0) {
                                    blockEditor.requestEditBlock(blockEditor.blocksModel.get(0).bid, 0);
                                    event.accepted = true;
                                    return;
                                }
                            }
                            root.confirmTagInput();
                            event.accepted = true;
                        }
                        Keys.onEnterPressed: (event) => Keys.onReturnPressed(event)
                        Keys.onUpPressed: (event) => {
                            if (root.tagSuggestions.length > 0) {
                                root.moveTagSugg(-1);
                                event.accepted = true;
                            } else {
                                root.focusTitleInput();
                                event.accepted = true;
                            }
                        }
                        Keys.onDownPressed: (event) => {
                            if (root.tagSuggestions.length > 0) {
                                root.moveTagSugg(1);
                                event.accepted = true;
                            } else if (blockEditor && blockEditor.blocksModel.count > 0) {
                                blockEditor.requestEditBlock(blockEditor.blocksModel.get(0).bid, 0);
                                event.accepted = true;
                            }
                        }
                        Keys.onTabPressed: (event) => {
                            if (blockEditor && blockEditor.blocksModel.count > 0) {
                                blockEditor.requestEditBlock(blockEditor.blocksModel.get(0).bid, 0);
                                event.accepted = true;
                            }
                        }
                        Keys.onEscapePressed: (event) => {
                            if (root.tagSuggestions.length > 0) {
                                root.hideTagSuggestions();
                                event.accepted = true;
                            }
                        }
                        onActiveFocusChanged: {
                            if (!activeFocus) root.hideTagSuggestions();
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) {
                                    tagInput.forceActiveFocus();
                                    editorContextMenu.open(tagInput);
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: I18n.t("notes.editor.tags_hint", "Enter o coma para agregar")
                    color: Qt.hsva(Theme.muted.hsvHue, Theme.muted.hsvSaturation, Theme.muted.hsvValue, 0.7)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeCaption - 1
                    elide: Text.ElideRight
                    visible: root.editTags.length === 0
                }
            }

            // Banner de conflicto externo
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.hasConflict ? 38 : 0
                visible: root.hasConflict
                clip: true
                radius: 8
                color: Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.15)
                border.color: Theme.warning
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: I18n.t("notes.editor.conflict_detected", "El archivo fue modificado externamente.")
                        color: Theme.warning
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeCaption
                        font.bold: true
                    }

                    // Opción 1: Recargar disco
                    Rectangle {
                        width: 110; height: 26; radius: 6
                        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1)
                        Text {
                            anchors.centerIn: parent
                            text: I18n.t("notes.editor.reload_disk", "Recargar disco")
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeCaption - 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var clean = MD.getCleanBody({ body: root.conflictContent });
                                root._originalBody = clean;
                                root._currentBody = clean;
                                blockEditor.loadMarkdown(clean);
                                root.dirty = false;
                                root.hasConflict = false;
                                NotesService.saveState = "saved";
                            }
                        }
                    }

                    // Opción 2: Conservar ambas
                    Rectangle {
                        width: 120; height: 26; radius: 6
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2)
                        Text {
                            anchors.centerIn: parent
                            text: I18n.t("notes.editor.keep_both", "Conservar ambas")
                            color: Theme.accent
                            font.pixelSize: Theme.fontSizeCaption - 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.resolveConflictKeepBoth()
                        }
                    }

                    // Opción 3: Sobrescribir
                    Rectangle {
                        width: 100; height: 26; radius: 6
                        color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.2)
                        Text {
                            anchors.centerIn: parent
                            text: I18n.t("notes.editor.overwrite_disk", "Sobrescribir")
                            color: Theme.danger
                            font.pixelSize: Theme.fontSizeCaption - 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.hasConflict = false;
                                root.dirty = true;
                                root.performSave(null, true);
                            }
                        }
                    }
                }
            }

            // ── Barra de aviso para Modo Vista Previa (Solo Lectura) ────────
            Rectangle {
                id: previewBanner
                Layout.fillWidth: true
                height: 44
                radius: 10
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.08)
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                border.width: 1
                visible: root.isPreviewMode && root.isExpanded

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Image {
                        width: 18
                        height: 18
                        source: Theme.iconsPath + "info.svg"
                        sourceSize: Qt.size(18, 18)
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: Theme.accent
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: I18n.t("notes.preview.banner_text", "Archivo externo abierto en modo de solo lectura.")
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight
                    }

                    // Botón "Editar aquí"
                    Rectangle {
                        height: 30
                        radius: 8
                        color: editInPlaceMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12) : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)
                        Layout.preferredWidth: editInPlaceRow.implicitWidth + 20

                        RowLayout {
                            id: editInPlaceRow
                            anchors.centerIn: parent
                            spacing: 6

                            Image {
                                width: 14
                                height: 14
                                source: Theme.iconsPath + "edit.svg"
                                sourceSize: Qt.size(14, 14)
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: Theme.text
                                }
                            }

                            Text {
                                text: I18n.t("notes.preview.action_edit_inplace", "Editar aquí")
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                            }
                        }

                        MouseArea {
                            id: editInPlaceMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                NotesService.unlockExternalInPlace();
                            }
                        }
                    }

                    // Botón "Importar a Notas"
                    Rectangle {
                        height: 30
                        radius: 8
                        color: importMa.containsMouse ? Qt.darker(Theme.accent, 1.15) : Theme.accent
                        Layout.preferredWidth: importRow.implicitWidth + 20

                        RowLayout {
                            id: importRow
                            anchors.centerIn: parent
                            spacing: 6

                            Image {
                                width: 14
                                height: 14
                                source: Theme.iconsPath + "download.svg"
                                sourceSize: Qt.size(14, 14)
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: Theme.textOn(Theme.accent)
                                }
                            }

                            Text {
                                text: I18n.t("notes.preview.action_import", "Importar a Notas")
                                color: Theme.textOn(Theme.accent)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                            }
                        }

                        MouseArea {
                            id: importMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                NotesService.importExternalAndEdit();
                            }
                        }
                    }
                }
            }

            // ── Barra de herramientas de formato Markdown ─────────────────
            Rectangle {
                id: toolbarRect
                Layout.fillWidth: true
                height: 42
                radius: 10
                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04)
                opacity: root.isExpanded ? 1.0 : 0.0
                visible: !root.isPreviewMode && opacity > 0.0

                Behavior on opacity {
                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: toolbarRow.implicitWidth
                    clip: true
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentWidth > width
                    onContentXChanged: tooltipLayer.hideTooltip()

                    RowLayout {
                        id: toolbarRow
                        height: parent.height
                        spacing: 2

                        Keys.onRightPressed: (event) => {
                            var btns = [];
                            for (var i = 0; i < toolbarRow.children.length; i++) {
                                var c = toolbarRow.children[i];
                                if (c && c.visible && c.activeFocusOnTab && !c.disabled) btns.push(c);
                            }
                            for (var j = 0; j < btns.length; j++) {
                                if (btns[j].activeFocus) {
                                    var nextBtn = btns[(j + 1) % btns.length];
                                    if (nextBtn) nextBtn.forceActiveFocus();
                                    event.accepted = true;
                                    return;
                                }
                            }
                            if (btns.length > 0) btns[0].forceActiveFocus();
                            event.accepted = true;
                        }

                        Keys.onLeftPressed: (event) => {
                            var btns = [];
                            for (var i = 0; i < toolbarRow.children.length; i++) {
                                var c = toolbarRow.children[i];
                                if (c && c.visible && c.activeFocusOnTab && !c.disabled) btns.push(c);
                            }
                            for (var j = 0; j < btns.length; j++) {
                                if (btns[j].activeFocus) {
                                    var prevBtn = btns[(j - 1 + btns.length) % btns.length];
                                    if (prevBtn) prevBtn.forceActiveFocus();
                                    event.accepted = true;
                                    return;
                                }
                            }
                            if (btns.length > 0) btns[btns.length - 1].forceActiveFocus();
                            event.accepted = true;
                        }

                        Keys.onEscapePressed: (event) => {
                            if (root.blockEditor) root.blockEditor.forceActiveFocus();
                            event.accepted = true;
                        }

                        // 1. Negrita
                        ToolbarButton {
                            actionId: "bold"
                            disabled: root.isTxt
                            tooltipLayer: tooltipLayer
                            iconSource: Theme.iconsPath + "format-bold.svg"
                            active: root.isFormatActive("bold")
                            onClicked: root.applyFormatOrAction("bold")
                        }

                        // 2. Cursiva
                        ToolbarButton {
                            actionId: "italic"
                            disabled: root.isTxt
                            tooltipLayer: tooltipLayer
                            iconSource: Theme.iconsPath + "format-italic.svg"
                            active: root.isFormatActive("italic")
                            onClicked: root.applyFormatOrAction("italic")
                        }

                        // 3. Subrayado
                        ToolbarButton {
                            actionId: "underline"
                            disabled: root.isTxt
                            tooltipLayer: tooltipLayer
                            textLabel: "U"
                            underlineText: true
                            active: root.isFormatActive("underline")
                            onClicked: root.applyFormatOrAction("underline")
                        }

                        // 4. Tachado
                        ToolbarButton {
                            actionId: "strike"
                            disabled: root.isTxt
                            tooltipLayer: tooltipLayer
                            iconSource: Theme.iconsPath + "format-strikethrough.svg"
                            active: root.isFormatActive("strike")
                            onClicked: root.applyFormatOrAction("strike")
                        }

                        // 5. Resaltado
                        ToolbarButton {
                            actionId: "highlight"
                            disabled: root.isTxt
                            tooltipLayer: tooltipLayer
                            iconSource: Theme.iconsPath + "format-highlight.svg"
                            active: root.isFormatActive("highlight")
                            onClicked: root.applyFormatOrAction("highlight")
                        }

                        // 6. Código inline
                        ToolbarButton {
                            actionId: "inline_code"
                            disabled: root.isTxt
                            tooltipLayer: tooltipLayer
                            iconSource: Theme.iconsPath + "code.svg"
                            active: root.isFormatActive("inline_code")
                            onClicked: root.applyFormatOrAction("inline_code")
                        }

                        Rectangle { width: 1; height: 18; color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1) }

                        // 6. H1
                        ToolbarButton {
                            actionId: "h1"
                            disabled: root.isTxt
                            tooltipLayer: tooltipLayer
                            textLabel: "H1"
                            active: root.isFormatActive("h1")
                            onClicked: root.applyFormatOrAction("h1")
                        }

                        // 7. H2
                        ToolbarButton {
                            actionId: "h2"
                            disabled: root.isTxt
                            tooltipLayer: tooltipLayer
                            textLabel: "H2"
                            active: root.isFormatActive("h2")
                            onClicked: root.applyFormatOrAction("h2")
                        }

                        // 8. H3
                        ToolbarButton {
                            actionId: "h3"
                            disabled: root.isTxt
                            tooltipLayer: tooltipLayer
                            textLabel: "H3"
                            active: root.isFormatActive("h3")
                            onClicked: root.applyFormatOrAction("h3")
                        }

                        Rectangle { width: 1; height: 18; color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1) }

                        // 9. Bullet list
                        ToolbarButton {
                            actionId: "bullet_list"
                            disabled: root.isTxt
                            tooltipLayer: tooltipLayer
                            textLabel: "•"
                            active: root.isFormatActive("bullet_list")
                            onClicked: root.applyFormatOrAction("bullet_list")
                        }

                        // 10. Numbered list
                        ToolbarButton {
                            actionId: "ordered_list"
                            disabled: root.isTxt
                            tooltipLayer: tooltipLayer
                            textLabel: "1."
                            active: root.isFormatActive("ordered_list")
                            onClicked: root.applyFormatOrAction("ordered_list")
                        }

                        // 11. Checklist
                        ToolbarButton {
                            actionId: "task_list"
                            disabled: root.isTxt
                            tooltipLayer: tooltipLayer
                            iconSource: Theme.iconsPath + "checklist.svg"
                            active: root.isFormatActive("task_list")
                            onClicked: root.applyFormatOrAction("task_list")
                        }

                        Rectangle { width: 1; height: 18; color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1) }

                        // 12. Blockquote
                        ToolbarButton {
                            actionId: "quote"
                            disabled: root.isTxt
                            tooltipLayer: tooltipLayer
                            textLabel: ">"
                            active: root.isFormatActive("quote")
                            onClicked: root.applyFormatOrAction("quote")
                        }

                        // 13. Code block
                        ToolbarButton {
                            actionId: "code_block"
                            disabled: root.isTxt
                            tooltipLayer: tooltipLayer
                            iconSource: Theme.iconsPath + "code-blocks.svg"
                            active: root.isFormatActive("code_block")
                            onClicked: root.applyFormatOrAction("code_block")
                        }

                        // 14. Table
                        ToolbarButton {
                            actionId: "table"
                            disabled: root.isTxt
                            tooltipLayer: tooltipLayer
                            iconSource: Theme.iconsPath + "table.svg"
                            active: root.isFormatActive("table")
                            onClicked: root.applyFormatOrAction("table")
                        }

                        // 14b. Mermaid Diagram
                        ToolbarButton {
                            id: mermaidToolbarBtn
                            actionId: "mermaid"
                            disabled: root.isTxt
                            tooltipLayer: tooltipLayer
                            iconSource: Theme.iconsPath + "diagram.svg"
                            active: root.isFormatActive("mermaid")
                            onClicked: mermaidMenuPopup.isOpen = !mermaidMenuPopup.isOpen
                        }

                        // 14c. LaTeX Math Formula
                        ToolbarButton {
                            id: mathToolbarBtn
                            actionId: "math"
                            disabled: root.isTxt
                            tooltipLayer: tooltipLayer
                            iconSource: Theme.iconsPath + "math.svg"
                            active: root.isFormatActive("math")
                            onClicked: mathMenuPopup.isOpen = !mathMenuPopup.isOpen
                            onRightClicked: mathMenuPopup.isOpen = !mathMenuPopup.isOpen
                        }

                        // 15. HR
                        ToolbarButton {
                            actionId: "hr"
                            disabled: root.isTxt
                            tooltipLayer: tooltipLayer
                            iconSource: Theme.iconsPath + "horizontal-rule.svg"
                            onClicked: root.applyFormatOrAction("hr")
                        }

                        Rectangle { width: 1; height: 18; color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1) }

                        // 16. Image
                        ToolbarButton {
                            id: imgToolbarBtn
                            actionId: "image"
                            disabled: root.isTxt
                            tooltipLayer: tooltipLayer
                            iconSource: Theme.iconsPath + "image.svg"
                            onClicked: imageMenuPopup.isOpen = !imageMenuPopup.isOpen
                        }

                        // 17. Link
                        ToolbarButton {
                            actionId: "link"
                            disabled: root.isTxt
                            tooltipLayer: tooltipLayer
                            iconSource: Theme.iconsPath + "link.svg"
                            active: root.isFormatActive("link")
                            onClicked: root.applyFormatOrAction("link")
                        }

                        Rectangle { width: 1; height: 18; color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1) }

                        // 18. Buscar en la nota
                        ToolbarButton {
                            actionId: "find"
                            tooltipLayer: tooltipLayer
                            iconSource: Theme.iconsPath + "search.svg"
                            active: root.isFindActive
                            onClicked: {
                                if (root.isFindActive) root.closeFind();
                                else root.openFind();
                            }
                        }

                        // 19. Modo código fuente — último de la fila scrollable
                        ToolbarButton {
                            actionId: "source_mode"
                            visible: !root.isTxt && (typeof NotesConfig !== "undefined" && NotesConfig.showSourceModeButton)
                            disabled: root.isTxt
                            tooltipLayer: tooltipLayer
                            textLabel: "</>"
                            active: root.isSourceMode
                            onClicked: root.toggleSourceMode()
                        }

                        // 20. Corrector ortográfico (F7)
                        ToolbarButton {
                            actionId: "spellcheck"
                            tooltipLayer: tooltipLayer
                            iconSource: Theme.iconsPath + "spellcheck.svg"
                            active: blockEditor.spellActive
                            onClicked: blockEditor.toggleSpellCheck()
                        }
                    }
                }

                // 20. Convertir a .md: píldora fija a la derecha, FUERA del
                // Flickable para no taparse nunca. Solo en .txt (sin espacio si no).
                Rectangle {
                    id: convertPill
                    visible: root.isTxt
                    Layout.preferredWidth: convertPillContent.implicitWidth + 22
                    Layout.preferredHeight: 30
                    Layout.alignment: Qt.AlignVCenter
                    radius: 15
                    color: convertMa.containsMouse
                        ? Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.28)
                        : Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.16)
                    border.color: Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.4)
                    border.width: 1

                    Behavior on color {
                        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                        ColorAnimation { duration: 120 }
                    }

                    RowLayout {
                        id: convertPillContent
                        anchors.centerIn: parent
                        spacing: 6

                        Image {
                            Layout.preferredWidth: 14
                            Layout.preferredHeight: 14
                            source: Theme.iconsPath + "code-blocks.svg"
                            sourceSize: Qt.size(14, 14)
                            smooth: true
                            mipmap: true
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: Theme.accent
                            }
                        }

                        Text {
                            text: EA.getLabel("convert_to_md", I18n)
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }
                    }

                    MouseArea {
                        id: convertMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: tooltipLayer.showTooltip(convertPill, EA.getLabel("convert_to_md", I18n), I18n.t("notes.editor.txt_convert_hint", "El contenido se conserva tal cual"))
                        onExited: tooltipLayer.hideTooltip()
                        onClicked: {
                            tooltipLayer.hideTooltip();
                            root.convertToMarkdown();
                        }
                    }
                }
            }
            }

            // Barra para ingresar URL de imagen web (Fase 8)
            Rectangle {
                id: webUrlBar
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? 40 : 0
                visible: false
                clip: true
                radius: 8
                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05)
                border.color: Theme.accent
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    Image {
                        width: 16; height: 16
                        source: Theme.iconsPath + "link.svg"
                        sourceSize: Qt.size(16, 16)
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: Theme.accent
                        }
                    }

                    TextInput {
                        id: webUrlInput
                        Layout.fillWidth: true
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        selectByMouse: true
                        CustomTextCursor {}

                        Text {
                            anchors.fill: parent
                            text: I18n.t("notes.image_url_placeholder", "Pegar URL de imagen (https://...)")
                            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.4)
                            font: parent.font
                            visible: !parent.text && !parent.activeFocus
                        }

                        Keys.onReturnPressed: root._confirmWebImageUrl()
                        Keys.onEnterPressed: root._confirmWebImageUrl()
                        Keys.onEscapePressed: {
                            webUrlBar.visible = false;
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) {
                                    webUrlInput.forceActiveFocus();
                                    editorContextMenu.open(parent);
                                }
                            }
                        }
                    }

                    // Botón confirmar
                    Rectangle {
                        width: 28; height: 28; radius: 6
                        color: confirmWebMa.containsMouse ? Theme.accent : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
                        Text {
                            anchors.centerIn: parent
                            text: "✓"
                            font.pixelSize: Theme.fontSizeBody
                            font.bold: true
                            color: confirmWebMa.containsMouse ? Theme.surface : Theme.text
                        }
                        MouseArea {
                            id: confirmWebMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root._confirmWebImageUrl()
                        }
                    }

                    // Botón cancelar
                    Rectangle {
                        width: 28; height: 28; radius: 6
                        color: cancelWebMa.containsMouse ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.2) : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
                        Image {
                            anchors.centerIn: parent
                            width: 14; height: 14
                            source: Theme.iconsPath + "close.svg"
                            sourceSize: Qt.size(14, 14)
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: cancelWebMa.containsMouse ? Theme.danger : Theme.muted
                            }
                        }
                        MouseArea {
                            id: cancelWebMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { webUrlBar.visible = false; }
                        }
                    }
                }
            }

            // ── Barra de búsqueda dentro de la nota ──────────────────
            Rectangle {
                id: findBar
                Layout.fillWidth: true
                Layout.preferredHeight: root.isFindActive ? 38 : 0
                visible: root.isFindActive || Layout.preferredHeight > 1
                clip: true
                opacity: root.isFindActive ? 1.0 : 0.0

                Behavior on Layout.preferredHeight {
                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                    SpringAnimation {
                        spring: 5.5
                        damping: 0.78
                        mass: 1.0
                        epsilon: 0.25
                    }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }

                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05)
                border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.15)
                border.width: 1
                radius: 8

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    Image {
                        width: 14; height: 14
                        source: Theme.iconsPath + "search.svg"
                        sourceSize: Qt.size(14, 14)
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: Theme.muted
                        }
                    }

                    TextInput {
                        id: findInput
                        Layout.fillWidth: true
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody - 1
                        color: Theme.text
                        selectByMouse: true
                        clip: true
                        CustomTextCursor {}

                        Text {
                            anchors.fill: parent
                            text: I18n.t("notes.editor.find_placeholder", "Buscar en la nota...")
                            color: Theme.muted
                            font: findInput.font
                            visible: !findInput.text && !findInput.activeFocus
                            verticalAlignment: Text.AlignVCenter
                        }

                        onTextChanged: {
                            root.findQuery = text;
                            root._updateFindMatches();
                            root._scrollToCurrentMatch();
                        }

                        Keys.onReturnPressed: (event) => {
                            if (event.modifiers & Qt.ControlModifier) {
                                root._confirmActiveMatch();
                            } else if (event.modifiers & Qt.ShiftModifier) {
                                root._findPrev();
                            } else {
                                root._findNext();
                            }
                            event.accepted = true;
                        }
                        Keys.onEnterPressed: (event) => {
                            Keys.onReturnPressed(event);
                        }
                        Keys.onUpPressed: (event) => {
                            root._findPrev();
                            event.accepted = true;
                        }
                        Keys.onDownPressed: (event) => {
                            root._findNext();
                            event.accepted = true;
                        }
                        Keys.onEscapePressed: (event) => {
                            root.closeFind();
                            event.accepted = true;
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) {
                                    findInput.forceActiveFocus();
                                    editorContextMenu.open(findInput);
                                }
                            }
                        }
                    }

                    // Contador de coincidencias
                    Text {
                        text: {
                            if (!root.findQuery) return "";
                            if (root.findTotalMatches === 0) return I18n.t("notes.editor.no_matches", "Sin coincidencias");
                            return (root.findMatchIndex + 1) + "/" + root.findTotalMatches;
                        }
                        color: root.findTotalMatches === 0 ? Theme.danger : Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeCaption
                        visible: root.findQuery.length > 0
                    }

                    // Botón Anterior
                    Rectangle {
                        width: 24; height: 24; radius: 4
                        color: prevFindMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1) : "transparent"
                        Image {
                            anchors.centerIn: parent
                            width: 14; height: 14
                            source: Theme.iconsPath + "chevron-down.svg"
                            sourceSize: Qt.size(14, 14)
                            rotation: 180
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: prevFindMa.containsMouse ? Theme.accent : Theme.text
                            }
                        }
                        MouseArea {
                            id: prevFindMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root._findPrev();
                                findInput.forceActiveFocus();
                            }
                        }
                    }

                    // Botón Siguiente
                    Rectangle {
                        width: 24; height: 24; radius: 4
                        color: nextFindMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1) : "transparent"
                        Image {
                            anchors.centerIn: parent
                            width: 14; height: 14
                            source: Theme.iconsPath + "chevron-down.svg"
                            sourceSize: Qt.size(14, 14)
                            rotation: 0
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: nextFindMa.containsMouse ? Theme.accent : Theme.text
                            }
                        }
                        MouseArea {
                            id: nextFindMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root._findNext();
                                findInput.forceActiveFocus();
                            }
                        }
                    }

                    // Botón Cerrar
                    Rectangle {
                        width: 24; height: 24; radius: 4
                        color: closeFindMa.containsMouse ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.2) : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: closeFindMa.containsMouse ? Theme.danger : Theme.muted
                            font.pixelSize: Theme.fontSizeCaption - 1
                        }
                        MouseArea {
                            id: closeFindMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.closeFind()
                        }
                    }
                }
            }

            // Línea divisoria
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
                opacity: root.isExpanded ? 1.0 : 0.0
                visible: opacity > 0.0
            }

            // ── Modo Código Fuente plano ──────────────────────────────
            Flickable {
                id: sourceFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.isSourceMode
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: !root.isSettingsOpen
                contentWidth: width
                contentHeight: Math.max(height, sourceCodeEditor.implicitHeight + 48)

                // Barra de scroll vertical con el estilo global
                ScrollBar.vertical: CustomScrollBar {}

                WheelHandler {
                    target: null
                    acceptedDevices: PointerDevice.AllDevices
                    acceptedModifiers: Qt.ControlModifier
                    grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType | PointerHandler.ApprovesTakeOverByAnything
                    onWheel: (event) => {
                        if (event.modifiers & Qt.ControlModifier) {
                            var delta = event.angleDelta ? event.angleDelta.y : 0;
                            if (delta > 0) {
                                EditorMetrics.zoomIn();
                                event.accepted = true;
                            } else if (delta < 0) {
                                EditorMetrics.zoomOut();
                                event.accepted = true;
                            } else {
                                event.accepted = false;
                            }
                        } else {
                            event.accepted = false;
                        }
                    }
                }

                // Click en cualquier área vacía enfoca el editor de código fuente al final
                MouseArea {
                    anchors.fill: parent
                    z: -1
                    cursorShape: Qt.IBeamCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (mouse) => {
                        sourceCodeEditor.forceActiveFocus();
                        if (mouse.button === Qt.RightButton) {
                            if (editorContextMenu) {
                                editorContextMenu.open(sourceCodeEditor);
                            }
                        } else {
                            sourceCodeEditor.cursorPosition = sourceCodeEditor.text.length;
                        }
                    }
                }

                TextEdit {
                    id: sourceCodeEditor
                    width: parent.width - 48
                    x: 24
                    y: 16
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    color: Theme.text
                    font.family: Theme.fontFamilyMonospace || "monospace"
                    font.pixelSize: EditorMetrics.body
                    selectByMouse: true
                    // La selección es el marcador de la coincidencia activa en
                    // modo fuente: debe seguir visible con el foco en el buscador
                    persistentSelection: true
                    cursorVisible: root.isSourceMode && activeFocus
                    CustomTextCursor {}

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        propagateComposedEvents: true
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton && editorContextMenu) {
                                sourceCodeEditor.forceActiveFocus();
                                var clickPos = sourceCodeEditor.positionAt(mouse.x, mouse.y);
                                if (sourceCodeEditor.selectionStart === sourceCodeEditor.selectionEnd ||
                                    clickPos < sourceCodeEditor.selectionStart || clickPos > sourceCodeEditor.selectionEnd) {
                                    sourceCodeEditor.cursorPosition = clickPos;
                                }
                                editorContextMenu.open(sourceCodeEditor);
                            }
                        }
                    }

                    onSelectionStartChanged: root.sourceFormatSeq++
                    onSelectionEndChanged: root.sourceFormatSeq++
                    onCursorPositionChanged: root.sourceFormatSeq++

                    onTextChanged: {
                        if (root.isSourceMode && !root.isLoading) {
                            root._currentBody = text;
                            if (text !== root._originalBody) {
                                root.markDirty();
                            }
                        }
                    }

                    // F23: Ctrl+Shift+V fuerza imagen; Ctrl+V decide por MIME real (Wayland).
                    // (inserta la etiqueta ![…](…) en el cursor). Con texto, pegado nativo.
                    Keys.onPressed: (event) => {
                        var cm = editorContextMenu;
                        if (cm && cm.visible && !cm.isClosing) {
                            if (event.key === Qt.Key_Menu || event.nativeScanCode === 135 || event.key === Qt.Key_Escape) {
                                cm.close();
                                event.accepted = true;
                                return;
                            }
                            if (event.key === Qt.Key_Up) {
                                cm.selectPreviousItem();
                                event.accepted = true;
                                return;
                            }
                            if (event.key === Qt.Key_Down) {
                                cm.selectNextItem();
                                event.accepted = true;
                                return;
                            }
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (cm.triggerSelectedItem()) {
                                    event.accepted = true;
                                    return;
                                }
                                cm.close();
                                event.accepted = true;
                                return;
                            }
                            if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                                event.accepted = true;
                                return;
                            }
                        }

                        if (event.key === Qt.Key_Menu || event.nativeScanCode === 135) {
                            if (editorContextMenu) {
                                if (typeof editorContextMenu.toggleAtTextCursor === "function") {
                                    editorContextMenu.toggleAtTextCursor(sourceCodeEditor);
                                } else if (typeof editorContextMenu.openAtTextCursor === "function") {
                                    editorContextMenu.openAtTextCursor(sourceCodeEditor);
                                } else {
                                    editorContextMenu.open(sourceCodeEditor);
                                }
                            }
                            event.accepted = true;
                            return;
                        }

                        if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_V) {
                            root.pasteClipboardImage();
                            event.accepted = true;
                            return;
                        }
                        if (((event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_V) ||
                            ((event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_Insert)) {
                            var clipText = (typeof Quickshell.clipboardText === "string") ? Quickshell.clipboardText : "";
                            var trimmed = clipText.trim();
                            if (/^(file:\/\/|\/).+\.(png|jpe?g|webp|gif|svg|bmp)$/i.test(trimmed)) {
                                event.accepted = true;
                                root.pasteClipboardImage();
                                return;
                            }
                            if (!clipText || trimmed === "") {
                                event.accepted = true;
                                NotesService.checkClipboardForImage(
                                    function() {
                                        root.pasteClipboardImage();
                                    },
                                    function() {}
                                );
                                return;
                            }
                        }
                    }
                }

                DropArea {
                    anchors.fill: parent
                    onDropped: (drop) => {
                        if (drop.hasUrls && drop.urls.length > 0 && root._handleImageDrop(drop.urls)) {
                            drop.acceptProposedAction();
                        }
                    }
                }
            }

            // ── Área de edición principal por bloques ──────────────────────
            BlockEditor {
                id: blockEditor
                Layout.fillWidth: true
                Layout.fillHeight: true
                readOnly: root.isPreviewMode
                interactive: !root.isSettingsOpen
                visible: !root.isSourceMode
                freezeLayout: !root.isExpanded || !root.morphReady
                searchQuery: root.isFindActive ? root.findQuery : ""
                activeMatchBid: (root.isFindActive && !root.isSourceMode && root._findMatchesList.length > 0 && root._findMatchesList[root.findMatchIndex])
                    ? root._findMatchesList[root.findMatchIndex].bid : -1
                activeMatchUnit: (root.isFindActive && !root.isSourceMode && root._findMatchesList.length > 0 && root._findMatchesList[root.findMatchIndex])
                    ? root._findMatchesList[root.findMatchIndex].unit : -1
                activeMatchOrdinal: (root.isFindActive && !root.isSourceMode && root._findMatchesList.length > 0 && root._findMatchesList[root.findMatchIndex])
                    ? root._findMatchesList[root.findMatchIndex].local : -1
                contextMenu: editorContextMenu
                slashMenu: slashMenu
                tooltipLayer: tooltipLayer
                editorModal: root
                onContentYChanged: tooltipLayer.hideTooltip()

                onContentModified: {
                    root.markDirty();
                    if (root.isFindActive) findRecalcTimer.restart();
                }
                onMarkdownEdited: (newMd) => {
                    root._currentBody = newMd;
                    if (newMd !== root._originalBody) {
                        root.markDirty();
                    }
                    if (root.isFindActive) findRecalcTimer.restart();
                }

                DropArea {
                    anchors.fill: parent
                    onDropped: (drop) => {
                        if (drop.hasUrls && drop.urls.length > 0 && root._handleImageDrop(drop.urls)) {
                            drop.acceptProposedAction();
                        }
                    }
                }
            }
        }

        // Velo de carga diferida: tapa el área de edición hasta que los
        // bloques se construyen tras el morph. Transparente, no intercepta nada.
        Rectangle {
            id: blocksVeil
            anchors.top: parent.top
            anchors.topMargin: mainColumn.y + toolbarRect.y + toolbarRect.height + 8
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            anchors.bottomMargin: 20
            radius: 12
            color: "transparent"
            z: 150
            opacity: (root._pendingBody !== "" && !root.isSourceMode) ? 1.0 : 0.0
            visible: opacity > 0.0

            Behavior on opacity {
                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            Text {
                anchors.centerIn: parent
                text: I18n.t("notes.editor.loading_blocks", "Cargando nota...")
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
            }
        }

        // Área transparente para cerrar los popups al hacer clic fuera
        MouseArea {
            anchors.fill: parent
            z: 199
            visible: imageMenuPopup.isOpen || mermaidMenuPopup.isOpen || mathMenuPopup.isOpen
            onClicked: {
                imageMenuPopup.isOpen = false;
                mermaidMenuPopup.isOpen = false;
                mathMenuPopup.isOpen = false;
            }
        }

        // Sugerencias de etiquetas: se posiciona bajo el campo vía
        // placeTagSuggestions(). onPressed (no clicked): el foco sigue en el campo.
        Rectangle {
            id: tagSuggPopup
            z: 300
            width: Math.max(180, tagInputBox.width + 60)
            height: Math.min(6, root.tagSuggestions.length) * 30 + 12
            radius: 8
            color: Theme.color0
            border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.15)
            border.width: 1
            visible: root.tagSuggestions.length > 0 && tagInput.activeFocus
            clip: true

            Column {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 0

                Repeater {
                    model: root.tagSuggestions
                    Rectangle {
                        width: parent.width
                        height: 30
                        radius: 6
                        color: index === root.tagSuggIndex
                            ? Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.22)
                            : "transparent"

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            verticalAlignment: Text.AlignVCenter
                            text: "#" + modelData
                            color: index === root.tagSuggIndex ? Theme.accent : Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody - 1
                            font.bold: index === root.tagSuggIndex
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.tagSuggIndex = index
                            onPressed: (mouse) => {
                                mouse.accepted = true;
                                root.pickTagSuggestion(index);
                            }
                        }
                    }
                }
            }
        }

        // Menú emergente de inserción de imagen (Fase 8)
        Rectangle {
            id: imageMenuPopup
            property bool isOpen: false
            visible: isOpen || scale > 0.02
            z: 200
            width: 190
            height: imageMenuCol.implicitHeight + 12
            radius: 8
            color: Theme.color0
            border.width: 0

            transformOrigin: Item.Top
            scale: isOpen ? 1.0 : 0.0
            opacity: isOpen ? 1.0 : 0.0

            Behavior on scale {
                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                SpringAnimation {
                    spring: 5.5
                    damping: 0.42
                    epsilon: 0.01
                }
            }
            Behavior on opacity {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.45)
                shadowBlur: 0.6
                shadowVerticalOffset: 3
            }

            x: {
                if (!imgToolbarBtn || !imageMenuPopup.parent) return 0;
                try {
                    var pt = imgToolbarBtn.mapToItem(imageMenuPopup.parent, 0, 0);
                    return Math.max(16, Math.min(imageMenuPopup.parent.width - width - 16, pt.x + (imgToolbarBtn.width - width) / 2));
                } catch(e) {
                    return Math.max(0, toolbarRect.x + toolbarRect.width - width);
                }
            }
            y: {
                if (!imgToolbarBtn || !imageMenuPopup.parent) return toolbarRect.y + toolbarRect.height + 4;
                try {
                    var pt = imgToolbarBtn.mapToItem(imageMenuPopup.parent, 0, 0);
                    return pt.y + imgToolbarBtn.height + 6;
                } catch(e) {
                    return toolbarRect.y + toolbarRect.height + 4;
                }
            }

            Column {
                id: imageMenuCol
                anchors.centerIn: parent
                width: parent.width - 12
                spacing: 2

                // Opción 1: Archivo local
                Rectangle {
                    width: parent.width
                    height: 32
                    radius: 6
                    color: optLocalMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1) : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8
                        Image {
                            width: 16; height: 16
                            source: Theme.iconsPath + "folder.svg"
                            sourceSize: Qt.size(16, 16)
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: Theme.accent
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: I18n.t("notes.image_from_local", "Desde archivo local")
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeCaption
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        id: optLocalMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            imageMenuPopup.isOpen = false;
                            root._openImagePicker();
                        }
                    }
                }

                // Opción 2: Enlace web
                Rectangle {
                    width: parent.width
                    height: 32
                    radius: 6
                    color: optWebMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1) : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8
                        Image {
                            width: 16; height: 16
                            source: Theme.iconsPath + "link.svg"
                            sourceSize: Qt.size(16, 16)
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: Theme.accent
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: I18n.t("notes.image_from_web", "Desde enlace web")
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeCaption
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        id: optWebMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            imageMenuPopup.isOpen = false;
                            webUrlBar.visible = true;
                            webUrlInput.text = "";
                            webUrlInput.forceActiveFocus();
                        }
                    }
                }
            }
        }

        // Menú emergente de inserción de diagrama Mermaid
        Rectangle {
            id: mermaidMenuPopup
            property bool isOpen: false
            visible: isOpen || scale > 0.02
            z: 200
            width: 250
            height: mermaidMenuCol.implicitHeight + 12
            radius: 8
            color: Theme.color0
            border.width: 0

            transformOrigin: Item.Top
            scale: isOpen ? 1.0 : 0.0
            opacity: isOpen ? 1.0 : 0.0

            Behavior on scale {
                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                SpringAnimation {
                    spring: 5.5
                    damping: 0.42
                    epsilon: 0.01
                }
            }
            Behavior on opacity {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.45)
                shadowBlur: 0.6
                shadowVerticalOffset: 3
            }

            x: {
                if (!mermaidToolbarBtn || !mermaidMenuPopup.parent) return 0;
                try {
                    var pt = mermaidToolbarBtn.mapToItem(mermaidMenuPopup.parent, 0, 0);
                    return Math.max(16, Math.min(mermaidMenuPopup.parent.width - width - 16, pt.x + (mermaidToolbarBtn.width - width) / 2));
                } catch(e) {
                    return Math.max(0, toolbarRect.x + toolbarRect.width - width);
                }
            }
            y: {
                if (!mermaidToolbarBtn || !mermaidMenuPopup.parent) return toolbarRect.y + toolbarRect.height + 4;
                try {
                    var pt = mermaidToolbarBtn.mapToItem(mermaidMenuPopup.parent, 0, 0);
                    return pt.y + mermaidToolbarBtn.height + 6;
                } catch(e) {
                    return toolbarRect.y + toolbarRect.height + 4;
                }
            }

            Column {
                id: mermaidMenuCol
                anchors.centerIn: parent
                width: parent.width - 12
                spacing: 2

                Repeater {
                    model: MermaidTemplates.getTemplateList()
                    delegate: Rectangle {
                        width: mermaidMenuCol.width
                        height: 32
                        radius: 6
                        color: tplMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Image {
                                width: 16; height: 16
                                source: Theme.iconsPath + (modelData.icon ? (modelData.icon + ".svg") : "diagram.svg")
                                sourceSize: Qt.size(16, 16)
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: Theme.accent
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: I18n.t(modelData.labelKey, modelData.defaultLabel)
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeCaption
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: tplMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                mermaidMenuPopup.isOpen = false;
                                root.applyFormatOrAction("mermaid:" + modelData.id);
                            }
                        }
                    }
                }
            }
        }

        // Menú emergente de inserción de fórmulas LaTeX
        Rectangle {
            id: mathMenuPopup
            property bool isOpen: false
            visible: isOpen || scale > 0.02
            z: 200
            width: 250
            height: mathMenuCol.implicitHeight + 12
            radius: 8
            color: Theme.color0
            border.width: 0

            transformOrigin: Item.Top
            scale: isOpen ? 1.0 : 0.0
            opacity: isOpen ? 1.0 : 0.0

            Behavior on scale {
                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                SpringAnimation {
                    spring: 5.5
                    damping: 0.42
                    epsilon: 0.01
                }
            }
            Behavior on opacity {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.45)
                shadowBlur: 0.6
                shadowVerticalOffset: 3
            }

            x: {
                if (!mathToolbarBtn || !mathMenuPopup.parent) return 0;
                try {
                    var pt = mathToolbarBtn.mapToItem(mathMenuPopup.parent, 0, 0);
                    return Math.max(16, Math.min(mathMenuPopup.parent.width - width - 16, pt.x + (mathToolbarBtn.width - width) / 2));
                } catch(e) {
                    return Math.max(0, toolbarRect.x + toolbarRect.width - width);
                }
            }
            y: {
                if (!mathToolbarBtn || !mathMenuPopup.parent) return toolbarRect.y + toolbarRect.height + 4;
                try {
                    var pt = mathToolbarBtn.mapToItem(mathMenuPopup.parent, 0, 0);
                    return pt.y + mathToolbarBtn.height + 6;
                } catch(e) {
                    return toolbarRect.y + toolbarRect.height + 4;
                }
            }

            Column {
                id: mathMenuCol
                anchors.centerIn: parent
                width: parent.width - 12
                spacing: 2

                Repeater {
                    model: MathTemplates.getTemplateList()
                    delegate: Rectangle {
                        width: mathMenuCol.width
                        height: 32
                        radius: 6
                        color: mathTplMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Image {
                                width: 16; height: 16
                                source: Theme.iconsPath + (modelData.icon ? (modelData.icon + ".svg") : "math.svg")
                                sourceSize: Qt.size(16, 16)
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: Theme.accent
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: I18n.t(modelData.labelKey, modelData.defaultLabel)
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeCaption
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: mathTplMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                mathMenuPopup.isOpen = false;
                                root.applyFormatOrAction("math:" + modelData.id);
                            }
                        }
                    }
                }
            }
        }
    }

    // Menú flotante de comandos '/' estilo Notion (F78)
    SlashMenu {
        id: slashMenu
        onCommandSelected: (cmd, triggerInfo) => {
            blockEditor.handleSlashCommandExecution(cmd, triggerInfo);
        }
    }

    // Menú contextual para el editor (Regla 9 .instrucciones.md)
    ContextMenu {
        id: editorContextMenu
        editor: root.blockEditor
    }

    function _resolvePortalPickerPath() {
        return (typeof Sys !== "undefined" && Sys.appExecutable) ? Sys.appExecutable : "notas";
    }

    // Proceso para seleccionar imagen vía xdg-desktop-portal
    Process {
        id: imagePickerProc
        command: [
            root._resolvePortalPickerPath(),
            "file-picker",
            "--title", "Seleccionar imagen",
            "--filter", "Imágenes:*.png:*.jpg:*.jpeg:*.webp:*.gif:*.bmp:*.svg"
        ]

        stdout: SplitParser {
            onRead: (line) => {
                var src = line.trim();
                if (src !== "") {
                    root._attachImageFile(src);
                }
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                console.warn("[NoteEditorModal] Selector de imagen cancelado o falló (código: " + exitCode + ")");
            }
        }

        Component.onDestruction: { running = false; }
    }

    Connections {
        target: NotesService
        function onExternalConflictDetected(slug, diskContent) {
            if (root.loadedSlug === slug) {
                root.hasConflict = true;
                root.conflictContent = diskContent;
            }
        }
    }

    // Indicador flotante de nivel de zoom (rectángulo con esquinas redondeadas semi-transparente abajo a la derecha)
    Rectangle {
        id: zoomPill
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 24
        z: 900
        width: Math.max(64, Math.round(zoomPillText.implicitWidth + 24))
        height: 32
        radius: 10
        color: zoomMa.containsMouse
            ? Qt.hsva(Theme.surface.hsvHue < 0 ? 0 : Theme.surface.hsvHue, Theme.surface.hsvSaturation, Theme.surface.hsvValue, 0.85)
            : Qt.hsva(Theme.surface.hsvHue < 0 ? 0 : Theme.surface.hsvHue, Theme.surface.hsvSaturation, Theme.surface.hsvValue, 0.65)
        border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.15)
        border.width: 1
        opacity: (zoomPillTimer.running || zoomMa.containsMouse) ? 1.0 : 0.0
        visible: opacity > 0.0

        Behavior on color {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            ColorAnimation { duration: 150 }
        }

        Behavior on opacity {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            NumberAnimation { duration: 200 }
        }

        Text {
            id: zoomPillText
            anchors.centerIn: parent
            text: Math.round(EditorMetrics.zoom * 100) + "%"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeCaption
            font.bold: true
        }

        MouseArea {
            id: zoomMa
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onEntered: tooltipLayer.showTooltip(parent, I18n.t("notes.editor.reset_zoom", "Restablecer zoom"), "Ctrl+0")
            onExited: tooltipLayer.hideTooltip()
            onClicked: {
                tooltipLayer.hideTooltip();
                EditorMetrics.zoomReset();
            }
        }
    }

    Timer {
        id: zoomPillTimer
        interval: 1200
        repeat: false
    }

    Connections {
        target: EditorMetrics
        function onZoomChanged() {
            tooltipLayer.hideTooltip();
            zoomPillTimer.restart();
        }
    }

    // Toast flotante para notificaciones del editor
    Rectangle {
        id: editorToast
        visible: opacity > 0
        opacity: toastTimer.running ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 24
        z: 900
        height: 40
        width: Math.min(parent.width - 48, toastRow.implicitWidth + 28)
        radius: 12
        color: Qt.hsva(Theme.surface.hsvHue,
                       Math.min(1, Theme.surface.hsvSaturation),
                       Math.min(1, Theme.surface.hsvValue + 0.04),
                       0.75)
        border.color: Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.14)
        border.width: 1

        RowLayout {
            id: toastRow
            anchors.centerIn: parent
            spacing: 12

            Text {
                id: toastText
                text: ""
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody - 1
                elide: Text.ElideRight
            }

            Rectangle {
                id: toastActionBtn
                visible: false
                property var actionCallback: null
                implicitWidth: toastActionLabel.implicitWidth + 14
                implicitHeight: 24
                radius: 6
                color: toastActionMa.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.4)
                border.width: 1

                Text {
                    id: toastActionLabel
                    anchors.centerIn: parent
                    text: ""
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody - 2
                    font.bold: true
                }

                MouseArea {
                    id: toastActionMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (typeof toastActionBtn.actionCallback === "function") {
                            toastActionBtn.actionCallback();
                        }
                        toastTimer.stop();
                    }
                }
            }
        }
    }

    Timer {
        id: toastTimer
        interval: 3200
        repeat: false
    }

    function showToast(message, actionLabel, actionCallback) {
        toastText.text = message || "";
        var hasAction = Boolean(actionLabel && actionCallback);
        toastActionBtn.visible = hasAction;
        if (hasAction) {
            toastActionLabel.text = actionLabel;
            toastActionBtn.actionCallback = actionCallback;
        } else {
            toastActionLabel.text = "";
            toastActionBtn.actionCallback = null;
        }
        toastTimer.restart();
    }

    // Capa única no recortada de tooltips para botones de barra y encabezado (Fase 1)
    EditorTooltipLayer {
        id: tooltipLayer
    }

    // Atajo global de zoom en todo el modal con Ctrl + Rueda del ratón
    WheelHandler {
        target: null
        acceptedDevices: PointerDevice.AllDevices
        acceptedModifiers: Qt.ControlModifier
        onWheel: (event) => {
            if (event.modifiers & Qt.ControlModifier) {
                var delta = event.angleDelta ? event.angleDelta.y : 0;
                if (delta > 0) {
                    EditorMetrics.zoomIn();
                    event.accepted = true;
                } else if (delta < 0) {
                    EditorMetrics.zoomOut();
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            } else {
                event.accepted = false;
            }
        }
    }
}
