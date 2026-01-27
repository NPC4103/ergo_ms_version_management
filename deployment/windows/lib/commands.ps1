# Обработчики команд: clone, add, commit, push, update, remove, create, download

# ============================================================================
# Клонирование репозитория
# Команда: ergovcs clone <путь> <имя_или_uuid>
# ============================================================================
function Invoke-Clone {
  param([string[]]$Args)
  
  $targetPath = $null
  $repoIdentifier = $null

  # 1. Парсинг
  if ($Args.Count -ge 2) {
      $targetPath = $Args[0]
      $repoIdentifier = $Args[1]
  }
  elseif ($Args.Count -eq 1) {
      $targetPath = "."
      $repoIdentifier = $Args[0]
  }
  else {
      Write-Host "[ERROR] Использование: ergovcs clone <путь> <имя_или_uuid>" -ForegroundColor Red
      exit 1
  }

  $uuid = $repoIdentifier

  # 2. Поиск UUID (через API), если передано имя
  if ($repoIdentifier -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
      Write-Host "[INFO] Поиск репозитория по имени '$repoIdentifier'..." -ForegroundColor Cyan
      
      $listResponse = Invoke-ApiListRepositories # Эта функция из repo.ps1 нам все еще НУЖНА
      if (-not $listResponse) {
          Write-Host "[ERROR] Ошибка API." -ForegroundColor Red
          exit 1
      }
      
      try {
          $data = $listResponse | ConvertFrom-Json
          $repos = if ($data.results) { $data.results } else { $data }
          $found = $repos | Where-Object { $_.name -eq $repoIdentifier }
          
          if ($found) {
              $uuid = if ($found.public_id) { $found.public_id } else { $found.uuid }
              Write-Host "[INFO] Найден UUID: $uuid" -ForegroundColor Gray
          } else {
              Write-Host "[ERROR] Репозиторий не найден." -ForegroundColor Red
              exit 1
          }
      }
      catch {
          Write-Host "[ERROR] Ошибка обработки ответа API." -ForegroundColor Red
          exit 1
      }
  }

  # 3. Поиск папки media (Локальная ФС)
  $mediaPath = $null
  
  # Проверяем переменную окружения
  if ($env:ERGOVCS_MEDIA_PATH) {
      $mediaPath = $env:ERGOVCS_MEDIA_PATH
  }
  else {
      # Ищем вверх от текущей директории
      $current = Get-Location
      for ($i = 0; $i -lt 4; $i++) {
          $testPath = Join-Path $current.Path "media\version_management"
          if (Test-Path $testPath) {
              $mediaPath = $testPath
              break
          }
          $current = try { Get-Item (Split-Path $current.Path -Parent) } catch { $null }
          if (-not $current) { break }
      }
  }

  if (-not $mediaPath) {
      Write-Host "[ERROR] Не удалось найти папку 'media\version_management'." -ForegroundColor Red
      Write-Host "[HINT] Зайдите в папку проекта или установите переменную ERGOVCS_MEDIA_PATH" -ForegroundColor Yellow
      exit 1
  }

  $sourceRepoPath = Join-Path $mediaPath $uuid

  if (-not (Test-Path $sourceRepoPath)) {
      Write-Host "[ERROR] Папка репозитория отсутствует на диске: $sourceRepoPath" -ForegroundColor Red
      exit 1
  }

  # 4. Копирование (Copy-Item)
  if (-not (Test-Path $targetPath)) {
      New-Item -ItemType Directory -Force -Path $targetPath | Out-Null
  }
  $absTargetPath = Resolve-Path $targetPath

  Write-Host "[INFO] Копирование файлов из $sourceRepoPath..." -ForegroundColor Cyan
  
  # Recurse копирует содержимое
  Copy-Item -Path "$sourceRepoPath\*" -Destination $absTargetPath -Recurse -Force

  # 5. Обновление конфига
  $configDir = Join-Path $env:USERPROFILE ".ergovcs"
  $configFile = Join-Path $configDir "repos.json"
  if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Force -Path $configDir | Out-Null }

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

  $configData.repositories[$uuid] = @{
      uuid = $uuid
      local_path = $absTargetPath.Path
      remote_path = $sourceRepoPath
      current_branch = "main"
      last_updated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
  }

  $configData | ConvertTo-Json -Depth 10 | Set-Content $configFile -Encoding UTF8
  Write-Host "[OK] Репозиторий клонирован в $absTargetPath" -ForegroundColor Green
}

# ============================================================================
# Добавление файла для коммита
# Команда: ergovcs add <файл.расширение>
# Добавляет файл для коммита
# ============================================================================
function Invoke-Add {
  param([string[]]$Files)
  
  # 1. Определить корень репозитория
  $repoRoot = Find-LocalRepositoryRoot
  if (-not $repoRoot) {
    Write-Host "[ERROR] Не удалось определить корень репозитория." -ForegroundColor Red
    exit 1
  }
  
  # 2. Получить UUID репозитория
  $uuid = Get-CurrentRepositoryUuid -LocalPath $repoRoot
  if (-not $uuid) {
    Write-Host "[ERROR] Не удалось определить UUID репозитория." -ForegroundColor Red
    exit 1
  }
  
  # 3. Получить предыдущее состояние проекта
  $previousState = Get-ProjectContent -RepoUuid $uuid -LocalPath $repoRoot
  
  # 4. Загрузить правила игнорирования
  $ignorePatterns = @()
  $ergovcsIgnorePath = Join-Path $repoRoot ".ergovcsignore"
  if (Test-Path $ergovcsIgnorePath) {
    $ignorePatterns = Get-Content $ergovcsIgnorePath | Where-Object { 
      -not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith("#")
    } | ForEach-Object { $_.Trim() }
  }
  
  $ignorePatterns += ".*"
  $ignorePatterns += "*/.*"
  $ignorePatterns += ".venv"
  
  # 5. Если аргументы не переданы, сканируем всю директорию
  if ($Files.Count -eq 0) {
    Write-Host "[INFO] Сканирую все файлы и директории..." -ForegroundColor Cyan
    
    $Files = Get-AllItems -Path $repoRoot -RepoRoot $repoRoot -IgnorePatterns $ignorePatterns
    
    if ($Files.Count -eq 0) {
      Write-Host "[INFO] Нет файлов для добавления." -ForegroundColor Yellow
      exit 0
    }
    
    Write-Host "[INFO] Найдено элементов: $($Files.Count)" -ForegroundColor Gray
  }
  
  # 6. Создать директорию .ergovcs
  $ergovcsPath = Join-Path $repoRoot ".ergovcs"
  if (-not (Test-Path $ergovcsPath)) {
    New-Item -ItemType Directory -Path $ergovcsPath -Force | Out-Null
  }
  
  # 7. Прочитать текущий staging area
  $stagingFile = Join-Path $ergovcsPath "staging.json"
  $staging = @{
    repository_uuid = $uuid
    files = [System.Collections.ArrayList]@()
  }
  
  if (Test-Path $stagingFile) {
    try {
      $existingStaging = Get-Content $stagingFile -Raw -Encoding UTF8 | ConvertFrom-Json
      $staging.repository_uuid = $existingStaging.repository_uuid
      if ($existingStaging.files) {
        $staging.files = [System.Collections.ArrayList]@($existingStaging.files)
      }
    }
    catch {
      Write-Host "[WARNING] Не удалось прочитать существующий staging area." -ForegroundColor Yellow
    }
  }
  
  # 8. Обработать каждый файл/директорию
  $addedItems = @()
  $ignoredItems = @()
  $errors = @()
  
  foreach ($item in $Files) {
    if ([string]::IsNullOrWhiteSpace($item)) {
      continue
    }
    
    # Определяем полный путь
    $fullPath = if ([System.IO.Path]::IsPathRooted($item)) {
      $item
    } else {
      Join-Path (Get-Location).Path $item
    }
    
    # Получаем относительный путь
    try {
      $relativePath = [System.IO.Path]::GetRelativePath($repoRoot, $fullPath).Replace('\', '/')
    }
    catch {
      Write-Host "[ERROR] Не удалось определить относительный путь: $item" -ForegroundColor Red
      $errors += $item
      continue
    }
    
    # Проверяем игнорирование
    if (Test-Ignored -FilePath $relativePath -IgnorePatterns $ignorePatterns) {
      $ignoredItems += $relativePath
      continue
    }
    
    # Проверяем существование
    $exists = Test-Path $fullPath
    $isDirectory = $exists -and (Get-Item $fullPath -ErrorAction SilentlyContinue).PSIsContainer
    
    # Определяем тип изменения
    $action = Get-FileChangeType -FilePath $fullPath -LocalPath $repoRoot -PreviousState $previousState -IsDirectory $isDirectory
    
    if ($action -eq "unchanged") {
      continue
    }
    
    # Проверяем, не добавлен ли уже в staging
    $itemIndex = -1
    for ($j = 0; $j -lt $staging.files.Count; $j++) {
      if ($staging.files[$j].path -eq $relativePath) {
        $itemIndex = $j
        break
      }
    }
    
    # Создаем запись
    $itemEntry = [ordered]@{
      path = $relativePath
      action = $action
      is_directory = $isDirectory
      timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    
    # Добавляем дополнительные данные в зависимости от типа изменения
    switch ($action) {
      "created" {
        if (-not $isDirectory -and $exists) {
          try {
            $content = Get-Content $fullPath -Raw -Encoding UTF8
            $itemEntry.content = $content
            $itemEntry.hash = Get-FileContentHash -FilePath $fullPath
          }
          catch {
            Write-Host "[WARNING] Не удалось прочитать содержимое файла: $relativePath" -ForegroundColor Yellow
          }
        }
      }
      "updated" {
        if (-not $isDirectory -and $exists) {
          try {
            $content = Get-Content $fullPath -Raw -Encoding UTF8
            $itemEntry.content = $content
            $itemEntry.hash = Get-FileContentHash -FilePath $fullPath
            
            # Добавляем старый хеш, если есть
            $previousEntry = $previousState.structure | Where-Object { $_.path -eq $relativePath } | Select-Object -First 1
            if ($previousEntry -and $previousEntry.hash) {
              $itemEntry.old_hash = $previousEntry.hash
            }
          }
          catch {
            Write-Host "[WARNING] Не удалось прочитать содержимое файла: $relativePath" -ForegroundColor Yellow
          }
        }
      }
      "renamed" {
        # Ищем старый путь в предыдущем состоянии
        $previousEntry = $previousState.structure | Where-Object { 
          $_.path -ne $relativePath -and ($_.old_path -eq $relativePath -or $_.path -eq $relativePath)
        } | Select-Object -First 1
        
        if ($previousEntry) {
          $itemEntry.old_path = $previousEntry.path
          $itemEntry.hash = $previousEntry.hash
        }
      }
      "deleted" {
        # Для удаленных файлов получаем информацию из предыдущего состояния
        $previousEntry = $previousState.structure | Where-Object { $_.path -eq $relativePath } | Select-Object -First 1
        if ($previousEntry) {
          $itemEntry.is_directory = $previousEntry.is_directory
          $itemEntry.hash = $previousEntry.hash
        }
      }
    }
    
    # Обновляем или добавляем запись
    if ($itemIndex -ge 0) {
      $staging.files[$itemIndex] = $itemEntry
    } else {
      $null = $staging.files.Add($itemEntry)
    }
    
    $addedItems += @{
      path = $relativePath
      action = $action
      is_directory = $isDirectory
    }
    
    Write-Host "[OK] Добавлено: $relativePath ($action)" -ForegroundColor Green
  }
  
  # 9. Сохранить staging area
  try {
    $jsonContent = $staging | ConvertTo-Json -Depth 10
    Set-Content -Path $stagingFile -Value $jsonContent -Encoding UTF8 -Force
    
    # Выводим статистику
    if ($addedItems.Count -gt 0) {
      Write-Host "`n[OK] Статистика добавленных изменений:" -ForegroundColor Green
      
      $actionGroups = $addedItems | Group-Object -Property action
      foreach ($group in $actionGroups) {
        $count = $group.Count
        $dirCount = ($group.Group | Where-Object { $_.is_directory }).Count
        $fileCount = $count - $dirCount
        
        Write-Host "  $($group.Name): $count" -ForegroundColor Cyan
        if ($fileCount -gt 0) {
          Write-Host "    Файлов: $fileCount" -ForegroundColor Gray
        }
        if ($dirCount -gt 0) {
          Write-Host "    Директорий: $dirCount" -ForegroundColor Gray
        }
      }
    }
    
    if ($ignoredItems.Count -gt 0) {
      Write-Host "`n[INFO] Проигнорировано: $($ignoredItems.Count)" -ForegroundColor Yellow
    }
    
    if ($errors.Count -gt 0) {
      Write-Host "`n[ERROR] Ошибки при обработке: $($errors.Count)" -ForegroundColor Red
      exit 1
    }
  }
  catch {
    Write-Host "[ERROR] Не удалось сохранить staging area: $_" -ForegroundColor Red
    exit 1
  }
}

# ============================================================================
# Создание коммита
# Команда: ergovcs commit --message "Сообщение" [--edit] [--save-message] [--save-changes]
# Создаёт коммит с изменениями
# ============================================================================
function Invoke-Commit {
  param([string[]]$MessageArg)
  
  # 1. Парсинг аргументов
  $message = $null
  $isChange = $false
  $saveMessageOnly = $false
  $saveFilesOnly = $false
  
  for ($i = 0; $i -lt $MessageArg.Count; $i++) {
      $arg = $MessageArg[$i]
      switch -Wildcard ($arg) {
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
          "-e" { $isChange = $true }
          "--edit" { $isChange = $true }
          "-sm" { $saveMessageOnly = $true }
          "--save-message" { $saveMessageOnly = $true }
          "-sc" { $saveFilesOnly = $true }
          "--save-changes" { $saveFilesOnly = $true }
          default {
              if (-not $message -and -not $arg.StartsWith("-")) {
                  $message = $arg
              }
          }
      }
  }
  
  # Валидация опций
  if ($saveMessageOnly -and $saveFilesOnly) {
      Write-Host "[ERROR] Опции --save-message и --save-changes не могут использоваться вместе." -ForegroundColor Red
      exit 1
  }
  
  if (($saveMessageOnly -or $saveFilesOnly) -and -not $isChange) {
      Write-Host "[ERROR] Опции --save-message и --save-changes требуют опции --edit." -ForegroundColor Red
      exit 1
  }
  
  if (-not $message -and -not $saveFilesOnly) {
      Write-Host "[ERROR] Необходимо указать сообщение коммита" -ForegroundColor Red
      Write-Host "Использование: ergovcs commit --message `"Сообщение`" [--edit] [--save-message] [--save-changes]" -ForegroundColor Yellow
      exit 1
  }
  
  # 2. Определить корень репозитория
  $repoRoot = Find-LocalRepositoryRoot
  if (-not $repoRoot) {
      Write-Host "[ERROR] Не удалось найти репозиторий." -ForegroundColor Red
      exit 1
  }
  
  # 3. Получить UUID текущего репозитория
  $uuid = Get-CurrentRepositoryUuid -LocalPath $repoRoot
  if (-not $uuid) {
      Write-Host "[ERROR] Не удалось определить UUID репозитория." -ForegroundColor Red
      exit 1
  }
  
  # 4. Прочитать staging area
  $stagingFile = Join-Path $repoRoot ".ergovcs" "staging.json"
  if (-not (Test-Path $stagingFile)) {
      Write-Host "[ERROR] Staging area не найден." -ForegroundColor Red
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
      Write-Host "[ERROR] Нет файлов в staging area." -ForegroundColor Red
      exit 1
  }
  
  # 6. Получить автора коммита
  $author = Get-CommitAuthor
  Write-Host "[INFO] Автор коммита: $author" -ForegroundColor Cyan
  
  # 7. Определить тип коммита
  $commitType = Get-CommitType -Files $staging.files -Message $message
  
  # Добавляем тип к сообщению, если его там нет
  $commitTypes = @("feat", "fix", "docs", "style", "refactor", "test", "chore", "perf", "ci", "build", "revert")
  $hasType = $false
  
  if ($message -match '^(\w+):') {
      $typeInMessage = $Matches[1]
      if ($commitTypes -contains $typeInMessage) {
          $hasType = true
      }
  }
  
  if (-not $hasType) {
      $message = "$commitType`: $message"
      Write-Host "[INFO] Автоматически определен тип коммита: $commitType" -ForegroundColor Cyan
  }
  
  # 8. Классификация изменений
  $actionStats = @{
      created = @{ count = 0; files = 0; dirs = 0 }
      updated = @{ count = 0; files = 0; dirs = 0 }
      deleted = @{ count = 0; files = 0; dirs = 0 }
      renamed = @{ count = 0; files = 0; dirs = 0 }
  }
  
  foreach ($file in $staging.files) {
      $action = $file.action
      if ($actionStats.ContainsKey($action)) {
          $actionStats[$action].count++
          if ($file.is_directory) {
              $actionStats[$action].dirs++
          } else {
              $actionStats[$action].files++
          }
      }
  }
  
  $changeSummary = @()
  foreach ($action in $actionStats.Keys) {
      if ($actionStats[$action].count -gt 0) {
          $summary = "$($actionStats[$action].count) $action"
          if ($actionStats[$action].files -gt 0) {
              $summary += " ($($actionStats[$action].files) файлов"
              if ($actionStats[$action].dirs -gt 0) {
                  $summary += ", $($actionStats[$action].dirs) директорий"
              }
              $summary += ")"
          } elseif ($actionStats[$action].dirs -gt 0) {
              $summary += " ($($actionStats[$action].dirs) директорий)"
          }
          $changeSummary += $summary
      }
  }
  
  $changeSummaryStr = if ($changeSummary.Count -gt 0) { ($changeSummary -join ", ") } else { "нет изменений" }
  
  # 9. Обработка файла commit.json
  $commitFile = Join-Path $repoRoot ".ergovcs" "commit.json"
  $existingCommit = $null
  
  if (Test-Path $commitFile) {
      try {
          $existingCommitJson = Get-Content $commitFile -Raw -Encoding UTF8
          $existingCommit = $existingCommitJson | ConvertFrom-Json -ErrorAction Stop
      }
      catch {
          Write-Host "[WARNING] Не удалось прочитать существующий коммит." -ForegroundColor Yellow
          $existingCommit = $null
      }
  }
  
  # 10. Создание/обновление коммита
  $commit = @{
      repository_uuid = $uuid
      message = $message
      author = $author
      type = $commitType
      created_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
      files = @()
      change_summary = $changeSummaryStr
      stats = $actionStats
  }
  
  if ($isChange -and $existingCommit) {
      Write-Host "[INFO] Обновление существующего коммита..." -ForegroundColor Yellow
      
      # Сохраняем исходные данные
      $commit.created_at = $existingCommit.created_at
      
      if ($saveMessageOnly) {
          $commit.message = $message
          $commit.type = $commitType
          $commit.files = $existingCommit.files
          Write-Host "[INFO] Обновлено только сообщение коммита." -ForegroundColor Cyan
      }
      elseif ($saveFilesOnly) {
          $commit.message = $existingCommit.message
          $commit.type = $existingCommit.type
          $commit.files = $staging.files
          Write-Host "[INFO] Обновлены только файлы в коммите." -ForegroundColor Cyan
      }
      else {
          $commit.message = $message
          $commit.type = $commitType
          $commit.files = $staging.files
          Write-Host "[INFO] Коммит полностью перезаписан." -ForegroundColor Cyan
      }
  }
  else {
      $commit.files = $staging.files
  }
  
  # 11. Сохранить коммит в файл commit.json
  try {
      $jsonContent = $commit | ConvertTo-Json -Depth 10
      Set-Content -Path $commitFile -Value $jsonContent -Encoding UTF8 -Force
      
      Write-Host "`n[OK] Коммит создан локально." -ForegroundColor Green
      Write-Host "Тип: $($commit.type)" -ForegroundColor Cyan
      Write-Host "Сообщение: $($commit.message)" -ForegroundColor Cyan
      Write-Host "Автор: $($commit.author)" -ForegroundColor Cyan
      Write-Host "Изменения: $($commit.change_summary)" -ForegroundColor Cyan
      
      # 12. Очистить staging area (только если не сохраняем только сообщение)
      if (-not $saveMessageOnly) {
          $emptyStaging = @{
              repository_uuid = $uuid
              files = @()
          }
          $emptyStagingJson = $emptyStaging | ConvertTo-Json -Depth 10
          Set-Content -Path $stagingFile -Value $emptyStagingJson -Encoding UTF8 -Force
          Write-Host "[INFO] Staging area очищен." -ForegroundColor Cyan
      }
      
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
    param([string[]]$BranchArg)

    # 1. Получить название ветки из аргументов
    $branch = $null
    if ($BranchArg.Count -ge 1) {
        $branch = $BranchArg[0]
    }

    if (-not $branch) {
        Write-Host "[ERROR] Необходимо указать название ветки" -ForegroundColor Red
        Write-Host "Использование: ergovcs push <ветка>" -ForegroundColor Yellow
        exit 1
    }

    # 2. Определить корень репозитория
    $repoRoot = Find-LocalRepositoryRoot
    if (-not $repoRoot) {
        Write-Host "[ERROR] Не удалось найти репозиторий. Убедитесь, что вы находитесь в директории репозитория." -ForegroundColor Red
        exit 1
    }

    # 3. Получить UUID текущего репозитория
    $uuid = Get-CurrentRepositoryUuid -LocalPath $repoRoot
    if (-not $uuid) {
        Write-Host "[ERROR] Не удалось определить UUID репозитория." -ForegroundColor Red
        Write-Host "[INFO] Убедитесь, что репозиторий был клонирован или создан через команду clone/create." -ForegroundColor Yellow
        exit 1
    }

    # 4. Прочитать коммит из commit.json
    $commitFile = Join-Path $repoRoot ".ergovcs" "commit.json"
    if (-not (Test-Path $commitFile)) {
        Write-Host "[ERROR] Нет коммита для отправки. Создайте коммит с помощью команды 'commit'." -ForegroundColor Red
        exit 1
    }

    try {
        $commitJson = Get-Content $commitFile -Raw -Encoding UTF8
        $commit = $commitJson | ConvertFrom-Json -ErrorAction Stop
        
        if (-not $commit.files -or $commit.files.Count -eq 0) {
            Write-Host "[ERROR] Коммит не содержит файлов для отправки." -ForegroundColor Red
            exit 1
        }
    }
    catch {
        Write-Host "[ERROR] Не удалось прочитать коммит: $_" -ForegroundColor Red
        exit 1
    }

    # 5. Собрать данные для отправки
    $commitData = @{
        message = $commit.message
        author = $commit.author
        type = $commit.type
        created_at = $commit.created_at
        files = $commit.files
        change_summary = $commit.change_summary
        stats = $commit.stats
    }

    $commitDataJson = $commitData | ConvertTo-Json -Depth 10

    # 6. Вызвать API эндпоинт для отправки
    Write-Host "[INFO] Отправка коммита в ветку '$branch'..." -ForegroundColor Cyan
    
    $response = Invoke-ApiPushChanges -Uuid $uuid -Branch $branch -CommitData $commitDataJson
    
    if (-not $response) {
        Write-Host "[ERROR] Не удалось отправить изменения. Проверьте подключение к API." -ForegroundColor Red
        exit 1
    }

    try {
        $responseObj = $response | ConvertFrom-Json
        
        if ($responseObj.status -eq "success" -or $responseObj.detail -match "успешно") {
            Write-Host "[OK] Изменения успешно отправлены на сервер." -ForegroundColor Green
            
            # 7. Создать backup.json
            Save-BackupJson -LocalPath $repoRoot -RepoUuid $uuid
            
            # 8. Удалить commit.json после успешной отправки
            Remove-Item -Path $commitFile -Force -ErrorAction SilentlyContinue
            Write-Host "[INFO] Файл коммита удален." -ForegroundColor Gray
            
            # 9. Обновить информацию в конфиге
            Update-RepositoryConfig -Uuid $uuid -LastUpdated (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") -CurrentBranch $branch
            
            Write-Host "`n[SUCCESS] Коммит успешно отправлен в ветку '$branch'" -ForegroundColor Green
            Write-Host "Сообщение: $($commit.message)" -ForegroundColor Cyan
            Write-Host "Автор: $($commit.author)" -ForegroundColor Cyan
            Write-Host "Изменения: $($commit.change_summary)" -ForegroundColor Cyan
            
        } else {
            Write-Host "[ERROR] API вернул ошибку: $($responseObj.detail)" -ForegroundColor Red
            exit 1
        }
    }
    catch {
        Write-Host "[ERROR] Не удалось обработать ответ от API: $_" -ForegroundColor Red
        exit 1
    }
}

# ============================================================================
# Обновление локального репозитория
# Команда: ergovcs update <ветка>
# Подтягивает изменения с сервера на комп пользователя
# ============================================================================
function Invoke-Update {
    param([string[]]$BranchArg)

    # 1. Получить ветку
    if ($BranchArg.Count -eq 0) {
        Write-Host "[ERROR] Использование: ergovcs update <ветка>" -ForegroundColor Red
        exit 1
    }
    $branch = $BranchArg[0]

    # 2. Определить корень репозитория
    $repoRoot = Find-LocalRepositoryRoot
    if (-not $repoRoot) {
        Write-Host "[ERROR] Не в репозитории. Используйте 'clone' сначала." -ForegroundColor Red
        exit 1
    }

    # 3. Получить UUID и путь к репозиторию
    $uuid = Get-CurrentRepositoryUuid -LocalPath $repoRoot
    if (-not $uuid) {
        Write-Host "[ERROR] UUID не найден. Репозиторий не инициализирован." -ForegroundColor Red
        exit 1
    }

    Write-Host "[INFO] Запрос обновлений из ветки '$branch'..." -ForegroundColor Cyan

    # 4. Сохранить текущее состояние staging area (если есть)
    $stagingFile = Join-Path $repoRoot ".ergovcs" "staging.json"
    $stagingBackup = $null
    if (Test-Path $stagingFile) {
        try {
            $stagingJson = Get-Content $stagingFile -Raw -Encoding UTF8
            $stagingBackup = $stagingJson | ConvertFrom-Json -ErrorAction Stop
            $stagingBackupPath = Join-Path $repoRoot ".ergovcs" "staging.backup.json"
            $stagingJson | Set-Content -Path $stagingBackupPath -Encoding UTF8
            Write-Host "[INFO] Staging area сохранен для восстановления." -ForegroundColor Gray
        }
        catch {
            Write-Host "[WARNING] Не удалось сохранить staging area: $_" -ForegroundColor Yellow
        }
    }

    # 5. Вызов API для обновления
    $response = Invoke-ApiUpdateRepository -Uuid $uuid -Branch $branch
    
    if (-not $response) {
        Write-Host "[ERROR] Ошибка API при обновлении" -ForegroundColor Red
        
        # Восстановить staging area
        if ($stagingBackup) {
            $stagingBackupJson = $stagingBackup | ConvertTo-Json -Depth 10
            Set-Content -Path $stagingFile -Value $stagingBackupJson -Encoding UTF8
            Write-Host "[INFO] Staging area восстановлен." -ForegroundColor Gray
        }
        
        exit 1
    }

    # 6. Обработка ответа
    try {
        $result = $response | ConvertFrom-Json
        
        if ($result.files -and $result.files.Count -gt 0) {
            Write-Host "[OK] Получено $($result.files.Count) файлов для обновления" -ForegroundColor Green
            $updatedCount = 0
            $addedCount = 0
            $deletedCount = 0
            
            # 7. Применить изменения к файлам
            foreach ($file in $result.files) {
                $filePath = Join-Path $repoRoot $file.path
                
                switch ($file.action.ToLower()) {
                    "added" {
                        $dir = Split-Path $filePath -Parent
                        if (-not (Test-Path $dir)) {
                            New-Item -ItemType Directory -Force -Path $dir | Out-Null
                        }
                        
                        if ($file.content) {
                            Set-Content -Path $filePath -Value $file.content -Encoding UTF8
                        } elseif ($file.base64_content) {
                            $bytes = [System.Convert]::FromBase64String($file.base64_content)
                            [System.IO.File]::WriteAllBytes($filePath, $bytes)
                        }
                        
                        Write-Host "  [+] $($file.path)" -ForegroundColor Green
                        $addedCount++
                    }
                    "modified" {
                        if ($file.content) {
                            Set-Content -Path $filePath -Value $file.content -Encoding UTF8
                        } elseif ($file.base64_content) {
                            $bytes = [System.Convert]::FromBase64String($file.base64_content)
                            [System.IO.File]::WriteAllBytes($filePath, $bytes)
                        }
                        
                        Write-Host "  [~] $($file.path)" -ForegroundColor Yellow
                        $updatedCount++
                    }
                    "deleted" {
                        if (Test-Path $filePath) {
                            Remove-Item -Path $filePath -Force
                            Write-Host "  [-] $($file.path)" -ForegroundColor Red
                            $deletedCount++
                        }
                    }
                }
            }
            
            # 8. Создать backup.json с новым состоянием
            Save-BackupJson -LocalPath $repoRoot -RepoUuid $uuid
            
            # 9. Обновить конфиг
            Update-RepositoryConfig -Uuid $uuid -LastUpdated (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") -CurrentBranch $branch
            
            Write-Host "`n[SUCCESS] Локальный репозиторий обновлен" -ForegroundColor Green
            Write-Host "Добавлено: $addedCount файлов" -ForegroundColor Green
            Write-Host "Обновлено: $updatedCount файлов" -ForegroundColor Yellow
            Write-Host "Удалено: $deletedCount файлов" -ForegroundColor Red
            
        }
        elseif ($result.message -or $result.detail) {
            Write-Host "[INFO] $($result.message)$($result.detail)" -ForegroundColor Cyan
        }
        else {
            Write-Host "[INFO] Нет новых изменений в ветке '$branch'" -ForegroundColor Yellow
            
            # Все равно обновляем backup.json
            Save-BackupJson -LocalPath $repoRoot -RepoUuid $uuid
        }
        
        # 10. Удалить staging backup
        $stagingBackupPath = Join-Path $repoRoot ".ergovcs" "staging.backup.json"
        if (Test-Path $stagingBackupPath) {
            Remove-Item -Path $stagingBackupPath -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Host "[WARNING] Ответ API не в JSON формате: $response" -ForegroundColor Yellow
        Write-Host "[ERROR] Ошибка при обработке ответа: $_" -ForegroundColor Red
        
        # Восстановить staging area
        if ($stagingBackup) {
            $stagingBackupJson = $stagingBackup | ConvertTo-Json -Depth 10
            Set-Content -Path $stagingFile -Value $stagingBackupJson -Encoding UTF8
            Write-Host "[INFO] Staging area восстановлен." -ForegroundColor Gray
        }
        
        exit 1
    }
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

  if (Test-Path -LiteralPath $localPath) {
    try {
      $item = Get-Item -LiteralPath $localPath -ErrorAction Stop
      if ($item.PSIsContainer) {
        Remove-Item -LiteralPath $localPath -Recurse -Force -ErrorAction Stop
      } else {
        Remove-Item -LiteralPath $localPath -Force -ErrorAction Stop
      }
      Write-Host "[OK] Локальная копия удалена: $localPath" -ForegroundColor Green
    } catch {
      Write-Host "[ERROR] Не удалось удалить локальную копию: $localPath" -ForegroundColor Red
      Write-Host $_.Exception.Message -ForegroundColor Yellow
      exit 1
    }
  } else {
    Write-Host "[WARN] Локальный путь не найден на диске: $localPath" -ForegroundColor Yellow
    Write-Host "[INFO] Запись всё равно будет удалена из конфига." -ForegroundColor Yellow
  }

  # Удаляем запись из repos.json
  $null = $repos.PSObject.Properties.Remove($uuid)
  $data.repositories = $repos

  try {
    $jsonOut = $data | ConvertTo-Json -Depth 10
    $jsonOut | Set-Content -Path $reposFile -Encoding UTF8
    Write-Host "[OK] Запись удалена из конфига: $reposFile" -ForegroundColor Green
  } catch {
    Write-Host "[ERROR] Не удалось обновить файл конфига: $reposFile" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    exit 1
  }
}

function Invoke-Create {
  param([string[]]$RepoArg)

  $name = $null
  $description = $null
  $isPrivate = $false
  $isReadOnly = $false
  $branchName = $null
  $cliUsername = $null
  $cliPassword = $null
  $localPath = $null

  for ($i = 0; $i -lt $RepoArg.Count; $i++) {
    $arg = $RepoArg[$i]
    switch -Wildcard ($arg) {
      "--name" { $i++; if ($i -lt $RepoArg.Count) { $name = $RepoArg[$i] } }
      "-n" { $i++; if ($i -lt $RepoArg.Count) { $name = $RepoArg[$i] } }
      "--description" { $i++; if ($i -lt $RepoArg.Count) { $description = $RepoArg[$i] } }
      "-d" { $i++; if ($i -lt $RepoArg.Count) { $description = $RepoArg[$i] } }
      "--private" { $isPrivate = $true }
      "-p" { $isPrivate = $true }
      "--read-only" { $isReadOnly = $true }
      "--branch" { $i++; if ($i -lt $RepoArg.Count) { $branchName = $RepoArg[$i] } }
      "-b" { $i++; if ($i -lt $RepoArg.Count) { $branchName = $RepoArg[$i] } }
      "--username" { $i++; if ($i -lt $RepoArg.Count) { $cliUsername = $RepoArg[$i] } }
      "-u" { $i++; if ($i -lt $RepoArg.Count) { $cliUsername = $RepoArg[$i] } }
      "--password" { $i++; if ($i -lt $RepoArg.Count) { $cliPassword = $RepoArg[$i] } }
      "-pw" { $i++; if ($i -lt $RepoArg.Count) { $cliPassword = $RepoArg[$i] } }
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
      default {
        if (-not $name -and -not $arg.StartsWith("-")) {
          $name = $arg
        }
      }
    }
  }

  if (-not $name) {
    $name = Read-Host "Название репозитория"
  }
  if (-not $name) {
    Write-Host "[ERROR] Необходимо указать название репозитория" -ForegroundColor Red
    exit 1
  }

  if (-not $localPath) {
    $localPath = (Get-Location).Path
  }

  if (-not (Test-Path $localPath)) {
    New-Item -ItemType Directory -Force -Path $localPath | Out-Null
  }
  $localPath = (Resolve-Path $localPath).Path

  if ($cliUsername -or $cliPassword) {
    if (-not $cliUsername -or -not $cliPassword) {
      Write-Host "[WARN] Для авторизации нужны --username и --password (оба)." -ForegroundColor Yellow
    }
  }

  $bodyObj = @{}
  if ($name) { $bodyObj["name"] = $name }
  if ($description) { $bodyObj["description"] = $description }
  if ($isPrivate) { $bodyObj["is_private"] = $true }
  if ($isReadOnly) { $bodyObj["is_read_only"] = $true }
  if ($branchName) { $bodyObj["initial_branch_name"] = $branchName }
  if ($cliUsername) { $bodyObj["cli_username"] = $cliUsername }
  if ($cliPassword) { $bodyObj["cli_password"] = $cliPassword }

  $bodyJson = $bodyObj | ConvertTo-Json -Depth 5

  Write-Host "[INFO] Создание репозитория через API..." -ForegroundColor Cyan
  $response = Invoke-ApiRequest -Method "POST" -Endpoint "/repositories/" -Body $bodyJson

  if (-not $response) {
    Write-Host "[ERROR] Не удалось создать репозиторий" -ForegroundColor Red
    exit 1
  }

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

    $ergovcsPath = Join-Path $localPath ".ergovcs"
    $reposJsonPath = Join-Path $ergovcsPath "repos.json"
    if (-not (Test-Path $ergovcsPath)) {
      New-Item -ItemType Directory -Path $ergovcsPath -Force | Out-Null
    }

    $repoEntry = @{
      "uuid" = $repoId
      "local_path" = $localPath
      "remote_path" = $repoPath
      "current_branch" = if ($branchName) { $branchName } else { "main" }
      "last_updated" = if ($createdAt) { $createdAt } else { Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ" }
    }

    if (Test-Path $reposJsonPath) {
      $existingData = Get-Content $reposJsonPath -Raw | ConvertFrom-Json -AsHashtable
      if (-not ($existingData.repositories -is [Hashtable])) {
        $existingData.repositories = @{}
      }
      $existingData.repositories[$repoId] = $repoEntry
      $jsonContent = $existingData | ConvertTo-Json -Depth 10
      Set-Content -Path $reposJsonPath -Value $jsonContent -Encoding UTF8
    } else {
      $repoData = @{ repositories = @{ "$repoId" = $repoEntry } }
      $jsonContent = $repoData | ConvertTo-Json -Depth 10
      Set-Content -Path $reposJsonPath -Value $jsonContent -Encoding UTF8
    }

    $ignoreFile = Join-Path $localPath ".ergovcsignore"
    if (-not (Test-Path $ignoreFile)) {
      '.ergovcs/' | Set-Content -Path $ignoreFile -Encoding ASCII
    }

    $readmeFile = Join-Path $localPath "README.md"
    if (-not (Test-Path $readmeFile)) {
      @(
        "# Repository",
        "",
        "Created by ergovcs."
      ) -join "`r`n" | Set-Content -Path $readmeFile -Encoding ASCII
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

# ============================================================================
# Управление ветками
# Команда: ergovcs branch <list|create|delete|set-default> ...
# ============================================================================
function Invoke-Branch {
param([string[]]$Args)

if (-not $Args -or $Args.Count -eq 0) {
  Write-Host "[ERROR] Использование: ergovcs branch <list|create|delete|set-default>" -ForegroundColor Red
  exit 1
}

$action = $Args[0]
$repoUuid = $null
$branchName = $null
$branchId = $null
$cliUsername = $null
$cliPassword = $null
$checkPermissions = $true

for ($i = 1; $i -lt $Args.Count; $i++) {
  switch ($Args[$i]) {
    "--repo" { $i++; if ($i -lt $Args.Count) { $repoUuid = $Args[$i] } }
    "--name" { $i++; if ($i -lt $Args.Count) { $branchName = $Args[$i] } }
    "--id" { $i++; if ($i -lt $Args.Count) { $branchId = $Args[$i] } }
    "--username" { $i++; if ($i -lt $Args.Count) { $cliUsername = $Args[$i] } }
    "-u" { $i++; if ($i -lt $Args.Count) { $cliUsername = $Args[$i] } }
    "--password" { $i++; if ($i -lt $Args.Count) { $cliPassword = $Args[$i] } }
    "-pw" { $i++; if ($i -lt $Args.Count) { $cliPassword = $Args[$i] } }
    "--no-check-permissions" { $checkPermissions = $false }
  }
}

if ($cliUsername -or $cliPassword) {
  if (-not $cliUsername -or -not $cliPassword) {
    Write-Host "[WARN] Для авторизации нужны --username и --password (оба)." -ForegroundColor Yellow
  }
}

switch ($action) {
  "list" {
    if (-not $repoUuid) {
      Write-Host "[ERROR] Нужно указать --repo <UUID>" -ForegroundColor Red
      exit 1
    }
    $response = Invoke-ApiListBranches -RepoUuid $repoUuid
    if (-not $response) { exit 1 }
    $data = $response | ConvertFrom-Json
    $branches = if ($data.branches) { $data.branches } else { $data }
    foreach ($b in $branches) {
      Write-Host ("- {0} (id={1}, default={2})" -f $b.name, $b.id, $b.is_default)
    }
  }
  "create" {
    if (-not $repoUuid -or -not $branchName) {
      Write-Host "[ERROR] Нужно указать --repo <UUID> и --name <ветка>" -ForegroundColor Red
      exit 1
    }
    Invoke-ApiCreateBranch -RepoUuid $repoUuid -BranchName $branchName -CliUsername $cliUsername -CliPassword $cliPassword -CheckPermissions:$checkPermissions | Out-Null
    Write-Host "[OK] Ветка создана: $branchName" -ForegroundColor Green
  }
  "delete" {
    if (-not $branchId) {
      if ($repoUuid -and $branchName) {
        $response = Invoke-ApiListBranches -RepoUuid $repoUuid
        if ($response) {
          $data = $response | ConvertFrom-Json
          $branches = if ($data.branches) { $data.branches } else { $data }
          $match = $branches | Where-Object { $_.name -eq $branchName } | Select-Object -First 1
          if ($match) { $branchId = $match.id }
        }
      }
    }
    if (-not $branchId) {
      Write-Host "[ERROR] Нужно указать --id <branch_id> (или --repo + --name для поиска)" -ForegroundColor Red
      exit 1
    }
    Invoke-ApiDeleteBranch -BranchId $branchId | Out-Null
    Write-Host "[OK] Ветка удалена (id=$branchId)" -ForegroundColor Green
  }
  "set-default" {
    if ($branchId) {
      Invoke-ApiSetDefaultBranchById -BranchId $branchId -CliUsername $cliUsername -CliPassword $cliPassword -CheckPermissions:$checkPermissions | Out-Null
      Write-Host "[OK] Ветка установлена по умолчанию (id=$branchId)" -ForegroundColor Green
    }
    elseif ($repoUuid -and $branchName) {
      Invoke-ApiSetDefaultBranchByName -RepoUuid $repoUuid -BranchName $branchName -CliUsername $cliUsername -CliPassword $cliPassword -CheckPermissions:$checkPermissions | Out-Null
      Write-Host "[OK] Ветка установлена по умолчанию: $branchName" -ForegroundColor Green
    }
    else {
      Write-Host "[ERROR] Нужно указать --id <branch_id> или --repo <UUID> и --name <ветка>" -ForegroundColor Red
      exit 1
    }
  }
  default {
    Write-Host "[ERROR] Неизвестное действие: $action" -ForegroundColor Red
    exit 1
  }
}
}

# ============================================================================
# Древо файлов репозитория
# Команда: ergovcs files --repo <UUID>
# ============================================================================
function Invoke-Files {
param([string[]]$Args)

$repoUuid = $null
for ($i = 0; $i -lt $Args.Count; $i++) {
  switch ($Args[$i]) {
    "--repo" { $i++; if ($i -lt $Args.Count) { $repoUuid = $Args[$i] } }
  }
}

if (-not $repoUuid) {
  Write-Host "[ERROR] Нужно указать --repo <UUID>" -ForegroundColor Red
  exit 1
}

$response = Invoke-ApiGetRepoFiles -RepoUuid $repoUuid
if (-not $response) { exit 1 }

$data = $response | ConvertFrom-Json
$items = if ($data.structure) { $data.structure } else { $data.items }

function Render-Tree($items, $prefix) {
  if (-not $items) { return }
  for ($i = 0; $i -lt $items.Count; $i++) {
    $item = $items[$i]
    $isLast = ($i -eq $items.Count - 1)
    $connector = if ($isLast) { "└── " } else { "├── " }
    $name = $item.name
    if ($item.is_directory) {
      Write-Host "$prefix$connector$name/"
      $nextPrefix = $prefix + (if ($isLast) { "    " } else { "│   " })
      Render-Tree $item.items $nextPrefix
    } else {
      Write-Host "$prefix$connector$name"
    }
  }
}

Render-Tree $items ""
}

