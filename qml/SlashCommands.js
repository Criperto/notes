.pragma library

// SlashCommands.js — Catálogo y definiciones de comandos con '/' estilo Notion (F78)

var COMMANDS = [
    // ── Bloques básicos ──────────────────────────────────────────────────────
    {
        id: "h1",
        category: "basic",
        icon: "format-h1.svg",
        titleKey: "notes.slash.h1",
        fallbackTitle: "Título 1",
        descKey: "notes.slash.h1_desc",
        fallbackDesc: "Encabezado principal grande",
        badge: "/h1",
        keywords: ["h1", "titulo1", "encabezado1", "heading1", "h", "titulo", "header"]
    },
    {
        id: "h2",
        category: "basic",
        icon: "format-h2.svg",
        titleKey: "notes.slash.h2",
        fallbackTitle: "Título 2",
        descKey: "notes.slash.h2_desc",
        fallbackDesc: "Subtítulo de sección mediano",
        badge: "/h2",
        keywords: ["h2", "titulo2", "encabezado2", "heading2", "subtitulo", "section"]
    },
    {
        id: "h3",
        category: "basic",
        icon: "format-h3.svg",
        titleKey: "notes.slash.h3",
        fallbackTitle: "Título 3",
        descKey: "notes.slash.h3_desc",
        fallbackDesc: "Encabezado pequeño",
        badge: "/h3",
        keywords: ["h3", "titulo3", "encabezado3", "heading3", "seccion"]
    },
    {
        id: "bullet_list",
        category: "basic",
        icon: "format-list-bulleted.svg",
        titleKey: "notes.slash.bullet_list",
        fallbackTitle: "Lista con viñetas",
        descKey: "notes.slash.bullet_list_desc",
        fallbackDesc: "Viñetas simples no ordenadas",
        badge: "/lista",
        keywords: ["lista", "vineta", "bullet", "puntos", "items", "ul"]
    },
    {
        id: "numbered_list",
        category: "basic",
        icon: "format-list-numbered.svg",
        titleKey: "notes.slash.numbered_list",
        fallbackTitle: "Lista numerada",
        descKey: "notes.slash.numbered_list_desc",
        fallbackDesc: "Secuencia ordenada con números",
        badge: "/numero",
        keywords: ["numero", "ordenada", "secuencia", "numbered", "123", "ol"]
    },
    {
        id: "task_list",
        category: "basic",
        icon: "checklist.svg",
        titleKey: "notes.slash.task_list",
        fallbackTitle: "Lista de tareas",
        descKey: "notes.slash.task_list_desc",
        fallbackDesc: "Casillas de verificación interactivas",
        badge: "/tarea",
        keywords: ["tarea", "checklist", "task", "todo", "casilla", "check"]
    },

    // ── Estructura y código ──────────────────────────────────────────────────
    {
        id: "table",
        category: "advanced",
        icon: "table.svg",
        titleKey: "notes.slash.table",
        fallbackTitle: "Tabla",
        descKey: "notes.slash.table_desc",
        fallbackDesc: "Insertar cuadrícula con filas y columnas",
        badge: "/tabla",
        keywords: ["tabla", "table", "grid", "cuadricula", "filas", "columnas"]
    },
    {
        id: "mermaid",
        category: "advanced",
        icon: "diagram.svg",
        titleKey: "notes.slash.mermaid",
        fallbackTitle: "Diagrama Mermaid",
        descKey: "notes.slash.mermaid_desc",
        fallbackDesc: "Flujos, secuencias, gráficos y arquitectura",
        badge: "/mermaid",
        keywords: ["mermaid", "diagrama", "flujo", "flowchart", "grafico", "chart", "secuencia"]
    },
    {
        id: "math",
        category: "advanced",
        icon: "math.svg",
        titleKey: "notes.slash.math",
        fallbackTitle: "Fórmula LaTeX",
        descKey: "notes.slash.math_desc",
        fallbackDesc: "Ecuación matemática con renderizado TeX",
        badge: "/math",
        keywords: ["math", "latex", "formula", "ecuacion", "tex", "integral", "fraccion", "matematica", "calcular"]
    },
    {
        id: "code_block",
        category: "advanced",
        icon: "code-blocks.svg",
        titleKey: "notes.slash.code_block",
        fallbackTitle: "Bloque de código",
        descKey: "notes.slash.code_block_desc",
        fallbackDesc: "Código con resaltado de sintaxis",
        badge: "/codigo",
        keywords: ["codigo", "code", "snippet", "syntax", "fence", "bloque"]
    },
    {
        id: "quote",
        category: "advanced",
        icon: "format-quote.svg",
        titleKey: "notes.slash.quote",
        fallbackTitle: "Cita",
        descKey: "notes.slash.quote_desc",
        fallbackDesc: "Cita de texto con barra lateral",
        badge: "/cita",
        keywords: ["cita", "quote", "blockquote", "frase"]
    },
    {
        id: "hr",
        category: "advanced",
        icon: "horizontal-rule.svg",
        titleKey: "notes.slash.hr",
        fallbackTitle: "Línea divisoria",
        descKey: "notes.slash.hr_desc",
        fallbackDesc: "Separador horizontal visual",
        badge: "/separador",
        keywords: ["separador", "hr", "linea", "divider", "regla"]
    },

    // ── Callouts estilo GitHub ───────────────────────────────────────────────
    {
        id: "callout_note",
        category: "callout",
        icon: "info.svg",
        calloutType: "NOTE",
        titleKey: "notes.slash.callout_note",
        fallbackTitle: "Nota (Callout)",
        descKey: "notes.slash.callout_note_desc",
        fallbackDesc: "Caja informativa azul con contexto adicional",
        badge: "/note",
        keywords: ["note", "nota", "callout", "info", "admonition", "azul"]
    },
    {
        id: "callout_tip",
        category: "callout",
        icon: "lightbulb.svg",
        calloutType: "TIP",
        titleKey: "notes.slash.callout_tip",
        fallbackTitle: "Consejo (Callout)",
        descKey: "notes.slash.callout_tip_desc",
        fallbackDesc: "Caja verde para sugerencias y atajos",
        badge: "/tip",
        keywords: ["tip", "consejo", "callout", "atajo", "verde", "truco"]
    },
    {
        id: "callout_important",
        category: "callout",
        icon: "report.svg",
        calloutType: "IMPORTANT",
        titleKey: "notes.slash.callout_important",
        fallbackTitle: "Importante (Callout)",
        descKey: "notes.slash.callout_important_desc",
        fallbackDesc: "Caja violeta para directivas críticas",
        badge: "/important",
        keywords: ["important", "importante", "callout", "violeta", "critico"]
    },
    {
        id: "callout_warning",
        category: "callout",
        icon: "warning.svg",
        calloutType: "WARNING",
        titleKey: "notes.slash.callout_warning",
        fallbackTitle: "Advertencia (Callout)",
        descKey: "notes.slash.callout_warning_desc",
        fallbackDesc: "Caja amarilla para alertar sobre riesgos",
        badge: "/warning",
        keywords: ["warning", "advertencia", "alerta", "callout", "amarillo", "riesgo"]
    },
    {
        id: "callout_caution",
        category: "callout",
        icon: "error.svg",
        calloutType: "CAUTION",
        titleKey: "notes.slash.callout_caution",
        fallbackTitle: "Precaución (Callout)",
        descKey: "notes.slash.callout_caution_desc",
        fallbackDesc: "Caja roja para acciones irreversibles",
        badge: "/caution",
        keywords: ["caution", "precaucion", "peligro", "callout", "rojo", "destructivo"]
    }
];

function getAllCommands() {
    return COMMANDS.slice();
}

function getCommand(id) {
    if (!id || typeof id !== "string") return null;
    for (var i = 0; i < COMMANDS.length; i++) {
        if (COMMANDS[i].id === id) return COMMANDS[i];
    }
    return null;
}
