#!/usr/bin/env bash
# scripts/install-system.sh — Instalación a nivel de sistema para empaquetado (AUR, Flatpak, deb, rpm)
# Respeta variables estándar PREFIX y DESTDIR.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-/usr}"
DESTDIR="${DESTDIR:-}"

# Metainfo dev.criperto.Notas.metainfo.xml instalada vía scripts/install.sh
export PREFIX DESTDIR
exec "${SCRIPT_DIR}/install.sh" --system "$@"
