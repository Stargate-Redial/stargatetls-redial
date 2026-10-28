@echo off
rem Stargate Redial: runs uninstall.ps1 with Windows PowerShell.
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
set RC=%ERRORLEVEL%
if not "%RC%"=="0" echo. & echo Uninstall FAILED (exit code %RC%).
if "%~1"=="" pause
exit /b %RC%
