@echo off
setlocal enabledelayedexpansion
REM ============================================================================
REM bootstrap.bat - lanzador Windows (cmd). Prioriza Git Bash; ignora el stub
REM de WSL (System32\bash.exe). Si no hay bash real, delega en PowerShell.
REM ============================================================================
set "HERE=%~dp0"
set "BASH="

REM 1) Rutas conocidas de Git para Windows
for %%B in ("%ProgramFiles%\Git\bin\bash.exe" "%ProgramFiles(x86)%\Git\bin\bash.exe" "%LocalAppData%\Programs\Git\bin\bash.exe") do (
  if not defined BASH if exist "%%~B" set "BASH=%%~B"
)

REM 2) Derivar de la ubicacion de git.exe (root\cmd\git.exe -> root\bin\bash.exe)
if not defined BASH (
  for /f "delims=" %%G in ('where git 2^>nul') do (
    if not defined BASH (
      for %%D in ("%%~dpG..") do set "GITROOT=%%~fD"
      if exist "!GITROOT!\bin\bash.exe" set "BASH=!GITROOT!\bin\bash.exe"
    )
  )
)

REM 3) where bash, excluyendo el stub de WSL en System32
if not defined BASH (
  for /f "delims=" %%B in ('where bash 2^>nul') do (
    if not defined BASH (
      echo %%B | findstr /I "System32" >nul || set "BASH=%%B"
    )
  )
)

if defined BASH (
  "!BASH!" "%HERE%bootstrap.sh" %*
  exit /b !ERRORLEVEL!
)

REM 4) Sin bash real: PowerShell nativo
where powershell >nul 2>&1
if !ERRORLEVEL! EQU 0 (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%bootstrap.ps1" %*
  exit /b !ERRORLEVEL!
)
echo [bootstrap] No se encontro Git Bash ni PowerShell. Instala Git para Windows.
exit /b 1
