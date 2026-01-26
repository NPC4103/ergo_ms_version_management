# CLI wrapper management

function Install-CliWrapper {
  $selfScript = $PSCommandPath
  $libDir = Split-Path -Parent $selfScript
  $windowsDir = Split-Path -Parent $libDir
  $mainScript = Join-Path $windowsDir "version_manager.ps1"

  $cliPath = Get-CliPath
  $content = @(
    '@echo off',
    "powershell.exe -ExecutionPolicy Bypass -NoProfile -File `"$mainScript`" %*"
  ) -join "`r`n"

  Set-Content -Path $cliPath -Value $content -Encoding ASCII
  Write-Host "[OK] CLI wrapper installed: $cliPath" -ForegroundColor Green
  $cliName = Get-CliName
  Write-Host "  You can now use: $cliName help" -ForegroundColor Cyan
}

function Uninstall-CliWrapper {
  $cliPath = Get-CliPath
  if (Test-Path $cliPath) {
    Remove-Item $cliPath -Force
    Write-Host "[OK] CLI wrapper removed: $cliPath" -ForegroundColor Green
  }
  else {
    Write-Host "- CLI wrapper not found" -ForegroundColor DarkGray
  }
}
