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
  create [--name <имя>] [--description <текст>] [--private] [--read-only] [--branch <ветка>] [--username <u>] [--password <p>] [--root <путь>]
    Создать новый репозиторий через API и подготовить локальные файлы

  branch <list|create|delete|set-default> [опции]
    Управление ветками (через API)
    Примеры:
      ergovcs branch list --repo <uuid>
      ergovcs branch create --repo <uuid> --name <ветка> --username <u> --password <p>
      ergovcs branch delete --id <branch_id>
      ergovcs branch set-default --repo <uuid> --name <ветка>

  files --repo <uuid>
    Показать дерево файлов репозитория
    
  download --source <zip|dir> [--uuid <uuid>] [--name <имя>]
    Скачать/импортировать репозиторий из zip-архива или папки

  install-cli
    Установить CLI-обертку /usr/local/bin/ergovcs

  uninstall-cli
    Удалить CLI-обертку /usr/local/bin/ergovcs
    
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
  ergovcs create --name "Мой репозиторий"
  ergovcs download --source /path/to/repo.zip
  ergovcs files --repo <uuid>
  sudo ./version_manager.sh install-cli
  sudo ./version_manager.sh uninstall-cli
EOF
}

