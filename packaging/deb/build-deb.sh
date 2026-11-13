#!/usr/bin/env bash
# packaging/deb/build-deb.sh — Generador automatizado de paquetes .deb para Debian/Ubuntu
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="$(grep -E '^version\s*=' "${REPO_DIR}/Cargo.toml" | head -n1 | sed -E 's/^version\s*=\s*"([^"]+)".*/\1/')"
OUTPUT_DIR="${REPO_DIR}/dist"
STAGE_DIR="${REPO_DIR}/packaging/deb/stage"

mkdir -p "${OUTPUT_DIR}"
rm -rf "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}/DEBIAN"

echo "==> Preparando estructura de paquete Debian para Notas v${VERSION}..."
PREFIX="/usr" DESTDIR="${STAGE_DIR}" bash "${REPO_DIR}/scripts/install.sh" --system >/dev/null 2>&1

INSTALLED_SIZE=$(du -sk "${STAGE_DIR}" | cut -f1)

cat << EOF > "${STAGE_DIR}/DEBIAN/control"
Package: criperto-notes
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Tomas (Criperto) <dev@criperto.com>
Depends: libc6, libgcc-s1, libstdc++6, qt6-base-dev | libqt6core6, libqt6gui6, libqt6qml6, libqt6quick6, libqt6svg6
Installed-Size: ${INSTALLED_SIZE}
Homepage: https://github.com/Criperto/notes
Description: Editor moderno y nativo de notas en Markdown para Wayland
 Aplicación nativa de notas en Markdown con editor de bloques y diagramas Mermaid.
 Diseñado e integrado especialmente para entornos Linux Wayland.
EOF

if command -v dpkg-deb &>/dev/null; then
    dpkg-deb --build --root-owner-group "${STAGE_DIR}" "${OUTPUT_DIR}/criperto-notes_${VERSION}_amd64.deb"
    (cd "${OUTPUT_DIR}" && sha256sum "criperto-notes_${VERSION}_amd64.deb" > "criperto-notes_${VERSION}_amd64.deb.sha256")
    echo "✓ Paquete Debian generado en ${OUTPUT_DIR}/criperto-notes_${VERSION}_amd64.deb"
else
    echo "ℹ Nota: dpkg-deb no disponible en este sistema host. Se compilará en GitHub Actions."
fi

rm -rf "${STAGE_DIR}"
