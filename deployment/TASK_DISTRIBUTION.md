# Распределение задач между разработчиками

## Общая информация

**Платформы:** Linux (bash) и Windows (PowerShell)  
**Подход:** Параллельная разработка с учетом зависимостей

---

## ✅ Этап 1: Инфраструктура (ВЫПОЛНЕНО)

### Базовые функции API
**Статус:** ✅ **ГОТОВО** (реализовано автоматически)

**Реализовано:**
- ✅ `get_api_base_url()` / `Get-ApiBaseUrl()` в `repo.sh` и `repo.ps1`
  - Поддержка переменной окружения `API_BASE_URL`
  - Поддержка переменных `API_HOST` и `API_PORT`
  - Конфиг файл `~/.ergovcs/config` (Linux) или `%USERPROFILE%\.ergovcs\config` (Windows)
  - Значение по умолчанию: `http://localhost:8000/api/version_management`

- ✅ `api_request()` / `Invoke-ApiRequest()` в `repo.sh` и `repo.ps1`
  - HTTP запросы через `curl` (Linux) и `Invoke-RestMethod` (Windows)
  - Поддержка методов: GET, POST, PUT, DELETE, PATCH
  - Обработка JSON запросов/ответов
  - Обработка ошибок HTTP с детальными сообщениями
  - Автоматическое извлечение сообщений об ошибках из ответов API

**Файлы:**
- `deployment/linux/lib/repo.sh` (строки 8-85)
- `deployment/windows/lib/repo.ps1` (строки 7-105)

**Использование:**
```bash
# Linux
api_request "GET" "/repositories/list/"
api_request "POST" "/repositories/create/" '{"name": "My Repo"}'

# Windows
Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/list/"
Invoke-ApiRequest -Method "POST" -Endpoint "/repositories/create/" -Body '{"name": "My Repo"}'
```

**Конфигурация:**
Создайте файл `~/.ergovcs/config` (Linux) или `%USERPROFILE%\.ergovcs\config` (Windows):
```
api_base_url=http://localhost:8000/api/version_management
```

Или используйте переменные окружения:
```bash
export API_BASE_URL="http://localhost:8000/api/version_management"
# или
export API_HOST="localhost"
export API_PORT="8000"
```

---

## Этап 2: Основной функционал (Параллельная разработка)

**⚠️ ВАЖНО:** Этап 1 (инфраструктура API) уже выполнен. Все функции `api_request()` / `Invoke-ApiRequest()` готовы к использованию.

### 👤 Говоров: Клонирование репозиториев (clone)
**Зависит от:** ✅ Этап 1 (базовые функции API) - ГОТОВО

**Задачи:**
- ✅ Реализовать `api_clone_repository()` / `Invoke-ApiCloneRepository()` в `repo.sh` и `repo.ps1`
- ✅ Реализовать `cmd_clone()` / `Invoke-Clone()` в `commands.sh` и `commands.ps1`
  - Вызов API `/api/repositories/{id}/clone/`
  - Скачивание репозитория на локальный компьютер
  - Сохранение информации о клонированном репозитории (конфиг файл)
  - Определение рабочей директории для локальных репозиториев

**Файлы:**
- `deployment/linux/lib/repo.sh` (строки 42-52)
- `deployment/linux/lib/commands.sh` (строки 9-35)
- `deployment/windows/lib/repo.ps1` (строки 52-62)
- `deployment/windows/lib/commands.ps1` (строки 6-35)

**Дополнительно:**
- Создать систему хранения конфигурации локальных репозиториев
  - Файл `~/.ergovcs/repos.json` (Linux) или `$env:USERPROFILE\.ergovcs\repos.json` (Windows)
  - Структура: `{ "uuid": "path/to/repo" }`

---

### 👤 Кирюнин: Работа с коммитами (add + commit)
**Зависит от:** ✅ Этап 1 (базовые функции API) - ГОТОВО

**Задачи:**

**Часть 1: Staging Area (add)**
- ✅ Реализовать `cmd_add()` / `Invoke-Add()` в `commands.sh` и `commands.ps1`
  - Проверка существования файла
  - Добавление файла в staging area (локальный файл `.ergovcs/staging.json`)
  - Структура staging: `{ "files": ["path/to/file1", "path/to/file2"] }`
  - Поддержка относительных и абсолютных путей

**Часть 2: Создание коммитов (commit)**
- ✅ Реализовать `api_create_commit()` / `Invoke-ApiCreateCommit()` в `repo.sh` и `repo.ps1`
- ✅ Реализовать `cmd_commit()` / `Invoke-Commit()` в `commands.sh` и `commands.ps1`
  - Получение UUID текущего репозитория (из конфига или `.ergovcs/config.json`)
  - Сбор изменений из staging area
  - Вызов API `/api/repositories/{id}/commits/create/`
  - **Важно:** После повторного `add` не создаётся новый коммит, а добавляются изменения в существующий, до тех пор пока коммит не отправлен на сервер
  - Очистка staging area после успешного создания коммита

**Файлы:**
- `deployment/linux/lib/repo.sh` (строки 54-76)
- `deployment/linux/lib/commands.sh` (строки 37-68, 70-108)
- `deployment/windows/lib/repo.ps1` (строки 64-90)
- `deployment/windows/lib/commands.ps1` (строки 37-68, 70-108)

**Дополнительно:**
- Система управления staging area
- Логика "незавершенного коммита" (до push)

---

### 👤 Левшонков: Синхронизация (push + update)
**Зависит от:** ✅ Этап 1 (базовые функции API) - ГОТОВО, желательно Этап 2 (commit)

**Задачи:**

**Часть 1: Отправка изменений (push)**
- ✅ Реализовать `api_push_changes()` / `Invoke-ApiPushChanges()` в `repo.sh` и `repo.ps1`
- ✅ Реализовать `cmd_push()` / `Invoke-Push()` в `commands.sh` и `commands.ps1`
  - Получение UUID текущего репозитория
  - Сбор всех незакоммиченных изменений (или последнего коммита)
  - Вызов API `/api/repositories/{id}/push/`
  - Отправка изменений в папку `media/version_management/<UUID>/`
  - Обновление статуса коммита (отмечен как отправленный)

**Часть 2: Обновление репозитория (update)**
- ✅ Реализовать `api_update_repository()` / `Invoke-ApiUpdateRepository()` в `repo.sh` и `repo.ps1`
- ✅ Реализовать `cmd_update()` / `Invoke-Update()` в `commands.sh` и `commands.ps1`
  - Получение UUID текущего репозитория
  - Вызов API `/api/repositories/{id}/update/`
  - Скачивание изменений из папки `media/version_management/<UUID>/` на локальный компьютер
  - Примечание: не важно какая ветка скачана у пользователя

**Файлы:**
- `deployment/linux/lib/repo.sh` (строки 78-100, 102-115)
- `deployment/linux/lib/commands.sh` (строки 110-140, 142-170)
- `deployment/windows/lib/repo.ps1` (строки 92-115, 117-135)
- `deployment/windows/lib/commands.ps1` (строки 110-140, 142-170)

---

### 👤 Щеткина: Удаление (remove)
**Зависит от:** ✅ Этап 1 (базовые функции API) - ГОТОВО

**Задачи:**

**Часть 1: Удаление репозитория (remove)**
- ✅ Реализовать `cmd_remove()` / `Invoke-Remove()` в `commands.sh` и `commands.ps1`
  - Получение UUID из аргументов
  - Поиск локальной копии репозитория (из конфига)
  - Удаление локальной копии репозитория
  - Удаление записи из конфига
  - Примечание: удаляет только локальную копию, не репозиторий на сервере

**Часть 2: Дополнительные API функции**
- ✅ Реализовать `api_list_commits()` / `Get-ApiCommitsList()` в `repo.sh` и `repo.ps1`
  - Вызов API `/api/repositories/{id}/commits/`
  - Возврат JSON со списком коммитов

- ✅ Реализовать `api_get_commit()` / `Get-ApiCommit()` в `repo.sh` и `repo.ps1`
  - Вызов API `/api/repositories/{id}/commits/{commit_hash}/`
  - Возврат JSON с метаданными коммита

- ✅ Реализовать `api_get_commit_diff()` / `Get-ApiCommitDiff()` в `repo.sh` и `repo.ps1`
  - Вызов API `/api/repositories/{id}/commits/{commit_hash}/diff/`
  - Возврат diff в формате unified diff

**Файлы:**
- `deployment/linux/lib/repo.sh` (строки 117-150)
- `deployment/linux/lib/commands.sh` (строки 172-200)
- `deployment/windows/lib/repo.ps1` (строки 137-180)
- `deployment/windows/lib/commands.ps1` (строки 172-200)
- `deployment/README.md`

---

## Чек-лист готовности

```
Этап 1:    [✅ Здорнова] ───────────────────────> Инфраструктура API (ВЫПОЛНЕНО)

Этап 2:    [Говоров]   ──────────────────> clone
           [Кирюнин]   ──────────────────> add + commit
           [Левшонков] ──────────────────> push + update
           [Щеткина]   ──────────────────> remove + доп. функции

Финал:     [Все] ────────────────────────────> Тестирование
```

**Примечание:** Все разработчики могут начинать работу параллельно, так как инфраструктура API уже готова.

---

## Критические зависимости

1. ✅ **Этап 1 (Инфраструктура)** - ВЫПОЛНЕНО
   - Все функции `api_request()` / `Invoke-ApiRequest()` готовы к использованию
   - Разработчики могут сразу приступать к работе

2. **Кирюнин (commit)** должен согласовать формат staging area с **Левшонковым (push)**
   - Push должен понимать формат данных от commit

3. **Левшонков (push)** должен согласовать формат данных с **Кирюниным (commit)**
   - Как передавать изменения в API

---

## Форматы данных (требуют согласования)

### Staging Area (`.ergovcs/staging.json`)
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

### Конфигурация репозиториев (`~/.ergovcs/repos.json`)
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

### Формат данных для API запросов
- **commit**: `{ "message": "...", "files": [...] }`
- **push**: `{ "branch": "...", "changes": [...] }`
- **update**: `{ "branch": "..." }`

---

## Рекомендации по работе

1. **Проводите ежедневные синхронизации** для согласования форматов
2. **Тестируйте на обеих платформах** перед коммитом
3. **Документируйте изменения** в форматах данных


