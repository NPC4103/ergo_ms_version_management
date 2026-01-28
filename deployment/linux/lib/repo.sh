#!/usr/bin/env bash
# Логика работы с репозиториями: создание структуры, сохранение метаданных, импорт, работа с API

# ============================================================================
# Функции для работы с API
# ============================================================================

# Получить базовый URL API
get_api_base_url() {
  # Приоритет: переменная окружения > конфиг файл > значение по умолчанию
  if [[ -n "${API_BASE_URL:-}" ]]; then
    echo "$API_BASE_URL"
    return
  fi
  
  # Проверяем конфиг файл в домашней директории
  local config_file="$HOME/.ergovcs/config"
  if [[ -f "$config_file" ]]; then
    local api_url
    api_url="$(grep -E "^api_base_url=" "$config_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")"
    if [[ -n "$api_url" ]]; then
      echo "$api_url"
      return
    fi
  fi
  
  # Проверяем переменные окружения для хоста и порта
  local api_host="${API_HOST:-localhost}"
  local api_port="${API_PORT:-8000}"
  echo "http://${api_host}:${api_port}/api/version_management"
}

# Выполнить HTTP запрос к API
api_request() {
  # Параметры:
  #   $1 - метод (GET, POST, PUT, DELETE)
  #   $2 - endpoint (относительный путь)
  #   $3 - тело запроса (опционально, для POST/PUT)
  #   $4 - заголовки (опционально, формат: "Header1: Value1,Header2: Value2")
  # Возвращает: JSON ответ от API (через stdout)
  # В случае ошибки: выводит сообщение об ошибке в stderr и возвращает код ошибки
  
  local method="$1"
  local endpoint="$2"
  local body="${3:-}"
  local headers="${4:-}"
  
  # Проверка наличия curl
  if ! command -v curl >/dev/null 2>&1; then
    echo "[ERROR] curl не установлен. Установите curl для работы с API." >&2
    return 1
  fi
  
  local base_url
  base_url="$(get_api_base_url)"
  local url="${base_url}${endpoint}"
  
  # Подготовка команды curl
  local curl_args=(
    -s
    -X "$method"
    -H "Content-Type: application/json"
    -H "Accept: application/json"
  )
  
  # Добавление кастомных заголовков
  if [[ -n "$headers" ]]; then
    IFS=',' read -ra HEADER_ARRAY <<< "$headers"
    for header in "${HEADER_ARRAY[@]}"; do
      curl_args+=(-H "$header")
    done
  fi
  
  # Добавление тела запроса для POST/PUT
  if [[ -n "$body" ]] && [[ "$method" == "POST" || "$method" == "PUT" ]]; then
    curl_args+=(-d "$body")
  fi
  
  # Выполнение запроса
  local response
  local http_code
  local error_output
  
  # Выполняем запрос и получаем HTTP код
  response="$(curl -s -w "\n%{http_code}" "${curl_args[@]}" "$url" 2>&1)"
  http_code="$(echo "$response" | tail -n1)"
  response="$(echo "$response" | sed '$d')"
  
  # Проверка HTTP кода
  if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
    # Успешный ответ
    echo "$response"
    return 0
  else
    # Ошибка HTTP
    local error_msg
    error_msg="$(echo "$response" | grep -o '"detail"[^}]*' | sed 's/"detail"://' | tr -d '"' | tr -d ',' || echo "HTTP $http_code")"
    if [[ -z "$error_msg" ]]; then
      error_msg="HTTP $http_code"
    fi
    echo "[ERROR] API запрос не удался: $error_msg" >&2
    echo "$response" >&2
    return 1
  fi
}

# Создать репозиторий через API
api_create_repository() {
  # Параметры:
  #   $1 - название репозитория (опционально)
  # Возвращает: JSON с информацией о созданном репозитории (id, name, path, created_at)
  
  local name="${1:-}"
  
  local body="{}"
  if [[ -n "$name" ]]; then
    body="{\"name\": \"$name\"}"
  fi
  
  # Стандартный create ViewSet в DRF доступен по POST /repositories/
  api_request "POST" "/repositories/" "$body"
}

# Получить список репозиториев через API
api_list_repositories() {
  # Возвращает: JSON со списком репозиториев
  api_request "GET" "/repositories/"
}

# Получить список веток репозитория
api_list_branches() {
  local repo_uuid="$1"
  api_request "GET" "/repositories/$repo_uuid/branches/"
}

# Создать ветку
api_create_branch() {
  local repo_uuid="$1"
  local branch_name="$2"
  local cli_username="${3:-}"
  local cli_password="${4:-}"
  local check_permissions="${5:-true}"

  local body
  body="$(python3 - <<PY
import json
check_permissions = "${check_permissions}".lower() == "true"
payload = {
  "repository_public_id": "${repo_uuid}",
  "name": "${branch_name}",
  "check_permissions": check_permissions
}
if "${cli_username}":
    payload["cli_username"] = "${cli_username}"
if "${cli_password}":
    payload["cli_password"] = "${cli_password}"
print(json.dumps(payload))
PY
)"

  api_request "POST" "/branches/" "$body"
}

# Установить ветку по умолчанию (по id)
api_set_default_branch_by_id() {
  local branch_id="$1"
  local cli_username="${2:-}"
  local cli_password="${3:-}"
  local check_permissions="${4:-true}"

  local body
  body="$(python3 - <<PY
import json
check_permissions = "${check_permissions}".lower() == "true"
payload = {
  "branch_id": ${branch_id},
  "check_permissions": check_permissions
}
if "${cli_username}":
    payload["cli_username"] = "${cli_username}"
if "${cli_password}":
    payload["cli_password"] = "${cli_password}"
print(json.dumps(payload))
PY
)"

  api_request "POST" "/branches/set_default/" "$body"
}

# Установить ветку по умолчанию (по repo+name)
api_set_default_branch_by_name() {
  local repo_uuid="$1"
  local branch_name="$2"
  local cli_username="${3:-}"
  local cli_password="${4:-}"
  local check_permissions="${5:-true}"

  local body
  body="$(python3 - <<PY
import json
check_permissions = "${check_permissions}".lower() == "true"
payload = {
  "repository_public_id": "${repo_uuid}",
  "branch_name": "${branch_name}",
  "check_permissions": check_permissions
}
if "${cli_username}":
    payload["cli_username"] = "${cli_username}"
if "${cli_password}":
    payload["cli_password"] = "${cli_password}"
print(json.dumps(payload))
PY
)"

  api_request "POST" "/branches/set_default/" "$body"
}

# Удалить ветку
api_delete_branch() {
  local branch_id="$1"
  api_request "DELETE" "/branches/$branch_id/"
}

# Получить дерево файлов репозитория
api_get_repo_files() {
  local repo_uuid="$1"
  api_request "GET" "/repositories/$repo_uuid/files/"
}

# Клонировать репозиторий через API
api_clone_repository() {
  # TODO: Реализовать клонирование через API
  # Параметры:
  #   $1 - UUID репозитория
  # Возвращает: путь к клонированному репозиторию
  
  local uuid="$1"
  echo "[TODO] Вызвать API /api/repositories/$uuid/clone/"
  api_request "GET" "/repositories/$uuid/clone/"
}

# Создать коммит через API
#   $1 - UUID, $2 - сообщение, $3 - файлы (JSON), $4 - ветка (опционально, branch_name)
api_create_commit() {
  local uuid="$1"
  local message="$2"
  local files="${3:-[]}"
  local branch="${4:-}"
  
  local body
  if [[ -n "$branch" ]]; then
    body="{\"message\": \"$message\", \"files\": $files, \"branch_name\": \"$branch\"}"
  else
    body="{\"message\": \"$message\", \"files\": $files}"
  fi
  api_request "POST" "/repositories/$uuid/commits/create/" "$body"
}

# Отправить изменения через API
api_push_changes() {
  # TODO: Реализовать отправку изменений через API
  # Параметры:
  #   $1 - UUID репозитория
  #   $2 - название ветки
  #   $3 - данные изменений (JSON или путь к файлу)
  
  local uuid="$1"
  local branch="$2"
  local changes="${3:-}"
  
  local body
  body="{\"branch\": \"$branch\""
  if [[ -n "$changes" ]]; then
    body="$body, \"changes\": $changes"
  fi
  body="$body}"
  
  echo "[TODO] Вызвать API /api/repositories/$uuid/push/"
  api_request "POST" "/repositories/$uuid/push/" "$body"
}

# Обновить локальный репозиторий через API
api_update_repository() {
  # TODO: Реализовать обновление через API
  # Параметры:
  #   $1 - UUID репозитория
  #   $2 - название ветки
  # Возвращает: путь к обновленным файлам или архив
  
  local uuid="$1"
  local branch="$2"
  
  echo "[TODO] Вызвать API /api/repositories/$uuid/update/"
  api_request "POST" "/repositories/$uuid/update/" "{\"branch\": \"$branch\"}"
}

# Получить список коммитов через API
api_list_commits() {
  # TODO: Реализовать получение списка коммитов через API
  # Параметры:
  #   $1 - UUID репозитория
  # Возвращает: JSON со списком коммитов
  
  local uuid="$1"
  echo "[TODO] Вызвать API /api/repositories/$uuid/commits/"
  api_request "GET" "/repositories/$uuid/commits/"
}

# Получить информацию о коммите через API
api_get_commit() {
  # TODO: Реализовать получение информации о коммите через API
  # Параметры:
  #   $1 - UUID репозитория
  #   $2 - хеш коммита
  # Возвращает: JSON с метаданными коммита
  
  local uuid="$1"
  local commit_hash="$2"
  echo "[TODO] Вызвать API /api/repositories/$uuid/commits/$commit_hash/"
  api_request "GET" "/repositories/$uuid/commits/$commit_hash/"
}

# Получить diff коммита через API
api_get_commit_diff() {
  # TODO: Реализовать получение diff коммита через API
  # Параметры:
  #   $1 - UUID репозитория
  #   $2 - хеш коммита
  # Возвращает: diff в формате unified diff
  
  local uuid="$1"
  local commit_hash="$2"
  echo "[TODO] Вызвать API /api/repositories/$uuid/commits/$commit_hash/diff/"
  api_request "GET" "/repositories/$uuid/commits/$commit_hash/diff/"
}

# Получить статистику репозитория через API
api_get_stats() {
  local repo_uuid="$1"
  api_request "GET" "/repositories/$repo_uuid/stats/"
}

# Получить прогноз роста репозитория через API
api_get_forecast() {
  local repo_uuid="$1"
  local days="${2:-30}"
  api_request "GET" "/repositories/$repo_uuid/forecast/?days=$days"
}

# ============================================================================
# Локальные функции работы с репозиториями
# ============================================================================

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

# ============================================================================
# Функции для работы с содержимым проекта и коммитами
# ============================================================================

# Получить содержимое проекта (из API или backup.json)
get_project_content() {
  local repo_uuid="$1"
  local local_path="$2"
  
  # 1. Пробуем получить через API
  local api_response
  api_response="$(api_get_repo_files "$repo_uuid" 2>/dev/null)"
  if [[ $? -eq 0 ]] && [[ -n "$api_response" ]]; then
    echo "$api_response" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    result = {
        'source': 'api',
        'structure': data.get('structure', data.get('items', []))
    }
    print(json.dumps(result))
except:
    pass
" 2>/dev/null && return 0
  fi
  
  # 2. Пробуем получить из backup.json
  local backup_file="$local_path/.ergovcs/backup.json"
  if [[ -f "$backup_file" ]]; then
    cat "$backup_file" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    result = {
        'source': 'backup',
        'structure': data.get('structure', data.get('items', [])),
        'timestamp': data.get('timestamp', '')
    }
    print(json.dumps(result))
except:
    pass
" 2>/dev/null && return 0
  fi
  
  # 3. Создаем пустую структуру
  echo '{"source": "empty", "structure": []}'
}

# Автоматическое определение типа на основе изменений
get_commit_type() {
  local message="$1"
  local files_json="$2"
  
  # Проверяем, указан ли тип в сообщении (формат Conventional Commits)
  if [[ "$message" =~ ^([a-zA-Z]+)(\([^)]+\))?: ]]; then
    local commit_type="${BASH_REMATCH[1]}"
    local commit_types=("feat" "fix" "docs" "style" "refactor" "test" "chore" "perf" "ci" "build" "revert")
    
    for type in "${commit_types[@]}"; do
      if [[ "$commit_type" == "$type" ]]; then
        echo "$message"
        return 0
      fi
    done
  fi
  
  # Автоматическое определение типа на основе изменений
  echo "[INFO] Автоматическое определение типа коммита..." >&2
  
  # Используем Python для анализа файлов (поскольку bash неудобен для JSON)
  local new_message
  new_message=$(echo "$files_json" | python3 -c "
import json, sys, re

message = '''$message'''
message_lower = message.lower()

# Инициализируем флаги
has_build_files = False
has_source_files = False
has_docs_files = False
has_style_files = False
has_test_files = False
has_refactor_files = False
has_fix_files = False
has_feature_files = False

# Анализируем ключевые слова в сообщении
if any(word in message_lower for word in ['fix', 'bug', 'error', 'issue']):
    has_fix_files = True
if any(word in message_lower for word in ['feat', 'feature', 'add', 'new']):
    has_feature_files = True
if any(word in message_lower for word in ['refactor', 'restructure', 'cleanup']):
    has_refactor_files = True
if any(word in message_lower for word in ['test', 'spec', 'unit', 'integration']):
    has_test_files = True
if any(word in message_lower for word in ['doc', 'readme', 'comment']):
    has_docs_files = True

try:
    files = json.loads(sys.stdin.read())
    
    # Анализируем файлы
    for file in files:
        path = file.get('path', '').lower()
        action = file.get('action', '')
        
        # Проверяем файлы сборки
        if re.search(r'(package\.json|pom\.xml|build\.gradle|build\.xml|cmakelists\.txt|makefile|dockerfile|\.yml$|\.yaml$|\.json$|\.config$|\.ini$)', path):
            has_build_files = True
        
        # Проверяем исходные файлы
        if re.search(r'(\.py$|\.js$|\.ts$|\.java$|\.cpp$|\.cs$|\.php$|\.rb$|\.go$|\.rs$|\.swift$|\.kt$|\.scala$)', path):
            if action == 'created':
                has_feature_files = True
            if action == 'updated':
                has_refactor_files = True
        
        # Проверяем документацию
        if re.search(r'(readme\.md|readme\.txt|\.md$|\.rst$|docs?\/|\.txt$)', path):
            has_docs_files = True
        
        # Проверяем стили
        if re.search(r'(\.css$|\.scss$|\.less$|\.sass$|\.styl$|\.html$|\.vue$|\.jsx$|\.tsx$)', path):
            has_style_files = True
        
        # Проверяем тесты
        if re.search(r'(test|spec|__tests__|__spec__|\.test\.|\.spec\.)', path):
            has_test_files = True

except Exception as e:
    print(f'[DEBUG] Ошибка анализа файлов: {e}', file=sys.stderr)

# Определяем тип по приоритету
if has_fix_files:
    print(f'fix: {message}')
elif has_test_files:
    print(f'test: {message}')
elif has_feature_files:
    print(f'feat: {message}')
elif has_docs_files:
    print(f'docs: {message}')
elif has_style_files:
    print(f'style: {message}')
elif has_build_files:
    print(f'build: {message}')
elif has_refactor_files:
    print(f'refactor: {message}')
else:
    print(f'chore: {message}')
")
  
  echo "$new_message"
}

# Получить текущую ветку из конфига (как в Windows: локальный .ergovcs/repos.json, затем ~/.ergovcs/repos.json)
get_current_branch() {
  local local_path="$1"
  local branch=""
  local f

  for f in "$local_path/.ergovcs/repos.json" "$HOME/.ergovcs/repos.json"; do
    if [[ -f "$f" ]]; then
      branch="$(ERGOVCS_REPO_ROOT="$local_path" ERGOVCS_REPOS_FILE="$f" python3 -c "
import json, os
r = os.environ.get('ERGOVCS_REPO_ROOT', '')
p = os.environ.get('ERGOVCS_REPOS_FILE', '')
try:
    with open(p) as fp:
        d = json.load(fp)
    for k, v in (d.get('repositories') or {}).items():
        if isinstance(v, dict) and (v.get('local_path') or '') == r:
            print(v.get('current_branch') or 'main')
            break
except Exception:
    pass
" 2>/dev/null)"
      [[ -n "$branch" ]] && echo "$branch" && return 0
    fi
  done
  echo "main"
}

# ============================================================================
# Функции для работы со staging area
# ============================================================================

# Получить путь к файлу staging area
get_staging_file_path() {
  local repo_root
  repo_root="$(find_repository_root)"
  if [[ -z "$repo_root" ]]; then
    return 1
  fi
  
  local ergovcs_dir="$repo_root/.ergovcs"
  mkdir -p "$ergovcs_dir"
  echo "$ergovcs_dir/staging.json"
}

# Прочитать staging area
get_staging_area() {
  local staging_file
  staging_file="$(get_staging_file_path)"
  if [[ -z "$staging_file" ]] || [[ ! -f "$staging_file" ]]; then
    echo '{"repository_uuid": null, "files": [], "pending_commit": null}'
    return 0
  fi
  
  cat "$staging_file" 2>/dev/null || echo '{"repository_uuid": null, "files": [], "pending_commit": null}'
}

# Сохранить staging area
save_staging_area() {
  local staging_json="$1"
  local staging_file
  staging_file="$(get_staging_file_path)"
  
  if [[ -z "$staging_file" ]]; then
    echo "[ERROR] Не удалось определить путь к staging area. Убедитесь, что вы находитесь в репозитории." >&2
    return 1
  fi
  
  echo "$staging_json" > "$staging_file"
}

