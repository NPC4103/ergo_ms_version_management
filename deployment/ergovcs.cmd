@echo off
REM Универсальный вход для утилиты ergovcs (Windows, cmd/PowerShell)
REM Проксирует все аргументы в windows\version_manager.ps1

setlocal ENABLEDELAYEDEXPANSION
set "SCRIPT_DIR=%~dp0"

pwsh -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%windows\version_manager.ps1" %*

endlocal


