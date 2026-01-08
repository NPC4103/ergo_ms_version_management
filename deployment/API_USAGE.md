# Инструкция по использованию API функций

## ✅ Этап 1 выполнен

Базовые функции для работы с API уже реализованы и готовы к использованию.

---

## Доступные функции

### Linux (bash)

#### `get_api_base_url()`
Получает базовый URL API с учетом приоритетов:
1. Переменная окружения `API_BASE_URL`
2. Конфиг файл `~/.ergovcs/config` (строка `api_base_url=...`)
3. Переменные `API_HOST` и `API_PORT`
4. Значение по умолчанию: `http://localhost:8000/api/version_management`

**Пример:**
```bash
base_url=$(get_api_base_url)
echo "$base_url"  # http://localhost:8000/api/version_management
```

#### `api_request()`
Выполняет HTTP запрос к API.

**Параметры:**
- `$1` - метод (GET, POST, PUT, DELETE)
- `$2` - endpoint (относительный путь, например `/repositories/`)
- `$3` - тело запроса (опционально, для POST/PUT, JSON строка)
- `$4` - заголовки (опционально, формат: `"Header1: Value1,Header2: Value2"`)

**Возвращает:**
- JSON ответ от API (через stdout)
- В случае ошибки: выводит сообщение в stderr и возвращает код ошибки

**Примеры:**
```bash
# GET запрос
response=$(api_request "GET" "/repositories/")
echo "$response"

# POST запрос с телом
body='{"name": "My Repository"}'
response=$(api_request "POST" "/repositories/" "$body")
echo "$response"

# POST запрос с кастомными заголовками
headers="Authorization: Bearer token123"
response=$(api_request "POST" "/repositories/" "$body" "$headers")
```

**Обработка ошибок:**
```bash
if ! response=$(api_request "GET" "/repositories/"); then
  echo "Ошибка при выполнении запроса"
  exit 1
fi
```

---

### Windows (PowerShell)

#### `Get-ApiBaseUrl`
Получает базовый URL API с учетом приоритетов:
1. Переменная окружения `$env:API_BASE_URL`
2. Конфиг файл `%USERPROFILE%\.ergovcs\config` (строка `api_base_url=...`)
3. Переменные `$env:API_HOST` и `$env:API_PORT`
4. Значение по умолчанию: `http://localhost:8000/api/version_management`

**Пример:**
```powershell
$baseUrl = Get-ApiBaseUrl
Write-Host $baseUrl  # http://localhost:8000/api/version_management
```

#### `Invoke-ApiRequest`
Выполняет HTTP запрос к API.

**Параметры:**
- `-Method` - метод (GET, POST, PUT, DELETE, PATCH) [обязательный]
- `-Endpoint` - endpoint (относительный путь) [обязательный]
- `-Body` - тело запроса (опционально, для POST/PUT, JSON строка)
- `-Headers` - заголовки (опционально, hashtable)

**Возвращает:**
- JSON строка с ответом от API
- `$null` в случае ошибки (сообщение об ошибке выводится в консоль)

**Примеры:**
```powershell
# GET запрос
$response = Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/"
Write-Host $response

# POST запрос с телом
$body = '{"name": "My Repository"}'
$response = Invoke-ApiRequest -Method "POST" -Endpoint "/repositories/" -Body $body
Write-Host $response

# POST запрос с кастомными заголовками
$headers = @{
    "Authorization" = "Bearer token123"
}
$response = Invoke-ApiRequest -Method "POST" -Endpoint "/repositories/" -Body $body -Headers $headers
```

**Обработка ошибок:**
```powershell
$response = Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/"
if (-not $response) {
    Write-Host "Ошибка при выполнении запроса"
    exit 1
}
```

---

## Конфигурация

### Создание конфиг файла

**Linux:**
```bash
mkdir -p ~/.ergovcs
cat > ~/.ergovcs/config <<EOF
api_base_url=http://localhost:8000/api/version_management
EOF
```

**Windows:**
```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.ergovcs" | Out-Null
Set-Content -Path "$env:USERPROFILE\.ergovcs\config" -Value "api_base_url=http://localhost:8000/api/version_management"
```

### Использование переменных окружения

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

---

## Примеры использования в командах

### Пример для `cmd_clone()` (Linux)

```bash
cmd_clone() {
  local uuid="$1"
  
  # Вызов API для клонирования
  local response
  response="$(api_request "GET" "/repositories/$uuid/clone/")"
  
  if [[ $? -ne 0 ]]; then
    echo "[ERROR] Не удалось клонировать репозиторий" >&2
    return 1
  fi
  
  # Парсинг ответа (пример)
  local repo_path
  repo_path="$(echo "$response" | grep -o '"path":"[^"]*"' | cut -d'"' -f4)"
  
  echo "[OK] Репозиторий клонирован: $repo_path"
}
```

### Пример для `Invoke-Clone` (Windows)

```powershell
function Invoke-Clone {
  param([string[]]$Args)
  
  $uuid = $Args[0]
  
  # Вызов API для клонирования
  $response = Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/$uuid/clone/"
  
  if (-not $response) {
    Write-Host "[ERROR] Не удалось клонировать репозиторий" -ForegroundColor Red
    exit 1
  }
  
  # Парсинг ответа (пример)
  $responseObj = $response | ConvertFrom-Json
  $repoPath = $responseObj.path
  
  Write-Host "[OK] Репозиторий клонирован: $repoPath" -ForegroundColor Green
}
```

---

## Формат ответов API

Все функции автоматически обрабатывают JSON ответы. Типичный формат ответа:

**Успешный ответ:**
```json
{
  "id": "abc-123-def",
  "name": "My Repository",
  "path": "/path/to/repo",
  "message": "Операция выполнена успешно"
}
```

**Ошибка:**
```json
{
  "detail": "Описание ошибки"
}
```

Функции автоматически извлекают сообщение об ошибке из поля `detail` и выводят его в консоль.

---

## Отладка

### Проверка базового URL

**Linux:**
```bash
get_api_base_url
```

**Windows:**
```powershell
Get-ApiBaseUrl
```

### Тестовый запрос

**Linux:**
```bash
api_request "GET" "/repositories/"
```

**Windows:**
```powershell
Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/"
```

---

## Важные замечания

1. **Все функции уже загружены** в `repo.sh` и `repo.ps1` - просто используйте их
2. **Обработка ошибок** встроена - проверяйте возвращаемые значения
3. **JSON автоматически обрабатывается** - используйте стандартные инструменты для парсинга
4. **Заголовки** можно передавать для аутентификации (если потребуется)
5. **Обе платформы** используют одинаковую логику, но разный синтаксис

---

## Готово к использованию!

Все функции готовы. Можете приступать к реализации команд в Этапе 2.

