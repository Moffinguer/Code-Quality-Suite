#Requires -Version 3
<#
  bootstrap.ps1 - lanzador Windows (PowerShell).
  1) Si hay bash (Git Bash), delega en bootstrap.sh (fuente unica de verdad).
  2) Si NO hay bash, ejecuta la implementacion nativa equivalente.
  Uso:  .\bootstrap.ps1 <git-url|ruta-repo> [dir-destino]
#>
param([Parameter(ValueFromRemainingArguments = $true)] [string[]] $Rest)
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Find-Bash {
  # 1) Rutas conocidas de Git Bash (prioridad: es el bash real)
  foreach ($p in @(
      "$env:ProgramFiles\Git\bin\bash.exe",
      "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
      "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")) {
    if (Test-Path $p) { return $p }
  }
  # 2) Derivar de git.exe
  $git = Get-Command git -ErrorAction SilentlyContinue
  if ($git) {
    $root = Split-Path (Split-Path $git.Source -Parent) -Parent
    $cand = Join-Path $root "bin\bash.exe"
    if (Test-Path $cand) { return $cand }
  }
  # 3) 'bash' en PATH, excluyendo el stub de WSL en System32
  $c = Get-Command bash -ErrorAction SilentlyContinue
  if ($c -and ($c.Source -notmatch 'System32')) { return $c.Source }
  return $null
}

# 1) Preferir bash: no duplicamos logica.
$bash = Find-Bash
if ($bash) {
  & $bash "$Here\bootstrap.sh" @Rest
  exit $LASTEXITCODE
}

Write-Host "[bootstrap] Sin bash; implementacion nativa de PowerShell."

# 2) Implementacion nativa (fallback) ----------------------------------------
if ($Rest.Count -lt 1) { throw "uso: .\bootstrap.ps1 <git-url|ruta-repo> [dir-destino]" }
$Src  = $Rest[0]
$Dest = if ($Rest.Count -ge 2) { $Rest[1] } else { "" }

$Workspace = if ($env:CQS_WORKSPACE) { $env:CQS_WORKSPACE } else { "." }

if ($Src -match '^(https?://|git@|ssh://)') {
  $name = [IO.Path]::GetFileNameWithoutExtension($Src.TrimEnd('/'))
  $target = if ($Dest) { $Dest } else { Join-Path $Workspace $name }
  if (Test-Path (Join-Path $target ".git")) { Write-Host "[bootstrap] '$target' ya existe; lo reutilizo." }
  else { Write-Host "[bootstrap] Clonando en $target ..."; git clone $Src $target }
  $Repo = (Resolve-Path $target).Path
} else {
  $Repo = (Resolve-Path $Src).Path
}
Write-Host "[bootstrap] Repo: $Repo"

$HookDir = Join-Path (git -C $Repo rev-parse --absolute-git-dir) "hooks"
New-Item -ItemType Directory -Force -Path $HookDir | Out-Null
$EnvFile = Join-Path $HookDir "quality-suite.env"

function Get-EnvVal($k) {
  if (Test-Path $EnvFile) {
    $m = Select-String -Path $EnvFile -Pattern "^$k=`"(.*)`"$" | Select-Object -First 1
    if ($m) { return $m.Matches[0].Groups[1].Value }
  }
  return ""
}
function Set-EnvVal($k, $v) {
  $line = "$k=`"$v`""
  if ((Test-Path $EnvFile) -and (Select-String -Path $EnvFile -Pattern "^$k=" -Quiet)) {
    (Get-Content $EnvFile) -replace "^$k=.*", $line | Set-Content $EnvFile
  } else { Add-Content $EnvFile $line }
}

# .gitattributes gestionado
$ga = Join-Path $Repo ".gitattributes"
$begin = "# >>> code-quality-suite (gestionado) >>>"
$end   = "# <<< code-quality-suite <<<"
$block = @($begin, "* text=auto eol=lf", "*.bat text eol=crlf", "*.cmd text eol=crlf", $end)
if ((Test-Path $ga) -and (Select-String -Path $ga -Pattern ([regex]::Escape($begin)) -Quiet)) {
  $lines = Get-Content $ga; $out = @(); $skip = $false
  foreach ($l in $lines) {
    if ($l -eq $begin) { $skip = $true }
    if (-not $skip) { $out += $l }
    if ($l -eq $end) { $skip = $false }
  }
  ($out + $block) | Set-Content $ga
} else {
  Add-Content $ga ($block -join "`n")
}
Write-Host "[bootstrap] .gitattributes gestionado"

# Detectar version de Java desde pom.xml (para PMD)
$jv = Get-EnvVal "PMD_JAVA_VERSION"
if (-not $jv) {
  $pom = Join-Path $Repo "pom.xml"
  if (Test-Path $pom) {
    foreach ($rx in @('<java.version>([0-9][0-9.]*)</java.version>',
                      '<maven.compiler.release>([0-9][0-9.]*)</maven.compiler.release>',
                      '<maven.compiler.source>([0-9][0-9.]*)</maven.compiler.source>')) {
      $m = Select-String -Path $pom -Pattern $rx | Select-Object -First 1
      if ($m) { $jv = $m.Matches[0].Groups[1].Value; break }
    }
  }
  if (-not $jv) { $jv = Read-Host "Version de Java del proyecto (ej. 17, 21)"; if (-not $jv) { $jv = "21" } }
}
Write-Host "[bootstrap] PMD_JAVA_VERSION = $jv"

# Imagen + hooks
$version = if (Test-Path (Join-Path $Here "VERSION")) { (Get-Content (Join-Path $Here "VERSION")).Trim() } else { "latest" }
$image = if ($env:QUALITY_SUITE_IMAGE) { $env:QUALITY_SUITE_IMAGE } else { "code-quality-suite:$version" }
Write-Host "[bootstrap] Construyendo $image ..."
docker build -t $image $Here

foreach ($h in @("pre-commit", "pre-push", "commit-msg", "prepare-commit-msg")) {
  Copy-Item (Join-Path $Here "hooks\$h") (Join-Path $HookDir $h) -Force
}

Set-EnvVal "QUALITY_SUITE_DIR"  $Here
Set-EnvVal "QUALITY_SUITE_IMAGE" $image
Set-EnvVal "PMD_JAVA_VERSION"   $jv
if (-not (Select-String -Path $EnvFile -Pattern "^COMMIT_SUBJECT_MAX=" -Quiet)) { Set-EnvVal "COMMIT_SUBJECT_MAX" "50" }
if (-not (Select-String -Path $EnvFile -Pattern "^COMMIT_TYPES=" -Quiet)) { Set-EnvVal "COMMIT_TYPES" "feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert" }

Write-Host "[bootstrap] Listo. Prueba: cd `"$Repo`" ; git commit"
