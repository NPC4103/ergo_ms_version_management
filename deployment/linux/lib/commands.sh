#!/usr/bin/env bash
# Обработчики команд: clone, add, commit, push, update, remove, create, download

# ============================================================================
# Клонирование репозитория
# Команда: ergovcs clone <путь> <имя_или_uuid>
# ============================================================================
cmd_clone() {
    local target_path="$1"
    local repo_identifier="$2"
    
    # --- 1. Обработка аргументов ---
    if [[ -z "$target_path" ]]; then
        echo "[ERROR] Использование: ergovcs clone <путь_назначения> <имя_репозитория_или_uuid>"
        return 1
    fi

    if [[ -z "$repo_identifier" ]]; then
        repo_identifier="$target_path"
        target_path="."
    fi

    # --- 2. Определение UUID (через API) ---
    local uuid="$repo_identifier"
    
    # Проверка на формат UUID
    if [[ ! "$repo_identifier" =~ ^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$ ]]; then
        echo "[INFO] Поиск репозитория по имени: '$repo_identifier'..."
        
        local list_response
        list_response=$(api_list_repositories)
        
        if [[ $? -ne 0 ]]; then
            echo "[ERROR] Не удалось получить список репозиториев (API недоступен?)."
            return 1
        fi
        
        # Парсим JSON чтобы найти UUID по имени
        uuid=$(echo "$list_response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Обработка списка или пагинации {results: [...]}
    repos = data.get('results', data) if isinstance(data, dict) else data
    
    found = ''
    if isinstance(repos, list):
        for r in repos:
            if r.get('name') == '$repo_identifier':
                found = r.get('public_id') or r.get('uuid')
                break
    print(found)
except:
    print('')
")
        
        if [[ -z "$uuid" ]]; then
            echo "[ERROR] Репозиторий с именем '$repo_identifier' не найден."
            return 1
        fi
        echo "[INFO] Найден UUID: $uuid"
    fi

    # --- 3. Поиск папки media на диске ---
    # Пытаемся найти папку media вверх по иерархии или в текущей папке
    local media_root=""
    local current_dir=$(pwd)
    
    # Простой поиск: проверяем текущую, родительскую и '..' до 3 уровней
    for path in "." ".." "../.." "../../.."; do
        if [[ -d "$path/media/version_management" ]]; then
            media_root=$(cd "$path/media/version_management" && pwd)
            break
        fi
    done
    
    # Если не нашли, проверяем переменную окружения
    if [[ -z "$media_root" && -n "$ERGOVCS_MEDIA_PATH" ]]; then
         media_root="$ERGOVCS_MEDIA_PATH"
    fi

    if [[ -z "$media_root" ]]; then
        echo "[ERROR] Не удалось найти локальную папку 'media/version_management'."
        echo "[HINT] Запустите команду из корня проекта бекенда или задайте ERGOVCS_MEDIA_PATH."
        return 1
    fi
    
    local source_repo_path="$media_root/$uuid"
    
    if [[ ! -d "$source_repo_path" ]]; then
        echo "[ERROR] Папка репозитория не найдена на диске: $source_repo_path"
        return 1
    fi

    # --- 4. Копирование файлов (Клонирование) ---
    if [[ ! -d "$target_path" ]]; then
        mkdir -p "$target_path"
    fi
    local abs_target_path
    abs_target_path=$(cd "$target_path" && pwd)

    echo "[INFO] Клонирование файлов из $source_repo_path..."
    
    # Копируем всё, кроме системных папок, если нужно (но cp -r копирует всё)
    # Используем точку в конце source, чтобы содержимое копировалось В target
    cp -r "$source_repo_path/." "$abs_target_path/"
    
    if [[ $? -ne 0 ]]; then
        echo "[ERROR] Ошибка при копировании файлов."
        return 1
    fi

    # --- 5. Сохранение конфига ---
    local config_file="$HOME/.ergovcs/repos.json"
    mkdir -p "$(dirname "$config_file")"
    
    python3 -c "
import json, os, datetime
file_path = '$config_file'
entry = {
    'uuid': '$uuid',
    'local_path': '$abs_target_path',
    'remote_path': '$source_repo_path',
    'current_branch': 'main',
    'last_updated': datetime.datetime.now().isoformat()
}

data = {'repositories': {}}
if os.path.exists(file_path):
    try:
        with open(file_path, 'r') as f:
            data = json.load(f)
    except: pass

if 'repositories' not in data: data['repositories'] = {}
data['repositories']['$uuid'] = entry

with open(file_path, 'w') as f:
    json.dump(data, f, indent=2)
"
    echo "[OK] Репозиторий успешно клонирован в $abs_target_path"
}


# ============================================================================
# Добавление файла для коммита
# Команда: ergovcs add <файл.расширение>
# Добавляет файл для коммита
# ============================================================================
cmd_add() {
  # create должен подготовить локальные метаданные в рабочей директории
  
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
  # create должен подготовить локальные метаданные в рабочей директории

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
  # 1. Получить UUID из аргументов
  # 2. Найти локальную копию репозитория
  # 3. Удалить локальную копию репозитория
  # 4. Удалить запись из конфига (~/.ergovcs/repos.json)
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
  
  local config_dir="$HOME/.ergovcs"
  local repos_file="$config_dir/repos.json"

  if [[ ! -f "$repos_file" ]]; then
    echo "[ERROR] Файл конфигурации репозиториев не найден: $repos_file" >&2
    echo "[INFO] Нечего удалять. Сначала клонируйте репозиторий (clone) или создайте запись в repos.json." >&2
    exit 1
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "[ERROR] Для команды remove нужен python3 (для работы с JSON)." >&2
    exit 1
  fi

  # Достаём local_path из repos.json
  local local_path=""
  local_path="$(python3 - "$uuid" "$repos_file" <<'PY'
import json, sys
uuid = sys.argv[1]
path = sys.argv[2]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except FileNotFoundError:
    sys.exit(2)
except Exception:
    sys.exit(3)
repos = (data or {}).get("repositories") or {}
entry = repos.get(uuid) or {}
lp = entry.get("local_path") or ""
sys.stdout.write(lp)
PY
)" || true

  if [[ -z "$local_path" ]]; then
    echo "[ERROR] Репозиторий $uuid не найден в $repos_file" >&2
    exit 1
  fi

  echo "[INFO] Удаление локальной копии репозитория $uuid..."

  if [[ -d "$local_path" || -f "$local_path" ]]; then
    rm -rf -- "$local_path"
    echo "[OK] Локальная копия удалена: $local_path"
  else
    echo "[WARN] Локальный путь не найден на диске: $local_path" >&2
    echo "[INFO] Запись будет удалена из конфига." >&2
  fi

  # Удаляем запись из repos.json
  python3 - "$uuid" "$repos_file" <<'PY'
import json, sys
uuid = sys.argv[1]
path = sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f) or {}
repos = data.get("repositories")
if not isinstance(repos, dict):
    repos = {}
if uuid in repos:
    repos.pop(uuid, None)
data["repositories"] = repos
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY

  echo "[OK] Запись удалена из конфига: $repos_file"
}

cmd_create() {
  local name=""
  local description=""
  local is_private="false"
  local is_read_only="false"
  local branch_name=""
  local cli_username=""
  local cli_password=""
  local local_path=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name|-n) shift; name="${1:-}" ;;
      --description|-d) shift; description="${1:-}" ;;
      --private|-p) is_private="true" ;;
      --read-only) is_read_only="true" ;;
      --branch|-b) shift; branch_name="${1:-}" ;;
      --username|-u) shift; cli_username="${1:-}" ;;
      --password|-pw) shift; cli_password="${1:-}" ;;
      --root|-r)
        shift
        local_path="${1:-}"
        echo "[INFO] Указан локальный путь: $local_path"
        ;;
      *)
        if [[ -z "$name" && "$1" != -* ]]; then
          name="$1"
        else
          echo "[WARN] Неизвестный параметр: $1" >&2
        fi
        ;;
    esac
    shift || true
  done

  if [[ -z "$name" ]]; then
    read -rp "Название репозитория: " name
  fi
  if [[ -z "$name" ]]; then
    echo "[ERROR] Необходимо указать название репозитория" >&2
    exit 1
  fi

  if [[ -z "$local_path" ]]; then
    local_path="$(pwd)"
  fi
  mkdir -p "$local_path"
  local_path="$(cd "$local_path" && pwd)"

  if [[ -n "$cli_username" || -n "$cli_password" ]]; then
    if [[ -z "$cli_username" || -z "$cli_password" ]]; then
      echo "[WARN] Для авторизации нужны --username и --password (оба)." >&2
    fi
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "[ERROR] python3 не установлен. Установите его для работы с create." >&2
    exit 1
  fi

  local body
  body="$(python3 - <<PY
import json
payload = {}
name = ${name@Q}
description = ${description@Q}
branch = ${branch_name@Q}
cli_username = ${cli_username@Q}
cli_password = ${cli_password@Q}
is_private = ${is_private@Q}
is_read_only = ${is_read_only@Q}
if name:
    payload["name"] = name
if description:
    payload["description"] = description
if is_private == "true":
    payload["is_private"] = True
if is_read_only == "true":
    payload["is_read_only"] = True
if branch:
    payload["initial_branch_name"] = branch
if cli_username:
    payload["cli_username"] = cli_username
if cli_password:
    payload["cli_password"] = cli_password
print(json.dumps(payload))
PY
)"

  echo "[INFO] Создание репозитория через API..."
  local response
  response="$(api_request "POST" "/repositories/" "$body")"
  if [[ $? -ne 0 ]]; then
    echo "[ERROR] Не удалось создать репозиторий" >&2
    exit 1
  fi

  local repo_id
  local repo_name
  local repo_path
  local created_at

  repo_id="$(echo "$response" | python3 - <<'PY'
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("public_id") or data.get("id") or "")
except Exception:
    print("")
PY
)"
  repo_name="$(echo "$response" | python3 - <<'PY'
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("name") or "")
except Exception:
    print("")
PY
)"
  repo_path="$(echo "$response" | python3 - <<'PY'
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("path") or "")
except Exception:
    print("")
PY
)"
  created_at="$(echo "$response" | python3 - <<'PY'
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("created_at") or "")
except Exception:
    print("")
PY
)"
  if [[ -z "$repo_path" && -n "$repo_id" ]]; then
    repo_path="media/version_management/$repo_id"
  fi

  local ergovcs_dir="$local_path/.ergovcs"
  mkdir -p "$ergovcs_dir"
  cat >"$ergovcs_dir/config.json" <<JSON
{
  "repository_uuid": "$repo_id",
  "name": "$repo_name",
  "local_path": "$local_path",
  "remote_path": "$repo_path",
  "current_branch": "${branch_name:-main}",
  "created_at": "$created_at"
}
JSON

  local ignore_file="$local_path/.ergovcsignore"
  if [[ ! -f "$ignore_file" ]]; then
    cat >"$ignore_file" <<'EOF'
.ergovcs/
EOF
  fi

  local readme_file="$local_path/README.md"
  if [[ ! -f "$readme_file" ]]; then
    cat >"$readme_file" <<'EOF'
# Repository

Created by ergovcs.
EOF
  fi

  echo "[OK] Репозиторий создан."
  echo "UUID:   $repo_id"
  echo "Название: $repo_name"
  echo "Путь:   $repo_path"
  echo "Локальный путь: $local_path"
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

# ============================================================================
# Управление ветками
# Команда: ergovcs branch <list|create|delete|set-default> ...
# ============================================================================
cmd_branch() {
  local action="${1:-}"
  shift || true

  if [[ -z "$action" ]]; then
    echo "[ERROR] Использование: ergovcs branch <list|create|delete|set-default>" >&2
    exit 1
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "[ERROR] python3 не установлен. Установите его для работы с ветками." >&2
    exit 1
  fi

  local repo_uuid=""
  local branch_name=""
  local branch_id=""
  local cli_username=""
  local cli_password=""
  local check_permissions="true"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) shift; repo_uuid="${1:-}" ;;
      --name) shift; branch_name="${1:-}" ;;
      --id) shift; branch_id="${1:-}" ;;
      --username|-u) shift; cli_username="${1:-}" ;;
      --password|-pw) shift; cli_password="${1:-}" ;;
      --no-check-permissions) check_permissions="false" ;;
      *) echo "[WARN] Неизвестный параметр: $1" >&2 ;;
    esac
    shift || true
  done

  if [[ -n "$cli_username" || -n "$cli_password" ]]; then
    if [[ -z "$cli_username" || -z "$cli_password" ]]; then
      echo "[WARN] Для авторизации нужны --username и --password (оба)." >&2
    fi
  fi

  case "$action" in
    list)
      if [[ -z "$repo_uuid" ]]; then
        echo "[ERROR] Нужно указать --repo <UUID>" >&2
        exit 1
      fi
      local response
      response="$(api_list_branches "$repo_uuid")" || exit 1
      echo "$response" | python3 - <<'PY'
import json, sys
data = json.load(sys.stdin)
branches = data.get("branches", data)
if isinstance(branches, list):
    for b in branches:
        name = b.get("name")
        bid = b.get("id")
        is_default = b.get("is_default")
        print(f"- {name} (id={bid}, default={is_default})")
else:
    print(json.dumps(data, ensure_ascii=False, indent=2))
PY
      ;;
    create)
      if [[ -z "$repo_uuid" || -z "$branch_name" ]]; then
        echo "[ERROR] Нужно указать --repo <UUID> и --name <ветка>" >&2
        exit 1
      fi
      api_create_branch "$repo_uuid" "$branch_name" "$cli_username" "$cli_password" "$check_permissions" >/dev/null
      echo "[OK] Ветка создана: $branch_name"
      ;;
    delete)
      if [[ -z "$branch_id" ]]; then
        if [[ -n "$repo_uuid" && -n "$branch_name" ]]; then
          local resp
          resp="$(api_list_branches "$repo_uuid")" || exit 1
          branch_id="$(echo "$resp" | python3 - <<PY
import json, sys
data = json.load(sys.stdin)
branches = data.get("branches", data)
target = "${branch_name}"
for b in branches:
    if b.get("name") == target:
        print(b.get("id"))
        sys.exit(0)
print("")
PY
)"
        fi
      fi
      if [[ -z "$branch_id" ]]; then
        echo "[ERROR] Нужно указать --id <branch_id> (или --repo + --name для поиска)" >&2
        exit 1
      fi
      api_delete_branch "$branch_id" >/dev/null
      echo "[OK] Ветка удалена (id=$branch_id)"
      ;;
    set-default)
      if [[ -n "$branch_id" ]]; then
        api_set_default_branch_by_id "$branch_id" "$cli_username" "$cli_password" "$check_permissions" >/dev/null
        echo "[OK] Ветка установлена по умолчанию (id=$branch_id)"
      elif [[ -n "$repo_uuid" && -n "$branch_name" ]]; then
        api_set_default_branch_by_name "$repo_uuid" "$branch_name" "$cli_username" "$cli_password" "$check_permissions" >/dev/null
        echo "[OK] Ветка установлена по умолчанию: $branch_name"
      else
        echo "[ERROR] Нужно указать --id <branch_id> или --repo <UUID> и --name <ветка>" >&2
        exit 1
      fi
      ;;
    *)
      echo "[ERROR] Неизвестное действие: $action" >&2
      exit 1
      ;;
  esac
}
