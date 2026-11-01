# Desvíos Detectados y Resoluciones Arquitectónicas (`DESVIOS.md`)

Registro de discrepancias encontradas entre la propuesta inicial (`PLAN-INDEPENDIZAR-NOTAS.md`), el código fuente real extraído de Quickshell (`notes/`), el árbol del sistema host (CachyOS / Arch Linux) y la solución implementada.

---

### D1: Dependencias QML adicionales del shell raíz (`CustomTextCursor`, `CustomScrollBar`, `HyprlandConfig`)
* **Detección:** 14 archivos en `qml/` consumían `CustomTextCursor` (18 usos), `CustomScrollBar` (7 usos) y `HyprlandConfig` (`blurEnabled`, `quickshellBlurMax`), además de los 5 singletons documentados.
* **Impacto:** Si se omitían, la app fallaba de inmediato al instanciar cualquier bloque de texto editable (`BlockEditor`, `BlockParagraph`, `BlockQuote`, `BlockHeading`, `BlockTable`, `BlockList`, `NoteEditorModal`).
* **Resolución:**
  - Portar `CustomTextCursor.qml` a `qml/` eliminando la línea `import Quickshell` (innecesaria).
  - Portar `CustomScrollBar.qml` a `qml/`.
  - Crear singleton `qml/HyprlandConfig.qml` conectado a `Config.blurEnabled` con fallback seguro de desenfoque.

---

### D2: Tokens visuales y de paleta consumidos en `Theme`
* **Detección:** `notes/*.qml` consumía 32 propiedades de `Theme`, entre ellas `color10`..`color14`, `fontFamilyDisplay`, `fontSizeCaption`, más `hasTouchscreen` y `hideScrollbars`.
* **Impacto:** Colores `undefined` en diagramas Mermaid y bloques de código; scrollbars visibles aún cuando la preferencia fuera ocultarlos.
* **Resolución:** `qml/Theme.qml` define la paleta completa ANSI `color0`..`color15`, helpers WCAG (`textOn`, `contrastRatio`), y tokens tipográficos completos.

---

### D3: Inventario real de iconos vectoriales SVG
* **Detección:** El conteo real de iconos SVG en el editor y tarjetas es de 38 archivos (faltaba `content-copy.svg`, usado en los bloques de código y diagramas Mermaid).
* **Resolución:** Los 38 iconos SVG están empaquetados en `assets/icons/` y registrados en los recursos compilados de Qt (QRC).

---

### D4: Comportamiento de `SplitParser` con delimitador vacío (`splitMarker: ""`)
* **Detección:** En `NotesService.qml`, `directFileReadProc` y `qsIndexProc` configuran `splitMarker: ""`. Si el parser nativo de Rust ejecuta `str::find("")`, devuelve siempre `Some(0)`, causando un bucle infinito que congela el proceso.
* **Resolución:** En `Notas.Native.SplitParser`, cuando `splitMarker.is_empty()`, cada chunk recibido se emite completo e inmediato a `read(chunk)`.

---

### D5: Versiones de `cxx-qt` y `ashpd` en `crates.io`
* **Detección:** `cxx-qt` se encuentra en versión `0.10.0` (la API `0.8` quedó obsoleta). `ashpd 0.13` depende de `zbus ^5.13` (mientras `zbus 6` ya fue liberado).
* **Resolución:** Usar `cxx-qt = "0.10"`, `cxx-qt-build = { version = "0.10", features = ["link_qt_object_files"] }` y unificar `zbus = "5.13"` para evitar compilar dos versiones mayores de D-Bus.

---

### D6: Dependencias del sistema host
* **Detección:** El host contaba con `qt6-base`, `qt6-declarative` y `qt6-svg`, pero faltaban `qt6-tools` (necesario para `qmlcachegen` y herramientas de build) y `qt6-wayland`.
* **Resolución:** Se añaden como dependencias de compilación y empaquetado en el `PKGBUILD` y se instalan en el entorno host.

---

### D7: Suite de pruebas `tests/run.js` y adaptación de rutas
* **Detección:** Los tests `F29` y `F31` leían el archivo de configuración en `../../Singletons/NotesConfig.qml` y los módulos JS esperaban estar en el directorio raíz.
* **Resolución:** `tests/run.js` resuelve dinámicamente las rutas hacia `qml/` y `qml/NotesConfig.qml`, manteniendo 139 tests OK y 0 fallos.
