#!/usr/bin/env bash
# scripts/install-system.sh — Instalación a nivel de sistema para empaquetado (AUR, Flatpak, deb, rpm)
# Respeta variables estándar PREFIX y DESTDIR.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PREFIX="${PREFIX:-/usr}"
DESTDIR="${DESTDIR:-}"

BIN_DIR="${DESTDIR}${PREFIX}/bin"
SHARE_DIR="${DESTDIR}${PREFIX}/share"
APPS_DIR="${SHARE_DIR}/applications"
ICONS_DIR="${SHARE_DIR}/icons/hicolor/scalable/apps"
METAINFO_DIR="${SHARE_DIR}/metainfo"
NOTAS_DATA_DIR="${SHARE_DIR}/notas"

echo "==> Instalando dev.criperto.Notas en ${DESTDIR}${PREFIX}..."

# 1. Localizar binario compilado
BIN_SRC=""
if [[ -f "${SCRIPT_DIR}/target/release/criperto-notes" ]]; then
    BIN_SRC="${SCRIPT_DIR}/target/release/criperto-notes"
elif [[ -f "${SCRIPT_DIR}/target/release/notas" ]]; then
    BIN_SRC="${SCRIPT_DIR}/target/release/notas"
elif [[ -f "${SCRIPT_DIR}/target/debug/criperto-notes" ]]; then
    BIN_SRC="${SCRIPT_DIR}/target/debug/criperto-notes"
elif [[ -f "${SCRIPT_DIR}/target/debug/notas" ]]; then
    BIN_SRC="${SCRIPT_DIR}/target/debug/notas"
else
    echo "❌ Error: No se encontró el binario compilado en ${SCRIPT_DIR}/target/release." >&2
    echo "   Por favor ejecuta 'cargo build --release' antes de instalar." >&2
    exit 1
fi

# 2. Instalar binario principal y symlink
install -d "${BIN_DIR}"
install -m 755 "${BIN_SRC}" "${BIN_DIR}/notas"
ln -sf "notas" "${BIN_DIR}/criperto-notes"
ln -sf "notas" "${BIN_DIR}/criperto.notes"
echo "✓ Binarios instalados en ${BIN_DIR}/notas"

# 3. Acceso directo de escritorio (.desktop)
install -d "${APPS_DIR}"
install -m 644 "${SCRIPT_DIR}/assets/dev.criperto.Notas.desktop" "${APPS_DIR}/dev.criperto.Notas.desktop"
echo "✓ Acceso directo instalado en ${APPS_DIR}/dev.criperto.Notas.desktop"

# 4. Icono vectorial SVG
install -d "${ICONS_DIR}"
install -m 644 "${SCRIPT_DIR}/assets/icons/dev.criperto.Notas.svg" "${ICONS_DIR}/dev.criperto.Notas.svg"
echo "✓ Icono instalado en ${ICONS_DIR}/dev.criperto.Notas.svg"

# 5. Metainfo AppStream
install -d "${METAINFO_DIR}"
install -m 644 "${SCRIPT_DIR}/data/dev.criperto.Notas.metainfo.xml" "${METAINFO_DIR}/dev.criperto.Notas.metainfo.xml"
echo "✓ Metainfo instalada en ${METAINFO_DIR}/dev.criperto.Notas.metainfo.xml"

# 6. Scripts y recursos de datos compartidos
install -d "${NOTAS_DATA_DIR}/scripts"
if [[ -f "${SCRIPT_DIR}/scripts/doc-to-md.py" ]]; then
    install -m 755 "${SCRIPT_DIR}/scripts/doc-to-md.py" "${NOTAS_DATA_DIR}/scripts/doc-to-md.py"
fi
if [[ -f "${SCRIPT_DIR}/scripts/docx-to-md.py" ]]; then
    install -m 755 "${SCRIPT_DIR}/scripts/docx-to-md.py" "${NOTAS_DATA_DIR}/scripts/docx-to-md.py"
fi
if [[ -f "${SCRIPT_DIR}/assets/spellcheck/catalog.json" ]]; then
    install -m 644 "${SCRIPT_DIR}/assets/spellcheck/catalog.json" "${NOTAS_DATA_DIR}/catalog.json"
fi
echo "✓ Recursos compartidos instalados en ${NOTAS_DATA_DIR}"

# 7. Si no estamos en un entorno empaquetado (DESTDIR vacío), actualizar caches si existen herramientas
if [[ -z "${DESTDIR}" ]]; then
    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "${APPS_DIR}" 2>/dev/null || true
    fi
    if command -v gtk-update-icon-cache &>/dev/null; then
        gtk-update-icon-cache -q -t -f "${SHARE_DIR}/icons/hicolor" 2>/dev/null || true
    fi
fi

echo "==> ¡Instalación en ${DESTDIR}${PREFIX} completada exitosamente!"
