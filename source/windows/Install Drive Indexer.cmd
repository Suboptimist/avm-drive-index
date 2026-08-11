@echo off
title AVM Drive Indexer Setup
rem Double-click this file to turn on automatic drive indexing.
rem It sets up a small background helper that runs whenever a drive is
rem connected or removed, so the index stays up to date on its own.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0App\Install-Watcher.ps1"
echo Press any key to close this window...
pause >nul
exit /b 0
