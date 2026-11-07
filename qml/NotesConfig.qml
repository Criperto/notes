pragma Singleton
import QtQuick
import Notas

QtObject {
    id: root

    readonly property var schema: [
        {
            key: "notesDir",
            type: "directory",
            default: "$XDG_DOCUMENTS_DIR/notes",
            label: I18n.t("config.notes.dir", "Carpeta de notas"),
            comment: I18n.t("config.notes.dir_comment", "Directorio donde se almacenarán las notas en formato Markdown (.md). Soporta variables como $XDG_DOCUMENTS_DIR y $HOME.")
        },
        {
            key: "showImagePreviews",
            type: "bool",
            default: true,
            label: I18n.t("config.notes.show_image_previews", "Previsualizar imágenes"),
            comment: I18n.t("config.notes.show_image_previews_comment", "Muestra miniaturas de imágenes en las tarjetas de notas.")
        },
        {
            key: "cyclePreviewImages",
            type: "bool",
            default: true,
            disabledWhen: { key: "showImagePreviews", equals: false },
            label: I18n.t("config.notes.cycle_preview_images", "Alternar imágenes de preview"),
            comment: I18n.t("config.notes.cycle_preview_images_comment", "Cambia suavemente cada 3 segundos entre las imágenes de la nota en vez de mostrar solo la primera.")
        },
        {
            key: "cardsPerRow",
            type: "int",
            min: 2,
            max: 5,
            default: 3,
            label: I18n.t("config.notes.cards_per_row", "Tarjetas por fila"),
            comment: I18n.t("config.notes.cards_per_row_comment", "Número preferido de columnas en la cuadrícula de notas.")
        },
        {
            key: "importMode",
            type: "enum",
            default: "move",
            values: ["copy", "move"],
            labels: [
                I18n.t("config.notes.import_mode_copy", "Copiar"),
                I18n.t("config.notes.import_mode_move", "Mover")
            ],
            label: I18n.t("config.notes.import_mode", "Al arrastrar un archivo"),
            comment: I18n.t("config.notes.import_mode_comment", "Si los .md arrastrados se copian o se mueven a la carpeta de notas.")
        },
        {
            key: "externalFileOpenMode",
            type: "enum",
            default: "preview",
            values: ["preview", "edit"],
            labels: [
                I18n.t("config.notes.external_mode_preview", "Vista previa (Solo lectura)"),
                I18n.t("config.notes.external_mode_edit", "Edición directa")
            ],
            label: I18n.t("config.notes.external_open_mode", "Al abrir archivos externos"),
            comment: I18n.t("config.notes.external_open_mode_comment", "Cómo abrir notas ubicadas fuera de la carpeta de notas.")
        },
        {
            key: "previewCloseAction",
            type: "enum",
            default: "home",
            values: ["close", "home"],
            labels: [
                I18n.t("config.notes.preview_close_exit", "Cerrar la aplicación"),
                I18n.t("config.notes.preview_close_home", "Volver al inicio de Notas")
            ],
            label: I18n.t("config.notes.preview_close_action", "Al cerrar vista previa con 'X'"),
            comment: I18n.t("config.notes.preview_close_action_comment", "Define si la 'X' cierra la aplicación o vuelve al inicio normal de Notas.")
        },
        {
            key: "editorZoom",
            type: "int",
            min: 50,
            max: 300,
            default: 100,
            suffix: " %",
            label: I18n.t("config.notes.editor_zoom", "Zoom del editor"),
            comment: I18n.t("config.notes.editor_zoom_comment", "Nivel de zoom predeterminado para el editor de notas (en porcentaje).")
        },
        {
            key: "spellcheckMode",
            type: "enum",
            default: "auto",
            values: ["off", "manual", "auto"],
            labels: [
                I18n.t("config.notes.spellcheck_off", "Desactivado"),
                I18n.t("config.notes.spellcheck_manual", "Manual (F7 / Botón)"),
                I18n.t("config.notes.spellcheck_auto", "Automático en tiempo real")
            ],
            label: I18n.t("config.notes.spellcheck_mode", "Corrector ortográfico"),
            comment: I18n.t("config.notes.spellcheck_mode_comment", "Modo de verificación ortográfica para el editor de notas.")
        },
        {
            key: "versionHistoryEnabled",
            type: "bool",
            default: true,
            label: I18n.t("config.notes.version_history_enabled", "Historial de versiones"),
            comment: I18n.t("config.notes.version_history_comment", "Guarda snapshots automáticos periódicos para comparar diferencias y restaurar versiones previas.")
        },
        {
            key: "versionHistoryMax",
            type: "int",
            min: 10,
            max: 200,
            default: 50,
            label: I18n.t("config.notes.version_history_max", "Máximo de versiones"),
            comment: I18n.t("config.notes.version_history_max_comment", "Cantidad máxima de snapshots automáticos conservados por nota antes de podar.")
        },
        {
            key: "versionHistoryMaxMb",
            type: "int",
            min: 1,
            max: 50,
            default: 5,
            label: I18n.t("config.notes.version_history_max_mb", "Límite de snapshots (MB)"),
            comment: I18n.t("config.notes.version_history_max_mb_comment", "Espacio máximo en megabytes para snapshots automáticos por nota antes de podar.")
        },
        {
            key: "persistUndo",
            type: "bool",
            default: true,
            label: I18n.t("config.notes.persist_undo", "Deshacer persistente"),
            comment: I18n.t("config.notes.persist_undo_comment", "Conserva la pila de deshacer/rehacer (Ctrl+Z) entre aperturas de la nota.")
        }
    ]

    property string notesDir: ConfigBackend.notasDir
    onNotesDirChanged: {
        if (ConfigBackend.notasDir !== notesDir) ConfigBackend.notasDir = notesDir;
    }

    property bool showImagePreviews: ConfigBackend.showImagePreviews
    onShowImagePreviewsChanged: {
        if (ConfigBackend.showImagePreviews !== showImagePreviews) ConfigBackend.showImagePreviews = showImagePreviews;
    }

    property bool cyclePreviewImages: ConfigBackend.cyclePreviewImages
    onCyclePreviewImagesChanged: {
        if (ConfigBackend.cyclePreviewImages !== cyclePreviewImages) ConfigBackend.cyclePreviewImages = cyclePreviewImages;
    }

    property int cardsPerRow: (ConfigBackend && ConfigBackend.cardsPerRow >= 2 && ConfigBackend.cardsPerRow <= 5) ? ConfigBackend.cardsPerRow : 3
    onCardsPerRowChanged: {
        if (ConfigBackend.cardsPerRow !== cardsPerRow) ConfigBackend.cardsPerRow = cardsPerRow;
    }

    property string importMode: (ConfigBackend && ConfigBackend.importMode) ? ConfigBackend.importMode : "move"
    onImportModeChanged: {
        if (ConfigBackend.importMode !== importMode) ConfigBackend.importMode = importMode;
    }

    property string externalFileOpenMode: (ConfigBackend && ConfigBackend.externalFileOpenMode) ? ConfigBackend.externalFileOpenMode : "preview"
    onExternalFileOpenModeChanged: {
        if (ConfigBackend.externalFileOpenMode !== externalFileOpenMode) ConfigBackend.externalFileOpenMode = externalFileOpenMode;
    }

    property string previewCloseAction: (ConfigBackend && ConfigBackend.previewCloseAction) ? ConfigBackend.previewCloseAction : "home"
    onPreviewCloseActionChanged: {
        if (ConfigBackend.previewCloseAction !== previewCloseAction) ConfigBackend.previewCloseAction = previewCloseAction;
    }

    property int editorZoom: (ConfigBackend && ConfigBackend.editorZoom >= 50) ? ConfigBackend.editorZoom : 100 // editorZoom: 100
    onEditorZoomChanged: {
        if (ConfigBackend.editorZoom !== editorZoom) ConfigBackend.editorZoom = editorZoom;
    }

    property string spellcheckMode: (ConfigBackend && ConfigBackend.spellcheckMode) ? ConfigBackend.spellcheckMode : "auto"
    onSpellcheckModeChanged: {
        if (ConfigBackend.spellcheckMode !== spellcheckMode) ConfigBackend.spellcheckMode = spellcheckMode;
    }

    property bool versionHistoryEnabled: (typeof ConfigBackend !== "undefined" && ConfigBackend.versionHistoryEnabled !== undefined) ? ConfigBackend.versionHistoryEnabled : true
    onVersionHistoryEnabledChanged: {
        if (typeof ConfigBackend !== "undefined" && ConfigBackend.versionHistoryEnabled !== versionHistoryEnabled) ConfigBackend.versionHistoryEnabled = versionHistoryEnabled;
    }

    property int versionHistoryMax: (typeof ConfigBackend !== "undefined" && ConfigBackend.versionHistoryMax !== undefined && ConfigBackend.versionHistoryMax >= 10) ? ConfigBackend.versionHistoryMax : 50
    onVersionHistoryMaxChanged: {
        if (typeof ConfigBackend !== "undefined" && ConfigBackend.versionHistoryMax !== versionHistoryMax) ConfigBackend.versionHistoryMax = versionHistoryMax;
    }

    property int versionHistoryMaxMb: (typeof ConfigBackend !== "undefined" && ConfigBackend.versionHistoryMaxMb !== undefined && ConfigBackend.versionHistoryMaxMb >= 1) ? ConfigBackend.versionHistoryMaxMb : 5
    onVersionHistoryMaxMbChanged: {
        if (typeof ConfigBackend !== "undefined" && ConfigBackend.versionHistoryMaxMb !== versionHistoryMaxMb) ConfigBackend.versionHistoryMaxMb = versionHistoryMaxMb;
    }

    property bool persistUndo: (typeof ConfigBackend !== "undefined" && ConfigBackend.persistUndo !== undefined) ? ConfigBackend.persistUndo : true
    onPersistUndoChanged: {
        if (typeof ConfigBackend !== "undefined" && ConfigBackend.persistUndo !== persistUndo) ConfigBackend.persistUndo = persistUndo;
    }

    property real uiScale: (typeof ConfigBackend !== "undefined" && ConfigBackend.uiScale !== undefined) ? ConfigBackend.uiScale : 1.0
    onUiScaleChanged: {
        if (typeof ConfigBackend !== "undefined" && ConfigBackend.uiScale !== uiScale) ConfigBackend.uiScale = uiScale;
    }

    property var _cfgSync: Connections {
        target: (typeof ConfigBackend !== "undefined") ? ConfigBackend : null
        function onNotasDirChanged() {
            if (root.notesDir !== ConfigBackend.notasDir) root.notesDir = ConfigBackend.notasDir;
        }
        function onShowImagePreviewsChanged() {
            if (root.showImagePreviews !== ConfigBackend.showImagePreviews) root.showImagePreviews = ConfigBackend.showImagePreviews;
        }
        function onCyclePreviewImagesChanged() {
            if (root.cyclePreviewImages !== ConfigBackend.cyclePreviewImages) root.cyclePreviewImages = ConfigBackend.cyclePreviewImages;
        }
        function onCardsPerRowChanged() {
            if (root.cardsPerRow !== ConfigBackend.cardsPerRow) root.cardsPerRow = ConfigBackend.cardsPerRow;
        }
        function onImportModeChanged() {
            if (root.importMode !== ConfigBackend.importMode) root.importMode = ConfigBackend.importMode;
        }
        function onExternalFileOpenModeChanged() {
            if (root.externalFileOpenMode !== ConfigBackend.externalFileOpenMode) root.externalFileOpenMode = ConfigBackend.externalFileOpenMode;
        }
        function onPreviewCloseActionChanged() {
            if (root.previewCloseAction !== ConfigBackend.previewCloseAction) root.previewCloseAction = ConfigBackend.previewCloseAction;
        }
        function onEditorZoomChanged() {
            if (root.editorZoom !== ConfigBackend.editorZoom) root.editorZoom = ConfigBackend.editorZoom;
        }
        function onSpellcheckModeChanged() {
            if (root.spellcheckMode !== ConfigBackend.spellcheckMode) root.spellcheckMode = ConfigBackend.spellcheckMode;
        }
        function onVersionHistoryEnabledChanged() {
            if (root.versionHistoryEnabled !== ConfigBackend.versionHistoryEnabled) root.versionHistoryEnabled = ConfigBackend.versionHistoryEnabled;
        }
        function onVersionHistoryMaxChanged() {
            if (root.versionHistoryMax !== ConfigBackend.versionHistoryMax) root.versionHistoryMax = ConfigBackend.versionHistoryMax;
        }
        function onVersionHistoryMaxMbChanged() {
            if (root.versionHistoryMaxMb !== ConfigBackend.versionHistoryMaxMb) root.versionHistoryMaxMb = ConfigBackend.versionHistoryMaxMb;
        }
        function onPersistUndoChanged() {
            if (root.persistUndo !== ConfigBackend.persistUndo) root.persistUndo = ConfigBackend.persistUndo;
        }
        function onUiScaleChanged() {
            if (root.uiScale !== ConfigBackend.uiScale) root.uiScale = ConfigBackend.uiScale;
        }
    }

    function postApply(raw) {
        if (!raw) return;
        if (raw.previewCloseAction !== undefined && root.previewCloseAction !== raw.previewCloseAction) {
            root.previewCloseAction = String(raw.previewCloseAction);
        }
        if (raw.zoom !== undefined && raw.editorZoom === undefined) {
            var z = parseInt(raw.zoom, 10);
            if (!isNaN(z) && z >= 50 && z <= 300 && root.editorZoom !== z) {
                root.editorZoom = z;
            }
        }
    }

    function effectiveImportMode() {
        return root.importMode === "move" ? "move" : "copy";
    }

    function resolveNotesDir(customPath) {
        var p = (customPath && typeof customPath === "string") ? customPath.trim() : root.notesDir.trim();
        var home = Sys.homeDir;

        if (!p || p === "") {
            p = "$XDG_DOCUMENTS_DIR/notes";
        }

        if (p === "~") return home;
        if (p.startsWith("~/")) {
            p = home + p.substring(1);
        }
        p = p.replace(/\$HOME/g, home).replace(/\$\{HOME\}/g, home);

        var docsDir = (typeof Sys !== "undefined" && Sys.documentsDir) ? Sys.documentsDir : Sys.env("XDG_DOCUMENTS_DIR", home + "/Documentos");
        if (!docsDir || docsDir === "") {
            docsDir = home + "/Documentos";
        }

        p = p.replace(/\$XDG_DOCUMENTS_DIR/g, docsDir).replace(/\$\{XDG_DOCUMENTS_DIR\}/g, docsDir);

        if (p.length > 1 && p.endsWith("/")) {
            p = p.substring(0, p.length - 1);
        }

        return p;
    }
}
