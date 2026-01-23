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
  # `create` пока не создаёт идентификационную папку/файл в рабочей директории,
  # это нужно учитывать при тестировании
  Write-Host "[DEBUG] Files count: $($Files.Count)" -ForegroundColor Gray
  Write-Host "[DEBUG] Files content: $($Files -join ', ')" -ForegroundColor Gray

  # 1. Найти корень репозитория
  $repoRoot = Find-RepositoryRoot
  Write-Host "[DEBUG] RepoRoot: $repoRoot" -ForegroundColor Gray
  if (-not $repoRoot) {
    Write-Host "[ERROR] Не удалось найти репозиторий. Убедитесь, что вы находитесь в директории репозитория." -ForegroundColor Red
    exit 1
  }
  
  # 2. Получить UUID репозитория
  $uuid = Get-CurrentRepositoryUuid
  Write-Host "[DEBUG] UUID: $uuid" -ForegroundColor Gray
  if (-not $uuid) {
    Write-Host "[ERROR] Не удалось определить UUID репозитория." -ForegroundColor Red
    Write-Host "[INFO] Убедитесь, что репозиторий был клонирован или создан через команду clone/create." -ForegroundColor Yellow
    exit 1
  }
  
  # 3. Прочитать текущий staging area один раз для всех файлов
  $staging = Get-StagingArea
  if (-not $staging.repository_uuid) {
    $staging.repository_uuid = $uuid
  }
  
  # Инициализируем массив files, если он не существует или имеет неправильный тип
  if (-not $staging.files -or $staging.files -isnot [System.Collections.ArrayList]) {
    $staging.files = [System.Collections.ArrayList]@()
  }

  # 4. Обработать каждый файл из аргументов
  $hasErrors = $false
  
  foreach ($file in $Files) {
    # 5. Пропустить пустые аргументы
    if ([string]::IsNullOrWhiteSpace($file)) {
      Write-Host "[WARNING] Пропущен пустой аргумент" -ForegroundColor Yellow
      continue
    }
    
    # 6. Определить полный путь к файлу
    $fullPath = if ([System.IO.Path]::IsPathRooted($file)) {
      $file
    } else {
      Join-Path (Get-Location).Path $file
    }
    
    # 7. Проверить существование файла
    if (-not (Test-Path $fullPath)) {
      Write-Host "[ERROR] Файл не найден: $file" -ForegroundColor Red
      $hasErrors = $true
      continue
    }
    
    Write-Host "[DEBUG] Original: $file | Full: $fullPath" -ForegroundColor Gray
    
    # 8. Получить относительный путь от корня репозитория
    $relativePath = [System.IO.Path]::GetRelativePath($repoRoot, $fullPath).Replace('\', '/')
    
    # 9. Прочитать содержимое файла
    try {
      $fileContent = Get-Content $fullPath -Raw -Encoding UTF8
    }
    catch {
      Write-Host "[ERROR] Не удалось прочитать файл: $file - $_" -ForegroundColor Red
      $hasErrors = $true
      continue
    }
    
    # 10. Определить действие файла
    $action = Get-FileAction -FilePath $relativePath -RepoRoot $repoRoot
    
    # 11. Проверить, не добавлен ли файл уже в staging
    $fileExists = $false

    for ($j = 0; $j -lt $staging.files.Count; $j++) {
      if ($staging.files[$j].path -eq $relativePath) {
        # Обновляем существующий файл
        $staging.files[$j].action = $action
        $staging.files[$j].content = $fileContent
        $fileExists = $true
        break
      }
    }
    
    if (-not $fileExists) {
      # Добавляем новый файл
      $fileEntry = @{
        path = $relativePath
        action = $action
        content = $fileContent
      }
      $null = $staging.files.Add($fileEntry)
      Write-Host "[OK] Файл добавлен в staging area: $relativePath" -ForegroundColor Green
    }
  }
  
  # 12. Сохранить staging area после обработки всех файлов
  if ($hasErrors) {
    if (Save-StagingArea -Staging $staging) {
      Write-Host "[WARNING] Некоторые файлы не были добавлены, но staging area сохранен" -ForegroundColor Yellow
      exit 1
    } else {
      Write-Host "[ERROR] Не удалось сохранить staging area" -ForegroundColor Red
      exit 1
    }
  } else {
    if (Save-StagingArea -Staging $staging) {
      Write-Host "[INFO] Все файлы были добавлены и staging area сохранен" -ForegroundColor Yellow
      exit 1
    } else {
      Write-Host "[ERROR] Не удалось сохранить staging area" -ForegroundColor Red
      exit 1
    }
  }
}


# ============================================================================
# Создание коммита
# Команда: ergovcs commit -m "Сообщение"
# Создаёт коммит с изменениями в папке media/version_management/<UUID>/
# ============================================================================
function Invoke-Commit {
  param([string[]]$Message)
  # `create` пока не создаёт идентификационную папку/файл в рабочей директории,
  # это нужно учитывать при тестировании

  # 1. Получить сообщение коммита из аргумента -m
  $message = $null
  
  for ($i = 0; $i -lt $Message.Count; $i++) {
    switch ($Message[$i]) {
      "-m" { 
        $i++
        if ($i -lt $Message.Count) {
          $message = $Message[$i]
        }
      }
      "--message" { 
        $i++
        if ($i -lt $Message.Count) {
          $message = $Message[$i]
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
  
  # 2. Найти корень репозитория
  $repoRoot = Find-RepositoryRoot
  if (-not $repoRoot) {
    Write-Host "[ERROR] Не удалось найти репозиторий. Убедитесь, что вы находитесь в директории репозитория." -ForegroundColor Red
    exit 1
  }
  
  # 3. Получить UUID текущего репозитория
  $uuid = Get-CurrentRepositoryUuid
  if (-not $uuid) {
    Write-Host "[ERROR] Не удалось определить UUID репозитория." -ForegroundColor Red
    Write-Host "[INFO] Убедитесь, что репозиторий был клонирован или создан через команду clone/create." -ForegroundColor Yellow
    exit 1
  }
  
  # 4. Прочитать staging area
  $staging = Get-StagingArea
  if ($staging.repository_uuid -ne $uuid) {
    $staging.repository_uuid = $uuid
  }
  
  # 5. Проверить, есть ли файлы в staging area
  if ($staging.files.Count -eq 0) {
    Write-Host "[ERROR] Нет файлов в staging area. Используйте команду 'add' для добавления файлов." -ForegroundColor Red
    exit 1
  }
  
  # 6. Проверить, есть ли уже pending_commit
  # Если есть, значит коммит уже создан локально, но не отправлен на сервер
  # В этом случае просто обновляем сообщение коммита (если изменилось) и файлы уже там
  if ($staging.pending_commit) {
    Write-Host "[INFO] Обнаружен незавершенный коммит. Файлы будут добавлены к существующему коммиту." -ForegroundColor Yellow
    Write-Host "[INFO] Используйте команду 'push' для отправки коммита на сервер." -ForegroundColor Yellow
    
    # Обновляем сообщение коммита, если оно изменилось
    $staging.pending_commit.message = $message
    $staging.pending_commit.created_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    if (Save-StagingArea -Staging $staging) {
      Write-Host "[OK] Коммит обновлен. Сообщение: $message" -ForegroundColor Green
      Write-Host "[INFO] Всего файлов в коммите: $($staging.files.Count)" -ForegroundColor Cyan
    } else {
      Write-Host "[ERROR] Не удалось сохранить staging area" -ForegroundColor Red
      exit 1
    }
    return
  }
  
  # 7. Подготовить данные для API
  $filesArray = @()
  foreach ($file in $staging.files) {
    $filesArray += @{
      path = $file.path
      action = $file.action
      content = $file.content
    }
  }
  
  $filesJson = ($filesArray | ConvertTo-Json -Depth 10 -Compress)
  
  # 8. Вызвать API для создания коммита
  Write-Host "[INFO] Создание коммита через API..." -ForegroundColor Cyan
  
  $response = Invoke-ApiCreateCommit -Uuid $uuid -Message $message -Files $filesJson
  
  if (-not $response) {
    Write-Host "[ERROR] Не удалось создать коммит через API" -ForegroundColor Red
    exit 1
  }
  
  # 9. Парсим ответ от API
  try {
    $responseObj = $response | ConvertFrom-Json
    $commitHash = if ($responseObj.hash) { $responseObj.hash } else { $responseObj.id }
    
    Write-Host "[OK] Коммит создан успешно." -ForegroundColor Green
    if ($commitHash) {
      Write-Host "Хеш коммита: $commitHash" -ForegroundColor Cyan
    }
    Write-Host "Сообщение: $message" -ForegroundColor Cyan
    Write-Host "Файлов: $($staging.files.Count)" -ForegroundColor Cyan
    
    # 10. Создаем pending_commit для отслеживания незавершенного коммита
    $staging.pending_commit = @{
      message = $message
      created_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
      hash = $commitHash
    }
    
    # 11. Сохраняем staging area с pending_commit
    # Файлы остаются в staging area до команды push
    if (Save-StagingArea -Staging $staging) {
      Write-Host "[INFO] Используйте команду 'push' для отправки коммита на сервер." -ForegroundColor Yellow
    } else {
      Write-Host "[WARN] Коммит создан, но не удалось сохранить информацию о pending_commit" -ForegroundColor Yellow
    }
  }
  catch {
    Write-Host "[ERROR] Не удалось распарсить ответ от API" -ForegroundColor Red
    Write-Host "Ответ: $response" -ForegroundColor Yellow
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
  param([string[]]$Args)

  # Создание репозитория через API
  # Использует API эндпоинт /api/repositories/ для избежания дублирования функционала
  # Примечание: API не поддерживает description, поэтому параметр --description игнорируется

  $name = $null

  for ($i = 0; $i -lt $Args.Count; $i++) {
    switch ($Args[$i]) {
      "--name"        { $i++; $name = $Args[$i] }
      "--description" { $i++; Write-Host "[WARN] Параметр --description не поддерживается API и будет проигнорирован" -ForegroundColor Yellow }
      "--root"        { Write-Host "[WARN] Параметр --root игнорируется при работе через API" -ForegroundColor Yellow }
    }
  }

  if (-not $name) { $name = Read-Host "Название репозитория" }

  Write-Host "[INFO] Создание репозитория через API..." -ForegroundColor Cyan

  $response = Invoke-ApiCreateRepository -Name $name

  if (-not $response) {
    Write-Host "[ERROR] Не удалось создать репозиторий" -ForegroundColor Red
    exit 1
  }

  # Парсим ответ от API
  try {
    $responseObj = $response | ConvertFrom-Json
    $repoId = $responseObj.id
    $repoName = $responseObj.name
    $repoPath = $responseObj.path
    $createdAt = $responseObj.created_at

    Write-Host "[OK] Репозиторий создан." -ForegroundColor Green
    Write-Host "UUID: $repoId"
    Write-Host "Название: $repoName"
    Write-Host "Путь: $repoPath"
    if ($createdAt) {
      Write-Host "Создан: $createdAt"
    }
  }
  catch {
    Write-Host "[ERROR] Не удалось распарсить ответ от API" -ForegroundColor Red
    Write-Host "Ответ: $response" -ForegroundColor Yellow
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

