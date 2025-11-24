# Обработчики команд create и download

function Invoke-Create {
  param([string[]]$Args)

  Detect-ProjectRoot

  $name = $null
  $description = $null
  $manualRoot = $null

  for ($i = 0; $i -lt $Args.Count; $i++) {
    switch ($Args[$i]) {
      "--name"        { $i++; $name = $Args[$i] }
      "--description" { $i++; $description = $Args[$i] }
      "--root"        { $i++; $manualRoot = $Args[$i] }
    }
  }

  if ($manualRoot) {
    $script:ProjectRoot = $manualRoot
    $script:MediaDir = Join-Path $script:ProjectRoot "media\version_management"
    New-Item -ItemType Directory -Force -Path $script:MediaDir | Out-Null
  }

  if (-not $name)        { $name = Read-Host "Название репозитория" }
  if (-not $description) { $description = Read-Host "Описание" }

  $uuid = New-Uuid
  $target = Ensure-RepoDirs -Uuid $uuid
  Save-Metadata -Target $target -Name $name -Description $description

  Write-Host "[OK] Репозиторий создан." -ForegroundColor Green
  Write-Host "UUID: $uuid"
  Write-Host "Путь: $target"
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

