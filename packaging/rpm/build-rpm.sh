#!/usr/bin/env bash
# packaging/rpm/build-rpm.sh — Generador automatizado de paquetes .rpm para Fedora/RHEL
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="$(grep -E '^version\s*=' "${REPO_DIR}/Cargo.toml" | head -n1 | sed -E 's/^version\s*=\s*"([^"]+)".*/\1/')"
OUTPUT_DIR="${REPO_DIR}/dist"
RPM_ROOT="${REPO_DIR}/packaging/rpm/build"

mkdir -p "${OUTPUT_DIR}"
rm -rf "${RPM_ROOT}"
mkdir -p "${RPM_ROOT}"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

cp "${REPO_DIR}/packaging/rpm/notas.spec" "${RPM_ROOT}/SPECS/notas.spec"
sed -i -E "s/^Version:\s*.*/Version:        ${VERSION}/" "${RPM_ROOT}/SPECS/notas.spec"

if command -v rpmbuild &>/dev/null; then
    echo "==> Generando paquete RPM para Fedora con rpmbuild..."
    rpmbuild -bb \
        --define "_topdir ${RPM_ROOT}" \
        --define "_sourcedir ${REPO_DIR}" \
        --define "buildroot ${RPM_ROOT}/BUILDROOT" \
        "${RPM_ROOT}/SPECS/notas.spec"

    if ls "${RPM_ROOT}/RPMS"/*/*.rpm 1>/dev/null 2>&1; then
        cp "${RPM_ROOT}/RPMS"/*/*.rpm "${OUTPUT_DIR}/"
        (cd "${OUTPUT_DIR}" && for f in *.rpm; do sha256sum "$f" > "${f}.sha256"; done)
        echo "✓ Paquete RPM generado en ${OUTPUT_DIR}/"
    fi
else
    echo "ℹ Nota: rpmbuild no disponible en este sistema host. Se compilará en GitHub Actions."
fi

rm -rf "${RPM_ROOT}"
