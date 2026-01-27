# Утилита ergovcs (version_management)

Утилита для управления репозиториями в модуле version_management. Работает на Linux и Windows. Интегрирована с API бэкенда для синхронизации репозиториев.

## Основные команды работы с репозиториями

### 1. **clone** `<UUID>` — клонировать репозиторий
   - Копирует репозиторий из `media/version_management/<UUID>/` на локальный компьютер
   - ??? ???????? ????? ??????????? ??????????? ?????? ???????????? ????? API ? ????? public_id
   - Сохраняет информацию о клонированном репозитории в конфиг

### 2. **add** `<файл.расширение>` — добавить файл для коммита
   - Добавляет файл в staging area (локально)
   - После команды `commit` изменения будут отправлены на сервер
   - Поддерживает относительные и абсолютные пути

### 3. **commit** `-m "Сообщение"` — создать коммит
   - Создаёт коммит с изменениями из staging area
   - Вызывает API: `/api/repositories/{id}/commits/create/`
   - **Важно:** После повторного `add` не создаётся новый коммит, а добавляются изменения в существующий, до тех пор пока коммит не отправлен на сервер

### 4. **push** `<ветка>` — отправить изменения на сервер
   - Отправляет изменения в папку `media/version_management/<UUID>/`
   - Вызывает API: `/api/repositories/{id}/push/`
   - Обновляет статус коммита (отмечен как отправленный)

### 5. **update** `<ветка>` — обновить локальный репозиторий
   - Подтягивает изменения с сервера на локальный компьютер
   - Вызывает API: `/api/repositories/{id}/update/`
   - Примечание: не важно какая ветка скачана у пользователя

### 6. **remove** `<UUID>` — удалить локальную копию
   - Удаляет локальную копию репозитория с компьютера пользователя
   - Примечание: удаляет только локальную копию, не репозиторий на сервере

## Вспомогательные команды

### 7. **create** ? ??????? ????? ??????????? ????? API
   - ???????? API: `/api/repositories/`
   - ???????????? UUID ?? ???????
   - ????????? ????????? ? `media/version_management/<UUID>/` ?? ??????? (?????, README, .repo_info.json)
   - ??????? ????????? ????? `.ergovcs/config.json`, `.ergovcsignore`, `README.md`
   - **??????????:** ????????? ?????????? API ?????? ? ??????? ?????? ??? CLI

### 8. **download** ? ??????? ????????? ???????????
 **download** — скачать сторонний репозиторий
   - Принимает путь к zip-архиву или папке
   - Распаковывает в `media/version_management/<UUID>/`

## Установка и использование

### Linux

```bash
# Один раз сделать обёртку исполняемой (если нужно)
chmod +x ergovcs
chmod +x linux/version_manager.sh

# (опционально) установить CLI-обёртку в /usr/local/bin (нужны права sudo)
sudo ./linux/version_manager.sh install-cli

# (опционально) добавить каталог утилиты в PATH
export PATH="$PATH:/path/to/ergo_ms_core/modules/version_management/deployment"

# Основные команды (через ergovcs)
ergovcs clone abc-123-def-456
ergovcs add src/main.py
ergovcs commit -m "Добавлен новый функционал"
ergovcs push main
ergovcs update main
ergovcs remove abc-123-def-456

# Вспомогательные команды
ergovcs create --name "Мой репозиторий"
ergovcs download --source /path/to/repo.zip --uuid <uuid>
```

### Windows

```powershell
# (опционально) добавить каталог утилиты в PATH для текущей сессии
$env:PATH += ";C:\Users\user\Project\ergo_ms_core\modules\version_management\deployment"

# (опционально) установить CLI-обёртку в System32 (нужны права администратора)
powershell -ExecutionPolicy Bypass -File .\windows\version_manager.ps1 install-cli

# Основные команды (через ergovcs)
ergovcs clone abc-123-def-456
ergovcs add src\main.py
ergovcs commit -m "Добавлен новый функционал"
ergovcs push main
ergovcs update main
ergovcs remove abc-123-def-456

# Вспомогательные команды
ergovcs create --name "Мой репозиторий"
ergovcs download --source "C:\path\to\repo.zip" --uuid <uuid>
```

## Параметры команд

### clone
- `<UUID>` — UUID репозитория для клонирования (обязательный)

### add
- `<файл.расширение>` — путь к файлу для добавления в staging area (обязательный)

### commit
- `-m "Сообщение"` или `--message "Сообщение"` — сообщение коммита (обязательное)

### push
- `<ветка>` — название ветки для отправки изменений (обязательный)

### update
- `<ветка>` — название ветки для обновления (обязательный)

### remove
- `<UUID>` — UUID репозитория для удаления локальной копии (обязательный)

### create
- `--name <???>` ? ???????? ??????????? (???? ?? ???????, ????????????? ????????????)
- `--description <?????>` ? ???????? ???????????
- `--branch <?????>` ? ??? ????????? ????? (?? ????????? `main`)
- `--private` ? ????????? ???????????
- `--read-only` ? ??????????? ?????? ??? ??????
- `--username <u>` ? `--password <p>` ? ??????? ?????? ??? CLI (???????????, ???? ?? ???????????? web-??????????????)
- `--root <????>` ? ????????? ??????????, ??? ????? ??????? `.ergovcs` ? README
- **??????????:** ??????? ???????? ????? API, ??????? ?????????? ??????

### download

- `--source <zip|dir>` — путь к zip-архиву или папке с репозиторием (обязательный)
- `--uuid <uuid>` — UUID для репозитория (если не указан, генерируется автоматически)
- `--name <имя>` — название репозитория (опционально, сохраняется в manifest.json)
- `--root <путь>` — указать корень проекта вручную (по умолчанию определяется автоматически)

## Структура репозитория

После создания или скачивания репозитория в `media/version_management/<UUID>/` будет следующая структура:

```
<UUID>/
  ├── api/
  ├── client/
  └── manifest.json
```

Файл `manifest.json` содержит метаданные:
```json
{
  "uuid": "<uuid>",
  "name": "Название репозитория",
  "description": "Описание"
}
```

## Конфигурация API

Утилита работает с API бэкенда. Настройка базового URL API:

### Через переменные окружения

**Linux:**
```bash
export API_BASE_URL="http://localhost:8000/api/version_management"
# или
export API_HOST="localhost"
export API_PORT="8000"
```

**Windows:**
```powershell
$env:API_BASE_URL = "http://localhost:8000/api/version_management"
# или
$env:API_HOST = "localhost"
$env:API_PORT = "8000"
```

### Через конфиг файл

**Linux:**
```bash
mkdir -p ~/.ergovcs
echo "api_base_url=http://localhost:8000/api/version_management" > ~/.ergovcs/config
```

**Windows:**
```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.ergovcs" | Out-Null
Set-Content -Path "$env:USERPROFILE\.ergovcs\config" -Value "api_base_url=http://localhost:8000/api/version_management"
```

### Приоритет конфигурации

1. Переменная окружения `API_BASE_URL`
2. Конфиг файл `~/.ergovcs/config` (Linux) или `%USERPROFILE%\.ergovcs\config` (Windows)
3. Переменные `API_HOST` и `API_PORT`
4. Значение по умолчанию: `http://localhost:8000/api/version_management`

## Структура локальных данных

Утилита создает следующие файлы для работы:

### Конфигурация репозиториев
- **Linux:** `~/.ergovcs/repos.json`
- **Windows:** `%USERPROFILE%\.ergovcs\repos.json`

Структура:
```json
{
  "repositories": {
    "abc-123-def": {
      "uuid": "abc-123-def",
      "local_path": "/home/user/projects/my-repo",
      "remote_path": "media/version_management/abc-123-def",
      "current_branch": "main",
      "last_updated": "2024-01-01T12:00:00Z"
    }
  }
}
```

### Staging Area
- **Linux:** `~/.ergovcs/staging.json` (в рабочей директории репозитория)
- **Windows:** `%USERPROFILE%\.ergovcs\staging.json` (в рабочей директории репозитория)

Структура:
```json
{
  "repository_uuid": "abc-123-def",
  "files": [
    {
      "path": "src/main.py",
      "action": "modified",
      "content": "..."
    }
  ],
  "pending_commit": {
    "message": "Initial commit",
    "created_at": "2024-01-01T12:00:00Z"
  }
}
```

## Примечания

- Утилита автоматически определяет корень проекта, ища папку `modules/version_management` вверх по дереву каталогов
- Все репозитории на сервере хранятся в `media/version_management/<UUID>/`
- Локальные копии репозиториев хранятся в указанной пользователем директории
- Утилита интегрирована с API бэкенда для синхронизации изменений
- Для работы требуется запущенный API сервер (по умолчанию `http://localhost:8000`)

## Дополнительная документация

- `TASK_DISTRIBUTION.md` — полное распределение задач между разработчиками
- `API_USAGE.md` — детальная инструкция по использованию API функций

