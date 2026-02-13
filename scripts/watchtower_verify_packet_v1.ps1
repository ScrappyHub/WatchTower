param([Parameter(Mandatory=$true)][string]$PacketRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw ("PCV1_VERIFY_FAIL: " + $m) }
function ReadBytes([string]$p){ [System.IO.File]::ReadAllBytes($p) }
function Sha256HexBytes([byte[]]$b){ if($null -eq $b){ $b=@() }; $sha=[System.Security.Cryptography.SHA256]::Create(); try{ $h=$sha.ComputeHash([byte[]]$b) } finally { $sha.Dispose() }; $sb=New-Object System.Text.StringBuilder; for($i=0;$i -lt $h.Length;$i++){ [void]$sb.Append($h[$i].ToString("x2")) }; $sb.ToString() }
function Sha256HexFile([string]$p){ Sha256HexBytes (ReadBytes $p) }
function RelSlash([string]$root,[string]$full){ $r=$root.TrimEnd("\") + "\"; if(-not $full.StartsWith($r,[StringComparison]::OrdinalIgnoreCase)){ Die ("path not under root: " + $full) }; $full.Substring($r.Length).Replace("\","/") }

$PacketRoot = (Resolve-Path -LiteralPath $PacketRoot).Path
if(-not (Test-Path -LiteralPath $PacketRoot -PathType Container)) { Die ("missing packet root: " + $PacketRoot) }
$man = Join-Path $PacketRoot "manifest.json"
$pidp = Join-Path $PacketRoot "packet_id.txt"
$sum = Join-Path $PacketRoot "sha256sums.txt"
if(-not (Test-Path -LiteralPath $man -PathType Leaf)) { Die "missing manifest.json" }
if(-not (Test-Path -LiteralPath $pidp -PathType Leaf)) { Die "missing packet_id.txt (Option A required)" }
if(-not (Test-Path -LiteralPath $sum -PathType Leaf)) { Die "missing sha256sums.txt" }

# Option A: manifest.json must NOT include packet_id
$raw = [System.IO.File]::ReadAllText($man,(New-Object System.Text.UTF8Encoding($false)))
$raw = $raw.Replace("`r`n","`n").Replace("`r","`n")
try { $obj = $raw | ConvertFrom-Json -ErrorAction Stop } catch { Die ("manifest.json not valid json: " + $_.Exception.Message) }
if ($null -ne ($obj.PSObject.Properties["packet_id"])) { Die "OptionA violation: manifest.json contains packet_id" }

# PacketId = SHA256(canonical bytes of manifest.json) (UTF-8 no BOM, LF)
$manBytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($raw)
$pidExpected = Sha256HexBytes $manBytes
$pidGot = [System.IO.File]::ReadAllText($pidp,(New-Object System.Text.UTF8Encoding($false))).Trim()
if ($pidGot -ne $pidExpected) { Die ("PacketId mismatch: got=" + $pidGot + " expect=" + $pidExpected) }

# sha256sums: must cover every file except sha256sums.txt itself
$lines = @(@([System.IO.File]::ReadAllLines($sum,(New-Object System.Text.UTF8Encoding($false)))))
$seen = @{}
for($i=0;$i -lt $lines.Count;$i++){
  $ln = $lines[$i]; if ($null -eq $ln) { continue }; $ln = $ln.Trim(); if ($ln -eq "" -or $ln.StartsWith("#")) { continue }
  $m = [regex]::Match($ln,"^(?<h>[0-9a-f]{64})\s+\*?(?<p>.+)$")
  if (-not $m.Success) { Die ("bad sha256sums line " + ($i+1) + ": " + $ln) }
  $hex = $m.Groups["h"].Value
  $rel = $m.Groups["p"].Value.Trim().Replace("\","/")
  if ($rel -eq "sha256sums.txt") { Die "sha256sums must not include itself" }
  $fp = Join-Path $PacketRoot ($rel.Replace("/","\"))
  if (-not (Test-Path -LiteralPath $fp -PathType Leaf)) { Die ("sha256sums references missing file: " + $rel) }
  $got = Sha256HexFile $fp
  if ($got -ne $hex) { Die ("sha256 mismatch: " + $rel + " got=" + $got + " expect=" + $hex) }
  $seen[$rel] = $true
}

$files = @(@(Get-ChildItem -LiteralPath $PacketRoot -Recurse -File -ErrorAction Stop))
foreach($f in @($files)){
  $rel = (RelSlash $PacketRoot $f.FullName)
  if ($rel -eq "sha256sums.txt") { continue }
  if (-not $seen.ContainsKey($rel)) { Die ("sha256sums missing entry for file: " + $rel) }
}
Write-Host ("VERIFY_OK PacketId=" + $pidGot) -ForegroundColor Green
