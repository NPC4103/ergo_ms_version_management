#!/usr/bin/env bash
set -euo pipefail

# Утилита для управления репозиториями version_management
# Работает без бэкенда, создавая локальную структуру

# Load modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# shellcheck source=lib/core.sh
source "$LIB_DIR/core.sh"
# shellcheck source=lib/repo.sh
source "$LIB_DIR/repo.sh"
# shellcheck source=lib/commands.sh
source "$LIB_DIR/commands.sh"
# shellcheck source=lib/help.sh
source "$LIB_DIR/help.sh"
# shellcheck source=lib/cli.sh
source "$LIB_DIR/cli.sh"

main() {
  local command="${1:-help}"
  shift || true

  case "$command" in
    clone)     cmd_clone "$@" ;;
    add)       cmd_add "$@" ;;
    commit)    cmd_commit "$@" ;;
    push)      cmd_push "$@" ;;
    update)    cmd_update "$@" ;;
    remove)    cmd_remove "$@" ;;
    create)    cmd_create "$@" ;;
    download)  cmd_download "$@" ;;
    install-cli) create_cli_wrapper "$SCRIPT_DIR/version_manager.sh" ;;
    uninstall-cli) remove_cli_wrapper ;;
    help|-h|--help) print_help ;;
    *) echo "[ERROR] Unknown command: $command" >&2; print_help; exit 1 ;;
  esac
}

main "$@"

