param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$MainPath,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$VerifyPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ReadUtf8([string]$p) { return [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) }
function WriteUtf8NoBom([string]$p, [string]$s) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  $norm = $s.Replace("`r`n","`n").Replace("`r","`n")
  [System.IO.File]::WriteAllText($p, $norm, $enc)
}

function Backup([string]$p) {
  $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
  $bak = "$p.bak_$stamp"
  WriteUtf8NoBom $bak (ReadUtf8 $p)
  Write-Host ("OK: backup: {0}" -f $bak) -ForegroundColor DarkGray
}

function MustChange([string]$before, [string]$after, [string]$msg) {
  if ($before -eq $after) { throw $msg }
}

# -------------------------
# MAIN PATCHES
# -------------------------
Backup $MainPath
$main0 = ReadUtf8 $MainPath
$main1 = $main0

# (A) Exclude sha256sums.txt from manifest file listing
# Replace exactly: Where-Object { $_.Name -ne "manifest.json" }
# with:           Where-Object { $_.Name -ne "manifest.json" -and $_.Name -ne "sha256sums.txt" }
if ($main1 -match 'Where-Object\s*\{\s*\$_\.Name\s*-ne\s*"manifest\.json"\s*\}') {
  $main1 = [regex]::Replace(
    $main1,
    'Where-Object\s*\{\s*\$_\.Name\s*-ne\s*"manifest\.json"\s*\}',
    'Where-Object { $_.Name -ne "manifest.json" -and $_.Name -ne "sha256sums.txt" }',
    'IgnoreCase'
  )
}

# If it already has sha256sums excluded, that's fine; otherwise we require the patch to apply
if ($main0 -notmatch 'sha256sums\.txt' ) {
  MustChange $main0 $main1 "MAIN patch A did not apply. Could not find expected Where-Object filter for manifest.json."
}

# (B) Remove the first Write-Sha256Sums $tmp that occurs BEFORE manifest write / core build
# We only remove the one that appears before: $core = BuildManifestCore
$patB = '(?s)(function\s+BuildPacketAndDuplicateToNFL\b.*?)(?:\r?\n|\n)\s*Write-Sha256Sums\s+\$tmp\s*(?:#.*)?(?:\r?\n|\n)(.*?\$core\s*=\s*BuildManifestCore\b)'
$main2 = [regex]::Replace($main1, $patB, '$1' + "`n" + '$2', 1)

# If there is a pre-manifest Write-Sha256Sums line, we MUST remove it
if ($main1 -match $patB) {
  MustChange $main1 $main2 "MAIN patch B did not apply. Found pre-core Write-Sha256Sums but failed to remove it."
}
$main1 = $main2

WriteUtf8NoBom $MainPath $main1
[ScriptBlock]::Create((ReadUtf8 $MainPath)) | Out-Null
Write-Host ("OK: MAIN patched + parses: {0}" -f $MainPath) -ForegroundColor Green

# -------------------------
# VERIFY PATCHES
# -------------------------
Backup $VerifyPath
$ver0 = ReadUtf8 $VerifyPath
$ver1 = $ver0

# Insert: if ($rel -ieq "sha256sums.txt") { continue }
# right after the line that sets $rel in the manifest loop(s).
# We do two common patterns.

# Pattern 1: $rel = [string](Get-Prop $f "path" "")
$patV1 = '(\$rel\s*=\s*\[string\]\s*\(Get-Prop\s+\$f\s+"path"\s+""\)\s*(?:\r?\n|\n))'
if ($ver1 -match $patV1 -and $ver1 -notmatch '\$rel\s*-ieq\s*"sha256sums\.txt"') {
  $ver1 = [regex]::Replace($ver1, $patV1, '$1' + '  if ($rel -ieq "sha256sums.txt") { continue }' + "`n", 1)
}

# Pattern 2: $rel = [string]$f.path
$patV2 = '(\$rel\s*=\s*\[string\]\s*\$f\.path\s*(?:\r?\n|\n))'
if ($ver1 -match $patV2 -and $ver1 -notmatch '\$rel\s*-ieq\s*"sha256sums\.txt"') {
  $ver1 = [regex]::Replace($ver1, $patV2, '$1' + '  if ($rel -ieq "sha256sums.txt") { continue }' + "`n", 1)
}

# If verifier already had the skip, ok; otherwise we require it to be present after patching.
if ($ver1 -notmatch '\$rel\s*-ieq\s*"sha256sums\.txt"\s*\)\s*\{\s*continue\s*\}') {
  throw "VERIFY patch did not apply. Could not insert skip for sha256sums.txt in manifest files verification loop."
}

WriteUtf8NoBom $VerifyPath $ver1
[ScriptBlock]::Create((ReadUtf8 $VerifyPath)) | Out-Null
Write-Host ("OK: VERIFY patched + parses: {0}" -f $VerifyPath) -ForegroundColor Green

Write-Host "OK: PATCH PIPELINE COMPLETE" -ForegroundColor Green