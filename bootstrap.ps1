#Requires -Version 3
<#
  bootstrap.ps1 - Windows launcher (PowerShell). Runs bootstrap.sh with Git Bash, the single
  implementation: git runs the hooks with Git Bash anyway, so Git for Windows is required.
  Usage:  .\bootstrap.ps1 <git-url|repo-path> [dest-dir]
#>
param([Parameter(ValueFromRemainingArguments = $true)] [string[]] $Rest)
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Find-Bash {
  # 1) usual Git for Windows locations
  foreach ($p in @(
      "$env:ProgramFiles\Git\bin\bash.exe",
      "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
      "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")) {
    if (Test-Path $p) { return $p }
  }
  # 2) next to git.exe (root\cmd\git.exe -> root\bin\bash.exe)
  $git = Get-Command git -ErrorAction SilentlyContinue
  if ($git) {
    $cand = Join-Path (Split-Path (Split-Path $git.Source -Parent) -Parent) "bin\bash.exe"
    if (Test-Path $cand) { return $cand }
  }
  # 3) 'bash' on PATH, except the WSL stub in System32
  $c = Get-Command bash -ErrorAction SilentlyContinue
  if ($c -and ($c.Source -notmatch 'System32')) { return $c.Source }
  return $null
}

$bash = Find-Bash
if (-not $bash) {
  Write-Host "[bootstrap] Git Bash not found. Install Git for Windows (https://git-scm.com/download/win) and retry."
  exit 1
}
& $bash "$Here\bootstrap.sh" @Rest
exit $LASTEXITCODE
