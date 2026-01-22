@echo off
REM Универсальный вход для утилиты ergovcs (Windows, cmd/PowerShell)
REM Проксирует все аргументы в windows\version_manager.ps1

chcp 65001 >nul
setlocal ENABLEDELAYEDEXPANSION
set "SCRIPT_DIR=%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; [Console]::InputEncoding=[System.Text.Encoding]::UTF8; $OutputEncoding=[System.Text.Encoding]::UTF8; & '%SCRIPT_DIR%windows\version_manager.ps1' %*"

endlocal