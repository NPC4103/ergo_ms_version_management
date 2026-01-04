#Requires -Version 5.1
<#
.SYNOPSIS
    Утилита для управления репозиториями version_management

.DESCRIPTION
    Работает без бэкенда, создавая локальную структуру репозиториев.
    Поддерживает команды: create, download

.PARAMETER Command
    Команда для выполнения: create, download, help

.EXAMPLE
    .\version_manager.ps1 create --name "Мой репозиторий"
    .\version_manager.ps1 download --source "C:\path\to\repo.zip"
#>

param(
  [Parameter(Position=0)]
  [string]$Command = "help",
  [Parameter(ValueFromRemainingArguments=$true)]
  [string[]]$Args = @()
)

$ErrorActionPreference = "Stop"

# Load modules
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LibDir    = Join-Path $ScriptDir "lib"

. (Join-Path $LibDir "core.ps1")
. (Join-Path $LibDir "repo.ps1")
. (Join-Path $LibDir "commands.ps1")
. (Join-Path $LibDir "help.ps1")

switch ($Command.ToLower()) {
  "clone"    { Invoke-Clone -Args $Args }
  "add"      { Invoke-Add -Args $Args }
  "commit"   { Invoke-Commit -Args $Args }
  "push"     { Invoke-Push -Args $Args }
  "update"   { Invoke-Update -Args $Args }
  "remove"   { Invoke-Remove -Args $Args }
  "create"   { Invoke-Create -Args $Args }
  "download" { Invoke-Download -Args $Args }
  "help"     { Show-Help }
  default    { Write-Host "[ERROR] Unknown command: $Command" -ForegroundColor Red; Show-Help; exit 1 }
}

