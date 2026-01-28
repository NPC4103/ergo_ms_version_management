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
    Write-Host "[ERROR] Ispolzovanie: ergovcs clone <put> <imya_ili_uuid>" -ForegroundColor Red
    exit 1
  }

  $uuid = $repoIdentifier

  # 2. Поиск UUID (через API), если передано имя
  if ($repoIdentifier -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
    Write-Host "[INFO] Poisk repozitoriya po imeni '$repoIdentifier'..." -ForegroundColor Cyan
    
    $listResponse = Invoke-ApiListRepositories # Эта функция из repo.ps1 нам все еще НУЖНА
    if (-not $listResponse) {
      Write-Host "[ERROR] Oshibka API." -ForegroundColor Red
      exit 1
    }
    
    try {
      $data = $listResponse | ConvertFrom-Json
      $repos = if ($data.results) { $data.results } else { $data }
      $found = $repos | Where-Object { $_.name -eq $repoIdentifier }
      
      if ($found) {
        $uuid = if ($found.public_id) { $found.public_id } else { $found.uuid }
        Write-Host "[INFO] Najden UUID: $uuid" -ForegroundColor Gray
      } else {
        Write-Host "[ERROR] Repozitorij ne najden." -ForegroundColor Red
        exit 1
      }
    }
    catch {
      Write-Host "[ERROR] Oshibka obrabotki otveta API." -ForegroundColor Red
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
    Write-Host "[ERROR] Ne udalos najti papku 'media\version_management'." -ForegroundColor Red
    Write-Host "[HINT] Zajdite v papku proekta ili ustanovite peremennuyu ERGOVCS_MEDIA_PATH" -ForegroundColor Yellow
    exit 1
  }

  $sourceRepoPath = Join-Path $mediaPath $uuid

  if (-not (Test-Path $sourceRepoPath)) {
    Write-Host "[ERROR] Papka repozitoriya otsutstvuet na diske: $sourceRepoPath" -ForegroundColor Red
    exit 1
  }

  # 4. Копирование (Copy-Item)
  if (-not (Test-Path $targetPath)) {
    New-Item -ItemType Directory -Force -Path $targetPath | Out-Null
  }
  $absTargetPath = Resolve-Path $targetPath

  Write-Host "[INFO] Kopirovanie fajlov iz $sourceRepoPath..." -ForegroundColor Cyan
  
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
  Write-Host "[OK] Repozitorij klonirovan v $absTargetPath" -ForegroundColor Green
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
    Write-Host "[ERROR] Ne udalos opredelit koren repozitoriya." -ForegroundColor Red
    exit 1
  }
  
  # 2. Получить UUID репозитория
  $uuid = Get-CurrentRepositoryUuid -LocalPath $repoRoot
  if (-not $uuid) {
    Write-Host "[ERROR] Ne udalos opredelit UUID repozitoriya." -ForegroundColor Red
    exit 1
  }
  
  # 3. Получить предыдущее состояние проекта
  $previousState = Get-ProjectContent -RepoUuid $uuid -LocalPath $repoRoot
  
  # 4. Загрузить правила игнорирования
  $ignorePatternsArray = @()
  $ergovcsIgnorePath = Join-Path $repoRoot ".ergovcsignore"
  if (Test-Path $ergovcsIgnorePath) {
    $patternsFromFile = Get-Content $ergovcsIgnorePath | Where-Object { 
      -not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith("#")
    } | ForEach-Object { $_.Trim() }
    if ($patternsFromFile) {
      $ignorePatternsArray += $patternsFromFile
    }
  }
  
  # Добавляем стандартные паттерны игнорирования (файлы/директории, начинающиеся с точки)
  $ignorePatternsArray += ".*"
  $ignorePatternsArray += "*/.*"
  
  # 5. Если аргументы не переданы, сканируем всю директорию
  if ($Files.Count -eq 0) {
    Write-Host "[INFO] Skaniruyu vse fajly i direktorii (isklyuchaya ignoriruemye)..." -ForegroundColor Cyan
    
    # Используем улучшенную функцию с фильтрацией
    # Исключаем .ergovcs директорию из сканирования
    $allItems = Get-ChildItem -Path $repoRoot -Recurse -Force | Where-Object {
      $_.FullName -notlike "*\.ergovcs*"
    } | ForEach-Object {
      $relativePath = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/')
      if (-not (Test-Ignored -FilePath $relativePath -IgnorePatterns $ignorePatternsArray)) {
        $relativePath
      }
    }
    
    if ($allItems.Count -eq 0) {
      Write-Host "[INFO] Net fajlov dlya dobavleniya (vse fajly ignoriruyutsya ili otsutstvuyut)." -ForegroundColor Yellow
      exit 0
    }
    
    Write-Host "[INFO] Najdeno elementov: $($allItems.Count)" -ForegroundColor Gray
    $Files = $allItems
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
      Write-Host "[WARNING] Ne udalos prochitat sushchestvuyushchij staging area." -ForegroundColor Yellow
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
      Write-Host "[ERROR] Ne udalos opredelit otnositelnyj put: $item" -ForegroundColor Red
      $errors += $item
      continue
    }
    
    # Проверяем игнорирование
    if (Test-Ignored -FilePath $relativePath -IgnorePatterns $ignorePatternsArray) {
      $ignoredItems += $relativePath
      Write-Host "[IGNORE] Ignorirovano: $relativePath" -ForegroundColor DarkGray
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
            Write-Host "[WARNING] Ne udalos prochitat soderzhimoe fajla: $relativePath" -ForegroundColor Yellow
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
            Write-Host "[WARNING] Ne udalos prochitat soderzhimoe fajla: $relativePath" -ForegroundColor Yellow
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
    
    Write-Host "[OK] Dobavleno: $relativePath ($action)" -ForegroundColor Green
  }
  
  # 9. Сохранить staging area
  try {
    $jsonContent = $staging | ConvertTo-Json -Depth 10
    Set-Content -Path $stagingFile -Value $jsonContent -Encoding UTF8 -Force
    
    # Выводим статистику
    if ($addedItems.Count -gt 0) {
      Write-Host "`n[OK] Statistika dobavlennyh izmenenij:" -ForegroundColor Green
      
      $actionGroups = $addedItems | Group-Object -Property action
      foreach ($group in $actionGroups) {
        $count = $group.Count
        $dirCount = ($group.Group | Where-Object { $_.is_directory }).Count
        $fileCount = $count - $dirCount
        
        Write-Host "  $($group.Name): $count" -ForegroundColor Cyan
        if ($fileCount -gt 0) {
          Write-Host "    Fajlov: $fileCount" -ForegroundColor Gray
        }
        if ($dirCount -gt 0) {
          Write-Host "    Direktorij: $dirCount" -ForegroundColor Gray
        }
      }
    }
    
    if ($ignoredItems.Count -gt 0) {
      Write-Host "`n[INFO] Proignorirovano: $($ignoredItems.Count)" -ForegroundColor Yellow
    }
    
    if ($errors.Count -gt 0) {
      Write-Host "`n[ERROR] Oshibki pri obrabotke: $($errors.Count)" -ForegroundColor Red
      exit 1
    }
  }
  catch {
    Write-Host "[ERROR] Ne udalos sohranit staging area: $_" -ForegroundColor Red
    exit 1
  }
}

# ============================================================================
# Создание коммита
# Команда: ergovcs commit --message "Сообщение"
# Создаёт коммит через API
# ============================================================================
function Invoke-Commit {
  param([string[]]$MessageArg)
  
  $message = $null
  
  for ($i = 0; $i -lt $MessageArg.Count; $i++) {
    $arg = $MessageArg[$i]
    switch -Wildcard ($arg) {
      "-m" { 
        $i++
        if ($i -lt $MessageArg.Count) {
            $message = $MessageArg[$i]
        } else {
            $message = ""
        }
      }
      "--message" { 
        $i++
        if ($i -lt $MessageArg.Count) {
            $message = $MessageArg[$i]
        } else {
            $message = ""
        }
      }
      default {
        if (-not $message -and -not $arg.StartsWith("-")) {
            $message = $arg
        }
      }
    }
  }
  
  # Определить корень репозитория
  $repoRoot = Find-LocalRepositoryRoot
  if (-not $repoRoot) {
    Write-Host "[ERROR] Ne udalos najti repozitorij." -ForegroundColor Red
    exit 1
  }
  
  # 3. Получить UUID текущего репозитория
  $uuid = Get-CurrentRepositoryUuid -LocalPath $repoRoot
  if (-not $uuid) {
    Write-Host "[ERROR] Ne udalos opredelit UUID repozitoriya." -ForegroundColor Red
    exit 1
  }
  
  # 4. Прочитать staging area
  $stagingFile = Join-Path $repoRoot ".ergovcs" "staging.json"
  if (-not (Test-Path $stagingFile)) {
    Write-Host "[ERROR] Staging area ne najden." -ForegroundColor Red
    exit 1
  }
  
  try {
    $stagingJson = Get-Content $stagingFile -Raw -Encoding UTF8
    $staging = $stagingJson | ConvertFrom-Json -ErrorAction Stop
  }
  catch {
    Write-Host "[ERROR] Ne udalos prochitat staging area: $_" -ForegroundColor Red
    exit 1
  }
  
  if (-not $staging.files -or $staging.files.Count -eq 0) {
    Write-Host "[ERROR] Net fajlov v staging area." -ForegroundColor Red
    exit 1
  }
  
  if ([string]::IsNullOrWhiteSpace($message)) {
    Write-Host "[INFO] Vvedite soobshchenie kommita:" -ForegroundColor Cyan
    $message = Read-Host "Message"
    if ([string]::IsNullOrWhiteSpace($message)) {
      Write-Host "[ERROR] Soobshchenie kommita ne mozhet byt pustym." -ForegroundColor Red
      exit 1
    }
  }
  
  # 5. Определить тип коммита
  $originalMessage = $message
  $commitType = Get-CommitType -Files $staging.files -Message $originalMessage
  $message = "$commitType $message"

  $filesForApi = @($staging.files | ForEach-Object {
    @{
      path = $_.path
      content = if ($_.content) { $_.content } else { "" }
      action = if ($_.action) { $_.action } else { "modified" }
    }
  })
  
  $currentBranch = Get-CurrentBranch -LocalPath $repoRoot
  $response = Invoke-ApiCreateCommit -Uuid $uuid -Message $message -Files $filesForApi -Branch $currentBranch
  
  if (-not $response) {
    Write-Host "[ERROR] Ne udalos sozdat kommit cherez API." -ForegroundColor Red
    exit 1
  }
  
  try {
    $res = $response | ConvertFrom-Json -ErrorAction Stop
  }
  catch {
    Write-Host "[ERROR] Nevernyj otvet API: $_" -ForegroundColor Red
    exit 1
  }
  
  if (-not $res.success) {
    Write-Host "[ERROR] $($res.error)" -ForegroundColor Red
    exit 1
  }
  
  $commit = $res.commit
  Write-Host "`n[OK] Kommit sozdan cherez API." -ForegroundColor Green
  if ($commit) {
    Write-Host "Hash: $($commit.hash)" -ForegroundColor Cyan
    Write-Host "Message: $($commit.message)" -ForegroundColor Cyan
    Write-Host "Files: $($commit.files_count)" -ForegroundColor Cyan
    if ($commit.author) { Write-Host "Author: $($commit.author)" -ForegroundColor Cyan }
  }
  
  $emptyStaging = @{ repository_uuid = $uuid; files = @() }
  Set-Content -Path $stagingFile -Value ($emptyStaging | ConvertTo-Json -Depth 10) -Encoding UTF8 -Force
  Write-Host "[INFO] Staging area ochishchen." -ForegroundColor Cyan
  Write-Host "[INFO] Ispolzujte komandu 'push' dlya otpravki kommita na server." -ForegroundColor Yellow
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
    Write-Host "[ERROR] Neobhodimo ukazat nazvanie vetki" -ForegroundColor Red
    Write-Host "Usage: ergovcs push <branch>" -ForegroundColor Yellow
    exit 1
  }

  # 2. Определить корень репозитория
  $repoRoot = Find-LocalRepositoryRoot
  if (-not $repoRoot) {
    Write-Host "[ERROR] Ne udalos najti repozitorij. Ubedites chto vy nahodites v direktorii repozitoriya." -ForegroundColor Red
    exit 1
  }

  # 3. Получить UUID текущего репозитория
  $uuid = Get-CurrentRepositoryUuid -LocalPath $repoRoot
  if (-not $uuid) {
    Write-Host "[ERROR] Ne udalos opredelit UUID repozitoriya." -ForegroundColor Red
    Write-Host "[INFO] Ubedites chto repozitorij byl klonirovan ili sozdan cherez komandu clone/create." -ForegroundColor Yellow
    exit 1
  }

  # 4. Прочитать коммит из commit.json
  $commitFile = Join-Path $repoRoot ".ergovcs" "commit.json"
  if (-not (Test-Path $commitFile)) {
    Write-Host "[ERROR] Net kommita dlya otpravki. Sozdajte kommit s pomoshchyu komandy 'commit'." -ForegroundColor Red
    exit 1
  }

  try {
    $commitJson = Get-Content $commitFile -Raw -Encoding UTF8
    $commit = $commitJson | ConvertFrom-Json -ErrorAction Stop
    
    if (-not $commit.files -or $commit.files.Count -eq 0) {
      Write-Host "[ERROR] Kommit ne soderzhit fajlov dlya otpravki." -ForegroundColor Red
      exit 1
    }
  }
  catch {
    Write-Host "[ERROR] Ne udalos prochitat kommit: $_" -ForegroundColor Red
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
  Write-Host "[INFO] Otpravka kommita v vetku '$branch'..." -ForegroundColor Cyan
  
  $response = Invoke-ApiPushChanges -Uuid $uuid -Branch $branch -CommitData $commitDataJson
  
  if (-not $response) {
    Write-Host "[ERROR] Ne udalos otpravit izmeneniya. Proverte podklyuchenie k API." -ForegroundColor Red
    exit 1
  }

  try {
    $responseObj = $response | ConvertFrom-Json
    
    if ($responseObj.status -eq "success" -or $responseObj.detail -match "uspeshno") {
      Write-Host "[OK] Izmeneniya uspeshno otpravleny na server." -ForegroundColor Green
      
      # 7. Создать backup.json
      Save-BackupJson -LocalPath $repoRoot -RepoUuid $uuid
      
      # 8. Удалить commit.json после успешной отправки
      Remove-Item -Path $commitFile -Force -ErrorAction SilentlyContinue
      Write-Host "[INFO] Fajl kommita udalen." -ForegroundColor Gray
      
      # 9. Обновить информацию в конфиге
      Update-RepositoryConfig -Uuid $uuid -LastUpdated (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") -CurrentBranch $branch
      
      Write-Host "`n[SUCCESS] Kommit uspeshno otpravlen v vetku '$branch'" -ForegroundColor Green
      Write-Host "Message: $($commit.message)" -ForegroundColor Cyan
      Write-Host "Author: $($commit.author)" -ForegroundColor Cyan
      Write-Host "Changes: $($commit.change_summary)" -ForegroundColor Cyan
    } else {
      Write-Host "[ERROR] API vernul oshibku: $($responseObj.detail)" -ForegroundColor Red
      exit 1
    }
  }
  catch {
      Write-Host "[ERROR] Ne udalos obrabotat otvet ot API: $_" -ForegroundColor Red
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
    Write-Host "[ERROR] Usage: ergovcs update <branch>" -ForegroundColor Red
    exit 1
  }
  $branch = $BranchArg[0]

  # 2. Определить корень репозитория
  $repoRoot = Find-LocalRepositoryRoot
  if (-not $repoRoot) {
    Write-Host "[ERROR] Ne v repozitorii. Ispolzujte 'clone' snachala." -ForegroundColor Red
    exit 1
  }

  # 3. Получить UUID и путь к репозиторию
  $uuid = Get-CurrentRepositoryUuid -LocalPath $repoRoot
  if (-not $uuid) {
    Write-Host "[ERROR] UUID ne najden. Repozitorij ne inicializirovan." -ForegroundColor Red
    exit 1
  }

  Write-Host "[INFO] Zapros obnovlenij iz vetki '$branch'..." -ForegroundColor Cyan

  # 4. Сохранить текущее состояние staging area (если есть)
  $stagingFile = Join-Path $repoRoot ".ergovcs" "staging.json"
  $stagingBackup = $null
  if (Test-Path $stagingFile) {
    try {
      $stagingJson = Get-Content $stagingFile -Raw -Encoding UTF8
      $stagingBackup = $stagingJson | ConvertFrom-Json -ErrorAction Stop
      $stagingBackupPath = Join-Path $repoRoot ".ergovcs" "staging.backup.json"
      $stagingJson | Set-Content -Path $stagingBackupPath -Encoding UTF8
      Write-Host "[INFO] Staging area sohranen dlya vosstanovleniya." -ForegroundColor Gray
    }
    catch {
      Write-Host "[WARNING] Ne udalos sohranit staging area: $_" -ForegroundColor Yellow
    }
  }

  # 5. Вызов API для обновления
  $response = Invoke-ApiUpdateRepository -Uuid $uuid -Branch $branch
  
  if (-not $response) {
    Write-Host "[ERROR] Oshibka API pri obnovlenii" -ForegroundColor Red
    
    # Восстановить staging area
    if ($stagingBackup) {
      $stagingBackupJson = $stagingBackup | ConvertTo-Json -Depth 10
      Set-Content -Path $stagingFile -Value $stagingBackupJson -Encoding UTF8
      Write-Host "[INFO] Staging area vosstanovlen." -ForegroundColor Gray
    }
    
    exit 1
  }

  # 6. Обработка ответа
  try {
    $result = $response | ConvertFrom-Json
    
    if ($result.files -and $result.files.Count -gt 0) {
      Write-Host "[OK] Polucheno $($result.files.Count) fajlov dlya obnovleniya" -ForegroundColor Green
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
      
      Write-Host "`n[SUCCESS] Lokalnyj repozitorij obnovlen" -ForegroundColor Green
      Write-Host "Added: $addedCount files" -ForegroundColor Green
      Write-Host "Updated: $updatedCount files" -ForegroundColor Yellow
      Write-Host "Deleted: $deletedCount files" -ForegroundColor Red
    }
    elseif ($result.message -or $result.detail) {
      Write-Host "[INFO] $($result.message)$($result.detail)" -ForegroundColor Cyan
    }
    else {
      Write-Host "[INFO] Net novyh izmenenij v vetke '$branch'" -ForegroundColor Yellow
      
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
    Write-Host "[WARNING] Otvet API ne v JSON formate: $response" -ForegroundColor Yellow
    Write-Host "[ERROR] Oshibka pri obrabotke otveta: $_" -ForegroundColor Red
    
    # Восстановить staging area
    if ($stagingBackup) {
      $stagingBackupJson = $stagingBackup | ConvertTo-Json -Depth 10
      Set-Content -Path $stagingFile -Value $stagingBackupJson -Encoding UTF8
      Write-Host "[INFO] Staging area vosstanovlen." -ForegroundColor Gray
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
    Write-Host "[ERROR] Neobhodimo ukazat UUID repozitoriya" -ForegroundColor Red
    Write-Host "Usage: ergovcs remove <UUID>" -ForegroundColor Yellow
    exit 1
  }

  # TODO: Реализовать удаление локальной копии
  Write-Host "[INFO] Udalenie lokalnoj kopii repozitoriya $uuid..." -ForegroundColor Cyan

  if (Test-Path -LiteralPath $localPath) {
    try {
      $item = Get-Item -LiteralPath $localPath -ErrorAction Stop
      if ($item.PSIsContainer) {
        Remove-Item -LiteralPath $localPath -Recurse -Force -ErrorAction Stop
      } else {
        Remove-Item -LiteralPath $localPath -Force -ErrorAction Stop
      }
      Write-Host "[OK] Lokalnaya kopiya udalena: $localPath" -ForegroundColor Green
    } catch {
      Write-Host "[ERROR] Ne udalos udalit lokalnuyu kopiyu: $localPath" -ForegroundColor Red
      Write-Host $_.Exception.Message -ForegroundColor Yellow
      exit 1
    }
  } else {
    Write-Host "[WARN] Lokalnyj put ne najden na diske: $localPath" -ForegroundColor Yellow
    Write-Host "[INFO] Zapis vse ravno budet udalena iz konfiga." -ForegroundColor Yellow
  }

  # Удаляем запись из repos.json
  $null = $repos.PSObject.Properties.Remove($uuid)
  $data.repositories = $repos

  try {
    $jsonOut = $data | ConvertTo-Json -Depth 10
    $jsonOut | Set-Content -Path $reposFile -Encoding UTF8
    Write-Host "[OK] Zapis udalena iz konfiga: $reposFile" -ForegroundColor Green
  } catch {
    Write-Host "[ERROR] Ne udalos obnovit fajl konfiga: $reposFile" -ForegroundColor Red
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
          Write-Host "[INFO] Ukazan lokalnyj put: $localPath" -ForegroundColor Cyan
        }
      }
      "-r" {
        $i++
        if ($i -lt $RepoArg.Count) {
          $localPath = $RepoArg[$i]
          Write-Host "[INFO] Ukazan lokalnyj put: $localPath" -ForegroundColor Cyan
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
    $name = Read-Host "Repository name"
  }
  if (-not $name) {
    Write-Host "[ERROR] Neobhodimo ukazat nazvanie repozitoriya" -ForegroundColor Red
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
      Write-Host "[WARN] Dlya avtorizacii nuzhny --username i --password (oba)." -ForegroundColor Yellow
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

  Write-Host "[INFO] Sozdanie repozitoriya cherez API..." -ForegroundColor Cyan
  $response = Invoke-ApiRequest -Method "POST" -Endpoint "/repositories/" -Body $bodyJson

  if (-not $response) {
    Write-Host "[ERROR] Ne udalos sozdat repozitorij" -ForegroundColor Red
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

    Write-Host "[OK] Repozitorij sozdan i dobavlen v konfiguraciyu." -ForegroundColor Green
    Write-Host "UUID: $repoId"
    Write-Host "Name: $repoName"
    Write-Host "Local path: $localPath"
    Write-Host "Remote path: $repoPath"
    Write-Host "Config saved to: $reposJsonPath"

    if ($createdAt) {
      Write-Host "Created: $createdAt"
    }
  }
  catch {
    Write-Host "[ERROR] Ne udalos rasparsit otvet ot API ili sozdat konfiguraciyu" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "API response: $response" -ForegroundColor Yellow
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
    Write-Host "[ERROR] Nuzhno ukazat --source" -ForegroundColor Red
    exit 1
  }

  if (-not (Test-Path $source)) {
    Write-Host "[ERROR] Istochnik ne najden: $source" -ForegroundColor Red
    exit 1
  }

  if (-not $uuid) { $uuid = New-Uuid }

  $target = Ensure-RepoDirs -Uuid $uuid
  Import-FromSource -Source $source -Target $target
  if ($name) { Save-Metadata -Target $target -Name $name -Description "" }

  Write-Host "[OK] Repozitorij importirovan." -ForegroundColor Green
  Write-Host "UUID: $uuid"
  Write-Host "Path: $target"
}

# ============================================================================
# Управление ветками
# Команда: ergovcs branch <list|create|delete|set-default> ...
# ============================================================================
function Invoke-Branch {
param([string[]]$Args)

if (-not $Args -or $Args.Count -eq 0) {
  Write-Host "[ERROR] Usage: ergovcs branch <list|create|delete|set-default>" -ForegroundColor Red
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
    Write-Host "[WARN] Dlya avtorizacii nuzhny --username i --password (oba)." -ForegroundColor Yellow
  }
}

switch ($action) {
  "list" {
    if (-not $repoUuid) {
      Write-Host "[ERROR] Nuzhno ukazat --repo <UUID>" -ForegroundColor Red
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
      Write-Host "[ERROR] Nuzhno ukazat --repo <UUID> i --name <branch>" -ForegroundColor Red
      exit 1
    }
    Invoke-ApiCreateBranch -RepoUuid $repoUuid -BranchName $branchName -CliUsername $cliUsername -CliPassword $cliPassword -CheckPermissions:$checkPermissions | Out-Null
    Write-Host "[OK] Vetka sozdana: $branchName" -ForegroundColor Green
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
      Write-Host "[ERROR] Nuzhno ukazat --id <branch_id> (ili --repo + --name dlya poiska)" -ForegroundColor Red
      exit 1
    }
    Invoke-ApiDeleteBranch -BranchId $branchId | Out-Null
    Write-Host "[OK] Vetka udalena (id=$branchId)" -ForegroundColor Green
  }
  "set-default" {
    if ($branchId) {
      Invoke-ApiSetDefaultBranchById -BranchId $branchId -CliUsername $cliUsername -CliPassword $cliPassword -CheckPermissions:$checkPermissions | Out-Null
      Write-Host "[OK] Vetka ustanovlena po umolchaniyu (id=$branchId)" -ForegroundColor Green
    }
    elseif ($repoUuid -and $branchName) {
      Invoke-ApiSetDefaultBranchByName -RepoUuid $repoUuid -BranchName $branchName -CliUsername $cliUsername -CliPassword $cliPassword -CheckPermissions:$checkPermissions | Out-Null
      Write-Host "[OK] Vetka ustanovlena po umolchaniyu: $branchName" -ForegroundColor Green
    }
    else {
      Write-Host "[ERROR] Nuzhno ukazat --id <branch_id> ili --repo <UUID> i --name <branch>" -ForegroundColor Red
      exit 1
    }
  }
  default {
    Write-Host "[ERROR] Neizvestnoe dejstvie: $action" -ForegroundColor Red
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
  Write-Host "[ERROR] Nuzhno ukazat --repo <UUID>" -ForegroundColor Red
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
    $connector = if ($isLast) { "+-- " } else { "|-- " }
    $name = $item.name
    if ($item.is_directory) {
      Write-Host "$prefix$connector$name/"
      $nextPrefix = $prefix + (if ($isLast) { "    " } else { "|   " })
      Render-Tree $item.items $nextPrefix
    } else {
      Write-Host "$prefix$connector$name"
    }
  }
}

Render-Tree $items ""
}

# ============================================================================
# Статистика репозитория
# Команда: ergovcs stats --repo <UUID>
# ============================================================================
function Invoke-Stats {
  param([string[]]$Args)
  
  $repoUuid = $null
  $outputFormat = "table"  # table, json
  
  for ($i = 0; $i -lt $Args.Count; $i++) {
    switch ($Args[$i]) {
      "--repo" { $i++; if ($i -lt $Args.Count) { $repoUuid = $Args[$i] } }
      "-r" { $i++; if ($i -lt $Args.Count) { $repoUuid = $Args[$i] } }
      "--json" { $outputFormat = "json" }
      "-j" { $outputFormat = "json" }
    }
  }
  
  # Если UUID не указан, пробуем получить из текущего репозитория
  if (-not $repoUuid) {
    $repoRoot = Find-LocalRepositoryRoot
    if ($repoRoot) {
      $repoUuid = Get-CurrentRepositoryUuid -LocalPath $repoRoot
    }
  }
  
  if (-not $repoUuid) {
    Write-Host "[ERROR] Nuzhno ukazat --repo <UUID> ili vypolnit komandu v direktorii repozitoriya" -ForegroundColor Red
    exit 1
  }
  
  Write-Host "[INFO] Poluchenie statistiki repozitoriya $repoUuid..." -ForegroundColor Cyan
  
  $response = Invoke-ApiGetStats -RepoUuid $repoUuid
  if (-not $response) {
    Write-Host "[ERROR] Ne udalos poluchit statistiku" -ForegroundColor Red
    exit 1
  }
  
  if ($outputFormat -eq "json") {
    Write-Host $response
    return
  }
  
  try {
    $data = $response | ConvertFrom-Json
    
    Write-Host "`n========== REPOSITORY STATISTICS ==========" -ForegroundColor Green
    Write-Host "Repository: $($data.repository_name)" -ForegroundColor Cyan
    Write-Host "UUID: $($data.repository_uuid)" -ForegroundColor Gray
    Write-Host ""
    
    # Общая статистика
    Write-Host "--- General Statistics ---" -ForegroundColor Yellow
    Write-Host "  Total size: $($data.total_size_human)"
    Write-Host "  Total files: $($data.total_files)"
    Write-Host "  Total commits: $($data.total_commits)"
    Write-Host "  Branches count: $($data.branches_count)"
    Write-Host ""
    
    # Статистика по типам файлов
    if ($data.files_by_extension) {
      Write-Host "--- Files by Extension ---" -ForegroundColor Yellow
      $extensions = $data.files_by_extension.PSObject.Properties | Sort-Object { $_.Value } -Descending
      foreach ($ext in $extensions | Select-Object -First 10) {
        $size = if ($data.size_by_extension."$($ext.Name)") {
          $data.size_by_extension_human."$($ext.Name)"
        } else { "N/A" }
        Write-Host ("  {0,-15} {1,6} files ({2})" -f $ext.Name, $ext.Value, $size)
      }
      Write-Host ""
    }
    
    # Топ-5 тяжёлых файлов
    if ($data.largest_files -and $data.largest_files.Count -gt 0) {
      Write-Host "--- Top 5 Largest Files ---" -ForegroundColor Yellow
      foreach ($file in $data.largest_files | Select-Object -First 5) {
        Write-Host ("  {0,-40} {1}" -f $file.path, $file.size_human)
      }
      Write-Host ""
    }
    
    # Кандидаты для холодного хранилища
    if ($data.cold_storage_candidates -and $data.cold_storage_candidates.Count -gt 0) {
      Write-Host "--- Cold Storage Candidates ---" -ForegroundColor Yellow
      Write-Host "  Found candidates: $($data.cold_storage_candidates.Count)" -ForegroundColor Cyan
      foreach ($candidate in $data.cold_storage_candidates | Select-Object -First 5) {
        $reasons = $candidate.reasons -join ", "
        Write-Host ("  [{0,2}] {1,-35} {2} ({3})" -f $candidate.priority, $candidate.path, $candidate.size_human, $reasons)
      }
      Write-Host ""
    }
    
    Write-Host "Analysis time: $($data.analysis_duration_ms) ms" -ForegroundColor Gray
    Write-Host "=============================================" -ForegroundColor Green
  }
  catch {
    Write-Host "[ERROR] Ne udalos obrabotat otvet: $_" -ForegroundColor Red
    Write-Host $response
    exit 1
  }
}

# ============================================================================
# Прогноз роста репозитория
# Команда: ergovcs forecast --repo <UUID> [--days 30]
# ============================================================================
function Invoke-Forecast {
  param([string[]]$Args)
  
  $repoUuid = $null
  $days = 30
  $outputFormat = "table"  # table, json
  
  for ($i = 0; $i -lt $Args.Count; $i++) {
    switch ($Args[$i]) {
      "--repo" { $i++; if ($i -lt $Args.Count) { $repoUuid = $Args[$i] } }
      "-r" { $i++; if ($i -lt $Args.Count) { $repoUuid = $Args[$i] } }
      "--days" { $i++; if ($i -lt $Args.Count) { $days = [int]$Args[$i] } }
      "-d" { $i++; if ($i -lt $Args.Count) { $days = [int]$Args[$i] } }
      "--json" { $outputFormat = "json" }
      "-j" { $outputFormat = "json" }
    }
  }
  
  # Если UUID не указан, пробуем получить из текущего репозитория
  if (-not $repoUuid) {
    $repoRoot = Find-LocalRepositoryRoot
    if ($repoRoot) {
      $repoUuid = Get-CurrentRepositoryUuid -LocalPath $repoRoot
    }
  }
  
  if (-not $repoUuid) {
    Write-Host "[ERROR] Nuzhno ukazat --repo <UUID> ili vypolnit komandu v direktorii repozitoriya" -ForegroundColor Red
    exit 1
  }
  
  Write-Host "[INFO] Poluchenie prognoza dlya repozitoriya $repoUuid (period: $days dnej)..." -ForegroundColor Cyan
  
  $response = Invoke-ApiGetForecast -RepoUuid $repoUuid -Days $days
  if (-not $response) {
    Write-Host "[ERROR] Ne udalos poluchit prognoz" -ForegroundColor Red
    exit 1
  }
  
  if ($outputFormat -eq "json") {
    Write-Host $response
    return
  }
  
  try {
    $data = $response | ConvertFrom-Json
    
    Write-Host "`n========== REPOSITORY GROWTH FORECAST ==========" -ForegroundColor Green
    Write-Host "Repository: $($data.repository_name)" -ForegroundColor Cyan
    Write-Host "UUID: $($data.repository_uuid)" -ForegroundColor Gray
    Write-Host ""
    
    # Текущее состояние
    Write-Host "--- Current State ---" -ForegroundColor Yellow
    Write-Host "  Current size: $($data.current_size_human)"
    Write-Host "  Analysis period: $($data.analysis_period_days) days"
    Write-Host ""
    
    # Прогноз
    if ($data.forecast) {
      Write-Host "--- Forecast for $($data.forecast.forecast_days) days ---" -ForegroundColor Yellow
      Write-Host "  Confidence: $($data.forecast.confidence)" -ForegroundColor $(
        switch ($data.forecast.confidence) {
          "very_high" { "Green" }
          "high" { "Green" }
          "medium" { "Yellow" }
          default { "Red" }
        }
      )
      Write-Host "  Moving average (7 days): $($data.forecast.moving_average_7d_human)/day"
      Write-Host "  Moving average (30 days): $($data.forecast.moving_average_30d_human)/day"
      Write-Host "  Trend: $($data.forecast.daily_trend_human)/day"
      Write-Host ""
      
      # Прогнозируемый рост
      if ($data.forecast.predictions -and $data.forecast.predictions.Count -gt 0) {
        Write-Host "--- Predicted Size ---" -ForegroundColor Yellow
        $step = [Math]::Max(1, [Math]::Floor($data.forecast.predictions.Count / 5))
        for ($i = 0; $i -lt $data.forecast.predictions.Count; $i += $step) {
          $pred = $data.forecast.predictions[$i]
          Write-Host ("  Day {0,3}: {1} (+ {2})" -f $pred.day, $pred.predicted_size_human, $pred.predicted_daily_growth_human)
        }
        
        # Последний день
        $lastPred = $data.forecast.predictions[-1]
        Write-Host ""
        Write-Host "  Total after $($lastPred.day) days: $($lastPred.predicted_size_human)" -ForegroundColor Cyan
      }
      Write-Host ""
    }
    
    # Временной ряд (последние 7 дней)
    if ($data.time_series -and $data.time_series.Count -gt 0) {
      Write-Host "--- Last 7 Days ---" -ForegroundColor Yellow
      $recentDays = $data.time_series | Select-Object -Last 7
      foreach ($day in $recentDays) {
        $netGrowth = if ($day.net_growth_human) { $day.net_growth_human } else { "N/A" }
        Write-Host ("  {0}: {1} commits, growth: {2}" -f $day.date, $day.commits_count, $netGrowth)
      }
    }
    
    Write-Host "================================================" -ForegroundColor Green
  }
  catch {
    Write-Host "[ERROR] Ne udalos obrabotat otvet: $_" -ForegroundColor Red
    Write-Host $response
    exit 1
  }
}
