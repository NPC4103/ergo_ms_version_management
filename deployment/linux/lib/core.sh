#!/usr/bin/env bash
# Общие утилиты: поиск корня проекта, генерация UUID

PROJECT_ROOT=""
MEDIA_DIR=""
CLI_NAME="ergovcs"

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

cli_name() {
  echo "$CLI_NAME"
}

cli_path() {
  echo "/usr/local/bin/$(cli_name)"
}

# ============================================================================
# Функции для работы с путями и поиска репозиториев
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

# ============================================================================
# Функции для работы с хэшированием и содержимым файлов
# ============================================================================

# Получить MD5 хэш содержимого файла
get_file_content_hash() {
  local file_path="$1"
  
  if [[ ! -f "$file_path" ]]; then
    return 1
  fi
  
  if command -v md5sum >/dev/null 2>&1; then
    md5sum < "$file_path" | cut -d' ' -f1
  elif command -v md5 >/dev/null 2>&1; then
    md5 -q "$file_path"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "
import hashlib
with open('$file_path', 'rb') as f:
    print(hashlib.md5(f.read()).hexdigest())
"
  else
    echo "[ERROR] Не найдена утилита для вычисления MD5 (md5sum, md5 или python3)" >&2
    return 1
  fi
}

# Получить тип изменения файла
get_file_change_type() {
  local file_path="$1"
  local local_path="$2"
  local previous_state_json="$3"
  local is_directory_param="${4:-false}"
  
  local relative_path
  relative_path="$(realpath --relative-to="$local_path" "$file_path" 2>/dev/null || echo "${file_path#$local_path/}")"
  relative_path="${relative_path//\\//}"
  
  # Проверяем существование файла/директории
  local exists=false
  local is_directory=false
  if [[ -e "$file_path" ]]; then
    exists=true
    if [[ -d "$file_path" ]]; then
      is_directory=true
    else
      is_directory=false
    fi
  else
    # Если файл не существует, используем переданный параметр
    is_directory="$is_directory_param"
  fi
  
  # Ищем в предыдущем состоянии
  local previous_entry
  previous_entry="$(echo "$previous_state_json" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    structure = data.get('structure', [])
    relative_path = '${relative_path}'
    
    # Ищем по текущему пути
    for item in structure:
        if item.get('path') == relative_path:
            print(json.dumps(item))
            sys.exit(0)
    
    # Ищем по старому пути (для переименований)
    for item in structure:
        if item.get('old_path') == relative_path:
            print(json.dumps(item))
            sys.exit(0)
except:
    pass
" 2>/dev/null)"
  
  if [[ "$exists" == "true" ]]; then
    if [[ -z "$previous_entry" ]]; then
      # Новый файл/директория
      echo "created"
      return 0
    else
      # Проверяем переименование
      local prev_path
      prev_path="$(echo "$previous_entry" | python3 -c "import json, sys; print(json.load(sys.stdin).get('path', ''))" 2>/dev/null)"
      
      if [[ "$prev_path" != "$relative_path" ]]; then
        echo "renamed"
        return 0
      fi
      
      # Для файлов проверяем хеш содержимого
      if [[ "$is_directory" == "false" ]]; then
        local current_hash
        current_hash="$(get_file_content_hash "$file_path")"
        local prev_hash
        prev_hash="$(echo "$previous_entry" | python3 -c "import json, sys; print(json.load(sys.stdin).get('hash', ''))" 2>/dev/null)"
        
        if [[ -n "$current_hash" && -n "$prev_hash" && "$current_hash" != "$prev_hash" ]]; then
          echo "updated"
          return 0
        fi
      fi
      
      # Нет изменений
      echo "unchanged"
      return 0
    fi
  else
    if [[ -n "$previous_entry" ]]; then
      # Файл/директория удален
      echo "deleted"
      return 0
    fi
    # Ничего не было и ничего нет
    echo "unchanged"
    return 0
  fi
}

# ============================================================================
# Функции для работы с игнорированием файлов
# ============================================================================

# Проверить, игнорируется ли файл
test_ignored() {
  local file_path="$1"
  local ignore_patterns_json="$2"
  
  # Всегда игнорируем .ergovcs
  if [[ "$file_path" == .ergovcs/* ]] || [[ "$file_path" == .ergovcs ]]; then
    return 0
  fi
  
  # Нормализуем путь (заменяем обратные слеши на прямые)
  local normalized_path="${file_path//\\//}"
  
  # Проверяем паттерны через Python для надежности
  echo "$ignore_patterns_json" | python3 -c "
import json, sys, re, os

file_path = '${normalized_path}'
patterns_json = sys.stdin.read()

try:
    patterns = json.loads(patterns_json)
    if not isinstance(patterns, list):
        patterns = []
except:
    patterns = []

for pattern in patterns:
    if not pattern or not isinstance(pattern, str):
        continue
    
    pattern = pattern.strip()
    if not pattern or pattern.startswith('#'):
        continue
    
    # Специальная обработка паттерна '.*'
    if pattern == '.*':
        file_name = os.path.basename(file_path)
        if file_name.startswith('.'):
            sys.exit(0)
        continue
    
    # Специальная обработка паттерна '*/.*'
    if pattern == '*/.*':
        path_segments = file_path.split('/')
        for segment in path_segments:
            if segment.startswith('.'):
                sys.exit(0)
        continue
    
    # Преобразуем glob-паттерны в regex
    regex_pattern = re.escape(pattern)
    regex_pattern = regex_pattern.replace('\\*', '.*').replace('\\?', '.')
    
    # Если паттерн начинается с /, он должен соответствовать началу пути
    if pattern.startswith('/'):
        regex_pattern = '^' + regex_pattern[1:]
    elif '/' in pattern:
        regex_pattern = '(^|/)' + regex_pattern
    else:
        regex_pattern = regex_pattern
    
    # Добавляем завершение для полного совпадения (если не заканчивается на *)
    if not regex_pattern.endswith('.*'):
        regex_pattern = regex_pattern + '\$'
    
    # Проверяем соответствие
    if re.match(regex_pattern, file_path):
        sys.exit(0)
    
    # Дополнительная проверка для директорий
    if file_path.startswith(pattern + '/'):
        sys.exit(0)

sys.exit(1)
" 2>/dev/null
  
  return $?
}

# Получить все элементы репозитория с учетом игнорирования
get_all_items() {
  local path="$1"
  local repo_root="$2"
  local ignore_patterns_json="$3"
  
  local items_json
  items_json="$(python3 -c "
import os, json

def get_items(current_path, repo_root, ignore_patterns_json):
    items = []
    
    try:
        ignore_patterns = json.loads(ignore_patterns_json)
    except:
        ignore_patterns = []
    
    normalized_repo_root = os.path.normpath(repo_root).replace('\\\\', '/')
    normalized_path = os.path.normpath(current_path).replace('\\\\', '/')
    
    # Добавляем саму директорию (если это не корень репозитория)
    if normalized_path != normalized_repo_root:
        try:
            relative_path = os.path.relpath(normalized_path, normalized_repo_root).replace('\\\\', '/')
            # Проверяем игнорирование через test_ignored
            # Для простоты добавляем, проверка будет в основной функции
            items.append(relative_path)
        except:
            pass
    
    # Получаем дочерние элементы
    try:
        for item_name in os.listdir(current_path):
            if item_name == '.ergovcs':
                continue
            
            item_path = os.path.join(current_path, item_name)
            try:
                relative_path = os.path.relpath(item_path, normalized_repo_root).replace('\\\\', '/')
                
                # Проверяем игнорирование
                normalized_relative = relative_path.replace('\\\\', '/')
                should_ignore = False
                
                for pattern in ignore_patterns:
                    if not pattern or not isinstance(pattern, str):
                        continue
                    pattern = pattern.strip()
                    if not pattern or pattern.startswith('#'):
                        continue
                    
                    if pattern == '.*':
                        if item_name.startswith('.'):
                            should_ignore = True
                            break
                        continue
                    
                    if pattern == '*/.*':
                        path_segments = normalized_relative.split('/')
                        for segment in path_segments:
                            if segment.startswith('.'):
                                should_ignore = True
                                break
                        if should_ignore:
                            break
                        continue
                    
                    import re
                    regex_pattern = re.escape(pattern)
                    regex_pattern = regex_pattern.replace('\\*', '.*').replace('\\?', '.')
                    
                    if pattern.startswith('/'):
                        regex_pattern = '^' + regex_pattern[1:]
                    elif '/' in pattern:
                        regex_pattern = '(^|/)' + regex_pattern
                    
                    if not regex_pattern.endswith('.*'):
                        regex_pattern = regex_pattern + '\$'
                    
                    if re.match(regex_pattern, normalized_relative):
                        should_ignore = True
                        break
                    
                    if normalized_relative.startswith(pattern + '/'):
                        should_ignore = True
                        break
                
                if not should_ignore:
                    items.append(relative_path)
                    
                    # Рекурсивно обрабатываем директории
                    if os.path.isdir(item_path):
                        sub_items = get_items(item_path, repo_root, ignore_patterns_json)
                        items.extend(sub_items)
            except:
                pass
    except:
        pass
    
    return items

items = get_items('${path}', '${repo_root}', '''${ignore_patterns_json}''')
print(json.dumps(items))
" 2>/dev/null)"
  
  echo "$items_json"
}

