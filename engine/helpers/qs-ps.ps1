# qs-ps.ps1 - PowerShell parse / format / lint for the quality suite.
#   pwsh -File qs-ps.ps1 syntax <files...>
#   pwsh -File qs-ps.ps1 format <settings.psd1> <files...>   (rewrites files in place)
#   pwsh -File qs-ps.ps1 lint   <settings.psd1> <files...>
param([Parameter(Mandatory)][string]$Mode, [Parameter(ValueFromRemainingArguments)][string[]]$Rest)
$ErrorActionPreference = 'Stop'
$failed = $false
switch ($Mode) {
  'syntax' {
    foreach ($f in $Rest) {
      $tokens = $null; $errors = $null
      [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f), [ref]$tokens, [ref]$errors) | Out-Null
      foreach ($e in $errors) {
        "{0}:{1}:{2}: {3}" -f $f, $e.Extent.StartLineNumber, $e.Extent.StartColumnNumber, $e.Message
        $failed = $true
      }
    }
  }
  'format' {
    $settings = $Rest[0]
    foreach ($f in $Rest[1..($Rest.Count - 1)]) {
      $src = [System.IO.File]::ReadAllText((Resolve-Path $f))
      $out = Invoke-Formatter -ScriptDefinition $src -Settings $settings
      if ($out -ne $src) { [System.IO.File]::WriteAllText((Resolve-Path $f), $out) }
    }
  }
  'lint' {
    $settings = $Rest[0]
    foreach ($f in $Rest[1..($Rest.Count - 1)]) {
      foreach ($r in (Invoke-ScriptAnalyzer -Path $f -Settings $settings)) {
        "{0}:{1}:{2}: {3} {4}: {5}" -f $f, $r.Line, $r.Column, $r.Severity, $r.RuleName, $r.Message
        $failed = $true
      }
    }
  }
  default { Write-Error "unknown mode $Mode"; exit 2 }
}
if ($failed) { exit 1 } else { exit 0 }
