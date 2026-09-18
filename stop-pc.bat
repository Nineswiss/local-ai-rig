@echo off
rem Double-click this to stop Ollama and Open WebUI. Just calls
rem stop-pc.ps1 - see that file for what it actually does.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop-pc.ps1"
echo.
pause
