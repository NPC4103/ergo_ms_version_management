#Requires -Version 5.1
<#
.SYNOPSIS
    Утилита для управления репозиториями version_management

.DESCRIPTION
    Консольная утилита модуля version_management.
    Поддерживает команды: clone, add, commit, push, update, remove, create, download.

.PARAMETER Command
    Команда для выполнения (например: create, clone, push, help)

.EXAMPLE
    .\version_manager.ps1 create --name "Мой репозиторий"
    .\version_manager.ps1 clone <UUID>
#>

param(
  [Parameter(Position=0)]
  [string]$Command = "help",
  [Parameter(ValueFromRemainingArguments=$true)]
  [string[]]$Args = @()
)

$ErrorActionPreference = "Stop"

# Гарантируем корректный вывод/ввод UTF-8 в консоли (актуально для кириллицы в PowerShell)
try {
  $utf8 = [System.Text.UTF8Encoding]::new($false)
  [Console]::InputEncoding = $utf8
  [Console]::OutputEncoding = $utf8
  $OutputEncoding = $utf8
} catch {
  # ignore: не критично, если не удалось выставить кодировку
}

# Load modules
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LibDir    = Join-Path $ScriptDir "lib"

. (Join-Path $LibDir "core.ps1")
. (Join-Path $LibDir "repo.ps1")
. (Join-Path $LibDir "commands.ps1")
. (Join-Path $LibDir "help.ps1")

switch ($Command.ToLower()) {
  "clone"    { Invoke-Clone -Args $Args }
  "add"      { Invoke-Add -Files $Args }
  "commit"   { Invoke-Commit -MessageArg $Args }
  "push"     { Invoke-Push -Args $Args }
  "update"   { Invoke-Update -Args $Args }
  "remove"   { Invoke-Remove -Args $Args }
  "create"   { Invoke-Create -RepoArg $Args }
  "download" { Invoke-Download -Args $Args }
  "help"     { Show-Help }
  default    { Write-Host "[ERROR] Unknown command: $Command" -ForegroundColor Red; Show-Help; exit 1 }
}

