@echo off
rem Double-click this file to open the AVM Drive Index window.
rem Nothing to install -- it uses the PowerShell that comes with Windows.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0App\DriveIndexApp.ps1"
exit /b 0
