#!/usr/bin/env bash
# Логика работы с репозиториями: создание структуры, сохранение метаданных, импорт

ensure_repo_dirs() {
  local uuid="$1"
  local target="$MEDIA_DIR/$uuid"
  mkdir -p "$target/api" "$target/client"
  echo "$target"
}

save_metadata() {
  local target="$1"
  local name="$2"
  local description="$3"
  local uuid="$(basename "$target")"
  
  cat >"$target/manifest.json" <<JSON
{
  "uuid": "$uuid",
  "name": "$name",
  "description": "$description"
}
JSON
}

import_from_source() {
  local source_path="$1"
  local target_dir="$2"

  if [[ -d "$source_path" ]]; then
    cp -R "$source_path"/. "$target_dir/"
  elif [[ "$source_path" == *.zip ]]; then
    if ! command -v unzip >/dev/null 2>&1; then
      echo "[ERROR] unzip не установлен. Установите его для работы с zip-архивами." >&2
      exit 1
    fi
    unzip -oq "$source_path" -d "$target_dir"
  else
    echo "[ERROR] Неизвестный источник: $source_path" >&2
    echo "[INFO] Поддерживаются: папка или zip-архив" >&2
    exit 1
  fi
}

