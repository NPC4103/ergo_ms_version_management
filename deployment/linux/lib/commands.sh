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
  # TODO: Реализовать добавление файла для коммита
  # 1. Получить путь к файлу из аргументов
  # 2. Проверить, что файл существует
  # 3. Добавить файл в staging area (локально)
  # 4. При следующем commit эти изменения будут отправлены на сервер
  
  local file_path=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      *) file_path="$1" ;;
    esac
    shift || true
  done
  
  if [[ -z "$file_path" ]]; then
    echo "[ERROR] Необходимо указать путь к файлу" >&2
    echo "Использование: ergovcs add <файл.расширение>" >&2
    exit 1
  fi
  
  # TODO: Реализовать добавление файла в staging area
  echo "[INFO] Добавление файла $file_path для коммита..."
  echo "[TODO] Проверить существование файла"
  echo "[TODO] Добавить файл в staging area"
}

# ============================================================================
# Создание коммита
# Команда: ergovcs commit -m "Сообщение"
# Создаёт коммит с изменениями в папке media/version_management/<UUID>/
# ============================================================================
cmd_commit() {
  # TODO: Реализовать создание коммита
  # 1. Получить сообщение коммита из аргумента -m
  # 2. Получить UUID текущего репозитория (из конфига или рабочей директории)
  # 3. Собрать все изменения из staging area
  # 4. Вызвать API эндпоинт /api/repositories/{id}/commits/create/
  # 5. После повторного добавления (add), не создаётся новый коммит,
  #    а добавляются изменения в существующий, до тех пор пока коммит не отправлен на сервер
  
  local message=""
  local uuid=""
  
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
  
  # TODO: Реализовать создание коммита
  echo "[INFO] Создание коммита с сообщением: $message"
  echo "[TODO] Получить UUID текущего репозитория"
  echo "[TODO] Собрать изменения из staging area"
  echo "[TODO] Вызвать API /api/repositories/{id}/commits/create/"
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

