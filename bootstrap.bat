@echo off
setlocal enabledelayedexpansion
REM ============================================================================
REM bootstrap.bat - Windows launcher (cmd). Runs bootstrap.sh with Git Bash and
REM ignores the WSL stub (System32\bash.exe). Git for Windows is required.
REM ============================================================================
set "HERE=%~dp0"
set "BASH="

REM 1) usual Git for Windows locations
for %%B in ("%ProgramFiles%\Git\bin\bash.exe" "%ProgramFiles(x86)%\Git\bin\bash.exe" "%LocalAppData%\Programs\Git\bin\bash.exe") do (
  if not defined BASH if exist "%%~B" set "BASH=%%~B"
)

REM 2) next to git.exe (root\cmd\git.exe -> root\bin\bash.exe)
if not defined BASH (
  for /f "delims=" %%G in ('where git 2^>nul') do (
    if not defined BASH (
      for %%D in ("%%~dpG..") do set "GITROOT=%%~fD"
      if exist "!GITROOT!\bin\bash.exe" set "BASH=!GITROOT!\bin\bash.exe"
    )
  )
)

REM 3) bash on PATH, except the WSL stub in System32
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

echo [bootstrap] Git Bash not found. Install Git for Windows (https://git-scm.com/download/win) and retry.
exit /b 1
