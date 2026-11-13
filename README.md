# Notas (`dev.criperto.Notas`)

> Editor moderno y nativo de notas en Markdown con edición visual por bloques, diagramas Mermaid enriquecidos, soporte multilingüe y rendimiento ultra-ligero.

![License: GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)
![Version: 0.2.8](https://img.shields.io/badge/version-0.2.8-orange.svg)
![Platform: Linux / Wayland](https://img.shields.io/badge/platform-Wayland-purple.svg)

---

## 🌟 Características Principales

- **Edición Híbrida Live-Preview:** Edición fluida por bloques de párrafos, listas con checkboxes interactivos, citas multinivel, tablas dinámicas y código resaltado con selector de lenguajes.
- **Motor Mermaid Nativo:** Soporte integrado completo para:
  - Fase 1: `flowchart` (TD/LR), `sequenceDiagram`, `pie`.
  - Fase 2: `classDiagram`, `erDiagram`, `gantt`, `timeline`, `mindmap`.
  - Fase 3: `gitGraph`, `quadrantChart`, `journey`, `xychart-beta`.
- **Integración con Wayland / Hyprland:** Ventana nativa Wayland (`dev.criperto.Notas`), renderizado acelerado por GPU vía Qt Quick y estilo visual moderno con desenfoque de fondo opcional.
- **Corrector Ortográfico Integrado:** Motor de corrección autónomo de alta velocidad basado en `Spellbook` con diccionarios base embebidos (`es_AR`, `es_ES`, `en_US`), catálogo descargable multilingüe y diccionario personal de usuario (`~/.config/criperto-notes/personal.dic`). Cero dependencias externas de paquetes de corrección.
- **Internacionalización Completa (i18n):** 9 idiomas incluidos (Español, Inglés, Portugués, Francés, Alemán, Italiano, Ruso, Japonés y Chino).
- **Persistencia Segura:** Guardado atómico con transacciones en disco (`QSaveFile`), exclusión de items en papelera y configuración centralizada en `~/.config/criperto-notes/config.json`.
- **Cero Dependencias de Quickshell:** Aplicación de escritorio 100% independiente compilada con Rust y Qt 6.

---

## 🛠 Arquitectura

- **Rust (`cxx-qt 0.10`):** Punto de entrada CLI, orquestación de ciclo de vida Wayland y herramientas nativas de indexación y parseo rápido.
- **C++ Native Bridge (`Notas.Native`):** Clases nativas integradas con QML (`QML_ELEMENT` y `QML_SINGLETON`):
  - `Sys`: Portapapeles, variables de entorno, ejecutor de procesos desacoplados y detección de pantalla táctil.
  - `ConfigBackend`: Configuración reactiva en JSON con migración automática desde configs legacy.
  - `SpellBackend`: Consultas al motor de corrección Spellbook y gestión de diccionarios.
  - `FileView`: Vigilancia de archivos mediante `QFileSystemWatcher` y guardado atómico.
  - `Process` & `SplitParser`: Lanzamiento y streaming de procesos con recolección de basura de subprocesos (cero huérfanos).
- **Qt Quick / QML:** Capa de presentación reactiva con diseño por bloques desacoplado, animaciones fluidas y soporte táctil/mouse/teclado.

---

## 📦 Requisitos del Sistema

- **Rust:** `rustc` y `cargo` 1.80 o superior.
- **Qt 6:** Versión 6.5+ con módulos:
  - `qt6-base`
  - `qt6-declarative` (QML / Quick / QuickControls 2)
  - `qt6-svg`
  - `qt6-wayland`
- **Compilador C++:** `clang++` o `g++` con soporte C++17.
- **CMake** y **pkg-config**.

### Comando único de dependencias para Arch Linux:
```bash
sudo pacman -S --needed base-devel rust cmake clang qt6-base qt6-declarative qt6-svg qt6-wayland
```

---

## 🚀 Compilación e Instalación

### 1. Clonar y Compilar

```bash
# Compilar binario de release
cargo build --release

# O para desarrollo:
cargo build
```

### 2. Instalar con el Script Unificado (`install.sh`)

El instalador unificado detecta automáticamente el entorno e idioma del sistema:

```bash
# Instalación global en el sistema (por defecto en /usr, solicita sudo si es necesario):
./scripts/install.sh

# O instalación local sólo para tu usuario actual (~/.local/):
./scripts/install.sh --user

# Desinstalación completa (detecta y limpia tanto /usr como ~/.local, sin tocar tus notas):
./scripts/install.sh --uninstall
```

---

## 📦 Paquetes y Distribución

En cada [Release de GitHub](https://github.com/Criperto/notes/releases) se publican paquetes binarios nativos precompilados listos para instalar:

### Arch Linux (`.pkg.tar.zst`)
```bash
sudo pacman -U criperto-notes-0.1.13-1-x86_64.pkg.tar.zst
```
Archivos PKGBUILD disponibles en [`packaging/arch/PKGBUILD`](packaging/arch/PKGBUILD) y [`packaging/arch/notas-git/PKGBUILD`](packaging/arch/notas-git/PKGBUILD).

### Debian / Ubuntu (`.deb`)
```bash
sudo dpkg -i criperto-notes_0.1.13_amd64.deb
```

### Fedora / RHEL (`.rpm`)
```bash
sudo dnf install criperto-notes-0.1.13-1.x86_64.rpm
```

### AppImage autónomo
```bash
chmod +x criperto-notes-0.1.13-x86_64.AppImage
./criperto-notes-0.1.13-x86_64.AppImage
```

### Flatpak

Manifiesto oficial para Flatpak basado en `org.kde.Platform`:

```bash
# Compilar e instalar localmente:
flatpak-builder --user --install --force-clean build-flatpak packaging/flatpak/dev.criperto.Notas.yml
```

Una vez instalado, la aplicación estará disponible en tu lanzador de aplicaciones favorito (Wofi, Rofi, Anyrun, etc.) y como comando `notas` en cualquier terminal.

---

## 💻 Uso de la Línea de Comandos (CLI)

```text
criperto.notes [OPTIONS] [PATH]

Argumentos:
  [PATH]                  Ruta a un archivo Markdown (.md) para abrir o previsualizar

Opciones:
  -n, --new [<NOMBRE>]    Crea y abre una nueva nota inmediatamente
  -t, --toggle            Alterna la visibilidad de la ventana en ejecución
  -p, --preview           Abre la nota directamente en modo solo lectura / previsualización
  -c, --close             Cierra la instancia activa de la aplicación
      --check             Verifica la inicialización del motor QML y sale (ideal para CI/tests)
  -h, --help              Muestra la ayuda
  -V, --version           Muestra la versión instalada
```

---

## ⌨️ Atajos de Teclado Principales

| Atajo | Acción |
|---|---|
| <kbd>Ctrl</kbd> + <kbd>,</kbd> | Abrir Menú de Configuración y Preferencias |
| <kbd>Ctrl</kbd> + <kbd>Q</kbd> | Cerrar la aplicación |
| <kbd>Ctrl</kbd> + <kbd>N</kbd> | Nueva nota |
| <kbd>Ctrl</kbd> + <kbd>Z</kbd> | Deshacer |
| <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>Z</kbd> / <kbd>Ctrl</kbd> + <kbd>Y</kbd> | Rehacer |
| <kbd>Ctrl</kbd> + <kbd>B</kbd> | Negrita (`**texto**`) |
| <kbd>Ctrl</kbd> + <kbd>I</kbd> | Cursiva (`*texto*`) |
| <kbd>Ctrl</kbd> + <kbd>K</kbd> | Insertar enlace (`[texto](url)`) |
| <kbd>F7</kbd> | Ejecutar verificación ortográfica |

---

## 🧪 Pruebas Automatizadas

La aplicación cuenta con una suite completa de pruebas unitarias que verifican la serialización/deserialización de Markdown, parsing de diagramas Mermaid, consistencia de esquemas y lógica de negocio:

```bash
node tests/run.js
```

---

## 📄 Licencia

Este proyecto está licenciado bajo los términos de la **GNU General Public License v3.0 or later (GPL-3.0-or-later)**.
Consulta el archivo [LICENSE](LICENSE) para más detalles.
