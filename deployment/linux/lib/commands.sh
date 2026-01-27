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
  # 1. Определить корень репозитория
  local repo_root
  repo_root="$(find_repository_root)"
  if [[ -z "$repo_root" ]]; then
    echo "[ERROR] Не удалось определить корень репозитория." >&2
    exit 1
  fi
  
  # 2. Получить UUID репозитория
  local uuid
  uuid="$(get_current_repository_uuid)"
  if [[ -z "$uuid" ]]; then
    echo "[ERROR] Не удалось определить UUID репозитория." >&2
    exit 1
  fi
  
  # 3. Получить предыдущее состояние проекта
  local previous_state_json
  previous_state_json="$(get_project_content "$uuid" "$repo_root")"
  
  # 4. Загрузить правила игнорирования
  local ignore_patterns_array=()
  local ergovcs_ignore_path="$repo_root/.ergovcsignore"
  if [[ -f "$ergovcs_ignore_path" ]]; then
    while IFS= read -r line; do
      line="${line%%#*}"  # Удаляем комментарии
      line="${line// /}"  # Удаляем пробелы
      if [[ -n "$line" ]]; then
        ignore_patterns_array+=("$line")
      fi
    done < "$ergovcs_ignore_path"
  fi
  
  # Добавляем стандартные паттерны игнорирования (файлы/директории, начинающиеся с точки)
  ignore_patterns_array+=(".*")
  ignore_patterns_array+=("*/.*")
  
  # Преобразуем массив в JSON для передачи в функции
  local ignore_patterns_json
  ignore_patterns_json="$(printf '%s\n' "${ignore_patterns_array[@]}" | python3 -c "import json, sys; print(json.dumps([line.strip() for line in sys.stdin if line.strip()]))")"
  
  # 5. Если аргументы не переданы, сканируем всю директорию
  local files_to_add=()
  if [[ $# -eq 0 ]]; then
    echo "[INFO] Сканирую все файлы и директории (исключая игнорируемые)..." >&2
    
    # Используем улучшенную функцию с фильтрацией
    local all_items_json
    all_items_json="$(get_all_items "$repo_root" "$repo_root" "$ignore_patterns_json")"
    
    # Исключаем .ergovcs директорию из сканирования
    local all_items
    all_items="$(echo "$all_items_json" | python3 -c "
import json, sys
items = json.load(sys.stdin)
filtered = [item for item in items if '.ergovcs' not in item]
print(json.dumps(filtered))
")"
    
    # Преобразуем JSON в массив путей
    files_to_add=($(echo "$all_items" | python3 -c "import json, sys; items = json.load(sys.stdin); print(' '.join(items))"))
    
    if [[ ${#files_to_add[@]} -eq 0 ]]; then
      echo "[INFO] Нет файлов для добавления (все файлы игнорируются или отсутствуют)." >&2
      exit 0
    fi
    
    echo "[INFO] Найдено элементов: ${#files_to_add[@]}" >&2
  else
    # Используем переданные аргументы
    files_to_add=("$@")
  fi
  
  # 6. Создать директорию .ergovcs
  local ergovcs_path="$repo_root/.ergovcs"
  mkdir -p "$ergovcs_path"
  
  # 7. Прочитать текущий staging area
  local staging_file="$ergovcs_path/staging.json"
  local staging_json
  staging_json="$(get_staging_area)"
  
  # Инициализируем структуру staging, если её нет
  staging_json="$(echo "$staging_json" | python3 -c "
import json, sys
try:
    staging = json.load(sys.stdin)
except:
    staging = {}
if 'repository_uuid' not in staging:
    staging['repository_uuid'] = '${uuid}'
if 'files' not in staging:
    staging['files'] = []
print(json.dumps(staging))
")"
  
  # 8. Обработать каждый файл/директорию
  local added_items=()
  local ignored_items=()
  local errors=()
  
  for item in "${files_to_add[@]}"; do
    if [[ -z "$item" ]]; then
      continue
    fi
    
    # Определяем полный путь
    local full_path
    if [[ "$item" == /* ]]; then
      full_path="$item"
    else
      full_path="$(realpath "$item" 2>/dev/null || echo "$(pwd)/$item")"
    fi
    
    # Получаем относительный путь
    local relative_path
    relative_path="$(realpath --relative-to="$repo_root" "$full_path" 2>/dev/null || echo "${full_path#$repo_root/}")"
    relative_path="${relative_path//\\//}"
    
    # Проверяем игнорирование
    if test_ignored "$relative_path" "$ignore_patterns_json"; then
      ignored_items+=("$relative_path")
      echo "[IGNORE] Игнорировано: $relative_path" >&2
      continue
    fi
    
    # Проверяем существование
    local exists=false
    local is_directory=false
    if [[ -e "$full_path" ]]; then
      exists=true
      if [[ -d "$full_path" ]]; then
        is_directory=true
      fi
    fi
    
    # Определяем тип изменения
    local action
    action="$(get_file_change_type "$full_path" "$repo_root" "$previous_state_json" "$is_directory")"
    
    if [[ "$action" == "unchanged" ]]; then
      continue
    fi
    
    # Обновляем staging area через Python
    staging_json="$(echo "$staging_json" | python3 - <<PYTHON
import json, sys, os
from datetime import datetime

try:
    staging = json.load(sys.stdin)
    relative_path = '${relative_path}'
    action = '${action}'
    is_directory = ${is_directory}
    full_path = '${full_path}'
    exists = ${exists}
    
    # Проверяем, не добавлен ли уже в staging
    item_index = -1
    for j, f in enumerate(staging['files']):
        if f.get('path') == relative_path:
            item_index = j
            break
    
    # Создаем запись
    item_entry = {
        'path': relative_path,
        'action': action,
        'is_directory': is_directory,
        'timestamp': datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
    }
    
    # Добавляем дополнительные данные в зависимости от типа изменения
    if action == 'created':
        if not is_directory and exists:
            try:
                with open(full_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                item_entry['content'] = content
                import hashlib
                item_entry['hash'] = hashlib.md5(content.encode('utf-8')).hexdigest()
            except Exception as e:
                pass
    elif action == 'updated':
        if not is_directory and exists:
            try:
                with open(full_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                item_entry['content'] = content
                import hashlib
                item_entry['hash'] = hashlib.md5(content.encode('utf-8')).hexdigest()
                
                # Добавляем старый хеш, если есть
                import json as json_module
                previous_state = json_module.loads('''${previous_state_json}''')
                previous_entry = None
                for entry in previous_state.get('structure', []):
                    if entry.get('path') == relative_path:
                        previous_entry = entry
                        break
                if previous_entry and previous_entry.get('hash'):
                    item_entry['old_hash'] = previous_entry['hash']
            except Exception as e:
                pass
    elif action == 'renamed':
        # Ищем старый путь в предыдущем состоянии
        import json as json_module
        previous_state = json_module.loads('''${previous_state_json}''')
        previous_entry = None
        for entry in previous_state.get('structure', []):
            if entry.get('path') != relative_path and (entry.get('old_path') == relative_path or entry.get('path') == relative_path):
                previous_entry = entry
                break
        if previous_entry:
            item_entry['old_path'] = previous_entry.get('path')
            item_entry['hash'] = previous_entry.get('hash')
    elif action == 'deleted':
        # Для удаленных файлов получаем информацию из предыдущего состояния
        import json as json_module
        previous_state = json_module.loads('''${previous_state_json}''')
        previous_entry = None
        for entry in previous_state.get('structure', []):
            if entry.get('path') == relative_path:
                previous_entry = entry
                break
        if previous_entry:
            item_entry['is_directory'] = previous_entry.get('is_directory', False)
            item_entry['hash'] = previous_entry.get('hash')
    
    # Обновляем или добавляем запись
    if item_index >= 0:
        staging['files'][item_index] = item_entry
    else:
        staging['files'].append(item_entry)
    
    print(json.dumps(staging, ensure_ascii=False))
except Exception as e:
    print(f"[ERROR] Ошибка при обновлении staging area: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON
)"
    
    if [[ $? -ne 0 ]]; then
      errors+=("$item")
      continue
    fi
    
    added_items+=("$relative_path|$action|$is_directory")
    echo "[OK] Добавлено: $relative_path ($action)" >&2
  done
  
  # 9. Сохранить staging area
  if ! save_staging_area "$staging_json"; then
    echo "[ERROR] Не удалось сохранить staging area" >&2
    exit 1
  fi
  
  # Выводим статистику
  if [[ ${#added_items[@]} -gt 0 ]]; then
    echo ""
    echo "[OK] Статистика добавленных изменений:" >&2
    
    # Группируем по действиям
    local created_count=0 created_files=0 created_dirs=0
    local updated_count=0 updated_files=0 updated_dirs=0
    local deleted_count=0 deleted_files=0 deleted_dirs=0
    local renamed_count=0 renamed_files=0 renamed_dirs=0
    
    for item_info in "${added_items[@]}"; do
      IFS='|' read -r path action is_dir <<< "$item_info"
      case "$action" in
        created)
          ((created_count++))
          if [[ "$is_dir" == "true" ]]; then
            ((created_dirs++))
          else
            ((created_files++))
          fi
          ;;
        updated)
          ((updated_count++))
          if [[ "$is_dir" == "true" ]]; then
            ((updated_dirs++))
          else
            ((updated_files++))
          fi
          ;;
        deleted)
          ((deleted_count++))
          if [[ "$is_dir" == "true" ]]; then
            ((deleted_dirs++))
          else
            ((deleted_files++))
          fi
          ;;
        renamed)
          ((renamed_count++))
          if [[ "$is_dir" == "true" ]]; then
            ((renamed_dirs++))
          else
            ((renamed_files++))
          fi
          ;;
      esac
    done
    
    if [[ $created_count -gt 0 ]]; then
      echo "  created: $created_count" >&2
      if [[ $created_files -gt 0 ]]; then
        echo "    Файлов: $created_files" >&2
      fi
      if [[ $created_dirs -gt 0 ]]; then
        echo "    Директорий: $created_dirs" >&2
      fi
    fi
    
    if [[ $updated_count -gt 0 ]]; then
      echo "  updated: $updated_count" >&2
      if [[ $updated_files -gt 0 ]]; then
        echo "    Файлов: $updated_files" >&2
      fi
      if [[ $updated_dirs -gt 0 ]]; then
        echo "    Директорий: $updated_dirs" >&2
      fi
    fi
    
    if [[ $deleted_count -gt 0 ]]; then
      echo "  deleted: $deleted_count" >&2
      if [[ $deleted_files -gt 0 ]]; then
        echo "    Файлов: $deleted_files" >&2
      fi
      if [[ $deleted_dirs -gt 0 ]]; then
        echo "    Директорий: $deleted_dirs" >&2
      fi
    fi
    
    if [[ $renamed_count -gt 0 ]]; then
      echo "  renamed: $renamed_count" >&2
      if [[ $renamed_files -gt 0 ]]; then
        echo "    Файлов: $renamed_files" >&2
      fi
      if [[ $renamed_dirs -gt 0 ]]; then
        echo "    Директорий: $renamed_dirs" >&2
      fi
    fi
  fi
  
  if [[ ${#ignored_items[@]} -gt 0 ]]; then
    echo ""
    echo "[INFO] Проигнорировано: ${#ignored_items[@]}" >&2
  fi
  
  if [[ ${#errors[@]} -gt 0 ]]; then
    echo ""
    echo "[ERROR] Ошибки при обработке: ${#errors[@]}" >&2
    exit 1
  fi
}

# ============================================================================
# Создание коммита
# Команда: ergovcs commit --message "Сообщение" [--update-changes] [--edit-message]
# Создаёт коммит с изменениями
# ============================================================================
cmd_commit() {
  # 1. Парсинг аргументов
  local message=""
  local update_changes=false
  local edit_message=false
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--message)
        shift
        message="${1:-}"
        ;;
      -uc|--update-changes)
        update_changes=true
        ;;
      -em|--edit-message)
        edit_message=true
        # Проверяем, есть ли следующее значение для сообщения
        if [[ $# -gt 1 ]] && [[ ! "$2" =~ ^- ]]; then
          shift
          message="$1"
        fi
        ;;
      *)
        if [[ -z "$message" ]] && [[ ! "$1" =~ ^- ]]; then
          message="$1"
        fi
        ;;
    esac
    shift || true
  done
  
  # Валидация опций
  if [[ "$update_changes" == "true" ]] && [[ "$edit_message" == "true" ]]; then
    echo "[ERROR] Опции --update-changes и --edit-message не могут использоваться вместе." >&2
    exit 1
  fi
  
  # 2. Определить корень репозитория
  local repo_root
  repo_root="$(find_repository_root)"
  if [[ -z "$repo_root" ]]; then
    echo "[ERROR] Не удалось найти репозиторий." >&2
    exit 1
  fi
  
  # 3. Получить UUID текущего репозитория
  local uuid
  uuid="$(get_current_repository_uuid)"
  if [[ -z "$uuid" ]]; then
    echo "[ERROR] Не удалось определить UUID репозитория." >&2
    exit 1
  fi
  
  # 4. Прочитать staging area
  local staging_file="$repo_root/.ergovcs/staging.json"
  if [[ ! -f "$staging_file" ]]; then
    echo "[ERROR] Staging area не найден." >&2
    exit 1
  fi
  
  local staging_json
  staging_json="$(get_staging_area)"
  
  # 5. Проверить, есть ли файлы в staging area
  local files_count
  files_count="$(echo "$staging_json" | python3 -c "import json, sys; data = json.load(sys.stdin); print(len(data.get('files', [])))" 2>/dev/null)"
  if [[ -z "$files_count" ]] || [[ "$files_count" -eq 0 ]]; then
    if [[ "$edit_message" != "true" ]]; then
      echo "[ERROR] Нет файлов в staging area." >&2
      exit 1
    fi
  fi
  
  # 6. Получить автора коммита
  local author
  author="$(get_commit_author)"
  echo "[INFO] Автор коммита: $author" >&2
  
  # 7. Определить тип коммита
  local files_json
  files_json="$(echo "$staging_json" | python3 -c "import json, sys; data = json.load(sys.stdin); print(json.dumps(data.get('files', [])))" 2>/dev/null)"
  local commit_type
  commit_type="$(get_commit_type "$files_json" "$message")"
  
  # 8. Запросить сообщение, если оно не указано
  if [[ -z "$message" ]] && [[ "$update_changes" != "true" ]]; then
    echo "[INFO] Введите сообщение коммита:" >&2
    read -r message
    
    if [[ -z "$message" ]]; then
      echo "[ERROR] Сообщение коммита не может быть пустым." >&2
      exit 1
    fi
  fi
  
  # Добавляем тип к сообщению, если его там нет
  local commit_types=("feat" "fix" "docs" "style" "refactor" "test" "chore" "perf" "ci" "build" "revert")
  local has_type=false
  
  if echo "$message" | grep -qE '^(\w+):'; then
    local type_in_message
    type_in_message="$(echo "$message" | sed -E 's/^(\w+):.*/\1/')"
    for ct in "${commit_types[@]}"; do
      if [[ "$type_in_message" == "$ct" ]]; then
        has_type=true
        break
      fi
    done
  fi
  
  if [[ "$has_type" == "false" ]]; then
    message="$commit_type: $message"
    echo "[INFO] Автоматически определен тип коммита: $commit_type" >&2
  fi
  
  # 9. Классификация изменений
  local action_stats_json
  action_stats_json="$(echo "$files_json" | python3 -c "
import json, sys
files = json.load(sys.stdin)
stats = {
    'created': {'count': 0, 'files': 0, 'dirs': 0},
    'updated': {'count': 0, 'files': 0, 'dirs': 0},
    'deleted': {'count': 0, 'files': 0, 'dirs': 0},
    'renamed': {'count': 0, 'files': 0, 'dirs': 0}
}

for file in files:
    action = file.get('action', '')
    is_dir = file.get('is_directory', False)
    if action in stats:
        stats[action]['count'] += 1
        if is_dir:
            stats[action]['dirs'] += 1
        else:
            stats[action]['files'] += 1

print(json.dumps(stats))
")"
  
  local change_summary
  change_summary="$(echo "$action_stats_json" | python3 -c "
import json, sys
stats = json.load(sys.stdin)
summary_parts = []

for action in ['created', 'updated', 'deleted', 'renamed']:
    if stats[action]['count'] > 0:
        summary = f\"{stats[action]['count']} {action}\"
        if stats[action]['files'] > 0:
            summary += f\" ({stats[action]['files']} файлов\"
            if stats[action]['dirs'] > 0:
                summary += f\", {stats[action]['dirs']} директорий\"
            summary += \")\"
        elif stats[action]['dirs'] > 0:
            summary += f\" ({stats[action]['dirs']} директорий)\"
        summary_parts.append(summary)

print(', '.join(summary_parts) if summary_parts else 'нет изменений')
")"
  
  # 10. Обработка файла commit.json
  local commit_file="$repo_root/.ergovcs/commit.json"
  local existing_commit_json=""
  
  if [[ -f "$commit_file" ]]; then
    existing_commit_json="$(cat "$commit_file" 2>/dev/null)"
  fi
  
  # 11. Создание/обновление коммита
  local commit_json
  commit_json="$(python3 - <<PYTHON
import json, sys
from datetime import datetime

uuid = '${uuid}'
message = '''${message}'''
author = '${author}'
commit_type = '${commit_type}'
files_json = '''${files_json}'''
action_stats_json = '''${action_stats_json}'''
change_summary = '''${change_summary}'''
existing_commit_json = '''${existing_commit_json}'''
update_changes = ${update_changes}
edit_message = ${edit_message}

try:
    files = json.loads(files_json)
    action_stats = json.loads(action_stats_json)
except:
    files = []
    action_stats = {'created': {'count': 0}, 'updated': {'count': 0}, 'deleted': {'count': 0}, 'renamed': {'count': 0}}

commit = {
    'repository_uuid': uuid,
    'message': message,
    'author': author,
    'type': commit_type,
    'created_at': datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    'files': files,
    'change_summary': change_summary,
    'stats': action_stats
}

if edit_message or update_changes:
    if not existing_commit_json:
        print('[ERROR] Не существует коммита для редактирования.', file=sys.stderr)
        sys.exit(1)
    
    try:
        existing_commit = json.loads(existing_commit_json)
    except:
        print('[ERROR] Не удалось прочитать существующий коммит.', file=sys.stderr)
        sys.exit(1)
    
    # Сохраняем исходную дату создания
    commit['created_at'] = existing_commit.get('created_at', commit['created_at'])
    
    if edit_message:
        # Обновляем только сообщение
        commit['files'] = existing_commit.get('files', [])
        commit['change_summary'] = existing_commit.get('change_summary', '')
        commit['stats'] = existing_commit.get('stats', {})
    elif update_changes:
        # Обновляем только файлы
        commit['message'] = existing_commit.get('message', message)
        commit['type'] = existing_commit.get('type', commit_type)
        commit['files'] = files

print(json.dumps(commit, ensure_ascii=False))
PYTHON
)"
  
  if [[ $? -ne 0 ]]; then
    echo "[ERROR] Не удалось создать коммит" >&2
    exit 1
  fi
  
  # 12. Сохранить коммит в файл commit.json
  echo "$commit_json" > "$commit_file"
  
  echo ""
  echo "[OK] Коммит создан локально." >&2
  
  local commit_message commit_type_display commit_author commit_summary
  commit_message="$(echo "$commit_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('message', ''))")"
  commit_type_display="$(echo "$commit_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('type', ''))")"
  commit_author="$(echo "$commit_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('author', ''))")"
  commit_summary="$(echo "$commit_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('change_summary', ''))")"
  
  echo "Тип: $commit_type_display" >&2
  echo "Сообщение: $commit_message" >&2
  echo "Автор: $commit_author" >&2
  echo "Изменения: $commit_summary" >&2
  
  # 13. Очистить staging area (только если не редактируем сообщение)
  if [[ "$edit_message" != "true" ]]; then
    local empty_staging_json
    empty_staging_json="$(python3 -c "
import json
print(json.dumps({
    'repository_uuid': '${uuid}',
    'files': []
}))
")"
    echo "$empty_staging_json" > "$staging_file"
    echo "[INFO] Staging area очищен." >&2
  else
    echo "[INFO] Staging area сохранен для возможных изменений." >&2
  fi
  
  echo "[INFO] Используйте команду 'push' для отправки коммита на сервер." >&2
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

# ============================================================================
# Древо файлов репозитория
# Команда: ergovcs files --repo <UUID>
# ============================================================================
cmd_files() {
  local repo_uuid=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) shift; repo_uuid="${1:-}" ;;
      *) echo "[WARN] Неизвестный параметр: $1" >&2 ;;
    esac
    shift || true
  done

  if [[ -z "$repo_uuid" ]]; then
    echo "[ERROR] Нужно указать --repo <UUID>" >&2
    exit 1
  fi

  local response
  response="$(api_get_repo_files "$repo_uuid")" || exit 1

  echo "$response" | python3 - <<'PY'
import json, sys

def render(items, prefix=""):
    for i, item in enumerate(items):
        is_last = (i == len(items) - 1)
        connector = "└── " if is_last else "├── "
        name = item.get("name", "")
        if item.get("is_directory"):
            print(f"{prefix}{connector}{name}/")
            render(item.get("items") or [], prefix + ("    " if is_last else "│   "))
        else:
            print(f"{prefix}{connector}{name}")

data = json.load(sys.stdin)
root_items = data.get("structure") or data.get("items") or []
render(root_items)
PY
}
