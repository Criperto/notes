#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Instalando Notas (dev.criperto.Notas)..."

# 1. Asegurar directorios de destino
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.local/share/applications"
mkdir -p "$HOME/.local/share/icons/hicolor/scalable/apps"
mkdir -p "$HOME/.local/share/notas/scripts"
mkdir -p "$HOME/.local/share/notas/dictionaries"

# Recursos compartidos (scripts de conversión y catálogo de diccionarios)
ln -sf "$SCRIPT_DIR/scripts/doc-to-md.py" "$HOME/.local/share/notas/scripts/doc-to-md.py"
ln -sf "$SCRIPT_DIR/scripts/docx-to-md.py" "$HOME/.local/share/notas/scripts/docx-to-md.py"
if [[ -f "$SCRIPT_DIR/assets/spellcheck/catalog.json" ]]; then
    ln -sf "$SCRIPT_DIR/assets/spellcheck/catalog.json" "$HOME/.local/share/notas/catalog.json"
fi
if [[ ! -f "$HOME/.local/share/notas/dictionaries/.dicts_stamp" ]] && [[ -d "$HOME/.config/quickshell/languages/spellcheck/dicts" ]]; then
    cp -n "$HOME/.config/quickshell/languages/spellcheck/dicts/"*.{aff,dic} "$HOME/.local/share/notas/dictionaries/" 2>/dev/null || true
    date +%s > "$HOME/.local/share/notas/dictionaries/.dicts_stamp"
fi

# 2. Binario
BIN_SRC=""
if [[ -f "$SCRIPT_DIR/target/release/notas" ]]; then
    BIN_SRC="$SCRIPT_DIR/target/release/notas"
elif [[ -f "$SCRIPT_DIR/target/debug/notas" ]]; then
    BIN_SRC="$SCRIPT_DIR/target/debug/notas"
else
    echo "Compilando binario de release..."
    cd "$SCRIPT_DIR" && cargo build --release
    BIN_SRC="$SCRIPT_DIR/target/release/notas"
fi

ln -sf "$BIN_SRC" "$HOME/.local/bin/notas"
echo "✓ Binario enlazado en $HOME/.local/bin/notas"

# 3. Icono
ln -sf "$SCRIPT_DIR/assets/icons/dev.criperto.Notas.svg" "$HOME/.local/share/icons/hicolor/scalable/apps/dev.criperto.Notas.svg"
echo "✓ Icono enlazado en $HOME/.local/share/icons/hicolor/scalable/apps/dev.criperto.Notas.svg"

# 4. Desktop entry
ln -sf "$SCRIPT_DIR/assets/dev.criperto.Notas.desktop" "$HOME/.local/share/applications/dev.criperto.Notas.desktop"
echo "✓ Acceso directo enlazado en $HOME/.local/share/applications/dev.criperto.Notas.desktop"

# 5. Actualizar bases de datos del sistema si existen
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi
if command -v gtk-update-icon-cache &>/dev/null; then
    gtk-update-icon-cache -q -t -f "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
fi

echo "==> ¡Instalación completada exitosamente! Puedes ejecutar 'notas' desde cualquier terminal o lanzador."
