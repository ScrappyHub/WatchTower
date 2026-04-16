# WatchTower CLI v1

Deterministic observer and evidence surface for WatchTower.

## Included
- scripts/watchtower_cli_v1.ps1
- scripts/_selftest_watchtower_cli_v1.ps1
- scripts/_RUN_watchtower_cli_freeze_v1.ps1
- proofs/freeze/watchtower_cli_v1/stdout.txt
- proofs/freeze/watchtower_cli_v1/stderr.txt
- proofs/freeze/watchtower_cli_v1/sha256sums.txt

## Example usage
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\watchtower_cli_v1.ps1 -RepoRoot . device list
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\watchtower_cli_v1.ps1 -RepoRoot . freeze show
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\_selftest_watchtower_cli_v1.ps1 -RepoRoot .

## Success tokens
- WATCHTOWER_DEVICE_LIST_OK
- WATCHTOWER_RECEIPTS_LIST_OK
- WATCHTOWER_FREEZE_SHOW_OK
- WATCHTOWER_CLI_SELFTEST_OK
- WATCHTOWER_CLI_FREEZE_OK
