param()
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Fail([string]$m){
  [Console]::Error.WriteLine($m)
  exit 1
}

$git = (Get-Command git.exe -ErrorAction Stop).Source
$paths = @(@(& $git diff --cached --name-only))
$bad = New-Object System.Collections.Generic.List[string]
foreach($p in @($paths)){
  if ($null -eq $p) { continue }
  $pp = ($p.ToString()).Trim()
  if ($pp -eq "") { continue }
  $ppSlash = $pp.Replace("\","/")
  if ($ppSlash.StartsWith("proofs/progress/")) { [void]$bad.Add($ppSlash); continue }
  if ($ppSlash.StartsWith("scripts/_scratch/")) { [void]$bad.Add($ppSlash); continue }
  if ($ppSlash -match "\.bak($|_)") { [void]$bad.Add($ppSlash); continue }
}

if (@(@($bad)).Count -gt 0) {
  $msg = "ERROR: blocked staging of local artifacts/backups:`n" + (@($bad) -join "`n") + "`nFix: git restore --staged <paths> (and delete local backups)."
  Fail $msg
}
exit 0
