# Общие утилиты: поиск корня проекта, генерация UUID

$script:ProjectRoot = $null
$script:MediaDir = $null

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

