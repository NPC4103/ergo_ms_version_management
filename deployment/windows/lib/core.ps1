# core.ps1
# Общие утилиты: поиск корня проекта, генерация UUID, хэширование, проверка игнорирования

$script:ProjectRoot = $null
$script:MediaDir = $null
$script:CliName = 'ergovcs'
$script:CliPath = "$env:SystemRoot\System32\$script:CliName.bat"

function Detect-ProjectRoot {
  if ($script:ProjectRoot) { return }

  $current = Get-Location
  while ($current.Path -ne $current.Drive.Root) {
    $versionManagementPath = Join-Path $current.Path "modules\version_management"
    if (Test-Path $versionManagementPath -PathType Container) {
      $script:ProjectRoot = $current.Path
      $script:MediaDir = Join-Path $script:ProjectRoot "media\version_management"
      New-Item -ItemType Directory -Force -Path $script:MediaDir | Out-Null
      return
    }
    $current = $current.Parent
  }

  Write-Host "[ERROR] Не удалось найти корень проекта (modules\version_management)!" -ForegroundColor Red
  exit 1
}

function New-Uuid {
  [guid]::NewGuid().ToString()
}

function Get-CliName {
  return $script:CliName
}

function Get-CliPath {
  return $script:CliPath
}

# ============================================================================
# Функции для работы с путями и поиска репозиториев
# ============================================================================

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

function Get-CurrentRepositoryUuid {
  param([string]$LocalPath)

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

# ============================================================================
# Функции для работы с хэшированием и содержимым файлов
# ============================================================================

function Get-FileContentHash {
  param([string]$FilePath)
  
  if (-not (Test-Path $FilePath)) {
    return $null
  }
  
  try {
    $content = Get-Content $FilePath -Raw -Encoding UTF8
    $hash = [System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($content))
    return [System.BitConverter]::ToString($hash).Replace("-", "").ToLower()
  }
  catch {
    return $null
  }
}

function Get-FileChangeType {
  param(
    [string]$FilePath,
    [string]$LocalPath,
    [hashtable]$PreviousState,
    [bool]$IsDirectory = $false
  )
  
  $relativePath = [System.IO.Path]::GetRelativePath($LocalPath, $FilePath).Replace('\', '/')
  
  # Проверяем, существует ли файл/директория
  $exists = Test-Path $FilePath
  
  # Ищем в предыдущем состоянии
  $previousEntry = $null
  if ($PreviousState.structure) {
    # Ищем по текущему пути
    $previousEntry = $PreviousState.structure | Where-Object { 
      $_.path -eq $relativePath 
    } | Select-Object -First 1
    
    # Если не нашли, ищем по старому пути (для переименований)
    if (-not $previousEntry) {
      $previousEntry = $PreviousState.structure | Where-Object { 
        $_.old_path -eq $relativePath 
      } | Select-Object -First 1
    }
  }
  
  if ($exists) {
    if (-not $previousEntry) {
      # Новый файл/директория
      return "created"
    }
    else {
      if ($previousEntry.is_directory -eq $IsDirectory) {
        # Проверяем переименование
        if ($previousEntry.path -ne $relativePath) {
          return "renamed"
        }
        
        # Для файлов проверяем хеш содержимого
        if (-not $IsDirectory) {
          $currentHash = Get-FileContentHash -FilePath $FilePath
          if ($currentHash -and $previousEntry.hash -and $currentHash -ne $previousEntry.hash) {
            return "updated"
          }
        }
        
        # Нет изменений
        return "unchanged"
      }
      else {
        # Изменился тип (был файл, стал директорией или наоборот)
        return "updated"
      }
    }
  }
  else {
    if ($previousEntry) {
      # Файл/директория удален
      return "deleted"
    }
    # Ничего не было и ничего нет
    return "unchanged"
  }
}

# ============================================================================
# Функции для работы с игнорированием файлов
# ============================================================================

function Test-Ignored {
  param(
    [string]$FilePath,
    [array]$IgnorePatterns
  )
  
  if ($FilePath -like '.ergovcs/*' -or $FilePath -eq '.ergovcs') {
    return $true
  }
  
  foreach ($pattern in $IgnorePatterns) {
    if ($pattern.Contains('*') -or $pattern.Contains('?')) {
      if ($FilePath -like $pattern) {
        return $true
      }
    } else {
      if ($FilePath -eq $pattern) {
        return $true
      }
    }
  }
  
  return $false
}

function Get-AllItems {
  param(
    [string]$Path,
    [string]$RepoRoot,
    [array]$IgnorePatterns
  )
  
  $items = @()
  
  # Добавляем саму директорию
  if ($Path -ne $RepoRoot) {
    $relativePath = [System.IO.Path]::GetRelativePath($RepoRoot, $Path).Replace('\', '/')
    if (-not (Test-Ignored -FilePath $relativePath -IgnorePatterns $IgnorePatterns)) {
      $items += $relativePath
    }
  }
  
  # Получаем дочерние элементы
  Get-ChildItem -Path $Path -Force | ForEach-Object {
    $relativePath = [System.IO.Path]::GetRelativePath($RepoRoot, $_.FullName).Replace('\', '/')
    
    if (-not (Test-Ignored -FilePath $relativePath -IgnorePatterns $IgnorePatterns)) {
      $items += $relativePath
      
      # Рекурсивно обрабатываем директории
      if ($_.PSIsContainer) {
        $items += Get-AllItems -Path $_.FullName -RepoRoot $RepoRoot -IgnorePatterns $IgnorePatterns
      }
    }
  }
  
  return $items
}

