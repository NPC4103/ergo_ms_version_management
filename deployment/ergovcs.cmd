@echo off
REM Универсальный вход для утилиты ergovcs (Windows, cmd/PowerShell)
REM Проксирует все аргументы в windows\version_manager.ps1

chcp 65001 >nul
setlocal ENABLEDELAYEDEXPANSION
set "SCRIPT_DIR=%~dp0"

REM Use -File to pass arguments verbatim; -Command can mangle quoting and args.
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%windows\version_manager.ps1" %*

endlocal
