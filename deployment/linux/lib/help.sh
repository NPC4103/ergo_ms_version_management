#!/usr/bin/env bash
# Справка по использованию утилиты

print_help() {
  cat <<'EOF'
version_manager.sh <command> [options]

Команды:
  create [--name <имя>] [--description <текст>]
    Создать новый локальный репозиторий
    
  download --source <zip|dir> [--uuid <uuid>] [--name <имя>]
    Скачать/импортировать репозиторий из zip-архива или папки
    
  help
    Показать эту справку

Флаги:
  --root <путь>   указать корень проекта вручную (по умолчанию определяется автоматически)

Примеры:
  ./version_manager.sh create --name "Мой репозиторий" --description "Описание"
  ./version_manager.sh download --source /path/to/repo.zip
  ./version_manager.sh download --source /path/to/repo --uuid abc-123-def
EOF
}

