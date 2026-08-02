@echo off
setlocal enabledelayedexpansion
REM ============================================================================
REM bootstrap.bat - lanzador Windows (cmd). Usa bash si existe (fuente unica de
REM verdad = bootstrap.sh); si no hay bash, delega en PowerShell.
REM ============================================================================
set "HERE=%~dp0"

where bash >nul 2>&1
if !ERRORLEVEL! EQU 0 (
  bash "%HERE%bootstrap.sh" %*
  exit /b !ERRORLEVEL!
)

for %%B in ("%ProgramFiles%\Git\bin\bash.exe" "%ProgramFiles(x86)%\Git\bin\bash.exe" "%LocalAppData%\Programs\Git\bin\bash.exe") do (
  if exist "%%~B" (
    "%%~B" "%HERE%bootstrap.sh" %*
    exit /b !ERRORLEVEL!
  )
)

where powershell >nul 2>&1
if !ERRORLEVEL! EQU 0 (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%bootstrap.ps1" %*
  exit /b !ERRORLEVEL!
)

echo [bootstrap] No se encontro bash ni PowerShell. Instala Git para Windows.
exit /b 1
