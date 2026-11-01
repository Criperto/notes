// notes/MermaidTemplates.js
// Plantillas predefinidas para la inserción rápida de diagramas Mermaid

var TEMPLATES = {
    flowchart: "```mermaid\nflowchart TD\n    A[Inicio] --> B{¿Es válido?}\n    B -- Sí --> C[Procesar]\n    B -- No --> D[Error]\n    C --> E([Fin])\n    D --> E\n```",
    sequence: "```mermaid\nsequenceDiagram\n    autonumber\n    actor Usuario\n    participant App as Aplicación\n    participant Servidor\n    Usuario->>App: Solicitar datos\n    App->>Servidor: GET /api/recursos\n    Servidor-->>App: 200 OK (JSON)\n    App-->>Usuario: Mostrar resultado\n```",
    pie: "```mermaid\npie title Distribución del Proyecto\n    \"Desarrollo\" : 45\n    \"Diseño UX/UI\" : 25\n    \"Testing & QA\" : 20\n    \"Documentación\" : 10\n```",
    state: "```mermaid\nstateDiagram-v2\n    [*] --> Reposo\n    Reposo --> Activo : Iniciar\n    state Activo {\n        [*] --> Procesando\n        Procesando --> Completado : Éxito\n    }\n    Activo --> Reposo : Detener\n    Completado --> [*]\n```",
    classDiagram: "```mermaid\nclassDiagram\n    direction LR\n    class Animal {\n        +int edad\n        +String genero\n        +respirar()\n    }\n    class Pato {\n        +String colorPico\n        +nadar()\n        +graznar()\n    }\n    Animal <|-- Pato : hereda\n```",
    erDiagram: "```mermaid\nerDiagram\n    CLIENTE ||--o{ PEDIDO : realiza\n    PEDIDO ||--|{ ITEM : contiene\n    CLIENTE {\n        string nombre\n        int id PK\n    }\n    PEDIDO {\n        int numero PK\n        int clienteId FK\n    }\n```",
    gantt: "```mermaid\ngantt\n    title Cronograma de Proyecto\n    dateFormat YYYY-MM-DD\n    section Desarrollo\n        Planificación :done, t1, 2026-10-01, 3d\n        Prototipo     :active, t2, after t1, 5d\n        Lanzamiento   :milestone, m1, after t2, 0d\n```",
    timeline: "```mermaid\ntimeline\n    title Cronología de Hitos\n    section 2024\n        Q1 : Inicio del proyecto\n        Q2 : Versión Alfa\n    section 2025\n        Q1 : Versión Estable\n```",
    mindmap: "```mermaid\nmindmap\n  root((Idea Principal))\n    Concepto A\n      Detalle 1\n      Detalle 2\n    Concepto B\n      Detalle 3\n```",
    gitGraph: "```mermaid\ngitGraph\n    commit id: \"Inicio\"\n    branch feature\n    checkout feature\n    commit id: \"Nueva función\" tag: \"v0.1\"\n    checkout main\n    merge feature id: \"Integrar cambios\"\n    commit id: \"Release\" tag: \"v1.0\"\n```",
    quadrantChart: "```mermaid\nquadrantChart\n    title Priorización de Proyectos\n    x-axis Bajo Impacto --> Alto Impacto\n    y-axis Baja Complejidad --> Alta Complejidad\n    quadrant-1 Evaluar con calma\n    quadrant-2 Prioridad inmediata\n    quadrant-3 Descartar\n    quadrant-4 Victorias rápidas\n    Refactor UI: [0.8, 0.4]\n    Documentación: [0.6, 0.2]\n    Migración BD: [0.9, 0.85]\n    Optimización: [0.4, 0.7]\n```",
    journey: "```mermaid\njourney\n    title Jornada de Trabajo\n    section Mañana\n        Café: 5: Yo\n        Revisión de correos: 3: Yo, Asistente\n    section Tarde\n        Desarrollo de features: 5: Yo\n        Testing & QA: 4: Yo, QA\n    section Fin del día\n        Deploy y release: 5: Yo\n```",
    xychart: "```mermaid\nxychart-beta\n    title \"Rendimiento y Ventas\"\n    x-axis [Q1, Q2, Q3, Q4]\n    y-axis \"Ingresos ($)\" 1000 --> 6000\n    bar [2200, 3400, 4100, 5600]\n    line [1800, 2900, 3900, 5200]\n```"
};

function getTemplate(key) {
    if (TEMPLATES[key]) {
        return TEMPLATES[key];
    }
    return TEMPLATES.flowchart;
}

function getTemplateList() {
    return [
        { id: "flowchart", labelKey: "notes.mermaid.template.flow", defaultLabel: "Diagrama de Flujo (Flowchart)", icon: "diagram" },
        { id: "sequence", labelKey: "notes.mermaid.template.sequence", defaultLabel: "Diagrama de Secuencia", icon: "skip-forward" },
        { id: "pie", labelKey: "notes.mermaid.template.pie", defaultLabel: "Gráfico Circular (Pie Chart)", icon: "chart-line" },
        { id: "state", labelKey: "notes.mermaid.template.state", defaultLabel: "Diagrama de Estados", icon: "activity" },
        { id: "classDiagram", labelKey: "notes.mermaid.template.class", defaultLabel: "Diagrama de Clases (UML)", icon: "code" },
        { id: "erDiagram", labelKey: "notes.mermaid.template.er", defaultLabel: "Diagrama Entidad-Relación (ER)", icon: "grid" },
        { id: "gantt", labelKey: "notes.mermaid.template.gantt", defaultLabel: "Diagrama de Gantt", icon: "calendar" },
        { id: "timeline", labelKey: "notes.mermaid.template.timeline", defaultLabel: "Línea de Tiempo (Timeline)", icon: "clock" },
        { id: "mindmap", labelKey: "notes.mermaid.template.mindmap", defaultLabel: "Mapa Mental (Mindmap)", icon: "diagram" },
        { id: "gitGraph", labelKey: "notes.mermaid.template.git", defaultLabel: "Grafo de Git (Git Graph)", icon: "diagram" },
        { id: "quadrantChart", labelKey: "notes.mermaid.template.quadrant", defaultLabel: "Gráfico de Cuadrantes", icon: "apps" },
        { id: "journey", labelKey: "notes.mermaid.template.journey", defaultLabel: "Viaje de Usuario (User Journey)", icon: "location" },
        { id: "xychart", labelKey: "notes.mermaid.template.xychart", defaultLabel: "Gráfico XY (Barras y Líneas)", icon: "chart-line" }
    ];
}
