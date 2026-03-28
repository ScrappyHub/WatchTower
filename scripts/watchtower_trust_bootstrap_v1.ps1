param(
  [Parameter(Mandatory=$true)]$RepoRoot
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw ("WT_TRUST_BOOTSTRAP_FAIL: " + $m) }

if($RepoRoot -is [System.IO.FileSystemInfo]){ $RepoRoot = $RepoRoot.FullName }
elseif($RepoRoot -is [array]){
  if($RepoRoot.Count -eq 0){ Die "EMPTY_REPO_ROOT_ARG" }
  $RepoRoot = $RepoRoot[0]
}
$RepoRoot = [string]$RepoRoot

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){
  Die ("INVALID_REPO_ROOT: " + $RepoRoot)
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$KeyDir   = Join-Path $RepoRoot "proofs\keys"
$TrustDir = Join-Path $RepoRoot "proofs\trust"
$RcptDir  = Join-Path $RepoRoot "proofs\receipts"
$Scratch  = Join-Path $RepoRoot "scripts\_scratch"

New-Item -ItemType Directory -Force -Path $KeyDir   | Out-Null
New-Item -ItemType Directory -Force -Path $TrustDir | Out-Null
New-Item -ItemType Directory -Force -Path $RcptDir  | Out-Null
New-Item -ItemType Directory -Force -Path $Scratch  | Out-Null

$KeyPath     = Join-Path $KeyDir "wt_key"
$PubPath     = $KeyPath + ".pub"
$TrustPath   = Join-Path $TrustDir "trust_bundle.json"
$AllowedPath = Join-Path $TrustDir "allowed_signers"
$ProbePath   = Join-Path $Scratch "watchtower_trust_probe.txt"
$SigPath     = $ProbePath + ".sig"
$ReceiptPath = Join-Path $RcptDir "watchtower_trust_bootstrap.ndjson"

foreach($p in @($KeyPath,$PubPath,$TrustPath,$AllowedPath,$ProbePath,$SigPath,$ReceiptPath)){
  if($p -and (Test-Path -LiteralPath $p -PathType Leaf)){
    Remove-Item -LiteralPath $p -Force
  }
}

$ssh = (Get-Command ssh-keygen.exe -ErrorAction Stop).Source

Write-Host "PHASE:KEYGEN_START" -ForegroundColor Yellow

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $ssh
$psi.Arguments = ('-q -t ed25519 -f "{0}" -N "" -C "wt"' -f $KeyPath)
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
$null = $proc.Start()
$stdout = $proc.StandardOutput.ReadToEnd()
$stderr = $proc.StandardError.ReadToEnd()
$proc.WaitForExit()

if($proc.ExitCode -ne 0){
  if([string]::IsNullOrWhiteSpace($stderr)){
    Die ("SSH_KEYGEN_FAILED_EXIT_" + $proc.ExitCode)
  } else {
    Die ("SSH_KEYGEN_FAILED_EXIT_" + $proc.ExitCode + ": " + $stderr.Trim())
  }
}

Write-Host "PHASE:KEYGEN_DONE" -ForegroundColor Yellow

if(-not (Test-Path -LiteralPath $KeyPath -PathType Leaf)){ Die ("NO_KEY: " + $KeyPath) }
if(-not (Test-Path -LiteralPath $PubPath -PathType Leaf)){ Die ("NO_PUB: " + $PubPath) }

$pubRaw = Get-Content -LiteralPath $PubPath -ErrorAction Stop
if($null -eq $pubRaw){ Die "EMPTY_PUB_FILE" }

$pubLines = @($pubRaw)
if($pubLines.Count -lt 1){ Die "EMPTY_PUB_FILE" }

$pub = ([string]$pubLines[0]).Trim()
if([string]::IsNullOrWhiteSpace($pub)){ Die "EMPTY_PUB_LINE" }

$parts = @($pub -split ' ' | Where-Object { $_ -and $_.Trim().Length -gt 0 })
if($parts.Count -lt 2){ Die ("BAD_PUB_FORMAT: " + $pub) }

$keyType = [string]$parts[0]
$keyBase64 = [string]$parts[1]

$sha = [System.Security.Cryptography.SHA256]::Create()
try {
  $keyId = ([System.BitConverter]::ToString(
    $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($pub))
  ) -replace "-","").ToLowerInvariant()
}
finally {
  $sha.Dispose()
}

if([string]::IsNullOrWhiteSpace($keyId)){ Die "EMPTY_KEY_ID" }

$trustJson = "{ `"key_id`": `"$keyId`", `"pub`": `"$pub`" }"
[System.IO.File]::WriteAllText($TrustPath,$trustJson,(New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText($AllowedPath,("watchtower namespaces=`"watchtower`" " + $keyType + " " + $keyBase64 + "`n"),(New-Object System.Text.UTF8Encoding($false)))

Write-Host "PHASE:SIGN_START" -ForegroundColor Yellow

[System.IO.File]::WriteAllText($ProbePath,"watchtower trust bootstrap probe`n",(New-Object System.Text.UTF8Encoding($false)))

$signProc = Start-Process -FilePath $ssh -ArgumentList @("-Y","sign","-f",$KeyPath,"-n","watchtower",$ProbePath) -Wait -PassThru -NoNewWindow
if($signProc.ExitCode -ne 0){ Die ("SIGN_FAILED_EXIT_" + $signProc.ExitCode) }
if(-not (Test-Path -LiteralPath $SigPath -PathType Leaf)){ Die ("NO_SIG: " + $SigPath) }

Write-Host "PHASE:SIGN_DONE" -ForegroundColor Yellow
Write-Host "PHASE:VERIFY_START" -ForegroundColor Yellow

$cmd = (Get-Command cmd.exe -ErrorAction Stop).Source
$verifyCmd = 'type "' + $ProbePath + '" | "' + $ssh + '" -Y verify -f "' + $AllowedPath + '" -I "watchtower" -n "watchtower" -s "' + $SigPath + '"'
$verifyProc = Start-Process -FilePath $cmd -ArgumentList @("/d","/c",$verifyCmd) -Wait -PassThru -NoNewWindow
if($verifyProc.ExitCode -ne 0){ Die ("VERIFY_FAILED_EXIT_" + $verifyProc.ExitCode) }

Write-Host "PHASE:VERIFY_DONE" -ForegroundColor Yellow

$receipt = "{ `"schema`": `"watchtower.trust.bootstrap.receipt.v1`", `"key_id`": `"$keyId`", `"status`": `"ok`" }"
[System.IO.File]::WriteAllText($ReceiptPath,$receipt,(New-Object System.Text.UTF8Encoding($false)))

Write-Host ("KEY_OK: " + $KeyPath) -ForegroundColor Green
Write-Host ("PUB_OK: " + $PubPath) -ForegroundColor Green
Write-Host ("TRUST_BUNDLE_OK: " + $TrustPath) -ForegroundColor Green
Write-Host ("ALLOWED_SIGNERS_OK: " + $AllowedPath) -ForegroundColor Green
Write-Host ("KEY_ID: " + $keyId) -ForegroundColor Green
Write-Host ("TRUST_VERIFY_OK: " + $SigPath) -ForegroundColor Green
Write-Host ("RECEIPT_OK: " + $ReceiptPath) -ForegroundColor Green
Write-Host "WT_TRUST_BOOTSTRAP_OK" -ForegroundColor Green
