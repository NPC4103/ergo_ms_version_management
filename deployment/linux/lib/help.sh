#!/usr/bin/env bash
# Справка по использованию утилиты

print_help() {
  cat <<'EOF'
ergovcs <command> [options]

Основные команды работы с репозиториями:
  clone <UUID>
    Клонировать репозиторий из media/version_management/<UUID>/ на локальный компьютер
    Вызывает API: /api/repositories/{id}/clone/
    
  add <файл.расширение>
    Добавить файл для коммита в staging area
    После команды commit изменения будут отправлены на сервер
    
  commit -m "Сообщение"
    Создать коммит с изменениями
    Вызывает API: /api/repositories/{id}/commits/create/
    После повторного add не создаётся новый коммит, а добавляются изменения
    в существующий, до тех пор пока коммит не отправлен на сервер
    
  push <ветка>
    Отправить изменения на сервер в папку media/version_management/<UUID>/
    Вызывает API: /api/repositories/{id}/push/
    
  update <ветка>
    Обновить локальный репозиторий, подтянув изменения с сервера
    Вызывает API: /api/repositories/{id}/update/
    Примечание: не важно какая ветка скачана у пользователя
    
  remove <UUID>
    Удалить локальную копию репозитория с компьютера пользователя
    Примечание: удаляет только локальную копию, не репозиторий на сервере

Вспомогательные команды:
  create [--name <имя>] [--description <текст>]
    Создать новый локальный репозиторий
    
  download --source <zip|dir> [--uuid <uuid>] [--name <имя>]
    Скачать/импортировать репозиторий из zip-архива или папки
    
  help
    Показать эту справку

Флаги:
  --root <путь>   указать корень проекта вручную (по умолчанию определяется автоматически)

Примеры:
  ergovcs clone abc-123-def-456
  ergovcs add src/main.py
  ergovcs commit -m "Добавлен новый функционал"
  ergovcs push main
  ergovcs update main
  ergovcs remove abc-123-def-456
  ./version_manager.sh create --name "Мой репозиторий" --description "Описание"
  ./version_manager.sh download --source /path/to/repo.zip
EOF
}

