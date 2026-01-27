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

# Получить список репозиториев через API
function Invoke-ApiListRepositories {
  # Возвращает: JSON со списком репозиториев
  Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/"
}

# Получить список веток репозитория
function Invoke-ApiListBranches {
  param([string]$RepoUuid)
  Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/$RepoUuid/branches/"
}

# Создать ветку
function Invoke-ApiCreateBranch {
  param(
    [string]$RepoUuid,
    [string]$BranchName,
    [string]$CliUsername = $null,
    [string]$CliPassword = $null,
    [bool]$CheckPermissions = $true
  )

  $bodyObj = @{
    repository_public_id = $RepoUuid
    name = $BranchName
    check_permissions = $CheckPermissions
  }
  if ($CliUsername) { $bodyObj["cli_username"] = $CliUsername }
  if ($CliPassword) { $bodyObj["cli_password"] = $CliPassword }

  $body = $bodyObj | ConvertTo-Json -Depth 5
  Invoke-ApiRequest -Method "POST" -Endpoint "/branches/" -Body $body
}

# Установить ветку по умолчанию (по id)
function Invoke-ApiSetDefaultBranchById {
  param(
    [int]$BranchId,
    [string]$CliUsername = $null,
    [string]$CliPassword = $null,
    [bool]$CheckPermissions = $true
  )

  $bodyObj = @{
    branch_id = $BranchId
    check_permissions = $CheckPermissions
  }
  if ($CliUsername) { $bodyObj["cli_username"] = $CliUsername }
  if ($CliPassword) { $bodyObj["cli_password"] = $CliPassword }

  $body = $bodyObj | ConvertTo-Json -Depth 5
  Invoke-ApiRequest -Method "POST" -Endpoint "/branches/set_default/" -Body $body
}

# Установить ветку по умолчанию (по repo+name)
function Invoke-ApiSetDefaultBranchByName {
  param(
    [string]$RepoUuid,
    [string]$BranchName,
    [string]$CliUsername = $null,
    [string]$CliPassword = $null,
    [bool]$CheckPermissions = $true
  )

  $bodyObj = @{
    repository_public_id = $RepoUuid
    branch_name = $BranchName
    check_permissions = $CheckPermissions
  }
  if ($CliUsername) { $bodyObj["cli_username"] = $CliUsername }
  if ($CliPassword) { $bodyObj["cli_password"] = $CliPassword }

  $body = $bodyObj | ConvertTo-Json -Depth 5
  Invoke-ApiRequest -Method "POST" -Endpoint "/branches/set_default/" -Body $body
}

# Удалить ветку
function Invoke-ApiDeleteBranch {
  param([int]$BranchId)
  Invoke-ApiRequest -Method "DELETE" -Endpoint "/branches/$BranchId/"
}

# Получить дерево файлов репозитория
function Invoke-ApiGetRepoFiles {
  param([string]$RepoUuid)
  Invoke-ApiRequest -Method "GET" -Endpoint "/repositories/$RepoUuid/files/"
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
    $Files = $null,
    [string]$Branch = $null
  )
  
  $filesArray = @()
  if ($Files) {
    try {
      if ($Files -is [string]) {
        $filesArray = @($Files | ConvertFrom-Json)
      } elseif ($Files -is [array]) {
        $filesArray = $Files
      } else {
        $filesArray = @($Files)
      }
    }
    catch {
      Write-Host "[ERROR] Не удалось преобразовать файлы: $_" -ForegroundColor Red
      return $null
    }
  }
  
  $bodyObj = @{
    message = $Message
    files = $filesArray
  }
  if ($Branch) {
    $bodyObj["branch_name"] = $Branch
  }
  
  $body = $bodyObj | ConvertTo-Json -Depth 10
  
  $response = Invoke-ApiRequest -Method "POST" -Endpoint "/repositories/$Uuid/commits/create/" -Body $body
  return $response
}

# Отправить изменения через API
function Invoke-ApiPushChanges {
  param(
    [string]$Uuid,
    [string]$Branch,
    [string]$CommitData = $null
  )
  
  # Подготавливаем тело запроса
  $body = @{
    branch = $Branch
  }
  
  # Если переданы данные коммита, добавляем их
  if ($CommitData) {
    $body["commit"] = $CommitData
  }
  
  $bodyJson = $body | ConvertTo-Json -Depth 10
  
  # Вызываем API эндпоинт
  return Invoke-ApiRequest -Method "POST" -Endpoint "/repositories/$Uuid/push/" -Body $bodyJson
}

# Обновить локальный репозиторий через API
function Invoke-ApiUpdateRepository {
  param(
    [string]$Uuid,
    [string]$Branch
  )
  
  # Подготавливаем тело запроса
  $body = @{
    branch = $Branch
  }
  
  $bodyJson = $body | ConvertTo-Json -Depth 2
  
  # Вызываем API эндпоинт
  return Invoke-ApiRequest -Method "POST" -Endpoint "/repositories/$Uuid/update/" -Body $bodyJson
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

# ============================================================================
# Функции для работы с содержимым проекта
# ============================================================================

# Получить содержимое проекта (из API или backup.json)
function Get-ProjectContent {
  param(
    [string]$RepoUuid,
    [string]$LocalPath
  )
  
  # 1. Пробуем получить через API
  try {
    $apiResponse = Invoke-ApiGetRepoFiles -RepoUuid $RepoUuid
    if ($apiResponse) {
      $data = $apiResponse | ConvertFrom-Json
      return @{
        source = "api"
        structure = if ($data.structure) { $data.structure } else { $data.items }
      }
    }
  }
  catch {
    Write-Host "[DEBUG] Не удалось получить содержимое проекта через API: $_" -ForegroundColor Gray
  }
  
  # 2. Пробуем получить из backup.json
  $backupFile = Join-Path $LocalPath ".ergovcs" "backup.json"
  if (Test-Path $backupFile) {
    try {
      $backupContent = Get-Content $backupFile -Raw -Encoding UTF8
      $backupData = $backupContent | ConvertFrom-Json
      return @{
        source = "backup"
        structure = if ($backupData.structure) { $backupData.structure } else { $backupData.items }
        timestamp = $backupData.timestamp
      }
    }
    catch {
      Write-Host "[DEBUG] Не удалось прочитать backup.json: $_" -ForegroundColor Gray
    }
  }
  
  # 3. Создаем пустую структуру
  Write-Host "[INFO] Не удалось получить предыдущее состояние проекта. Будет создано пустое состояние." -ForegroundColor Yellow
  return @{
    source = "empty"
    structure = @()
  }
}

# ============================================================================
# Функции для работы с backup.json
# ============================================================================

# Сохранить backup.json с текущим состоянием репозитория
function Save-BackupJson {
  param(
    [string]$LocalPath,
    [string]$RepoUuid
  )
  
  $backupFile = Join-Path $LocalPath ".ergovcs" "backup.json"
  $backupDir = Split-Path $backupFile -Parent
  if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
  }
  
  # Получаем структуру файлов репозитория
  $structure = Get-RepositoryStructure -LocalPath $LocalPath
  $currentBranch = Get-CurrentBranch -LocalPath $LocalPath
  
  $backupData = @{
    repository_uuid = $RepoUuid
    timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    branch = $currentBranch
    structure = $structure
  }
  
  $backupData | ConvertTo-Json -Depth 20 | Set-Content -Path $backupFile -Encoding UTF8
  Write-Host "[INFO] Backup сохранен: $backupFile" -ForegroundColor Gray
}

# Получить структуру репозитория для backup.json
function Get-RepositoryStructure {
  param([string]$LocalPath)
  
  $structure = @()
  
  # Получаем все файлы и директории (исключая .ergovcs)
  Get-ChildItem -Path $LocalPath -Recurse -Force | ForEach-Object {
    if ($_.FullName -notlike "*\.ergovcs*") {
      $relativePath = [System.IO.Path]::GetRelativePath($LocalPath, $_.FullName).Replace('\', '/')
      
      $item = @{
        path = $relativePath
        name = $_.Name
        is_directory = $_.PSIsContainer
        last_modified = $_.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
      }
      
      if (-not $_.PSIsContainer) {
        # Для файлов добавляем хеш содержимого
        $item.hash = Get-FileContentHash -FilePath $_.FullName
        $item.size = $_.Length
      }
      
      $structure += $item
    }
  }
  
  return $structure
}

# Получить текущую ветку из конфига
function Get-CurrentBranch {
  param([string]$LocalPath)
  
  # Пробуем получить из локального конфига
  $localReposFile = Join-Path $LocalPath ".ergovcs" "repos.json"
  if (Test-Path $localReposFile) {
    try {
      $reposJson = Get-Content $localReposFile -Raw -Encoding UTF8
      $repos = $reposJson | ConvertFrom-Json -ErrorAction Stop
      foreach ($property in $repos.repositories.PSObject.Properties) {
        $repo = $property.Value
        if ($repo.local_path -eq $LocalPath) {
          return if ($repo.current_branch) { $repo.current_branch } else { "main" }
        }
      }
    }
    catch {}
  }
  
  # Фолбэк: глобальный конфиг
  $globalReposFile = Join-Path $env:USERPROFILE ".ergovcs" "repos.json"
  if (Test-Path $globalReposFile) {
    try {
      $reposJson = Get-Content $globalReposFile -Raw -Encoding UTF8
      $repos = $reposJson | ConvertFrom-Json -ErrorAction Stop
      foreach ($property in $repos.repositories.PSObject.Properties) {
        $repo = $property.Value
        if ($repo.local_path -eq $LocalPath) {
          return if ($repo.current_branch) { $repo.current_branch } else { "main" }
        }
      }
    }
    catch {}
  }
  
  return "main"
}

# Обновить конфиг репозитория
function Update-RepositoryConfig {
  param(
    [string]$Uuid,
    [string]$LastUpdated,
    [string]$CurrentBranch = $null
  )
  
  $configDir = Join-Path $env:USERPROFILE ".ergovcs"
  $configFile = Join-Path $configDir "repos.json"
  
  if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
  }
  
  $configData = @{ repositories = @{} }
  if (Test-Path $configFile) {
    try {
      $existing = Get-Content $configFile -Raw | ConvertFrom-Json
      if ($existing.repositories) {
        foreach ($p in $existing.repositories.PSObject.Properties) {
          $configData.repositories[$p.Name] = $p.Value
        }
      }
    } catch {}
  }
  
  if ($configData.repositories.ContainsKey($Uuid)) {
    $configData.repositories[$Uuid].last_updated = $LastUpdated
    if ($CurrentBranch) {
      $configData.repositories[$Uuid].current_branch = $CurrentBranch
    }
  }
  
  $configData | ConvertTo-Json -Depth 10 | Set-Content $configFile -Encoding UTF8
}

