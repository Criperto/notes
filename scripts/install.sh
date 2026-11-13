#!/usr/bin/env bash
# scripts/install.sh — Instalador y desinstalador unificado para Notas (dev.criperto.Notas)
# Soporta instalación global (/usr, por defecto con sudo) o de usuario (~/.local vía --user).
# Soporta desinstalación automática (--uninstall / -u) con detección de ubicaciones.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── 1. Detección de idioma (Bilingüe ES / EN sin dependencias externas) ──────
IS_ES=false
if [[ "${LANG:-}" =~ ^es ]]; then
    IS_ES=true
fi

msg() {
    local es="$1"
    local en="$2"
    if [[ "$IS_ES" == true ]]; then
        echo -e "$es"
    else
        echo -e "$en"
    fi
}

err() {
    local es="$1"
    local en="$2"
    if [[ "$IS_ES" == true ]]; then
        echo -e "❌ Error: $es" >&2
    else
        echo -e "❌ Error: $en" >&2
    fi
}

# ── 2. Parseo de argumentos ──────────────────────────────────────────────────
MODE="system"
UNINSTALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)
            MODE="user"
            shift
            ;;
        --system)
            MODE="system"
            shift
            ;;
        -u|--uninstall)
            UNINSTALL=true
            shift
            ;;
        -h|--help)
            msg "Uso: $0 [OPCIONES]\n\nOpciones:\n  (por defecto)     Instalar a nivel global en /usr (solicita sudo si es necesario)\n  --user            Instalar localmente para el usuario actual en ~/.local\n  -u, --uninstall   Desinstalar Notas (detecta y limpia tanto /usr como ~/.local)\n  -h, --help        Mostrar esta ayuda" \
                "Usage: $0 [OPTIONS]\n\nOptions:\n  (default)         Install system-wide into /usr (prompts for sudo if needed)\n  --user            Install locally for current user into ~/.local\n  -u, --uninstall   Uninstall Notas (detects and cleans /usr and ~/.local)\n  -h, --help        Show this help message"
            exit 0
            ;;
        *)
            err "Opción desconocida: $1. Usá --help para ver las opciones." "Unknown option: $1. Use --help to view options."
            exit 1
            ;;
    esac
done

# ── 3. Modo Desinstalación ───────────────────────────────────────────────────
if [[ "$UNINSTALL" == true ]]; then
    msg "==> Iniciando desinstalación de Notas (dev.criperto.Notas)..." \
        "==> Starting uninstallation of Notas (dev.criperto.Notas)..."

    HAS_SYSTEM=false
    HAS_USER=false

    # Verificar si hay instalación a nivel de sistema (/usr)
    if [[ -f "/usr/bin/criperto.notes" || -d "/usr/share/criperto.notes" || -d "/usr/share/notas" || -f "/usr/share/applications/dev.criperto.Notas.desktop" ]]; then
        HAS_SYSTEM=true
    fi

    # Verificar si hay instalación de usuario (~/.local)
    USER_HOME="${HOME:-~}"
    if [[ -f "$USER_HOME/.local/bin/criperto.notes" || -f "$USER_HOME/.local/bin/notas" || -f "$USER_HOME/.local/bin/criperto-notes" || -d "$USER_HOME/.local/share/criperto.notes" || -d "$USER_HOME/.local/share/notas" || -f "$USER_HOME/.local/share/applications/dev.criperto.Notas.desktop" ]]; then
        HAS_USER=true
    fi

    if [[ "$HAS_SYSTEM" == false && "$HAS_USER" == false ]]; then
        msg "ℹ No se detectaron instalaciones activas de Notas en el sistema ni en ~/.local." \
            "ℹ No active installation of Notas was found in the system or ~/.local."
        exit 0
    fi

    # Si hay archivos de sistema y no somos root, re-ejecutar con sudo
    if [[ "$HAS_SYSTEM" == true && "$EUID" -ne 0 ]]; then
        msg "==> Se detectaron archivos en /usr. Solicitando permisos de administrador (sudo)..." \
            "==> System-wide files detected in /usr. Requesting administrative privileges (sudo)..."
        exec sudo -E "$0" --uninstall
    fi

    # Limpieza en /usr si somos root o se detectó instalación de sistema
    if [[ "$HAS_SYSTEM" == true ]]; then
        msg "==> Eliminando instalación del sistema en /usr..." \
            "==> Removing system-wide installation in /usr..."
        rm -f "/usr/bin/criperto.notes" "/usr/bin/notas" "/usr/bin/criperto-notes"
        rm -f "/usr/share/applications/dev.criperto.Notas.desktop"
        rm -f "/usr/share/icons/hicolor/scalable/apps/dev.criperto.Notas.svg"
        rm -f "/usr/share/metainfo/dev.criperto.Notas.metainfo.xml"
        rm -rf "/usr/share/criperto.notes" "/usr/share/notas"
        msg "✓ Archivos en /usr eliminados correctamente." \
            "✓ Files in /usr successfully removed."

        if command -v update-desktop-database &>/dev/null; then
            update-desktop-database "/usr/share/applications" 2>/dev/null || true
        fi
        if command -v gtk-update-icon-cache &>/dev/null; then
            gtk-update-icon-cache -q -t -f "/usr/share/icons/hicolor" 2>/dev/null || true
        fi
    fi

    # Limpieza en ~/.local
    # Si se corrió con sudo, intentar limpiar también el home del usuario original
    TARGET_HOME="$HOME"
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        USER_ENTRY=$(getent passwd "$SUDO_USER" || true)
        if [[ -n "$USER_ENTRY" ]]; then
            TARGET_HOME="$(echo "$USER_ENTRY" | cut -d: -f6)"
        fi
    fi

    if [[ -d "$TARGET_HOME/.local" ]]; then
        msg "==> Limpiando enlaces y archivos de usuario en $TARGET_HOME/.local..." \
            "==> Cleaning user files and links in $TARGET_HOME/.local..."
        rm -f "$TARGET_HOME/.local/bin/criperto.notes" "$TARGET_HOME/.local/bin/notas" "$TARGET_HOME/.local/bin/criperto-notes"
        rm -f "$TARGET_HOME/.local/share/applications/dev.criperto.Notas.desktop"
        rm -f "$TARGET_HOME/.local/share/icons/hicolor/scalable/apps/dev.criperto.Notas.svg"
        rm -rf "$TARGET_HOME/.local/share/criperto.notes" "$TARGET_HOME/.local/share/notas"

        # Limpiar asociaciones MIME en mimeapps.list
        MIMEAPPS="$TARGET_HOME/.config/mimeapps.list"
        if [[ -f "$MIMEAPPS" ]]; then
            sed -i '/dev\.criperto\.Notas\.desktop/d' "$MIMEAPPS" 2>/dev/null || true
        fi

        if command -v update-desktop-database &>/dev/null; then
            update-desktop-database "$TARGET_HOME/.local/share/applications" 2>/dev/null || true
        fi
        if command -v gtk-update-icon-cache &>/dev/null; then
            gtk-update-icon-cache -q -t -f "$TARGET_HOME/.local/share/icons/hicolor" 2>/dev/null || true
        fi
        msg "✓ Archivos en ~/.local eliminados correctamente." \
            "✓ Files in ~/.local successfully removed."
    fi

    msg "\n🎉 Desinstalación completada con éxito." \
        "\n🎉 Uninstallation completed successfully."
    msg "🛡️  Tus notas y documentos personales en Documentos/notes NUNCA fueron modificados ni eliminados." \
        "🛡️  Your notes and personal documents in Documents/notes were NEVER touched or removed."
    exit 0
fi

# ── 4. Modo Instalación ───────────────────────────────────────────────────────
PREFIX="${PREFIX:-/usr}"
DESTDIR="${DESTDIR:-}"

# Si es instalación de sistema (/usr) y no somos root y DESTDIR está vacío: solicitar sudo
if [[ "$MODE" == "system" && -z "${DESTDIR}" && "$EUID" -ne 0 ]]; then
    msg "==> La instalación global en /usr requiere permisos de administrador." \
        "==> System-wide installation in /usr requires administrative privileges."
    msg "    (Consejo: si preferís instalar sin contraseña sólo para tu usuario, usá: ./scripts/install.sh --user)" \
        "    (Tip: if you prefer installing without password for your user only, run: ./scripts/install.sh --user)"
    exec sudo -E "$0" --system "$@"
fi

# 1. Localizar binario compilado
BIN_SRC=""
if [[ -f "${SCRIPT_DIR}/target/release/criperto-notes" ]]; then
    BIN_SRC="${SCRIPT_DIR}/target/release/criperto-notes"
elif [[ -f "${SCRIPT_DIR}/target/release/criperto.notes" ]]; then
    BIN_SRC="${SCRIPT_DIR}/target/release/criperto.notes"
elif [[ -f "${SCRIPT_DIR}/target/release/notas" ]]; then
    BIN_SRC="${SCRIPT_DIR}/target/release/notas"
elif [[ -f "${SCRIPT_DIR}/target/debug/criperto-notes" ]]; then
    BIN_SRC="${SCRIPT_DIR}/target/debug/criperto-notes"
elif [[ -f "${SCRIPT_DIR}/target/debug/criperto.notes" ]]; then
    BIN_SRC="${SCRIPT_DIR}/target/debug/criperto.notes"
elif [[ -f "${SCRIPT_DIR}/target/debug/notas" ]]; then
    BIN_SRC="${SCRIPT_DIR}/target/debug/notas"
else
    msg "==> Compilando binario de release con Cargo..." \
        "==> Building release binary with Cargo..."
    (cd "${SCRIPT_DIR}" && cargo build --release)
    BIN_SRC="${SCRIPT_DIR}/target/release/criperto-notes"
fi

# 2. Configurar rutas de destino según el modo
if [[ "$MODE" == "user" ]]; then
    TARGET_BASE="${HOME}/.local"
    BIN_DIR="${TARGET_BASE}/bin"
    SHARE_DIR="${TARGET_BASE}/share"
    APPS_DIR="${SHARE_DIR}/applications"
    ICONS_DIR="${SHARE_DIR}/icons/hicolor/scalable/apps"
    DATA_DIR="${SHARE_DIR}/criperto.notes"

    msg "==> Instalando Notas en modo usuario (${TARGET_BASE})..." \
        "==> Installing Notas in user mode (${TARGET_BASE})..."

    mkdir -p "${BIN_DIR}" "${APPS_DIR}" "${ICONS_DIR}" "${DATA_DIR}/scripts" "${DATA_DIR}/dictionaries"

    # Enlaces simbólicos directos en modo usuario (para desarrollo ágil)
    rm -f "${BIN_DIR}/notas"
    ln -sf "${BIN_SRC}" "${BIN_DIR}/criperto-notes"
    ln -sf "criperto-notes" "${BIN_DIR}/criperto.notes"
    ln -sf "${SCRIPT_DIR}/assets/dev.criperto.Notas.desktop" "${APPS_DIR}/dev.criperto.Notas.desktop"
    ln -sf "${SCRIPT_DIR}/assets/icons/dev.criperto.Notas.svg" "${ICONS_DIR}/dev.criperto.Notas.svg"

    # Scripts y catálogo
    ln -sf "${SCRIPT_DIR}/scripts/doc-to-md.py" "${DATA_DIR}/scripts/doc-to-md.py"
    ln -sf "${SCRIPT_DIR}/scripts/docx-to-md.py" "${DATA_DIR}/scripts/docx-to-md.py"
    if [[ -f "${SCRIPT_DIR}/assets/spellcheck/catalog.json" ]]; then
        ln -sf "${SCRIPT_DIR}/assets/spellcheck/catalog.json" "${DATA_DIR}/catalog.json"
    fi

    # Copiar diccionarios base si existen en quickshell
    if [[ ! -f "${DATA_DIR}/dictionaries/.dicts_stamp" ]] && [[ -d "${HOME}/.config/quickshell/languages/spellcheck/dicts" ]]; then
        cp -n "${HOME}/.config/quickshell/languages/spellcheck/dicts/"*.{aff,dic} "${DATA_DIR}/dictionaries/" 2>/dev/null || true
        date +%s > "${DATA_DIR}/dictionaries/.dicts_stamp"
    fi

    # Asociar tipos MIME para el usuario
    MIME_TYPES=("text/markdown" "text/plain" "text/x-markdown")
    if command -v xdg-mime &>/dev/null; then
        for mime in "${MIME_TYPES[@]}"; do
            xdg-mime default dev.criperto.Notas.desktop "$mime" 2>/dev/null || true
        done
    fi

    MIMEAPPS="${HOME}/.config/mimeapps.list"
    if [[ -f "$MIMEAPPS" ]]; then
        if ! grep -q "^\[Default Applications\]" "$MIMEAPPS"; then
            printf "\n[Default Applications]\n" >> "$MIMEAPPS"
        fi
        for mime in "${MIME_TYPES[@]}"; do
            if grep -q "^${mime}=" "$MIMEAPPS"; then
                sed -i "s|^${mime}=.*|${mime}=dev.criperto.Notas.desktop|" "$MIMEAPPS"
            else
                sed -i "/^\[Default Applications\]/a ${mime}=dev.criperto.Notas.desktop" "$MIMEAPPS"
            fi
        done
    fi

    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "${APPS_DIR}" 2>/dev/null || true
    fi
    if command -v gtk-update-icon-cache &>/dev/null; then
        gtk-update-icon-cache -q -t -f "${SHARE_DIR}/icons/hicolor" 2>/dev/null || true
    fi

    msg "✓ Instalación de usuario completada en ${TARGET_BASE}." \
        "✓ User installation completed in ${TARGET_BASE}."
    msg "  Comando disponible: criperto-notes (asegurate de tener ~/.local/bin en tu PATH)" \
        "  Available command: criperto-notes (ensure ~/.local/bin is in your PATH)"
else
    # Modo global / sistema (/usr o PREFIX/DESTDIR)
    BIN_DIR="${DESTDIR}${PREFIX}/bin"
    SHARE_DIR="${DESTDIR}${PREFIX}/share"
    APPS_DIR="${SHARE_DIR}/applications"
    ICONS_DIR="${SHARE_DIR}/icons/hicolor/scalable/apps"
    METAINFO_DIR="${SHARE_DIR}/metainfo"
    DATA_DIR="${SHARE_DIR}/criperto.notes"

    msg "==> Instalando Notas a nivel global en ${DESTDIR}${PREFIX}..." \
        "==> Installing Notas system-wide into ${DESTDIR}${PREFIX}..."

    install -d "${BIN_DIR}"
    install -m 755 "${BIN_SRC}" "${BIN_DIR}/criperto-notes"
    ln -sf "criperto-notes" "${BIN_DIR}/criperto.notes"
    rm -f "${BIN_DIR}/notas"

    install -d "${APPS_DIR}"
    install -m 644 "${SCRIPT_DIR}/assets/dev.criperto.Notas.desktop" "${APPS_DIR}/dev.criperto.Notas.desktop"

    install -d "${ICONS_DIR}"
    install -m 644 "${SCRIPT_DIR}/assets/icons/dev.criperto.Notas.svg" "${ICONS_DIR}/dev.criperto.Notas.svg"

    install -d "${METAINFO_DIR}"
    install -m 644 "${SCRIPT_DIR}/data/dev.criperto.Notas.metainfo.xml" "${METAINFO_DIR}/dev.criperto.Notas.metainfo.xml"

    install -d "${DATA_DIR}/scripts"
    if [[ -f "${SCRIPT_DIR}/scripts/doc-to-md.py" ]]; then
        install -m 755 "${SCRIPT_DIR}/scripts/doc-to-md.py" "${DATA_DIR}/scripts/doc-to-md.py"
    fi
    if [[ -f "${SCRIPT_DIR}/scripts/docx-to-md.py" ]]; then
        install -m 755 "${SCRIPT_DIR}/scripts/docx-to-md.py" "${DATA_DIR}/scripts/docx-to-md.py"
    fi
    if [[ -f "${SCRIPT_DIR}/assets/spellcheck/catalog.json" ]]; then
        install -m 644 "${SCRIPT_DIR}/assets/spellcheck/catalog.json" "${DATA_DIR}/catalog.json"
    fi

    if [[ -z "${DESTDIR}" ]]; then
        if command -v update-desktop-database &>/dev/null; then
            update-desktop-database "${APPS_DIR}" 2>/dev/null || true
        fi
        if command -v gtk-update-icon-cache &>/dev/null; then
            gtk-update-icon-cache -q -t -f "${SHARE_DIR}/icons/hicolor" 2>/dev/null || true
        fi
    fi

    msg "✓ Instalación global completada en ${DESTDIR}${PREFIX}." \
        "✓ System-wide installation completed in ${DESTDIR}${PREFIX}."
    msg "  Comando disponible en cualquier terminal: criperto-notes" \
        "  Command available in any terminal: criperto-notes"
fi
