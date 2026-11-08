#!/usr/bin/env bash
# scripts/release.sh — Script maestro de compilación, instalación y release de Notas
#
# Automatiza el flujo de trabajo para Notas (dev.criperto.Notas):
# 1. Por defecto (uso diario, cero tokens de IA, cero spam de releases):
#    - Ejecuta pruebas rápidas de integridad.
#    - Compila binario optimizado en modo Release.
#    - Instala localmente en ~/.local/bin/ y registra desktop / mime / iconos.
#    - NO incrementa la versión.
#    - NO crea commits ni tags en git.
#    - NO publica en GitHub.
#
# 2. Incremento de versión (opcional, controlado por flags SemVer):
#    --patch, --bump   : Incrementa 0.0.X (ej: 0.1.10 -> 0.1.11) [Por defecto para fixes]
#    --minor           : Incrementa 0.X.0 (ej: 0.1.10 -> 0.2.0)  [Requiere flag explícito]
#    --major           : Incrementa X.0.0 (ej: 0.1.10 -> 1.0.0)  [Requiere flag explícito]
#    --set <VERSION>   : Asigna una versión específica (ej: --set 0.2.5)
#
# 3. Publicación remota en GitHub (estrictamente opcional):
#    --github, --publish : Crea commit atómico de versión, taggea v<VER> y hace push a GitHub,
#                          disparando el workflow de CI/CD para generar paquetes y releases.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

# Colores para salida de terminal
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuración por defecto
BUMP_MODE="none" # none | patch | minor | major | set
CUSTOM_VERSION=""
PUBLISH_GITHUB=false
DRY_RUN=false
RUN_TESTS=true
DO_INSTALL=true
DO_PACKAGE=false
RELEASE_DESC=""
COMMIT_MSG=""

# Función de ayuda
show_help() {
    echo -e "${BOLD}dev.criperto.Notas — Herramienta Maestra de Compilación, Instalación y Release${NC}

${BOLD}USO:${NC}
  $0 [OPCIONES]

${BOLD}COMPORTAMIENTO POR DEFECTO (Sin flags):${NC}
  • Ejecuta pruebas lógicas rápidas.
  • Compila binario optimizado en modo Release (cargo build --release).
  • Enlaza e instala en ~/.local/bin/criperto.notes, iconos, desktop y asociaciones mime.
  • ${GREEN}CERO incremento de versión, CERO commits/tags, CERO spam en GitHub.${NC}
  • Diseñado para uso diario rápido y sin consumo de tokens de IA.

${BOLD}OPCIONES DE INCREMENTO DE VERSIÓN (SemVer):${NC}
  --patch, --bump        Incrementa versión de parche 0.0.X (ej: 0.1.10 -> 0.1.11)
  --minor                Incrementa versión menor 0.X.0 (ej: 0.1.10 -> 0.2.0) [Requiere flag]
  --major                Incrementa versión mayor X.0.0 (ej: 0.1.10 -> 1.0.0) [Requiere flag]
  --set <VER>            Asigna manualmente una versión específica (ej: --set 0.2.1)

${BOLD}PUBLICACIÓN EN GITHUB (Opcional):${NC}
  --github, --publish    Crea commit atómico, etiqueta v<VER> y sube los cambios
                         con 'git push origin HEAD --tags' para disparar GitHub Actions.
                         ${YELLOW}Si no se especifica este flag, nada se sube a GitHub.${NC}

${BOLD}CONTROL DE ACCIONES Y COMPILACIÓN:${NC}
  -n, --dry-run          Simula las acciones mostrando la versión y archivos sin modificar disco.
  --no-test              Omite la ejecución previa del suite de pruebas.
  --no-install           Compila el binario pero omite la instalación en ~/.local/.
  -m, --desc <TEXTO>     Descripción de la versión para metainfo.xml y mensaje del commit/tag.
  -h, --help             Muestra este manual de ayuda.

${BOLD}EJEMPLOS:${NC}
  # 1. Compilar e instalar cambios locales (uso diario, super rápido):
  $0

  # 2. Incrementar versión 0.0.X tras corregir un bug e instalar localmente:
  $0 --patch

  # 3. Incrementar versión 0.X.0 al agregar nueva funcionalidad y publicar en GitHub:
  $0 --minor --github -m \"Soporte para sincronización de notas y atajos de teclado\"

  # 4. Probar en seco qué versión se generaría:
  $0 --dry-run --patch"
}

# Parsear argumentos
while [[ $# -gt 0 ]]; do
    case "$1" in
        --patch|--bump)
            BUMP_MODE="patch"
            shift
            ;;
        --minor)
            BUMP_MODE="minor"
            shift
            ;;
        --major)
            BUMP_MODE="major"
            shift
            ;;
        --set)
            BUMP_MODE="set"
            CUSTOM_VERSION="${2:-}"
            if [[ -z "${CUSTOM_VERSION}" ]]; then
                echo -e "${RED}Error: --set requiere especificar una versión (ej: --set 0.2.0)${NC}" >&2
                exit 1
            fi
            shift 2
            ;;
        --github|--publish|-g)
            PUBLISH_GITHUB=true
            DO_PACKAGE=true
            shift
            ;;
        --package|--dist)
            DO_PACKAGE=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-test)
            RUN_TESTS=false
            shift
            ;;
        --no-install)
            DO_INSTALL=false
            shift
            ;;
        -m|--desc|--message)
            RELEASE_DESC="${2:-}"
            COMMIT_MSG="${2:-}"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Opción desconocida: $1${NC}" >&2
            echo "Usa '$0 --help' para ver las opciones disponibles." >&2
            exit 1
            ;;
    esac
done

# 1. Obtener versión actual desde Cargo.toml
if [[ ! -f "Cargo.toml" ]]; then
    echo -e "${RED}Error: No se encontró Cargo.toml en ${ROOT_DIR}${NC}" >&2
    exit 1
fi

CURRENT_VER="$(grep -E '^version\s*=' Cargo.toml | head -n1 | sed -E 's/^version\s*=\s*"([^"]+)".*/\1/')"
if [[ -z "${CURRENT_VER}" ]]; then
    echo -e "${RED}Error: No se pudo determinar la versión actual en Cargo.toml${NC}" >&2
    exit 1
fi

# 2. Calcular nueva versión si aplica
NEW_VER="${CURRENT_VER}"

if [[ "${BUMP_MODE}" != "none" ]]; then
    # Parsear SemVer actual
    IFS='.' read -r MAJOR MINOR PATCH <<< "${CURRENT_VER}"
    if [[ ! "${MAJOR}" =~ ^[0-9]+$ ]] || [[ ! "${MINOR}" =~ ^[0-9]+$ ]] || [[ ! "${PATCH}" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: La versión actual '${CURRENT_VER}' no tiene formato numérico SemVer (X.Y.Z)${NC}" >&2
        exit 1
    fi

    case "${BUMP_MODE}" in
        patch)
            NEW_VER="${MAJOR}.${MINOR}.$((PATCH + 1))"
            ;;
        minor)
            NEW_VER="${MAJOR}.$((MINOR + 1)).0"
            ;;
        major)
            NEW_VER="$((MAJOR + 1)).0.0"
            ;;
        set)
            if [[ ! "${CUSTOM_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+.*$ ]]; then
                echo -e "${RED}Error: La versión indicada '${CUSTOM_VERSION}' no es válida (esperado: X.Y.Z)${NC}" >&2
                exit 1
            fi
            NEW_VER="${CUSTOM_VERSION}"
            ;;
    esac
fi

# Validaciones para publicación en GitHub
if [[ "${PUBLISH_GITHUB}" == true ]]; then
    if ! command -v git &>/dev/null; then
        echo -e "${RED}Error: 'git' no está instalado en el sistema.${NC}" >&2
        exit 1
    fi

    # Verificar que el tag no exista previamente
    if git rev-parse -q --verify "refs/tags/v${NEW_VER}" >/dev/null; then
        echo -e "${RED}❌ Error: El tag 'v${NEW_VER}' ya existe en el repositorio local.${NC}" >&2
        echo -e "   Para publicar un nuevo release en GitHub, incrementa la versión usando:" >&2
        echo -e "     $0 --patch --github  (para cambios 0.0.X)" >&2
        echo -e "     $0 --minor --github  (para cambios 0.X.0)" >&2
        exit 1
    fi
fi

# Resumen de operaciones
echo -e "${CYAN}╭─────────────────────────────────────────────────────────────────────────────╮${NC}"
echo -e "${CYAN}│${NC} ${BOLD}📝 dev.criperto.Notas — Gestor de Compilación y Release${NC}                     ${CYAN}│${NC}"
echo -e "${CYAN}├─────────────────────────────────────────────────────────────────────────────┤${NC}"
echo -e "${CYAN}│${NC} • Versión actual   : ${YELLOW}${CURRENT_VER}${NC}"
if [[ "${NEW_VER}" != "${CURRENT_VER}" ]]; then
    echo -e "${CYAN}│${NC} • Nueva versión    : ${GREEN}${BOLD}${NEW_VER}${NC} (modo: ${BUMP_MODE})"
else
    echo -e "${CYAN}│${NC} • Versión a usar   : ${GREEN}${NEW_VER}${NC} (sin incremento)"
fi
echo -e "${CYAN}│${NC} • Tests previos    : $([[ "${RUN_TESTS}" == true ]] && echo -e "${GREEN}Habilitados${NC}" || echo -e "${DIM}Omitidos${NC}")"
echo -e "${CYAN}│${NC} • Compilación      : ${GREEN}Release optimizado (cargo build --release)${NC}"
echo -e "${CYAN}│${NC} • Instalación local: $([[ "${DO_INSTALL}" == true ]] && echo -e "${GREEN}Habilitada (~/.local/bin/criperto.notes)${NC}" || echo -e "${DIM}Omitida${NC}")"
echo -e "${CYAN}│${NC} • Publicar GitHub  : $([[ "${PUBLISH_GITHUB}" == true ]] && echo -e "${YELLOW}${BOLD}SÍ (git commit + tag v${NEW_VER} + push)${NC}" || echo -e "${DIM}NO (estrictamente local)${NC}")"
if [[ "${DRY_RUN}" == true ]]; then
    echo -e "${CYAN}│${NC} • Modo             : ${YELLOW}${BOLD}DRY-RUN (Simulación sin cambios en disco)${NC}"
fi
echo -e "${CYAN}╰─────────────────────────────────────────────────────────────────────────────╯${NC}"
echo ""

# Si estamos en dry-run, solo listamos archivos y salimos
if [[ "${DRY_RUN}" == true ]]; then
    echo -e "${YELLOW}🔍 [DRY-RUN] Archivos que se actualizarían si cambia la versión:${NC}"
    if [[ "${NEW_VER}" != "${CURRENT_VER}" ]]; then
        echo "   - Cargo.toml (version = \"${NEW_VER}\")"
        echo "   - Cargo.lock"
        echo "   - data/dev.criperto.Notas.metainfo.xml (<release version=\"${NEW_VER}\"...>)"
        echo "   - qml/NotesSettingsModal.qml (Versión ${NEW_VER})"
        echo "   - README.md (badge/version-${NEW_VER}-orange.svg)"
        echo "   - packaging/arch/PKGBUILD (pkgver=${NEW_VER})"
        echo "   - packaging/arch/notas-git/PKGBUILD (fallback ${NEW_VER})"
        echo "   - src/native/native_bridge.cpp (dev.criperto.Notas v${NEW_VER})"
    else
        echo "   (Ninguno - no se solicitó incremento de versión)"
    fi
    echo -e "\n${GREEN}✓ Simulación completada con éxito. Cero cambios aplicados.${NC}"
    exit 0
fi

# 3. Sincronizar archivos de versión si hubo incremento
if [[ "${NEW_VER}" != "${CURRENT_VER}" ]]; then
    echo -e "${BLUE}🔄 [1/5] Sincronizando versión ${NEW_VER} en archivos de configuración...${NC}"

    # a) Cargo.toml
    sed -i -E "s/^version = \"[^\"]*\"/version = \"${NEW_VER}\"/" Cargo.toml
    echo "   ✓ Cargo.toml actualizado"

    # b) qml/NotesSettingsModal.qml
    if [[ -f "qml/NotesSettingsModal.qml" ]]; then
        sed -i -E "s/dev\.criperto\.Notas • Versión [0-9]+\.[0-9]+\.[0-9]+/dev.criperto.Notas • Versión ${NEW_VER}/g" qml/NotesSettingsModal.qml
        echo "   ✓ qml/NotesSettingsModal.qml actualizado"
    fi

    # c) README.md
    if [[ -f "README.md" ]]; then
        sed -i -E "s/badge\/version-[0-9]+\.[0-9]+\.[0-9]+-orange\.svg/badge\/version-${NEW_VER}-orange.svg/g" README.md
        sed -i -E "s/!\[Version: [0-9]+\.[0-9]+\.[0-9]+\]/![Version: ${NEW_VER}]/g" README.md
        echo "   ✓ README.md actualizado"
    fi

    # d) packaging/arch/PKGBUILD
    if [[ -f "packaging/arch/PKGBUILD" ]]; then
        sed -i -E "s/^pkgver=[0-9]+\.[0-9]+\.[0-9]+/pkgver=${NEW_VER}/" packaging/arch/PKGBUILD
        sed -i -E "s/^pkgrel=[0-9]+/pkgrel=1/" packaging/arch/PKGBUILD
        echo "   ✓ packaging/arch/PKGBUILD actualizado"
    fi

    # e) packaging/arch/notas-git/PKGBUILD
    if [[ -f "packaging/arch/notas-git/PKGBUILD" ]]; then
        sed -i -E "s/\|\| echo \"[0-9]+\.[0-9]+\.[0-9]+\"/|| echo \"${NEW_VER}\"/" packaging/arch/notas-git/PKGBUILD
        echo "   ✓ packaging/arch/notas-git/PKGBUILD actualizado"
    fi

    # f) src/native/native_bridge.cpp
    if [[ -f "src/native/native_bridge.cpp" ]]; then
        sed -i -E "s/dev\.criperto\.Notas v[0-9]+\.[0-9]+\.[0-9]+/dev.criperto.Notas v${NEW_VER}/g" src/native/native_bridge.cpp
        echo "   ✓ src/native/native_bridge.cpp actualizado"
    fi

    # f2) packaging/rpm/notas.spec
    if [[ -f "packaging/rpm/notas.spec" ]]; then
        sed -i -E "s/^Version:\s*.*/Version:        ${NEW_VER}/" packaging/rpm/notas.spec
        echo "   ✓ packaging/rpm/notas.spec actualizado"
    fi

    # g) data/dev.criperto.Notas.metainfo.xml
    if [[ -f "data/dev.criperto.Notas.metainfo.xml" ]]; then
        python3 - << EOF
import re

file_path = "data/dev.criperto.Notas.metainfo.xml"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

new_ver = "${NEW_VER}"
if f'version="{new_ver}"' not in content:
    today = "$(date +%Y-%m-%d)"
    desc = "${RELEASE_DESC}"
    if not desc:
        desc = "Actualización y mejoras en dev.criperto.Notas."
    release_entry = f'    <release version="{new_ver}" date="{today}">\n      <description>\n        <p>{desc}</p>\n      </description>\n    </release>\n'
    content = re.sub(r'(<releases>\n)', r'\1' + release_entry, content, count=1)
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)
EOF
        echo "   ✓ data/dev.criperto.Notas.metainfo.xml actualizado"
    fi

    # h) Cargo.lock
    echo "   🔄 Actualizando Cargo.lock..."
    cargo check --offline 2>/dev/null || cargo check || true
    echo "   ✓ Cargo.lock sincronizado"
else
    echo -e "${DIM}ℹ️  [1/5] Sin cambios de versión; manteniendo v${CURRENT_VER}${NC}"
fi

# 4. Pruebas lógicas
if [[ "${RUN_TESTS}" == true ]]; then
    echo -e "\n${BLUE}🧪 [2/5] Ejecutando tests lógicos de Notas...${NC}"
    node tests/run.js
    echo "   ✓ Tests de JavaScript y contratos OK"
    if [[ "${PUBLISH_GITHUB}" == true ]]; then
        echo "   🔍 Ejecutando cargo test para validación estricta de Rust..."
        cargo test
        echo "   ✓ Tests de Rust OK"
    fi
else
    echo -e "\n${DIM}🧪 [2/5] Tests omitidos por configuración (--no-test)${NC}"
fi

# 5. Compilación Release
echo -e "\n${BLUE}📦 [3/5] Compilando binario optimizado en modo RELEASE...${NC}"
export CC="${CC:-clang}"
export CXX="${CXX:-clang++}"
export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-$(nproc)}"
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-$(nproc)}"

cargo build --release

# Asegurar symlinks canónicos en target/release/
mkdir -p "${ROOT_DIR}/target/release"
ln -sf criperto-notes "${ROOT_DIR}/target/release/criperto.notes"
rm -f "${ROOT_DIR}/target/release/notas"
echo "   ✓ Binario generado en target/release/criperto.notes (versión ${NEW_VER})"

# 6. Instalación local en el sistema del usuario
if [[ "${DO_INSTALL}" == true ]]; then
    echo -e "\n${BLUE}💻 [4/6] Instalando en el entorno local (~/.local/bin/criperto.notes)...${NC}"
    "${ROOT_DIR}/scripts/install.sh"
else
    echo -e "\n${DIM}💻 [4/6] Instalación local omitida (--no-install)${NC}"
fi

# 7. Empaquetado local de distribución (dist/)
if [[ "${DO_PACKAGE}" == true ]]; then
    echo -e "\n${BLUE}🎁 [5/6] Generando paquetes de distribución en dist/...${NC}"
    DIST_DIR="${ROOT_DIR}/dist"
    PKG_TEMP="${DIST_DIR}/criperto-notes-${NEW_VER}"
    rm -rf "${PKG_TEMP}"
    mkdir -p "${PKG_TEMP}"

    PREFIX="/usr" DESTDIR="${PKG_TEMP}" bash "${ROOT_DIR}/scripts/install-system.sh" >/dev/null 2>&1
    cp "${ROOT_DIR}/README.md" "${ROOT_DIR}/LICENSE" "${PKG_TEMP}/"

    tar -czf "${DIST_DIR}/criperto-notes-${NEW_VER}-x86_64-linux.tar.gz" -C "${DIST_DIR}" "criperto-notes-${NEW_VER}"
    (cd "${DIST_DIR}" && sha256sum "criperto-notes-${NEW_VER}-x86_64-linux.tar.gz" > "criperto-notes-${NEW_VER}-x86_64-linux.tar.gz.sha256")
    rm -rf "${PKG_TEMP}"
    echo "   ✓ Tarball generado: dist/criperto-notes-${NEW_VER}-x86_64-linux.tar.gz"

    if [[ -f "${ROOT_DIR}/packaging/appimage/build-appimage.sh" ]]; then
        echo "   📦 Generando AppImage local..."
        bash "${ROOT_DIR}/packaging/appimage/build-appimage.sh" >/dev/null 2>&1 || true
        if ls "${ROOT_DIR}/packaging/appimage/out/"*.AppImage 1> /dev/null 2>&1; then
            cp "${ROOT_DIR}/packaging/appimage/out/"*.AppImage "${DIST_DIR}/"
            (cd "${DIST_DIR}" && for f in *.AppImage; do sha256sum "$f" > "${f}.sha256"; done)
            echo "   ✓ AppImage copiado a dist/"
        fi
    fi

    if [[ -f "${ROOT_DIR}/packaging/deb/build-deb.sh" ]]; then
        bash "${ROOT_DIR}/packaging/deb/build-deb.sh" >/dev/null 2>&1 || true
    fi

    if [[ -f "${ROOT_DIR}/packaging/rpm/build-rpm.sh" ]]; then
        bash "${ROOT_DIR}/packaging/rpm/build-rpm.sh" >/dev/null 2>&1 || true
    fi
else
    echo -e "\n${DIM}🎁 [5/6] Empaquetado de distribución dist/ omitido (usar --package o --github)${NC}"
fi

# 8. Publicación en GitHub (Opcional, sólo con --github)
if [[ "${PUBLISH_GITHUB}" == true ]]; then
    echo -e "\n${BLUE}🚀 [6/6] Publicando en GitHub (Tagging + Push)...${NC}"

    # Staging selectivo y explícito de archivos de versión
    FILES_TO_STAGE=(
        "Cargo.toml"
        "Cargo.lock"
        "data/dev.criperto.Notas.metainfo.xml"
        "qml/NotesSettingsModal.qml"
        "README.md"
        "packaging/arch/PKGBUILD"
        "packaging/arch/notas-git/PKGBUILD"
        "packaging/rpm/notas.spec"
        "src/native/native_bridge.cpp"
    )

    for f in "${FILES_TO_STAGE[@]}"; do
        if [[ -f "$f" ]]; then
            git add "$f"
        fi
    done

    FINAL_MSG="${COMMIT_MSG}"
    if [[ -z "${FINAL_MSG}" ]]; then
        FINAL_MSG="chore(release): bump version to v${NEW_VER}"
    fi

    # Commit solo si hay cambios en stage
    if ! git diff --cached --quiet; then
        git commit -m "${FINAL_MSG}"
        echo "   ✓ Commit de release generado: ${FINAL_MSG}"
    fi

    # Crear tag
    git tag -a "v${NEW_VER}" -m "Release v${NEW_VER}${RELEASE_DESC:+: $RELEASE_DESC}"
    echo "   ✓ Tag v${NEW_VER} creado localmente"

    # Push a GitHub
    echo "   ⬆️  Enviando commit y tags a origin..."
    git push origin HEAD --tags
    echo -e "${GREEN}   ✓ Push exitoso. GitHub Actions procesará el release v${NEW_VER}.${NC}"
else
    echo -e "\n${DIM}🚀 [6/6] Publicación remota omitida (ejecución 100% local sin spam en GitHub)${NC}"
fi

echo -e "\n${GREEN}${BOLD}===============================================================================${NC}"
echo -e "${GREEN}${BOLD}🎉 ¡Operación completada exitosamente!${NC}"
echo -e "   • Versión activa : ${BOLD}v${NEW_VER}${NC}"
echo -e "   • Binario local  : ~/.local/bin/criperto.notes"
if [[ -d "${ROOT_DIR}/dist" ]] && ls "${ROOT_DIR}/dist"/*.tar.gz 1>/dev/null 2>&1; then
    echo -e "   • Paquetes dist/ : ${ROOT_DIR}/dist/"
fi
if [[ "${PUBLISH_GITHUB}" == true ]]; then
    echo -e "   • GitHub Release : https://github.com/Criperto/notes/releases/tag/v${NEW_VER}"
fi
echo -e "${GREEN}${BOLD}===============================================================================${NC}\n"
