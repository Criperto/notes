#!/usr/bin/env bash
# packaging/appimage/build-appimage.sh — Generador automatizado de AppImage para Notas
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${REPO_DIR}/packaging/appimage/build"
APP_DIR="${BUILD_DIR}/AppDir"
OUTPUT_DIR="${REPO_DIR}/packaging/appimage/out"

echo "==> Iniciando construcción de AppImage de Notas..."

mkdir -p "${BUILD_DIR}"
mkdir -p "${OUTPUT_DIR}"

# 1. Compilar binario de release si no existe o está desactualizado
echo "==> Compilando binario de release con Cargo..."
cd "${REPO_DIR}"
cargo build --release

# 2. Preparar AppDir limpio
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}"

echo "==> Instalando estructura de sistema en AppDir..."
PREFIX="/usr" DESTDIR="${APP_DIR}" bash "${REPO_DIR}/scripts/install-system.sh"

# 3. Enlaces estándar en la raíz de AppDir (Desktop Entry, Icono y .DirIcon)
cd "${APP_DIR}"
ln -sf "usr/share/applications/dev.criperto.Notas.desktop" "dev.criperto.Notas.desktop"
ln -sf "usr/share/icons/hicolor/scalable/apps/dev.criperto.Notas.svg" "dev.criperto.Notas.svg"
ln -sf "dev.criperto.Notas.svg" ".DirIcon"

# 4. Crear launcher AppRun
cat << 'EOF' > "${APP_DIR}/AppRun"
#!/bin/sh
set -e

SELF=$(readlink -f "$0")
HERE=${SELF%/*}

export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${HERE}/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"
export XDG_DATA_DIRS="${HERE}/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export QT_PLUGIN_PATH="${HERE}/usr/lib/qt6/plugins:${HERE}/usr/lib/x86_64-linux-gnu/qt6/plugins:${QT_PLUGIN_PATH}"
export QML2_IMPORT_PATH="${HERE}/usr/lib/qt6/qml:${HERE}/usr/lib/x86_64-linux-gnu/qt6/qml:${QML2_IMPORT_PATH}"

exec "${HERE}/usr/bin/notas" "$@"
EOF
chmod +x "${APP_DIR}/AppRun"

# 5. Empaquetar con appimagetool si está disponible
APPIMAGETOOL=""
if command -v appimagetool &>/dev/null; then
    APPIMAGETOOL="appimagetool"
elif [[ -f "${BUILD_DIR}/appimagetool-x86_64.AppImage" ]]; then
    APPIMAGETOOL="${BUILD_DIR}/appimagetool-x86_64.AppImage"
else
    echo "==> Descargando appimagetool..."
    curl -sL "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage" -o "${BUILD_DIR}/appimagetool-x86_64.AppImage" || true
    if [[ -f "${BUILD_DIR}/appimagetool-x86_64.AppImage" ]]; then
        chmod +x "${BUILD_DIR}/appimagetool-x86_64.AppImage"
        APPIMAGETOOL="${BUILD_DIR}/appimagetool-x86_64.AppImage"
    fi
fi

if [[ -n "${APPIMAGETOOL}" && -x "${APPIMAGETOOL}" ]]; then
    VERSION="$(grep -E '^version\s*=' "${REPO_DIR}/Cargo.toml" | head -n1 | sed -E 's/^version\s*=\s*"([^"]+)".*/\1/')"
    OUTPUT_FILE="${OUTPUT_DIR}/Notas-${VERSION}-x86_64.AppImage"
    echo "==> Generando ${OUTPUT_FILE}..."
    ARCH=x86_64 "${APPIMAGETOOL}" --appimage-extract-and-run "${APP_DIR}" "${OUTPUT_FILE}"
    echo "✓ AppImage generado con éxito en ${OUTPUT_FILE}"
else
    echo "ℹ Nota: appimagetool no disponible para empaquetado final local. AppDir preparado en ${APP_DIR}."
fi
