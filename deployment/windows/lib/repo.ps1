# Логика работы с репозиториями: создание структуры, сохранение метаданных, импорт, работа с API

# ============================================================================
# Функции для работы с API
# ============================================================================

# Получить базовый URL API
function Get-ApiBaseUrl {
  # Приоритет: переменная окружения > конфиг файл > значение по умолчанию
  
  # Проверяем переменную окружения
  if ($env:API_BASE_URL) {
    return $env:API_BASE_URL
  }
  
  # Проверяем конфиг файл в домашней директории
  $configFile = Join-Path $env:USERPROFILE ".ergovcs\config"
  if (Test-Path $configFile) {
    $configContent = Get-Content $configFile -Raw
    if ($configContent -match 'api_base_url\s*=\s*(.+)') {
      $apiUrl = $matches[1].Trim().Trim('"').Trim("'")
      if ($apiUrl) {
        return $apiUrl
      }
    }
  }
  
  # Используем переменные окружения для хоста и порта или значения по умолчанию
  $apiHost = if ($env:API_HOST) { $env:API_HOST } else { "localhost" }
  $apiPort = if ($env:API_PORT) { $env:API_PORT } else { "8000" }
  
  return "http://${apiHost}:${apiPort}/api/version_management"
}

# Выполнить HTTP запрос к API
function Invoke-ApiRequest {
  param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("GET", "POST", "PUT", "DELETE", "PATCH")]
    [string]$Method,
    
    [Parameter(Mandatory=$true)]
    [string]$Endpoint,
    
    [string]$Body = $null,
    
    [hashtable]$Headers = @{}
  )
  
  # Получаем базовый URL
  $baseUrl = Get-ApiBaseUrl
  $url = "$baseUrl$Endpoint"
  
  # Подготовка заголовков
  $requestHeaders = @{
    "Content-Type" = "application/json"
    "Accept" = "application/json"
  }
  
  # Добавляем кастомные заголовки
  foreach ($key in $Headers.Keys) {
    $requestHeaders[$key] = $Headers[$key]
  }
  
  try {
    # Подготовка параметров для Invoke-RestMethod
    $params = @{
      Uri = $url
      Method = $Method
      Headers = $requestHeaders
      ErrorAction = "Stop"
    }
    
    # Добавляем тело запроса для POST/PUT/PATCH
    if ($Body -and ($Method -eq "POST" -or $Method -eq "PUT" -or $Method -eq "PATCH")) {
      $params["Body"] = $Body
    }
    
    # Выполнение запроса
    $response = Invoke-RestMethod @params
    
    # Возвращаем ответ (может быть объект или строка)
    if ($response -is [string]) {
      return $response
    } else {
      return ($response | ConvertTo-Json -Depth 10)
    }
  }
  catch {
    # Обработка ошибок
    $statusCode = $null
    $errorMessage = $_.Exception.Message
    
    # Пытаемся извлечь детали ошибки из ответа
    if ($_.Exception.Response) {
      try {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        $reader.Close()
        
        # Пытаемся распарсить JSON с ошибкой
        $errorObj = $responseBody | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($errorObj -and $errorObj.detail) {
          $errorMessage = $errorObj.detail
        } else {
          $errorMessage = $responseBody
        }
      }
      catch {
        # Если не удалось распарсить, используем стандартное сообщение
      }
    }
    
    Write-Host "[ERROR] API запрос не удался: $errorMessage" -ForegroundColor Red
    Write-Host "  URL: $url" -ForegroundColor Yellow
    Write-Host "  Метод: $Method" -ForegroundColor Yellow
    if ($statusCode) {
      Write-Host "  HTTP код: $statusCode" -ForegroundColor Yellow
    }
    
    # Возвращаем код ошибки
    return $null
  }
}

# Создать репозиторий через API
function Invoke-ApiCreateRepository {
  param([string]$Name = $null)
  
  # Параметры:
  #   $Name - название репозитория (опционально)
  # Возвращает: JSON с информацией о созданном репозитории (id, name, path, created_at)
  
  $body = @{}
  if ($Name) {
    $body = @{ name = $Name }
  }
  $bodyJson = $body | ConvertTo-Json -Depth 2
  
  # Стандартный create ViewSet в DRF доступен по POST /repositories/
  Invoke-ApiRequest -Method "POST" -Endpoint "/repositories/" -Body $bodyJson
}

# Клонировать репозиторий через API
function Invoke-ApiCloneRepository {
  param([string]$Uuid)
  
  # TODO: Реализовать клонирование через API
  # Возвращает: путь к клонированному репозиторию
  
  Write-Host "[TODO] Вызвать API /api/repositories/$Uuid/clone/" -ForegroundColor Yellow
  Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/$Uuid/clone/"
}

# Создать коммит через API
function Invoke-ApiCreateCommit {
  param(
    [string]$Uuid,
    [string]$Message,
    [string]$Files = $null
  )
  
  # TODO: Реализовать создание коммита через API
  # Возвращает: хеш коммита
  
  $body = @{
    message = $Message
  } | ConvertTo-Json -Depth 2
  
  if ($Files) {
    $bodyObj = $body | ConvertFrom-Json
    $bodyObj | Add-Member -NotePropertyName "files" -NotePropertyValue ($Files | ConvertFrom-Json)
    $body = $bodyObj | ConvertTo-Json -Depth 2
  }
  
  Write-Host "[TODO] Вызвать API /api/repositories/$Uuid/commits/create/" -ForegroundColor Yellow
  Invoke-ApiRequest -Method "POST" -Endpoint "/repositories/$Uuid/commits/create/" -Body $body
}

# Отправить изменения через API
function Invoke-ApiPushChanges {
  param(
    [string]$Uuid,
    [string]$Branch,
    [string]$Changes = $null
  )
  
  # TODO: Реализовать отправку изменений через API
  
  $body = @{
    branch = $Branch
  } | ConvertTo-Json -Depth 2
  
  if ($Changes) {
    $bodyObj = $body | ConvertFrom-Json
    $bodyObj | Add-Member -NotePropertyName "changes" -NotePropertyValue ($Changes | ConvertFrom-Json)
    $body = $bodyObj | ConvertTo-Json -Depth 2
  }
  
  Write-Host "[TODO] Вызвать API /api/repositories/$Uuid/push/" -ForegroundColor Yellow
  Invoke-ApiRequest -Method "POST" -Endpoint "/repositories/$Uuid/push/" -Body $body
}

# Обновить локальный репозиторий через API
function Invoke-ApiUpdateRepository {
  param(
    [string]$Uuid,
    [string]$Branch
  )
  
  # TODO: Реализовать обновление через API
  # Возвращает: путь к обновлённым файлам или архив
  
  $body = @{
    branch = $Branch
  } | ConvertTo-Json -Depth 2
  
  Write-Host "[TODO] Вызвать API /api/repositories/$Uuid/update/" -ForegroundColor Yellow
  Invoke-ApiRequest -Method "POST" -Endpoint "/repositories/$Uuid/update/" -Body $body
}

# Получить список коммитов через API
function Get-ApiCommitsList {
  param([string]$Uuid)
  
  # TODO: Реализовать получение списка коммитов через API
  # Возвращает: JSON со списком коммитов
  
  Write-Host "[TODO] Вызвать API /api/repositories/$Uuid/commits/" -ForegroundColor Yellow
  Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/$Uuid/commits/"
}

# Получить информацию о коммите через API
function Get-ApiCommit {
  param(
    [string]$Uuid,
    [string]$CommitHash
  )
  
  # TODO: Реализовать получение информации о коммите через API
  # Возвращает: JSON с метаданными коммита
  
  Write-Host "[TODO] Вызвать API /api/repositories/$Uuid/commits/$CommitHash/" -ForegroundColor Yellow
  Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/$Uuid/commits/$CommitHash/"
}

# Получить diff коммита через API
function Get-ApiCommitDiff {
  param(
    [string]$Uuid,
    [string]$CommitHash
  )
  
  # TODO: Реализовать получение diff коммита через API
  # Возвращает: diff в формате unified diff
  
  Write-Host "[TODO] Вызвать API /api/repositories/$Uuid/commits/$CommitHash/diff/" -ForegroundColor Yellow
  Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/$Uuid/commits/$CommitHash/diff/"
}

# ============================================================================
# Локальные функции работы с репозиториями
# ============================================================================

function Ensure-RepoDirs {
  param([string]$Uuid)

  $target = Join-Path $script:MediaDir $Uuid
  New-Item -ItemType Directory -Force -Path (Join-Path $target "api") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $target "client") | Out-Null
  return $target
}

function Save-Metadata {
  param(
    [string]$Target,
    [string]$Name,
    [string]$Description
  )

  $uuid = Split-Path $Target -Leaf
  $content = @{
    uuid = $uuid
    name = $Name
    description = $Description
  } | ConvertTo-Json -Depth 2

  $content | Set-Content -Encoding UTF8 -Path (Join-Path $Target "manifest.json")
}

function Import-FromSource {
  param(
    [string]$Source,
    [string]$Target
  )

  if (Test-Path $Source -PathType Container) {
    Copy-Item "$Source\*" $Target -Recurse -Force
  }
  elseif ($Source.ToLower().EndsWith(".zip")) {
    if (-not (Get-Command Expand-Archive -ErrorAction SilentlyContinue)) {
      Write-Host "[ERROR] Expand-Archive недоступен. Используйте PowerShell 5.1 или выше." -ForegroundColor Red
      exit 1
    }
    Expand-Archive -Path $Source -DestinationPath $Target -Force
  }
  else {
    Write-Host "[ERROR] Неизвестный источник: $Source" -ForegroundColor Red
    Write-Host "[INFO] Поддерживаются: папка или zip-архив" -ForegroundColor Yellow
    exit 1
  }
}
