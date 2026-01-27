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
    [string]$Files = $null
  )
  
  # Преобразуем строку JSON в объект, если она передана
  $filesArray = @()
  if ($Files) {
    try {
      if ($Files -is [string]) {
        $filesArray = $Files | ConvertFrom-Json
      } else {
        $filesArray = $Files
      }
    }
    catch {
      Write-Host "[ERROR] Не удалось преобразовать файлы: $_" -ForegroundColor Red
      return $null
    }
  }
  
  # Подготавливаем тело запроса
  $bodyObj = @{
    message = $Message
    files = $filesArray
  }
  
  $body = $bodyObj | ConvertTo-Json -Depth 10
  
  # Вызываем API
  $response = Invoke-ApiRequest -Method "POST" -Endpoint "/repositories/$Uuid/commits/create/" -Body $body
  
  return $response
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

# ============================================================================
# Функции для работы со staging area
# ============================================================================

# Найти корень репозитория (ищет .ergovcs/staging.json или .ergovcs/repos.json вверх по дереву)
function Find-LocalRepositoryRoot {
  $current = Get-Location
  while ($current.Path -ne $current.Drive.Root) {
    $ergovcsDir = Join-Path $current.Path ".ergovcs"
    $stagingFile = Join-Path $ergovcsDir "staging.json"
    $configFile = Join-Path $ergovcsDir "repos.json"
    
    if ((Test-Path $stagingFile) -or (Test-Path $configFile)) {
      return $current.Path
    }
    $current = $current.Parent
  }
  return $null
}

# Получить UUID текущего репозитория
function Get-CurrentRepositoryUuid {
  param([string[]]$LocalPath)

  if (-not $LocalPath) {
    Write-Host "[DEBUG] Корень репозитория не найден" -ForegroundColor Gray
    return $null
  }
  
  Write-Host "[DEBUG] Корень репозитория: $LocalPath" -ForegroundColor Gray
  
  # Путь к локальному файлу repos.json в .ergovcs директории
  $localReposFile = Join-Path $LocalPath ".ergovcs" "repos.json"
  Write-Host "[DEBUG] Ищем локальный файл: $localReposFile" -ForegroundColor Gray
  
  # Пробуем сначала прочитать из локального .ergovcs/repos.json
  if (Test-Path $localReposFile) {
    Write-Host "[DEBUG] Локальный файл repos.json найден" -ForegroundColor Gray
    try {
      $reposJson = Get-Content $localReposFile -Raw -Encoding UTF8
      $repos = $reposJson | ConvertFrom-Json -ErrorAction Stop
      
      Write-Host "[DEBUG] Прочитано репозиториев: $($repos.repositories.PSObject.Properties.Count)" -ForegroundColor Gray
      
      # Ищем репозиторий с local_path, который совпадает с текущим путем
      foreach ($property in $repos.repositories.PSObject.Properties) {
        $uuid = $property.Name
        $repo = $property.Value
        
        Write-Host "[DEBUG] Проверяем репозиторий: $uuid" -ForegroundColor Gray
        Write-Host "[DEBUG]  local_path: $($repo.local_path)" -ForegroundColor Gray
        Write-Host "[DEBUG]  current: $LocalPath" -ForegroundColor Gray
        
        # Сравниваем пути (учитываем возможные различия в формате)
        if ($repo.local_path -and (
            $repo.local_path -eq $LocalPath -or 
            (Resolve-Path $repo.local_path -ErrorAction SilentlyContinue) -eq (Resolve-Path $LocalPath -ErrorAction SilentlyContinue))) {
          Write-Host "[DEBUG] Найден UUID: $uuid" -ForegroundColor Gray
          return $uuid
        }
      }
    }
    catch {
      Write-Host "[ERROR] Не удалось прочитать или распарсить локальный repos.json: $_" -ForegroundColor Red
    }
  } else {
    Write-Host "[DEBUG] Локальный файл repos.json не найден" -ForegroundColor Gray
  }
  
  # Фолбэк: проверяем staging.json (если существует)
  $stagingFile = Join-Path $LocalPath ".ergovcs\staging.json"
  if (Test-Path $stagingFile) {
    Write-Host "[DEBUG] Пробуем прочитать staging.json" -ForegroundColor Gray
    try {
      $stagingJson = Get-Content $stagingFile -Raw -Encoding UTF8
      $staging = $stagingJson | ConvertFrom-Json -ErrorAction Stop
      if ($staging.repository_uuid) {
        Write-Host "[DEBUG] Найден UUID из staging: $($staging.repository_uuid)" -ForegroundColor Gray
        return $staging.repository_uuid
      }
    }
    catch {
      Write-Host "[ERROR] Не удалось прочитать staging area: $_" -ForegroundColor Red
    }
  }
  
  # Фолбэк: проверяем глобальный файл (для обратной совместимости)
  $globalReposFile = Join-Path $env:USERPROFILE ".ergovcs\repos.json"
  if (Test-Path $globalReposFile) {
    Write-Host "[DEBUG] Пробуем глобальный файл: $globalReposFile" -ForegroundColor Gray
    try {
      $reposJson = Get-Content $globalReposFile -Raw -Encoding UTF8
      $repos = $reposJson | ConvertFrom-Json -ErrorAction Stop
      
      foreach ($property in $repos.repositories.PSObject.Properties) {
        $uuid = $property.Name
        $repo = $property.Value
        
        if ($repo.local_path -and (
            $repo.local_path -eq $LocalPath -or 
            (Resolve-Path $repo.local_path -ErrorAction SilentlyContinue) -eq (Resolve-Path $LocalPath -ErrorAction SilentlyContinue))) {
          Write-Host "[DEBUG] Найден UUID в глобальном файле: $uuid" -ForegroundColor Gray
          return $uuid
        }
      }
    }
    catch {
      Write-Host "[ERROR] Не удалось прочитать глобальный repos.json: $_" -ForegroundColor Red
    }
  }
  
  Write-Host "[DEBUG] UUID репозитория не найден" -ForegroundColor Gray
  return $null
}

# Получить путь к файлу staging area
function Get-StagingFilePath {
  $LocalPath = Find-LocalRepositoryRoot
  if (-not $LocalPath) {
    return $null
  }
  
  $ergovcsDir = Join-Path $LocalPath ".ergovcs"
  New-Item -ItemType Directory -Force -Path $ergovcsDir | Out-Null
  return Join-Path $ergovcsDir "staging.json"
}

# Прочитать staging area
function Get-StagingArea {
  $stagingFile = Get-StagingFilePath
  if (-not $stagingFile -or -not (Test-Path $stagingFile)) {
    return @{
      repository_uuid = $null
      files = @()
      pending_commit = $null
    }
  }
  
  try {
    $content = Get-Content $stagingFile -Raw -Encoding UTF8 | ConvertFrom-Json
    return @{
      repository_uuid = $content.repository_uuid
      files = if ($content.files) { $content.files } else { @() }
      pending_commit = $content.pending_commit
    }
  }
  catch {
    Write-Host "[ERROR] Не удалось прочитать staging area: $_" -ForegroundColor Red
    return @{
      repository_uuid = $null
      files = @()
      pending_commit = $null
    }
  }
}

# Сохранить staging area
function Save-StagingArea {
  param([hashtable]$Staging)
  
  $stagingFile = Get-StagingFilePath
  if (-not $stagingFile) {
    Write-Host "[ERROR] Не удалось определить путь к staging area. Убедитесь, что вы находитесь в репозитории." -ForegroundColor Red
    return $false
  }
  
  try {
    $json = @{
      repository_uuid = $Staging.repository_uuid
      files = $Staging.files
      pending_commit = $Staging.pending_commit
    } | ConvertTo-Json -Depth 10
    
    $json | Set-Content -Path $stagingFile -Encoding UTF8 -NoNewline
    return $true
  }
  catch {
    Write-Host "[ERROR] Не удалось сохранить staging area: $_" -ForegroundColor Red
    return $false
  }
}

# Определить действие файла (added, modified, deleted)
function Get-FileAction {
  param(
    [string]$FilePath,
    [string]$LocalPath
  )
  
  $fullPath = if ([System.IO.Path]::IsPathRooted($FilePath)) {
    $FilePath
  } else {
    Join-Path $LocalPath $FilePath
  }
  
  if (-not (Test-Path $fullPath)) {
    return "deleted"
  }
  
  # Проверяем, существует ли файл в репозитории на сервере
  # Для простоты считаем, что если файл существует локально, то он modified или added
  # Проверяем наличие файла в удаленном репозитории через API (если доступно)
  # Пока что используем эвристику: если файл в подпапках api/ или client/, то это новый файл
  # В будущем можно добавить проверку через API или локальный индекс
  
  $relativePath = [System.IO.Path]::GetRelativePath($LocalPath, $fullPath).Replace('\', '/')
  if ($relativePath -match '^(api|client)/') {
    # Файлы в api/ или client/ считаем новыми (added)
    return "added"
  }
  
  return "modified"
}

