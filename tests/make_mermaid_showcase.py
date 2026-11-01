#!/usr/bin/env -S python3 -B
# -*- coding: utf-8 -*-
import sys
sys.dont_write_bytecode = True
import os
import shutil

SHOWCASE_CONTENT = """---
title: "Muestra Completa de Diagramas Mermaid"
created: "2026-10-26 23:00:00"
modified: "2026-10-26 23:00:00"
type: note
tags: [mermaid, diagramas, test]
---

# Muestra y Validación de Diagramas Mermaid Nativos

Esta nota reúne todas las capacidades de la Fase 1 del motor nativo de Mermaid en Quickshell, además de casos borde y ejemplos de fases futuras.

---

## 1. Diagramas de Flujo (Flowchart / Graph)

### 1.1 Direcciones y Formas Básicas (TD / TB)

```mermaid
flowchart TD
    A[Rectángulo estándar] --> B(Esquinas redondeadas)
    B --> C([Forma de estadio])
    C --> D[[Subrutina con bordes dobles]]
    D --> E[(Base de datos cilindro)]
    E --> F((Círculo simple))
    F --> G(((Doble círculo)))
```

### 1.2 Formas Geométricas Avanzadas y Decisión (LR)

```mermaid
flowchart LR
    Start([Inicio]) --> Check{¿Condición válida?}
    Check -- Sí --> Hex{{Proceso Hexagonal}}
    Check -- No --> Parallel[/Paralelogramo entrada/]
    Hex --> Trap[/Trapecio escalado\\]
    Parallel --> Asym>Etiqueta Asimétrica]
    Trap --> End([Fin])
    Asym --> End
```

### 1.3 Tipos de Aristas y Conexiones Múltiples

```mermaid
flowchart TD
    A -->|Flecha sólida con texto| B
    B ---|Línea sin flecha| C
    C -.->|Línea punteada flecha| D
    D -.-|Línea punteada sin flecha| E
    E ==>|Flecha gruesa| F
    F ===|Línea gruesa sin flecha| G
    A & B --> C & D
```

### 1.4 Subgrafos (Clusters)

```mermaid
flowchart TB
    subgraph Frontend [Capa de Usuario]
        UI[Interfaz QML] --> Store[Estado Local]
    end
    subgraph Backend [Servicios del Sistema]
        Core[NotesService] --> DB[(Disco Local)]
    end
    Store --> Core
```

---

## 2. Diagramas de Secuencia (Sequence Diagram)

```mermaid
sequenceDiagram
    autonumber
    actor Usuario
    participant Modal as NoteEditorModal
    participant Editor as BlockEditor
    participant Parser as MermaidParser

    Usuario->>Modal: Clic en nuevo diagrama
    Modal->>Editor: Insertar bloque mermaid
    Editor->>Parser: Parsear texto
    Parser-->>Editor: Retornar AST
    Note over Editor: Renderizar Shapes vectoriales
    Editor-->>Usuario: Vista previa interactiva
```

---

## 3. Gráficos de Torta (Pie Chart)

```mermaid
pie title Distribución de Formatos de Notas
    "Markdown (.md)" : 65
    "Texto plano (.txt)" : 15
    "Documentos importados" : 12
    "Borradores rápidos" : 8
```

---

## 4. Diagramas de Estado (State Diagram)

```mermaid
stateDiagram-v2
    [*] --> Reposo
    Reposo --> Editando: Clic en bloque
    Editando --> Validando: Modificar código
    Validando --> Editando: Error de sintaxis
    Validando --> Reposo: Ctrl+Enter /<br/>Confirmar
    Reposo --> [*]: Cerrar nota
```

---

## 5. Diagramas Fase 2

### 5.1 Diagrama de Clases (Fase 2)

```mermaid
classDiagram
    direction LR
    class BlockMermaid {
        +String raw
        +Boolean isEditing
        -int cacheKey
        +render()
        +syncModel()*
    }
    class ViewItem {
        <<interface>>
        +display()
    }
    BlockMermaid --|> ViewItem : implements
    BlockMermaid "1" *-- "many" ChildItem : contains
```

### 5.2 Diagrama Entidad-Relación (Fase 2)

```mermaid
erDiagram
    CLIENTE ||--o{ PEDIDO : realiza
    PEDIDO ||--|{ ITEM : contiene
    CLIENTE {
        string nombre
        int id PK
        string email UK
    }
    PEDIDO {
        int numero PK
        int clienteId FK
        string direccion
    }
```

### 5.3 Cronograma Gantt (Fase 2)

```mermaid
gantt
    title Plan de Desarrollo
    dateFormat YYYY-MM-DD
    section Fase 1
        Parser Base    :done, p1, 2026-10-01, 3d
        Layout Motor   :done, l1, after p1, 4d
    section Fase 2
        Nuevos Tipos   :active, n1, after l1, 5d
        Hito Alpha     :milestone, m1, after n1, 0d
```

### 5.4 Línea de Tiempo (Fase 2)

```mermaid
timeline
    title Hitos del Proyecto
    section 2024
        Q1 : Lanzamiento Inicial : Feedback
        Q2 : Arquitectura QML Nativa
    section 2025
        Q1 : Soporte Markdown Typora
        Q3 : Motor Mermaid Fase 1 y 2
```

### 5.5 Mapa Mental (Fase 2)

```mermaid
mindmap
  root((Arquitectura))
    Frontend
      QML Nativo
      Theme Reactive
    Backend
      Rust qs-helper
      JS Parsers
    Tests
      Headless Suite
```

---

## 6. Diagramas Analíticos y de Flujo (Fase 3)

### 6.1 Git Graph (Fase 3)

```mermaid
gitGraph
    commit id: "Init"
    commit id: "Base"
    branch feature/mermaid
    checkout feature/mermaid
    commit id: "Parser Fase 3" tag: "v0.3"
    commit id: "Layout Motor"
    checkout main
    merge feature/mermaid id: "Merge PR #3" tag: "v1.0"
    commit id: "Release"
```

### 6.2 Gráfico de Cuadrantes (Fase 3)

```mermaid
quadrantChart
    title Priorización de Features
    x-axis Bajo Impacto --> Alto Impacto
    y-axis Baja Complejidad --> Alta Complejidad
    quadrant-1 Evaluar cuidadosamente
    quadrant-2 Prioridad inmediata
    quadrant-3 Descartar
    quadrant-4 Victorias rápidas
    Refactor Parser: [0.75, 0.35]
    Nuevos Temas: [0.65, 0.20]
    Backend Rust: [0.90, 0.85]
    Animaciones Lottie: [0.45, 0.70]
```

### 6.3 Mapa de Viaje de Usuario (Fase 3)

```mermaid
journey
    title Jornada de Trabajo en Quickshell
    section Inicio del día
        Encendido y Login: 5: Usuario
        Revisión de Notificaciones: 4: Usuario, Sistema
    section Productividad
        Edición de Notas: 5: Usuario
        Depuración y Tests: 3: Usuario, Agente
    section Cierre
        Sincronización Git: 5: Usuario, Git
        Apagado limpio: 5: Usuario
```

### 6.4 Gráfico Cartesiano XY (Fase 3)

```mermaid
xychart-beta
    title "Rendimiento y Métricas Trimestrales"
    x-axis [Q1, Q2, Q3, Q4]
    y-axis "Puntuación" 1000 --> 6000
    bar [2400, 3200, 4100, 5600]
    line [2100, 2900, 3900, 5300]
```

---

## 7. Casos Borde y Robustez

### 7.1 Manejo de Caracteres Especiales y HTML Seguro

```mermaid
flowchart LR
    A["Texto con <br/> salto de línea"] --> B["Comillas &quot;escapadas&quot;"]
    B --> C["Caracteres: <>&'#9829; ♥"]
```

### 6.2 Diagrama Vacío

```mermaid
flowchart TD
```
"""

def main():
    repo_tests = os.path.dirname(os.path.abspath(__file__))
    showcase_path = os.path.join(repo_tests, "mermaid_showcase.md")
    
    with open(showcase_path, "w", encoding="utf-8") as f:
        f.write(SHOWCASE_CONTENT)
    print(f"  ✓ Archivo de prueba creado en repo: {showcase_path}")

    # Copiar a Documentos/notes/ si existe
    home = os.path.expanduser("~")
    notes_dir = os.path.join(home, "Documentos", "notes")
    if not os.path.isdir(notes_dir):
        notes_dir = os.path.join(home, "Documents", "notes")
    
    if os.path.isdir(notes_dir):
        target_note = os.path.join(notes_dir, "mermaid_showcase.md")
        with open(target_note, "w", encoding="utf-8") as f:
            f.write(SHOWCASE_CONTENT)
        print(f"  ✓ Copiado a directorio de notas del usuario: {target_note}")

if __name__ == "__main__":
    main()
