param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

# Универсальный вход для утилиты ergovcs (Windows / PowerShell)
# Проксирует все аргументы в windows\version_manager.ps1

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$target = Join-Path $ScriptDir "windows\version_manager.ps1"

pwsh -NoProfile -ExecutionPolicy Bypass -File $target @Args


