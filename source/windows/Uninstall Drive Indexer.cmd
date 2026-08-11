@echo off
title AVM Drive Indexer
rem Double-click this file to turn automatic drive indexing off.
rem Your index is left exactly as it is -- this only stops new updates.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0App\Uninstall-Watcher.ps1"
echo Press any key to close this window...
pause >nul
exit /b 0
