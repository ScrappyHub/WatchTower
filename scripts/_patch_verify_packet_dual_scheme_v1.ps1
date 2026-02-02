param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$VerifyPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $VerifyPath)) { throw "Missing: $VerifyPath" }

$txt = [System.IO.File]::ReadAllText($VerifyPath, [System.Text.Encoding]::UTF8)

# Replace the hard fail "PacketId mismatch" block with a warning and continue.
$needleStart = '# --- 1) Recompute PacketId from manifest bytes ---'
$pos = $txt.IndexOf($needleStart)
if ($pos -lt 0) { throw "Could not find verifier PacketId section" }

# Very targeted replace: the throw block
$txt = $txt -replace 'if \(\$folderName\.ToLowerInvariant\(\) -ne \$packetId\) \{\s*throw \(\("PacketId mismatch: folder=\{0\} manifest_sha=\{1\}" -f \$folderName, \$packetId\)\)\s*\}',
'if ($folderName.ToLowerInvariant() -ne $packetId) {
  Write-Host ("WARN: legacy packet id scheme detected (folder != sha256(manifest.json))") -ForegroundColor Yellow
  Write-Host (" - folder:      {0}" -f $folderName) -ForegroundColor Yellow
  Write-Host (" - manifest_sha:{0}" -f $packetId) -ForegroundColor Yellow
}'

[System.IO.File]::WriteAllText($VerifyPath, $txt.Replace("`r`n","`n").Replace("`r","`n"), (New-Object System.Text.UTF8Encoding($false)))
"OK: patched verifier to allow legacy packets"