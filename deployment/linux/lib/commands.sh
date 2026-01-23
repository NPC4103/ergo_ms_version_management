#!/usr/bin/env bash
# Обработчики команд: clone, add, commit, push, update, remove, create, download

# ============================================================================
# Клонирование репозитория
# Команда: ergovcs clone <UUID>
# Копирует репозиторий из media/version_management/<UUID>/ на комп пользователя
# ============================================================================
cmd_clone() {
  # TODO: Реализовать клонирование репозитория
  # 1. Получить UUID из аргументов
  # 2. Вызвать API эндпоинт /api/repositories/{id}/clone/
  # 3. Скачать репозиторий на локальный компьютер
  # 4. Сохранить информацию о клонированном репозитории (путь, UUID)
  
  local uuid=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      *) uuid="$1" ;;
    esac
    shift || true
  done
  
  if [[ -z "$uuid" ]]; then
    echo "[ERROR] Необходимо указать UUID репозитория" >&2
    echo "Использование: ergovcs clone <UUID>" >&2
    exit 1
  fi
  
  # TODO: Реализовать вызов API и клонирование
  echo "[INFO] Клонирование репозитория $uuid..."
  echo "[TODO] Реализовать вызов API /api/repositories/$uuid/clone/"
  echo "[TODO] Скачать репозиторий на локальный компьютер"
}

# ============================================================================
# Добавление файла для коммита
# Команда: ergovcs add <файл.расширение>
# Добавляет файл для коммита
# ============================================================================
cmd_add() {
  # `create` пока не создаёт идентификационную папку/файл в рабочей директории,
  # это нужно учитывать при тестировании
  
  # 1. Найти корень репозитория
  local repo_root
  repo_root="$(find_repository_root)"
  if [[ -z "$repo_root" ]]; then
    echo "[ERROR] Не удалось найти репозиторий. Убедитесь, что вы находитесь в директории репозитория." >&2
    exit 1
  fi
  
  # 2. Получить UUID репозитория
  local uuid
  uuid="$(get_current_repository_uuid)"
  if [[ -z "$uuid" ]]; then
    echo "[ERROR] Не удалось определить UUID репозитория." >&2
    echo "[INFO] Убедитесь, что репозиторий был клонирован или создан через команду clone/create." >&2
    exit 1
  fi
  
  # 3. Прочитать текущий staging area один раз для всех файлов
  local staging_json
  staging_json="$(get_staging_area)"
  
  # 4. Обработать каждый файл из аргументов
  local file_path
  local has_errors=0
  
  while [[ $# -gt 0 ]]; do
    file_path="$1"
    shift || true
    
    # 5. Пропустить пустые аргументы
    if [[ -z "$file_path" ]]; then
      echo "[WARNING] Пропущен пустой аргумент" >&2
      continue
    fi
    
    # 6. Определить полный путь к файлу
    local full_path
    if [[ "$file_path" == /* ]]; then
      full_path="$file_path"
    else
      full_path="$(realpath "$file_path" 2>/dev/null || echo "$(pwd)/$file_path")"
    fi
    
    # 7. Проверить существование файла
    if [[ ! -e "$full_path" ]]; then
      echo "[ERROR] Файл не найден: $file_path" >&2
      has_errors=1
      continue
    fi
    
    # 8. Получить относительный путь от корня репозитория
    local relative_path
    relative_path="$(realpath --relative-to="$repo_root" "$full_path" 2>/dev/null || echo "${full_path#$repo_root/}")"
    relative_path="${relative_path//\\//}"
    
    # 9. Прочитать содержимое файла (как текст, будет экранировано в JSON)
    local file_content
    file_content="$(cat "$full_path" 2>/dev/null)"
    if [[ $? -ne 0 ]]; then
      echo "[ERROR] Не удалось прочитать файл: $file_path" >&2
      has_errors=1
      continue
    fi
    
    # 10. Определить действие файла
    local action
    action="$(get_file_action "$relative_path" "$repo_root")"
    
    # 11. Обновить staging area через Python (надежнее, чем ручной парсинг)
    if ! command -v python3 >/dev/null 2>&1; then
      echo "[ERROR] python3 не установлен. Установите его для работы со staging area." >&2
      exit 1
    fi
    
    # Экранируем содержимое файла для безопасной передачи в Python
    local file_content_escaped
    file_content_escaped="$(echo "$file_content" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))" 2>/dev/null)"
    
    # Обновляем staging area для текущего файла
    staging_json="$(echo "$staging_json" | python3 - <<PYTHON
import json
import sys

try:
    staging = json.load(sys.stdin)
    
    # Убедимся, что структура правильная
    if 'repository_uuid' not in staging:
        staging['repository_uuid'] = '$uuid'
    if 'files' not in staging:
        staging['files'] = []
    if 'pending_commit' not in staging:
        staging['pending_commit'] = None
    
    # Декодируем содержимое файла из JSON строки
    file_content = json.loads('''$file_content_escaped''')
    
    # Проверяем, не добавлен ли файл уже
    file_exists = False
    for i, f in enumerate(staging['files']):
        if f.get('path') == '$relative_path':
            # Обновляем существующий файл
            staging['files'][i]['action'] = '$action'
            staging['files'][i]['content'] = file_content
            file_exists = True
            break
    
    if not file_exists:
        # Добавляем новый файл
        staging['files'].append({
            'path': '$relative_path',
            'action': '$action',
            'content': file_content
        })
    
    print(json.dumps(staging, ensure_ascii=False))
except Exception as e:
    print(f"[ERROR] Ошибка при обновлении staging area: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON
)"
    
    if [[ $? -ne 0 ]]; then
      echo "[ERROR] Не удалось обновить staging area для файла: $file_path" >&2
      has_errors=1
      continue
    fi
    
    echo "[OK] Файл добавлен в staging area: $relative_path"
  done
  
  # 12. Сохранить staging area после обработки всех файлов
  if [[ $has_errors -eq 0 ]]; then
    if save_staging_area "$staging_json"; then
      : # Успешно сохранено
    else
      echo "[ERROR] Не удалось сохранить staging area" >&2
      exit 1
    fi
  else
    # Сохраняем staging area даже если были ошибки, чтобы не потерять успешно добавленные файлы
    if save_staging_area "$staging_json"; then
      echo "[WARNING] Некоторые файлы не были добавлены, но staging area сохранен" >&2
      exit 1
    else
      echo "[ERROR] Не удалось сохранить staging area" >&2
      exit 1
    fi
  fi
}

# ============================================================================
# Создание коммита
# Команда: ergovcs commit -m "Сообщение"
# Создаёт коммит с изменениями в папке media/version_management/<UUID>/
# ============================================================================
cmd_commit() {
  # `create` пока не создаёт идентификационную папку/файл в рабочей директории,
  # это нужно учитывать при тестировании

  # 1. Получить сообщение коммита из аргумента -m
  local message=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--message) shift; message="${1:-}" ;;
      *) echo "[WARN] Неизвестный параметр: $1" >&2 ;;
    esac
    shift || true
  done
  
  if [[ -z "$message" ]]; then
    echo "[ERROR] Необходимо указать сообщение коммита" >&2
    echo "Использование: ergovcs commit -m \"Сообщение\"" >&2
    exit 1
  fi
  
  # 2. Найти корень репозитория
  local repo_root
  repo_root="$(find_repository_root)"
  if [[ -z "$repo_root" ]]; then
    echo "[ERROR] Не удалось найти репозиторий. Убедитесь, что вы находитесь в директории репозитория." >&2
    exit 1
  fi
  
  # 3. Получить UUID текущего репозитория
  local uuid
  uuid="$(get_current_repository_uuid)"
  if [[ -z "$uuid" ]]; then
    echo "[ERROR] Не удалось определить UUID репозитория." >&2
    echo "[INFO] Убедитесь, что репозиторий был клонирован или создан через команду clone/create." >&2
    exit 1
  fi
  
  # 4. Прочитать staging area
  if ! command -v python3 >/dev/null 2>&1; then
    echo "[ERROR] python3 не установлен. Установите его для работы со staging area." >&2
    exit 1
  fi
  
  local staging_json
  staging_json="$(get_staging_area)"
  
  # 5. Проверить, есть ли файлы в staging area
  local files_count
  files_count="$(echo "$staging_json" | python3 -c "import json, sys; data = json.load(sys.stdin); print(len(data.get('files', [])))" 2>/dev/null)"
  if [[ -z "$files_count" ]] || [[ "$files_count" -eq 0 ]]; then
    echo "[ERROR] Нет файлов в staging area. Используйте команду 'add' для добавления файлов." >&2
    exit 1
  fi
  
  # 6. Проверить, есть ли уже pending_commit
  local has_pending
  has_pending="$(echo "$staging_json" | python3 -c "import json, sys; data = json.load(sys.stdin); print('true' if data.get('pending_commit') else 'false')" 2>/dev/null)"
  
  if [[ "$has_pending" == "true" ]]; then
    echo "[INFO] Обнаружен незавершенный коммит. Файлы будут добавлены к существующему коммиту." >&2
    echo "[INFO] Используйте команду 'push' для отправки коммита на сервер." >&2
    
    # Обновляем сообщение коммита и время создания
    local updated_staging
    updated_staging="$(echo "$staging_json" | python3 - <<PYTHON
import json
import sys
from datetime import datetime

try:
    staging = json.load(sys.stdin)
    staging['pending_commit'] = {
        'message': '$message',
        'created_at': datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
    }
    print(json.dumps(staging, ensure_ascii=False))
except Exception as e:
    print(f"[ERROR] Ошибка при обновлении staging area: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON
)"
    
    if [[ $? -ne 0 ]]; then
      echo "[ERROR] Не удалось обновить staging area" >&2
      exit 1
    fi
    
    if save_staging_area "$updated_staging"; then
      echo "[OK] Коммит обновлен. Сообщение: $message"
      echo "[INFO] Всего файлов в коммите: $files_count"
    else
      echo "[ERROR] Не удалось сохранить staging area" >&2
      exit 1
    fi
    return
  fi
  
  # 7. Подготовить данные для API (извлекаем файлы из staging)
  local files_json
  files_json="$(echo "$staging_json" | python3 -c "import json, sys; data = json.load(sys.stdin); print(json.dumps(data.get('files', [])))" 2>/dev/null)"
  
  # 8. Вызвать API для создания коммита
  echo "[INFO] Создание коммита через API..."
  
  local response
  response="$(api_create_commit "$uuid" "$message" "$files_json")"
  
  if [[ $? -ne 0 ]] || [[ -z "$response" ]]; then
    echo "[ERROR] Не удалось создать коммит через API" >&2
    exit 1
  fi
  
  # 9. Парсим ответ от API
  local commit_hash
  commit_hash="$(echo "$response" | python3 -c "import json, sys; data = json.load(sys.stdin); print(data.get('hash') or data.get('id', ''))" 2>/dev/null)"
  
  if [[ -z "$commit_hash" ]]; then
    echo "[WARN] Не удалось извлечь хеш коммита из ответа API" >&2
    commit_hash="unknown"
  fi
  
  echo "[OK] Коммит создан успешно."
  echo "Хеш коммита: $commit_hash"
  echo "Сообщение: $message"
  echo "Файлов: $files_count"
  
  # 10. Создаем pending_commit для отслеживания незавершенного коммита
  local updated_staging
  updated_staging="$(echo "$staging_json" | python3 - <<PYTHON
import json
import sys
from datetime import datetime

try:
    staging = json.load(sys.stdin)
    staging['pending_commit'] = {
        'message': '$message',
        'created_at': datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
        'hash': '$commit_hash'
    }
    print(json.dumps(staging, ensure_ascii=False))
except Exception as e:
    print(f"[ERROR] Ошибка при обновлении staging area: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON
)"
  
  # 11. Сохраняем staging area с pending_commit
  # Файлы остаются в staging area до команды push
  if [[ $? -ne 0 ]]; then
    echo "[WARN] Коммит создан, но не удалось сохранить информацию о pending_commit" >&2
  else
    if save_staging_area "$updated_staging"; then
      echo "[INFO] Используйте команду 'push' для отправки коммита на сервер."
    else
      echo "[WARN] Коммит создан, но не удалось сохранить информацию о pending_commit" >&2
    fi
  fi
}

# ============================================================================
# Отправка изменений на сервер
# Команда: ergovcs push <ветка>
# Отправляет изменения в папку media/version_management/<UUID>/
# ============================================================================
cmd_push() {
  # TODO: Реализовать отправку изменений на сервер
  # 1. Получить название ветки из аргументов
  # 2. Получить UUID текущего репозитория
  # 3. Собрать все незакоммиченные изменения
  # 4. Вызвать API эндпоинт /api/repositories/{id}/push/
  # 5. Отправить изменения в папку media/version_management/<UUID>/
  
  local branch=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      *) branch="$1" ;;
    esac
    shift || true
  done
  
  if [[ -z "$branch" ]]; then
    echo "[ERROR] Необходимо указать название ветки" >&2
    echo "Использование: ergovcs push <ветка>" >&2
    exit 1
  fi
  
  # TODO: Реализовать отправку изменений
  echo "[INFO] Отправка изменений в ветку $branch..."
  echo "[TODO] Получить UUID текущего репозитория"
  echo "[TODO] Собрать незакоммиченные изменения"
  echo "[TODO] Вызвать API /api/repositories/{id}/push/"
}

# ============================================================================
# Обновление локального репозитория
# Команда: ergovcs update <ветка>
# Подтягивает изменения с сервера на комп пользователя
# ============================================================================
cmd_update() {
  # TODO: Реализовать обновление локального репозитория
  # 1. Получить название ветки из аргументов
  # 2. Получить UUID текущего репозитория
  # 3. Вызвать API эндпоинт /api/repositories/{id}/update/
  # 4. Скачать изменения из папки media/version_management/<UUID>/ на локальный компьютер
  # Примечание: не важно какая ветка скачана у пользователя, программе всё равно куда она шлёт данные
  
  local branch=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      *) branch="$1" ;;
    esac
    shift || true
  done
  
  if [[ -z "$branch" ]]; then
    echo "[ERROR] Необходимо указать название ветки" >&2
    echo "Использование: ergovcs update <ветка>" >&2
    exit 1
  fi
  
  # TODO: Реализовать обновление
  echo "[INFO] Обновление локального репозитория из ветки $branch..."
  echo "[TODO] Получить UUID текущего репозитория"
  echo "[TODO] Вызвать API /api/repositories/{id}/update/"
  echo "[TODO] Скачать изменения на локальный компьютер"
}

# ============================================================================
# Удаление репозитория
# Команда: ergovcs remove <UUID>
# Удаляет репозиторий с компа пользователя
# ============================================================================
cmd_remove() {
  # TODO: Реализовать удаление репозитория
  # 1. Получить UUID из аргументов
  # 2. Найти локальную копию репозитория
  # 3. Удалить локальную копию репозитория
  # Примечание: это удаляет только локальную копию, не репозиторий на сервере
  
  local uuid=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      *) uuid="$1" ;;
    esac
    shift || true
  done
  
  if [[ -z "$uuid" ]]; then
    echo "[ERROR] Необходимо указать UUID репозитория" >&2
    echo "Использование: ergovcs remove <UUID>" >&2
    exit 1
  fi
  
  # TODO: Реализовать удаление локальной копии
  echo "[INFO] Удаление локальной копии репозитория $uuid..."
  echo "[TODO] Найти локальную копию репозитория"
  echo "[TODO] Удалить локальную копию"
}

cmd_create() {
  # Создание репозитория через API
  # Использует API эндпоинт /api/repositories/ для избежания дублирования функционала
  # Примечание: API не поддерживает description, поэтому параметр --description игнорируется
  
  local name=""
  local description=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) shift; name="${1:-}" ;;
      --description) shift; description="${1:-}"; echo "[WARN] Параметр --description не поддерживается API и будет проигнорирован" >&2 ;;
      --root) shift; echo "[WARN] Параметр --root игнорируется при работе через API" >&2 ;;
      *) echo "[WARN] Неизвестный параметр: $1" >&2 ;;
    esac
    shift || true
  done

  [[ -z "$name" ]] && read -rp "Название репозитория: " name

  echo "[INFO] Создание репозитория через API..."
  
  local response
  response="$(api_create_repository "$name")"
  
  if [[ $? -ne 0 ]]; then
    echo "[ERROR] Не удалось создать репозиторий" >&2
    exit 1
  fi
  
  # Парсим ответ от API
  local repo_id
  local repo_name
  local repo_path
  local created_at
  
  repo_id="$(echo "$response" | grep -o '"id"[^,]*' | cut -d'"' -f4)"
  repo_name="$(echo "$response" | grep -o '"name"[^,]*' | cut -d'"' -f4)"
  repo_path="$(echo "$response" | grep -o '"path"[^,]*' | cut -d'"' -f4)"
  created_at="$(echo "$response" | grep -o '"created_at"[^,]*' | cut -d'"' -f4)"
  
  echo "[OK] Репозиторий создан."
  echo "UUID:   $repo_id"
  echo "Название: $repo_name"
  echo "Путь:   $repo_path"
  if [[ -n "$created_at" ]]; then
    echo "Создан: $created_at"
  fi
}

cmd_download() {
  detect_project_root

  local source=""
  local uuid=""
  local name=""
  local manual_root=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source) shift; source="${1:-}" ;;
      --uuid) shift; uuid="${1:-}" ;;
      --name) shift; name="${1:-}" ;;
      --root) shift; manual_root="${1:-}" ;;
      *) echo "[WARN] Неизвестный параметр: $1" >&2 ;;
    esac
    shift || true
  done

  if [[ -n "$manual_root" ]]; then
    PROJECT_ROOT="$manual_root"
    MEDIA_DIR="$PROJECT_ROOT/media/version_management"
    mkdir -p "$MEDIA_DIR"
  fi

  [[ -z "$source" ]] && { echo "[ERROR] Нужно указать --source" >&2; exit 1; }
  [[ ! -e "$source" ]] && { echo "[ERROR] Источник не найден: $source" >&2; exit 1; }
  
  if [[ -z "$uuid" ]]; then
    uuid="$(ensure_uuid)"
  fi

  local target
  target="$(ensure_repo_dirs "$uuid")"
  import_from_source "$source" "$target"
  
  if [[ -n "$name" ]]; then
    save_metadata "$target" "$name" ""
  fi

  echo "[OK] Репозиторий импортирован."
  echo "UUID:   $uuid"
  echo "Путь:   $target"
}

