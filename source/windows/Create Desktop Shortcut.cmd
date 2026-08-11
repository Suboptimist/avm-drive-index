@echo off
title AVM Drive Index
rem Double-click this file to put an "AVM Drive Index" icon on your Desktop.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0App\New-Shortcut.ps1"
echo Press any key to close this window...
pause >nul
exit /b 0
