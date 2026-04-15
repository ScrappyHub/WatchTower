param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

$runId = [Guid]::NewGuid().ToString("N")
$reportDir = Join-Path $RepoRoot ("reports\validator_scan\" + $runId)
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

$scanFile = Join-Path $reportDir ($runId + ".scan.json")
$findingsFile = Join-Path $reportDir ($runId + ".findings.ndjson")

$targets = @(
  "$env:SystemRoot\System32",
  "$env:SystemRoot\SysWOW64",
  "$env:ProgramFiles",
  "$env:ProgramFiles(x86)"
)

$suspicious = @()

foreach($t in $targets){
  if(Test-Path $t){
    Get-ChildItem -Path $t -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
      if($_.Extension -in ".exe",".dll",".sys"){
        if($_.Length -eq 0){
          $suspicious += @{
            path = $_.FullName
            reason = "ZERO_LENGTH_EXECUTABLE"
          }
        }
      }
    }
  }
}

$scanObj = @{
  schema = "clarity.validator_scan.v1"
  run_id = $runId
  scanned_targets = $targets
  suspicious_count = $suspicious.Count
}

$scanJson = ($scanObj | ConvertTo-Json -Depth 5)
[System.IO.File]::WriteAllText($scanFile,$scanJson,[System.Text.Encoding]::UTF8)

foreach($f in $suspicious){
  $line = ($f | ConvertTo-Json -Compress)
  Add-Content -Path $findingsFile -Value $line
}

Write-Output ("SCAN_REPORT=" + $scanFile)
Write-Output ("SCAN_FINDINGS=" + $findingsFile)
Write-Output "CLARITY_TIER1_STEP6_SCAN_OK"
