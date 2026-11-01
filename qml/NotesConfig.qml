pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import quickshell 1.0

Singleton {
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
            default: "copy",
            values: ["copy", "move"],
            labels: [
                I18n.t("config.notes.import_mode_copy", "Copiar"),
                I18n.t("config.notes.import_mode_move", "Mover")
            ],
            label: I18n.t("config.notes.import_mode", "Al arrastrar un archivo"),
            comment: I18n.t("config.notes.import_mode_comment", "Si los .md arrastrados se copian o se mueven a la carpeta de notas.")
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
        }
    ]

    property string notesDir: "$XDG_DOCUMENTS_DIR/notes"
    property bool   showImagePreviews: true
    property bool   cyclePreviewImages: true
    property int    cardsPerRow: 3
    property string importMode: "copy"
    property int    editorZoom: 100
    property string spellcheckMode: "auto"

    function postApply(raw) {
        if (!raw) return;
        if (raw.zoom !== undefined && raw.editorZoom === undefined) {
            var z = parseInt(raw.zoom, 10);
            if (!isNaN(z) && z >= 50 && z <= 300 && root.editorZoom !== z) {
                root.editorZoom = z;
            }
        }
    }

    // Modo efectivo: solo "move" mueve; cualquier otro valor (conf corrupto) copia
    function effectiveImportMode() {
        return root.importMode === "move" ? "move" : "copy";
    }

    // ── Lector reactivo de ~/.config/user-dirs.dirs ─────────────────────
    FileView {
        id: userDirsFile
        path: (Quickshell.env("HOME") || "") + "/.config/user-dirs.dirs"
        preload: true
        watchChanges: true
        printErrors: false
    }

    // ── Resuelve rutas de notas expandiendo variables XDG y HOME ─────────
    function resolveNotesDir(customPath) {
        var p = (customPath && typeof customPath === "string") ? customPath.trim() : root.notesDir.trim();
        var home = Quickshell.env("HOME") || "";

        if (!p || p === "") {
            p = "$XDG_DOCUMENTS_DIR/notes";
        }

        // 1. Resolver ~
        if (p === "~") return home;
        if (p.startsWith("~/")) {
            p = home + p.substring(1);
        }
        p = p.replace(/\$HOME/g, home).replace(/\$\{HOME\}/g, home);

        // 2. Resolver $XDG_DOCUMENTS_DIR
        var docsDir = "";
        var envDocs = Quickshell.env("XDG_DOCUMENTS_DIR");
        if (envDocs && envDocs !== "") {
            docsDir = envDocs;
        } else if (userDirsFile.loaded) {
            var raw = userDirsFile.text();
            var m = raw.match(/^\s*XDG_DOCUMENTS_DIR="?([^"\n]+)"?/m);
            if (m && m[1]) {
                docsDir = m[1].replace("$HOME", home);
            }
        }

        if (!docsDir || docsDir === "") {
            docsDir = home + "/Documentos";
        }

        p = p.replace(/\$XDG_DOCUMENTS_DIR/g, docsDir).replace(/\$\{XDG_DOCUMENTS_DIR\}/g, docsDir);

        // Limpiar barras finales si las tuviese
        if (p.length > 1 && p.endsWith("/")) {
            p = p.substring(0, p.length - 1);
        }

        return p;
    }

    ConfigBinder { target: root; configName: "notes" }
}
