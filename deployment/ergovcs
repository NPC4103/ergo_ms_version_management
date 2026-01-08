#!/usr/bin/env bash
set -euo pipefail

# Универсальный вход для утилиты ergovcs (Linux / WSL)
# Просто проксирует все аргументы в linux/version_manager.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "${SCRIPT_DIR}/linux/version_manager.sh" "$@"


