#!/usr/bin/env bash
# Общие утилиты: поиск корня проекта, генерация UUID

PROJECT_ROOT=""
MEDIA_DIR=""

detect_project_root() {
  local start="$(pwd)"
  while [[ "$start" != "/" ]]; do
    if [[ -d "$start/modules/version_management" ]]; then
      PROJECT_ROOT="$start"
      MEDIA_DIR="$PROJECT_ROOT/media/version_management"
      mkdir -p "$MEDIA_DIR"
      return
    fi
    start="$(dirname "$start")"
  done
  echo "[ERROR] Не удалось найти корень проекта (modules/version_management)!" >&2
  exit 1
}

ensure_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen
  else
    python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
  fi
}

