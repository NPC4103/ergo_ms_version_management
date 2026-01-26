# Обработчики команд: clone, add, commit, push, update, remove, create, download

# ============================================================================
# Клонирование репозитория
# Команда: ergovcs clone <UUID>
# Копирует репозиторий из media/version_management/<UUID>/ на комп пользователя
# ============================================================================
function Invoke-Clone {
  param([string[]]$Args)
  
  # TODO: Реализовать клонирование репозитория
  # 1. Получить UUID из аргументов
  # 2. Вызвать API эндпоинт /api/repositories/{id}/clone/
  # 3. Скачать репозиторий на локальный компьютер
  # 4. Сохранить информацию о клонированном репозитории (путь, UUID)
  
  $uuid = $null
  
  for ($i = 0; $i -lt $Args.Count; $i++) {
    $uuid = $Args[$i]
  }
  
  if (-not $uuid) {
    Write-Host "[ERROR] Необходимо указать UUID репозитория" -ForegroundColor Red
    Write-Host "Использование: ergovcs clone <UUID>" -ForegroundColor Yellow
    exit 1
  }
  
  # TODO: Реализовать вызов API и клонирование
  Write-Host "[INFO] Клонирование репозитория $uuid..." -ForegroundColor Cyan
  Write-Host "[TODO] Реализовать вызов API /api/repositories/$uuid/clone/" -ForegroundColor Yellow
  Write-Host "[TODO] Скачать репозиторий на локальный компьютер" -ForegroundColor Yellow
}

# ============================================================================
# Добавление файла для коммита
# Команда: ergovcs add <файл.расширение>
# Добавляет файл для коммита
# ============================================================================
function Invoke-Add {
  param([string[]]$Files)
  
  Write-Host "[DEBUG] Files count: $($Files.Count)" -ForegroundColor Gray
  Write-Host "[DEBUG] Files content: $($Files -join ', ')" -ForegroundColor Gray

  # 1. Определить корень репозитория из пути
  $repoRoot = Find-LocalRepositoryRoot
  Write-Host "[DEBUG] RepoRoot: $repoRoot" -ForegroundColor Gray
  if (-not $repoRoot) {
    Write-Host "[ERROR] Не удалось определить корень репозитория." -ForegroundColor Red
    exit 1
  }

  # 2. Получить UUID репозитория
  $uuid = Get-CurrentRepositoryUuid -LocalPath $repoRoot
  Write-Host "[DEBUG] UUID: $uuid" -ForegroundColor Gray
  if (-not $uuid) {
    Write-Host "[ERROR] Не удалось определить UUID репозитория." -ForegroundColor Red
    Write-Host "[INFO] Убедитесь, что репозиторий был клонирован или создан через команду clone/create." -ForegroundColor Yellow
    exit 1
  }

  # 3. Если аргументы не переданы, добавить все файлы в репозитории
  if ($Files.Count -eq 0) {
    Write-Host "[INFO] Аргументы не указаны. Добавляю все файлы в репозитории..." -ForegroundColor Cyan
    $Files = Get-ChildItem -Path $repoRoot -File -Recurse -Force |
             Where-Object { $_.FullName -notlike "*\.ergovcs\*" } |
             ForEach-Object { 
               $relativePath = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/')
               $relativePath
             }
    
    if ($Files.Count -eq 0) {
      Write-Host "[INFO] Нет файлов для добавления." -ForegroundColor Yellow
      exit 0
    }
    
    Write-Host "[DEBUG] Всего найдено файлов: $($Files.Count)" -ForegroundColor Gray
  }

  # 4. Создать директорию .ergovcs, если она не существует
  $ergovcsPath = Join-Path $repoRoot ".ergovcs"
  if (-not (Test-Path $ergovcsPath)) {
    New-Item -ItemType Directory -Path $ergovcsPath -Force | Out-Null
    Write-Host "[INFO] Создана директория .ergovcs" -ForegroundColor Cyan
  }

  # 5. Прочитать текущий staging area или создать новый
  $stagingFile = Join-Path $ergovcsPath "staging.json"
  $staging = @{
    repository_uuid = $uuid
    files = [System.Collections.ArrayList]@()
    pending_commit = $null
  }

  if (Test-Path $stagingFile) {
    try {
      $existingStaging = Get-Content $stagingFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
      # Обновляем UUID на случай, если он изменился
      $existingStaging.repository_uuid = $uuid
      
      # Копируем существующие данные
      $staging.repository_uuid = $uuid
      if ($existingStaging.files -and $existingStaging.files.Count -gt 0) {
        $staging.files = [System.Collections.ArrayList]@($existingStaging.files)
      }
      if ($existingStaging.pending_commit) {
        $staging.pending_commit = $existingStaging.pending_commit
      }
      
      Write-Host "[DEBUG] Загружен существующий staging area" -ForegroundColor Gray
    }
    catch {
      Write-Host "[WARNING] Не удалось прочитать существующий staging.json, создаем новый" -ForegroundColor Yellow
    }
  }

  # 6. Обработать каждый файл
  $hasErrors = $false
  $addedFiles = @()
  
  foreach ($file in $Files) {
    # Пропустить пустые аргументы
    if ([string]::IsNullOrWhiteSpace($file)) {
      Write-Host "[WARNING] Пропущен пустой аргумент" -ForegroundColor Yellow
      continue
    }
    
    # Определить полный путь к файлу
    $fullPath = if ([System.IO.Path]::IsPathRooted($file)) {
      $file
    } else {
      Join-Path (Get-Location).Path $file
    }
    
    # Проверить существование файла
    if (-not (Test-Path $fullPath)) {
      Write-Host "[ERROR] Файл не найден: $file" -ForegroundColor Red
      $hasErrors = $true
      continue
    }
    
    Write-Host "[DEBUG] Original: $file | Full: $fullPath" -ForegroundColor Gray
    
    # Получить относительный путь от корня репозитория
    $relativePath = [System.IO.Path]::GetRelativePath($repoRoot, $fullPath).Replace('\', '/')
    Write-Host "[DEBUG] RelativePath: $relativePath"

    # Пропустить файлы в директории .ergovcs
    if ($relativePath -like '.ergovcs/*' -or $relativePath -eq '.ergovcs') {
      Write-Host "[INFO] Пропущен системный файл: $relativePath" -ForegroundColor Gray
      continue
    }

    # Прочитать содержимое файла
    try {
      $fileContent = Get-Content $fullPath -Raw -Encoding UTF8
    }
    catch {
      Write-Host "[ERROR] Не удалось прочитать файл: $file - $_" -ForegroundColor Red
      $hasErrors = $true
      continue
    }
    
    # Определить действие файла
    $action = Get-FileAction -FilePath $relativePath -LocalPath $repoRoot
    
    # Проверить, не добавлен ли файл уже в staging
    $fileExists = $false
    $fileIndex = -1

    for ($j = 0; $j -lt $staging.files.Count; $j++) {
      if ($staging.files[$j].path -eq $relativePath) {
        $fileExists = $true
        $fileIndex = $j
        break
      }
    }
    
    if ($fileExists) {
      # Обновляем существующий файл
      $staging.files[$fileIndex].action = $action
      $staging.files[$fileIndex].content = $fileContent
      Write-Host "[INFO] Файл обновлен в staging area: $relativePath" -ForegroundColor Cyan
    } else {
      # Добавляем новый файл
      $fileEntry = [ordered]@{
        path = $relativePath
        action = $action
        content = $fileContent
      }
      $null = $staging.files.Add($fileEntry)
      Write-Host "[OK] Файл добавлен в staging area: $relativePath" -ForegroundColor Green
      $addedFiles += $relativePath
    }
  }
  
  # 7. Сохранить staging area
  try {
    $jsonContent = $staging | ConvertTo-Json -Depth 10
    Set-Content -Path $stagingFile -Value $jsonContent -Encoding UTF8 -Force
    Write-Host "[INFO] Staging area сохранен: $stagingFile" -ForegroundColor Cyan
    
    if ($addedFiles.Count -gt 0) {
      Write-Host "[OK] Успешно добавлено файлов: $($addedFiles.Count)" -ForegroundColor Green
      foreach ($addedFile in $addedFiles) {
        Write-Host "  - $addedFile" -ForegroundColor Gray
      }
    }
    
    if ($hasErrors) {
      Write-Host "[WARNING] Некоторые файлы не были добавлены из-за ошибок" -ForegroundColor Yellow
      exit 1
    } else {
      exit 0
    }
  }
  catch {
    Write-Host "[ERROR] Не удалось сохранить staging area: $_" -ForegroundColor Red
    exit 1
  }
}

# ============================================================================
# Создание коммита
# Команда: ergovcs commit -m "Сообщение"
# Создаёт коммит с изменениями в папке media/version_management/<UUID>/
# ============================================================================
function Invoke-Commit {
  param([string[]]$MessageArg)
  
  # 1. Получить сообщение коммита из аргумента -m
  $message = $null
  
  for ($i = 0; $i -lt $MessageArg.Count; $i++) {
    switch ($MessageArg[$i]) {
      "-m" { 
        $i++
        if ($i -lt $MessageArg.Count) {
          $message = $MessageArg[$i]
        }
      }
      "--message" { 
        $i++
        if ($i -lt $MessageArg.Count) {
          $message = $MessageArg[$i]
        }
      }
      default {
        # Игнорируем неизвестные параметры
      }
    }
  }
  
  if ([string]::IsNullOrWhiteSpace($message)) {
    Write-Host "[ERROR] Необходимо указать сообщение коммита" -ForegroundColor Red
    Write-Host "Использование: ergovcs commit -m `"Сообщение`"" -ForegroundColor Yellow
    exit 1
  }
  
  # 2. Получить UUID текущего репозитория
  $uuid = Get-CurrentRepositoryUuid
  if (-not $uuid) {
    Write-Host "[ERROR] Не удалось определить UUID репозитория." -ForegroundColor Red
    Write-Host "[INFO] Убедитесь, что репозиторий был клонирован или создан через команду clone/create." -ForegroundColor Yellow
    exit 1
  }
  
  # 3. Определить корень репозитория
  $repoRoot = Find-LocalRepositoryRoot
  if (-not $repoRoot) {
    Write-Host "[ERROR] Не удалось найти репозиторий. Убедитесь, что вы находитесь в директории репозитория." -ForegroundColor Red
    exit 1
  }
  
  # 4. Прочитать staging area
  $stagingFile = Join-Path $repoRoot ".ergovcs" "staging.json"
  if (-not (Test-Path $stagingFile)) {
    Write-Host "[ERROR] Staging area не найден. Используйте команду 'add' для добавления файлов." -ForegroundColor Red
    exit 1
  }
  
  try {
    $stagingJson = Get-Content $stagingFile -Raw -Encoding UTF8
    $staging = $stagingJson | ConvertFrom-Json -ErrorAction Stop
  }
  catch {
    Write-Host "[ERROR] Не удалось прочитать staging area: $_" -ForegroundColor Red
    exit 1
  }
  
  # 5. Проверить, есть ли файлы в staging area
  if (-not $staging.files -or $staging.files.Count -eq 0) {
    Write-Host "[ERROR] Нет файлов в staging area. Используйте команду 'add' для добавления файлов." -ForegroundColor Red
    exit 1
  }
  
  # 6. Проверить, есть ли уже pending_commit
  # Если есть, обновляем его и добавляем новые файлы
  if ($staging.pending_commit) {
    Write-Host "[INFO] Обнаружен незавершенный коммит. Файлы будут добавлены к существующему коммиту." -ForegroundColor Yellow
    
    # Обновляем сообщение коммита
    $staging.pending_commit.message = $message
    $staging.pending_commit.created_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    # Сохраняем обновленный staging area
    $jsonContent = $staging | ConvertTo-Json -Depth 10
    Set-Content -Path $stagingFile -Value $jsonContent -Encoding UTF8 -Force
    
    Write-Host "[OK] Коммит обновлен. Сообщение: $message" -ForegroundColor Green
    Write-Host "[INFO] Всего файлов в коммите: $($staging.files.Count)" -ForegroundColor Cyan
    Write-Host "[INFO] Используйте команду 'push' для отправки коммита на сервер." -ForegroundColor Yellow
    return
  }
  
  # 7. Создаем новый pending_commit
  $staging.pending_commit = @{
    message = $message
    created_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    author = $env:USERNAME
  }
  
  # 8. Сохраняем staging area с pending_commit
  try {
    $jsonContent = $staging | ConvertTo-Json -Depth 10
    Set-Content -Path $stagingFile -Value $jsonContent -Encoding UTF8 -Force
    
    Write-Host "[OK] Коммит создан локально." -ForegroundColor Green
    Write-Host "Сообщение: $message" -ForegroundColor Cyan
    Write-Host "Файлов: $($staging.files.Count)" -ForegroundColor Cyan
    Write-Host "[INFO] Используйте команду 'push' для отправки коммита на сервер." -ForegroundColor Yellow
  }
  catch {
    Write-Host "[ERROR] Не удалось сохранить коммит: $_" -ForegroundColor Red
    exit 1
  }
}

# ============================================================================
# Отправка изменений на сервер
# Команда: ergovcs push <ветка>
# Отправляет изменения в папку media/version_management/<UUID>/
# ============================================================================
function Invoke-Push {
  param([string[]]$Args)
  
  # TODO: Реализовать отправку изменений на сервер
  # 1. Получить название ветки из аргументов
  # 2. Получить UUID текущего репозитория
  # 3. Собрать все незакоммиченные изменения
  # 4. Вызвать API эндпоинт /api/repositories/{id}/push/
  # 5. Отправить изменения в папку media/version_management/<UUID>/
  
  $branch = $null
  
  for ($i = 0; $i -lt $Args.Count; $i++) {
    $branch = $Args[$i]
  }
  
  if (-not $branch) {
    Write-Host "[ERROR] Необходимо указать название ветки" -ForegroundColor Red
    Write-Host "Использование: ergovcs push <ветка>" -ForegroundColor Yellow
    exit 1
  }
  
  # TODO: Реализовать отправку изменений
  Write-Host "[INFO] Отправка изменений в ветку $branch..." -ForegroundColor Cyan
  Write-Host "[TODO] Получить UUID текущего репозитория" -ForegroundColor Yellow
  Write-Host "[TODO] Собрать незакоммиченные изменения" -ForegroundColor Yellow
  Write-Host "[TODO] Вызвать API /api/repositories/{id}/push/" -ForegroundColor Yellow
}

# ============================================================================
# Обновление локального репозитория
# Команда: ergovcs update <ветка>
# Подтягивает изменения с сервера на комп пользователя
# ============================================================================
function Invoke-Update {
  param([string[]]$Args)
  
  # TODO: Реализовать обновление локального репозитория
  # 1. Получить название ветки из аргументов
  # 2. Получить UUID текущего репозитория
  # 3. Вызвать API эндпоинт /api/repositories/{id}/update/
  # 4. Скачать изменения из папки media/version_management/<UUID>/ на локальный компьютер
  # Примечание: не важно какая ветка скачана у пользователя, программе всё равно куда она шлёт данные
  
  $branch = $null
  
  for ($i = 0; $i -lt $Args.Count; $i++) {
    $branch = $Args[$i]
  }
  
  if (-not $branch) {
    Write-Host "[ERROR] Необходимо указать название ветки" -ForegroundColor Red
    Write-Host "Использование: ergovcs update <ветка>" -ForegroundColor Yellow
    exit 1
  }
  
  # TODO: Реализовать обновление
  Write-Host "[INFO] Обновление локального репозитория из ветки $branch..." -ForegroundColor Cyan
  Write-Host "[TODO] Получить UUID текущего репозитория" -ForegroundColor Yellow
  Write-Host "[TODO] Вызвать API /api/repositories/{id}/update/" -ForegroundColor Yellow
  Write-Host "[TODO] Скачать изменения на локальный компьютер" -ForegroundColor Yellow
}

# ============================================================================
# Удаление репозитория
# Команда: ergovcs remove <UUID>
# Удаляет репозиторий с компа пользователя
# ============================================================================
function Invoke-Remove {
  param([string[]]$Args)
  
  # TODO: Реализовать удаление репозитория
  # 1. Получить UUID из аргументов
  # 2. Найти локальную копию репозитория
  # 3. Удалить локальную копию репозитория
  # Примечание: это удаляет только локальную копию, не репозиторий на сервере
  
  $uuid = $null
  
  for ($i = 0; $i -lt $Args.Count; $i++) {
    $uuid = $Args[$i]
  }
  
  if (-not $uuid) {
    Write-Host "[ERROR] Необходимо указать UUID репозитория" -ForegroundColor Red
    Write-Host "Использование: ergovcs remove <UUID>" -ForegroundColor Yellow
    exit 1
  }
  
  # TODO: Реализовать удаление локальной копии
  Write-Host "[INFO] Удаление локальной копии репозитория $uuid..." -ForegroundColor Cyan
  Write-Host "[TODO] Найти локальную копию репозитория" -ForegroundColor Yellow
  Write-Host "[TODO] Удалить локальную копию" -ForegroundColor Yellow
}

function Invoke-Create {
  param([string[]]$RepoArg)

  # Создание репозитория через API
  # Использует API эндпоинт /api/repositories/ для избежания дублирования функционала
  # Примечание: API не поддерживает description, поэтому параметр --description игнорируется

  $name = $null
  $localPath = $null

  for ($i = 0; $i -lt $RepoArg.Count; $i++) {
    switch ($RepoArg[$i]) {
      "--name" { 
        $i++
        if ($i -lt $RepoArg.Count) {
          $name = $RepoArg[$i]
        }
      }
      "-n" { 
        $i++
        if ($i -lt $RepoArg.Count) {
          $name = $RepoArg[$i]
        }
      }
      "--description" { 
        $i++; 
        Write-Host "[WARN] Параметр --description не поддерживается API и будет проигнорирован" -ForegroundColor Yellow 
      }
      "-d" { 
        $i++; 
        Write-Host "[WARN] Параметр --description не поддерживается API и будет проигнорирован" -ForegroundColor Yellow 
      }
      "--root" { 
        $i++
        if ($i -lt $RepoArg.Count) {
          $localPath = $RepoArg[$i]
          Write-Host "[INFO] Указан локальный путь: $localPath" -ForegroundColor Cyan 
        }
      }
      "-r" { 
        $i++
        if ($i -lt $RepoArg.Count) {
          $localPath = $RepoArg[$i]
          Write-Host "[INFO] Указан локальный путь: $localPath" -ForegroundColor Cyan 
        }
      }
    }
  }

  if (-not $name) { $name = Read-Host "Название репозитория" }
  
  # Если локальный путь не указан, используем текущую директорию
  if (-not $localPath) {
    $localPath = (Get-Location).Path
    Write-Host "[INFO] Используется текущая директория: $localPath" -ForegroundColor Cyan
  }

  Write-Host "[INFO] Создание репозитория через API..." -ForegroundColor Cyan

  $response = Invoke-ApiCreateRepository -Name $name

  if (-not $response) {
    Write-Host "[ERROR] Не удалось создать репозиторий" -ForegroundColor Red
    exit 1
  }

  # Парсим ответ от API
  try {
    $responseObj = $response | ConvertFrom-Json
    $repoId = $responseObj.public_id
    if (-not $repoId) { $repoId = $responseObj.id }
    $repoName = $responseObj.name
    $repoPath = $responseObj.path
    $createdAt = $responseObj.created_at
    if (-not $repoPath -and $repoId) {
      $repoPath = "media/version_management/$repoId"
    }

    # Создаем структуру данных для repos.json
    $repoData = @{
      "repositories" = @{
        "$repoId" = @{
          "uuid" = $repoId
          "local_path" = $localPath
          "remote_path" = $repoPath
          "current_branch" = "main"
          "last_updated" = if ($createdAt) { $createdAt } else { Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ" }
        }
      }
    }

    # Определяем путь для .ergovcs/repos.json
    $ergovcsPath = Join-Path $localPath ".ergovcs"
    $reposJsonPath = Join-Path $ergovcsPath "repos.json"
    
    # Создаем директорию .ergovcs, если она не существует
    if (-not (Test-Path $ergovcsPath)) {
      New-Item -ItemType Directory -Path $ergovcsPath -Force | Out-Null
      Write-Host "[INFO] Создана директория: $ergovcsPath" -ForegroundColor Cyan
    }
    
    # Проверяем, существует ли уже файл repos.json
    if (Test-Path $reposJsonPath) {
      # Читаем существующий файл
      $existingData = Get-Content $reposJsonPath -Raw | ConvertFrom-Json -AsHashtable
      
      # Добавляем или обновляем репозиторий
      if ($existingData.repositories -is [Hashtable]) {
        $existingData.repositories[$repoId] = $repoData.repositories[$repoId]
      } else {
        $existingData.repositories = $repoData.repositories
      }
      
      $jsonContent = $existingData | ConvertTo-Json -Depth 10
      Set-Content -Path $reposJsonPath -Value $jsonContent -Encoding UTF8
      Write-Host "[INFO] Обновлен файл: $reposJsonPath" -ForegroundColor Cyan
    } else {
      # Создаем новый файл
      $jsonContent = $repoData | ConvertTo-Json -Depth 10
      Set-Content -Path $reposJsonPath -Value $jsonContent -Encoding UTF8
      Write-Host "[INFO] Создан файл: $reposJsonPath" -ForegroundColor Cyan
    }

    Write-Host "[OK] Репозиторий создан и добавлен в конфигурацию." -ForegroundColor Green
    Write-Host "UUID: $repoId"
    Write-Host "Название: $repoName"
    Write-Host "Локальный путь: $localPath"
    Write-Host "Удаленный путь: $repoPath"
    Write-Host "Конфигурация сохранена в: $reposJsonPath"
    
    if ($createdAt) {
      Write-Host "Создан: $createdAt"
    }
  }
  catch {
    Write-Host "[ERROR] Не удалось распарсить ответ от API или создать конфигурацию" -ForegroundColor Red
    Write-Host "Ошибка: $_" -ForegroundColor Red
    Write-Host "Ответ от API: $response" -ForegroundColor Yellow
    exit 1
  }
}

function Invoke-Download {
  param([string[]]$Args)

  Detect-ProjectRoot

  $source = $null
  $uuid = $null
  $name = $null
  $manualRoot = $null

  for ($i = 0; $i -lt $Args.Count; $i++) {
    switch ($Args[$i]) {
      "--source" { $i++; $source = $Args[$i] }
      "--uuid"   { $i++; $uuid = $Args[$i] }
      "--name"   { $i++; $name = $Args[$i] }
      "--root"   { $i++; $manualRoot = $Args[$i] }
    }
  }

  if ($manualRoot) {
    $script:ProjectRoot = $manualRoot
    $script:MediaDir = Join-Path $script:ProjectRoot "media\version_management"
    New-Item -ItemType Directory -Force -Path $script:MediaDir | Out-Null
  }

  if (-not $source) {
    Write-Host "[ERROR] Нужно указать --source" -ForegroundColor Red
    exit 1
  }

  if (-not (Test-Path $source)) {
    Write-Host "[ERROR] Источник не найден: $source" -ForegroundColor Red
    exit 1
  }

  if (-not $uuid) { $uuid = New-Uuid }

  $target = Ensure-RepoDirs -Uuid $uuid
  Import-FromSource -Source $source -Target $target
  if ($name) { Save-Metadata -Target $target -Name $name -Description "" }

  Write-Host "[OK] Репозиторий импортирован." -ForegroundColor Green
  Write-Host "UUID: $uuid"
  Write-Host "Путь: $target"
}

