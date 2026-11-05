@echo off
setlocal
title Autonomous Dev Environment Installer

echo Starting Autonomous Dev Environment setup...
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-ADE.ps1" %*
set "ADE_EXIT=%ERRORLEVEL%"

echo.
if not "%ADE_EXIT%"=="0" (
    echo Installer exited with code %ADE_EXIT%.
) else (
    echo Installer finished.
)
echo See the log path printed above if anything failed.
echo.
pause
exit /b %ADE_EXIT%
