param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$KeyPub,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Principal,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$OutPath,
  [string]$KeyId = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Dir([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
  $dir = Split-Path -Parent $Path
  if ($dir) { Ensure-Dir $dir }
  $enc = New-Object System.Text.UTF8Encoding($false)
  $norm = $Content.Replace("`r`n","`n").Replace("`r","`n")
  [System.IO.File]::WriteAllText($Path, $norm, $enc)
}

if (-not (Test-Path -LiteralPath $KeyPub)) { throw "Missing pubkey: $KeyPub" }

# Expect OpenSSH public key line: "ssh-ed25519 AAAA... comment"
$line = (Get-Content -LiteralPath $KeyPub -TotalCount 1).Trim()
if (-not $line.StartsWith("ssh-ed25519 ")) {
  throw "Pubkey file does not look like OpenSSH ed25519 pubkey: $KeyPub"
}

# Keep only "ssh-ed25519 AAAA...." (drop trailing comment if present)
$parts = $line.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
if ($parts.Count -lt 2) { throw "Invalid pubkey line in $KeyPub" }
$pub = ($parts[0] + " " + $parts[1])

# allowed_signers format: identity <space> pubkey [options]
# We'll include keyid=... if provided (useful metadata; not required by verify)
$outLine = if ($KeyId) {
  "{0} {1} keyid={2}" -f $Principal, $pub, $KeyId
} else {
  "{0} {1}" -f $Principal, $pub
}

Write-Utf8NoBom $OutPath ($outLine + "`n")
Write-Host ("OK: wrote allowed_signers: {0}" -f $OutPath) -ForegroundColor Green
Write-Host ("OK: identity: {0}" -f $Principal) -ForegroundColor Cyan
Write-Host ("OK: pubkey: {0}" -f $pub) -ForegroundColor DarkGray