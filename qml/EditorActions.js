.pragma library

// EditorActions.js — Definición centralizada de acciones, atajos e i18n del editor de notas
var ACTIONS = {
    "bold": {
        id: "bold",
        labelKey: "notes.editor.action.bold",
        fallbackLabel: "Negrita",
        shortcut: "Ctrl+B"
    },
    "italic": {
        id: "italic",
        labelKey: "notes.editor.action.italic",
        fallbackLabel: "Cursiva",
        shortcut: "Ctrl+I"
    },
    "underline": {
        id: "underline",
        labelKey: "notes.editor.action.underline",
        fallbackLabel: "Subrayado",
        shortcut: "Ctrl+U"
    },
    "strike": {
        id: "strike",
        labelKey: "notes.editor.action.strike",
        fallbackLabel: "Tachado",
        shortcut: "Ctrl+Shift+X"
    },
    "highlight": {
        id: "highlight",
        labelKey: "notes.editor.action.highlight",
        fallbackLabel: "Resaltar",
        shortcut: "Ctrl+H"
    },
    "inline_code": {
        id: "inline_code",
        labelKey: "notes.editor.action.inline_code",
        fallbackLabel: "Código inline",
        shortcut: "Ctrl+E"
    },
    "h1": {
        id: "h1",
        labelKey: "notes.editor.action.h1",
        fallbackLabel: "Encabezado 1",
        shortcut: "Ctrl+Alt+1"
    },
    "h2": {
        id: "h2",
        labelKey: "notes.editor.action.h2",
        fallbackLabel: "Encabezado 2",
        shortcut: "Ctrl+Alt+2"
    },
    "h3": {
        id: "h3",
        labelKey: "notes.editor.action.h3",
        fallbackLabel: "Encabezado 3",
        shortcut: "Ctrl+Alt+3"
    },
    "h4": {
        id: "h4",
        labelKey: "notes.editor.action.h4",
        fallbackLabel: "Encabezado 4",
        shortcut: "Ctrl+Alt+4"
    },
    "h5": {
        id: "h5",
        labelKey: "notes.editor.action.h5",
        fallbackLabel: "Encabezado 5",
        shortcut: "Ctrl+Alt+5"
    },
    "h6": {
        id: "h6",
        labelKey: "notes.editor.action.h6",
        fallbackLabel: "Encabezado 6",
        shortcut: "Ctrl+Alt+6"
    },
    "heading_menu": {
        id: "heading_menu",
        labelKey: "notes.editor.action.heading_menu",
        fallbackLabel: "Encabezados (H1-H6)",
        shortcut: ""
    },
    "bullet_list": {
        id: "bullet_list",
        labelKey: "notes.editor.action.bullet_list",
        fallbackLabel: "Lista de viñetas",
        shortcut: "Ctrl+Shift+8"
    },
    "ordered_list": {
        id: "ordered_list",
        labelKey: "notes.editor.action.ordered_list",
        fallbackLabel: "Lista numerada",
        shortcut: "Ctrl+Shift+7"
    },
    "task_list": {
        id: "task_list",
        labelKey: "notes.editor.action.task_list",
        fallbackLabel: "Lista de tareas",
        shortcut: "Ctrl+Shift+9"
    },
    "quote": {
        id: "quote",
        labelKey: "notes.editor.action.quote",
        fallbackLabel: "Cita",
        shortcut: "Ctrl+Shift+Q"
    },
    "code_block": {
        id: "code_block",
        labelKey: "notes.editor.action.code_block",
        fallbackLabel: "Bloque de código",
        shortcut: "Ctrl+Shift+E"
    },
    "table": {
        id: "table",
        labelKey: "notes.editor.action.table",
        fallbackLabel: "Tabla",
        shortcut: "Ctrl+Shift+T"
    },
    "mermaid": {
        id: "mermaid",
        labelKey: "notes.editor.action.mermaid",
        fallbackLabel: "Insertar diagrama Mermaid",
        shortcut: "Ctrl+Shift+M"
    },
    "math": {
        id: "math",
        labelKey: "notes.editor.action.math",
        fallbackLabel: "Fórmula matemática (LaTeX)",
        shortcut: ""
    },
    "hr": {
        id: "hr",
        labelKey: "notes.editor.action.hr",
        fallbackLabel: "Línea divisoria",
        shortcut: "Ctrl+Shift+H"
    },
    "image": {
        id: "image",
        labelKey: "notes.editor.action.image",
        fallbackLabel: "Insertar imagen",
        shortcut: "Ctrl+Shift+I"
    },
    "link": {
        id: "link",
        labelKey: "notes.editor.action.link",
        fallbackLabel: "Insertar enlace",
        shortcut: "Ctrl+K"
    },
    "wikilink": {
        id: "wikilink",
        labelKey: "notes.editor.action.wikilink",
        fallbackLabel: "Referencia a otra nota",
        shortcut: "Ctrl+Shift+K"
    },
    "anchor": {
        id: "anchor",
        labelKey: "notes.editor.action.anchor",
        fallbackLabel: "Enlace a sección",
        shortcut: "Ctrl+Alt+A"
    },
    "find": {
        id: "find",
        labelKey: "notes.editor.action.find",
        fallbackLabel: "Buscar en la nota",
        shortcut: "Ctrl+F"
    },
    "source_mode": {
        id: "source_mode",
        labelKey: "notes.editor.action.source_mode",
        fallbackLabel: "Modo código fuente",
        shortcut: ""
    },
    "convert_to_md": {
        id: "convert_to_md",
        labelKey: "notes.editor.action.convert_to_md",
        fallbackLabel: "Convertir a .md",
        shortcut: ""
    },
    "preview": {
        id: "preview",
        labelKey: "notes.editor.action.preview",
        fallbackLabel: "Vista previa",
        shortcut: "Ctrl+P"
    },
    "save": {
        id: "save",
        labelKey: "notes.editor.action.save",
        fallbackLabel: "Guardar",
        shortcut: "Ctrl+S"
    },
    "close": {
        id: "close",
        labelKey: "notes.editor.action.close",
        fallbackLabel: "Cerrar",
        shortcut: "Esc"
    },
    "pin": {
        id: "pin",
        labelKey: "notes.editor.action.pin",
        fallbackLabel: "Fijar nota",
        shortcut: ""
    },
    "unpin": {
        id: "unpin",
        labelKey: "notes.editor.action.unpin",
        fallbackLabel: "Desfijar nota",
        shortcut: ""
    },
    "delete": {
        id: "delete",
        labelKey: "notes.editor.action.delete",
        fallbackLabel: "Eliminar nota",
        shortcut: ""
    },
    "spellcheck": {
        id: "spellcheck",
        labelKey: "notes.editor.action.spellcheck",
        fallbackLabel: "Corrector ortográfico",
        shortcut: "F7"
    }
};

function getAction(id) {
    return ACTIONS[id] || null;
}

function getLabel(id, i18n) {
    var act = getAction(id);
    if (!act) return "";
    if (i18n && typeof i18n.t === "function") {
        return i18n.t(act.labelKey, act.fallbackLabel);
    }
    return act.fallbackLabel;
}

function getShortcut(id) {
    var act = getAction(id);
    return act ? act.shortcut : "";
}
