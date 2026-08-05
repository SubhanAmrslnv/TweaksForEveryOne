@echo off
REM Window Tweaks - double-click installer.
REM Bypasses the execution policy for this one process only; nothing permanent
REM is changed and no admin rights are needed.
title Window Tweaks - Setup
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1"
echo.
pause
