#Requires -Version 5.1
<#
.SYNOPSIS
    Utility for managing version_management repositories

.DESCRIPTION
    Console utility for version_management module.
    Supports commands: clone, add, commit, push, update, remove, create, download.

.PARAMETER Command
    Command to execute (e.g.: create, clone, push, help)

.EXAMPLE
    .\version_manager.ps1 create --name "My repository"
    .\version_manager.ps1 clone <UUID>
#>

param(
  [Parameter(Position=0)]
  [string]$Command = "help",
  [Parameter(ValueFromRemainingArguments=$true)]
  [string[]]$Args = @()
)

$ErrorActionPreference = "Stop"

# Ensure correct UTF-8 input/output in console
try {
  $utf8 = [System.Text.UTF8Encoding]::new($false)
  [Console]::InputEncoding = $utf8
  [Console]::OutputEncoding = $utf8
  $OutputEncoding = $utf8
} catch {
  # ignore: not critical if encoding setup failed
}

# Load modules
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LibDir    = Join-Path $ScriptDir "lib"

. (Join-Path $LibDir "core.ps1")
. (Join-Path $LibDir "repo.ps1")
. (Join-Path $LibDir "commands.ps1")
. (Join-Path $LibDir "help.ps1")
. (Join-Path $LibDir "cli.ps1")

switch ($Command.ToLower()) {
  "clone"    { Invoke-Clone -Args $Args }
  "add"      { Invoke-Add -Files $Args }
  "commit"   { Invoke-Commit -MessageArg $Args }
  "push"     { Invoke-Push -BranchArg $Args }
  "update"   { Invoke-Update -BranchArg $Args }
  "remove"   { Invoke-Remove -Args $Args }
  "create"   { Invoke-Create -RepoArg $Args }
  "download" { Invoke-Download -Args $Args }
  "branch"   { Invoke-Branch -Args $Args }
  "files"    { Invoke-Files -Args $Args }
  "stats"    { Invoke-Stats -Args $Args }
  "forecast" { Invoke-Forecast -Args $Args }
  "install-cli" { Install-CliWrapper }
  "uninstall-cli" { Uninstall-CliWrapper }
  "help"     { Show-Help }
  default    { Write-Host "[ERROR] Unknown command: $Command" -ForegroundColor Red; Show-Help; exit 1 }
}
