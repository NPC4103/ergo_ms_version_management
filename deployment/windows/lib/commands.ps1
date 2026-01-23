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
  param([string[]]$Args)
  
  # TODO: Реализовать добавление файла для коммита
  # 1. Получить путь к файлу из аргументов
  # 2. Проверить, что файл существует
  # 3. Добавить файл в staging area (локально)
  # 4. При следующем commit эти изменения будут отправлены на сервер
  
  $filePath = $null
  
  for ($i = 0; $i -lt $Args.Count; $i++) {
    $filePath = $Args[$i]
  }
  
  if (-not $filePath) {
    Write-Host "[ERROR] Необходимо указать путь к файлу" -ForegroundColor Red
    Write-Host "Использование: ergovcs add <файл.расширение>" -ForegroundColor Yellow
    exit 1
  }
  
  # TODO: Реализовать добавление файла в staging area
  Write-Host "[INFO] Добавление файла $filePath для коммита..." -ForegroundColor Cyan
  Write-Host "[TODO] Проверить существование файла" -ForegroundColor Yellow
  Write-Host "[TODO] Добавить файл в staging area" -ForegroundColor Yellow
}

# ============================================================================
# Создание коммита
# Команда: ergovcs commit -m "Сообщение"
# Создаёт коммит с изменениями в папке media/version_management/<UUID>/
# ============================================================================
function Invoke-Commit {
  param([string[]]$Args)
  
  # TODO: Реализовать создание коммита
  # 1. Получить сообщение коммита из аргумента -m
  # 2. Получить UUID текущего репозитория (из конфига или рабочей директории)
  # 3. Собрать все изменения из staging area
  # 4. Вызвать API эндпоинт /api/repositories/{id}/commits/create/
  # 5. После повторного добавления (add), не создаётся новый коммит,
  #    а добавляются изменения в существующий, до тех пор пока коммит не отправлен на сервер
  
  $message = $null
  
  for ($i = 0; $i -lt $Args.Count; $i++) {
    switch ($Args[$i]) {
      "-m" { $i++; $message = $Args[$i] }
      "--message" { $i++; $message = $Args[$i] }
    }
  }
  
  if (-not $message) {
    Write-Host "[ERROR] Необходимо указать сообщение коммита" -ForegroundColor Red
    Write-Host "Использование: ergovcs commit -m `"Сообщение`"" -ForegroundColor Yellow
    exit 1
  }
  
  # TODO: Реализовать создание коммита
  Write-Host "[INFO] Создание коммита с сообщением: $message" -ForegroundColor Cyan
  Write-Host "[TODO] Получить UUID текущего репозитория" -ForegroundColor Yellow
  Write-Host "[TODO] Собрать изменения из staging area" -ForegroundColor Yellow
  Write-Host "[TODO] Вызвать API /api/repositories/{id}/commits/create/" -ForegroundColor Yellow
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

