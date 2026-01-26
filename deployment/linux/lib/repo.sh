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
api_create_commit() {
  # Параметры:
  #   $1 - UUID репозитория
  #   $2 - сообщение коммита
  #   $3 - список измененных файлов (JSON)
  # Возвращает: JSON с информацией о созданном коммите (hash, id, message, etc.)
  
  local uuid="$1"
  local message="$2"
  local files="${3:-}"
  
  local body
  if [[ -n "$files" ]]; then
    body="{\"message\": \"$message\", \"files\": $files}"
  else
    body="{\"message\": \"$message\"}"
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
# Функции для работы со staging area
# ============================================================================

# Найти корень репозитория (ищет .ergovcs/staging.json или .ergovcs/config.json вверх по дереву)
find_repository_root() {
  local start="$(pwd)"
  while [[ "$start" != "/" ]]; do
    local ergovcs_dir="$start/.ergovcs"
    local staging_file="$ergovcs_dir/staging.json"
    local config_file="$ergovcs_dir/config.json"
    
    if [[ -f "$staging_file" ]] || [[ -f "$config_file" ]]; then
      echo "$start"
      return 0
    fi
    start="$(dirname "$start")"
  done
  return 1
}

# Получить UUID текущего репозитория
get_current_repository_uuid() {
  local repo_root
  repo_root="$(find_repository_root)"
  if [[ -z "$repo_root" ]]; then
    return 1
  fi
  
  local staging_file="$repo_root/.ergovcs/staging.json"
  if [[ -f "$staging_file" ]]; then
    # Используем python или jq для парсинга JSON, если доступен
    if command -v python3 >/dev/null 2>&1; then
      local uuid
      uuid="$(python3 -c "import json, sys; data = json.load(open('$staging_file')); print(data.get('repository_uuid', ''))" 2>/dev/null)"
      if [[ -n "$uuid" ]]; then
        echo "$uuid"
        return 0
      fi
    elif command -v jq >/dev/null 2>&1; then
      local uuid
      uuid="$(jq -r '.repository_uuid // empty' "$staging_file" 2>/dev/null)"
      if [[ -n "$uuid" ]] && [[ "$uuid" != "null" ]]; then
        echo "$uuid"
        return 0
      fi
    else
      # Простой парсинг через grep (менее надежный)
      local uuid
      uuid="$(grep -o '"repository_uuid"[[:space:]]*:[[:space:]]*"[^"]*"' "$staging_file" 2>/dev/null | cut -d'"' -f4)"
      if [[ -n "$uuid" ]]; then
        echo "$uuid"
        return 0
      fi
    fi
  fi
  
  # Пробуем найти UUID из конфига репозиториев
  local repos_file="$HOME/.ergovcs/repos.json"
  if [[ -f "$repos_file" ]]; then
    if command -v python3 >/dev/null 2>&1; then
      local uuid
      uuid="$(python3 -c "
import json, sys
try:
    with open('$repos_file') as f:
        repos = json.load(f)
    for uuid, repo in repos.get('repositories', {}).items():
        if repo.get('local_path') == '$repo_root':
            print(uuid)
            sys.exit(0)
except:
    pass
" 2>/dev/null)"
      if [[ -n "$uuid" ]]; then
        echo "$uuid"
        return 0
      fi
    fi
  fi
  
  return 1
}

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

# Определить действие файла (added, modified, deleted)
get_file_action() {
  local file_path="$1"
  local repo_root="$2"
  
  local full_path
  if [[ "$file_path" == /* ]]; then
    full_path="$file_path"
  else
    full_path="$repo_root/$file_path"
  fi
  
  if [[ ! -e "$full_path" ]]; then
    echo "deleted"
    return 0
  fi
  
  # Проверяем, существует ли файл в репозитории на сервере
  # Для простоты считаем, что если файл существует локально, то он modified или added
  # Проверяем наличие файла в удаленном репозитории через API (если доступно)
  # Пока что используем эвристику: если файл в подпапках api/ или client/, то это новый файл
  # В будущем можно добавить проверку через API или локальный индекс
  
  local relative_path="${full_path#$repo_root/}"
  if [[ "$relative_path" == api/* ]] || [[ "$relative_path" == client/* ]]; then
    # Файлы в api/ или client/ считаем новыми (added)
    echo "added"
    return 0
  fi
  
  echo "modified"
}

