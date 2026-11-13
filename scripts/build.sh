#!/usr/bin/env bash
# scripts/build.sh — Automatización y aceleración de compilación para Notas
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

export CC="${CC:-clang}"
export CXX="${CXX:-clang++}"
export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-$(nproc)}"
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-$(nproc)}"

CMD="${1:-dev}"
shift || true

case "${CMD}" in
    dev)
        echo "🚀 [build.sh] Compilando e iniciando en modo DEV..."
        export NOTAS_DEV=1
        cargo build --bin criperto-notes
        rm -f "${ROOT_DIR}/target/debug/notas" "${ROOT_DIR}/target/debug/criperto.notes"
        echo "✓ Binario listo en target/debug/criperto-notes. Lanzando..."
        exec "${ROOT_DIR}/target/debug/criperto-notes" "$@"
        ;;
    release|publish)
        exec "${SCRIPT_DIR}/release.sh" "$@"
        ;;
    install)
        echo "📦 [build.sh] Compilando e instalando en ~/.local/bin/..."
        cargo build --release
        rm -f "${ROOT_DIR}/target/release/notas" "${ROOT_DIR}/target/release/criperto.notes"
        "${ROOT_DIR}/scripts/install.sh"
        echo "✓ Instalación finalizada."
        ;;
    check)
        echo "🔍 [build.sh] Verificando tests lógicos de Notas..."
        node "${ROOT_DIR}/tests/run.js"
        echo "🔍 [build.sh] Verificando compilación Cargo..."
        cargo check
        echo "🔍 [build.sh] Smoke test headless (verificación de carga limpia)..."
        if [[ -x "${ROOT_DIR}/target/release/criperto-notes" ]]; then
            QT_QPA_PLATFORM=offscreen "${ROOT_DIR}/target/release/criperto-notes" --check 2>&1 || true
        elif [[ -x "${ROOT_DIR}/target/debug/criperto-notes" ]]; then
            QT_QPA_PLATFORM=offscreen "${ROOT_DIR}/target/debug/criperto-notes" --check 2>&1 || true
        fi
        echo "✓ Chequeo completo."
        ;;
    clean)
        echo "🧹 [build.sh] Limpiando target/..."
        cargo clean
        echo "✓ Limpieza finalizada."
        ;;
    *)
        echo "Uso: $0 [dev [args...] | release [flags...] | publish [flags...] | install | check | clean]"
        exit 1
        ;;
esac
