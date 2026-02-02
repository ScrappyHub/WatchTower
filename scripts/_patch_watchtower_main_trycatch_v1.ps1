param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$MainPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $MainPath)) { throw "Missing: $MainPath" }

$txt = [System.IO.File]::ReadAllText($MainPath, [System.Text.Encoding]::UTF8)

# Ensure there's a newline before "return $packetId" if it was glued after Copy-Item
$txt = $txt.Replace("Copy-Item -LiteralPath $final -Destination $dest -Recurse -Force    return $packetId",
                    "Copy-Item -LiteralPath $final -Destination $dest -Recurse -Force`n`n  return $packetId")

# Find the BuildPacketAndDuplicateToNFL function block
$fnStart = $txt.IndexOf("function BuildPacketAndDuplicateToNFL")
if ($fnStart -lt 0) { throw "Could not find function BuildPacketAndDuplicateToNFL" }

# Find opening brace of the function
$braceOpen = $txt.IndexOf("{", $fnStart)
if ($braceOpen -lt 0) { throw "Could not find '{' for BuildPacketAndDuplicateToNFL" }

# Find the line containing: $tmp = Join-Path $Outbox ("_tmp_" + [Guid]::NewGuid().ToString("N"))
$tmpNeedle = '$tmp = Join-Path $Outbox ("_tmp_" + [Guid]::NewGuid().ToString("N"))'
$tmpPos = $txt.IndexOf($tmpNeedle, $fnStart)
if ($tmpPos -lt 0) { throw "Could not find tmp creation line (needle not found)." }

# Find end-of-line after tmp creation
$eolAfterTmp = $txt.IndexOf("`n", $tmpPos)
if ($eolAfterTmp -lt 0) { throw "Could not find EOL after tmp creation line" }

# If there is already a try { soon after tmp line, do nothing; else insert "try {"
$lookahead = $txt.Substring($eolAfterTmp, [Math]::Min(200, $txt.Length - $eolAfterTmp))
if ($lookahead -notmatch "^\s*try\s*\{") {
  $txt = $txt.Insert($eolAfterTmp + 1, "  try {`n")
}

# Now we must ensure the function ends with:
#   return $packetId
#   } catch { cleanup; throw }
#   }
# We'll insert catch JUST BEFORE the final "}" of the function if it's not already present.

# Find the end of function by counting braces from braceOpen
$depth = 0
$end = -1
for ($i = $braceOpen; $i -lt $txt.Length; $i++) {
  $ch = $txt[$i]
  if ($ch -eq "{") { $depth++ }
  elseif ($ch -eq "}") {
    $depth--
    if ($depth -eq 0) { $end = $i; break }
  }
}
if ($end -lt 0) { throw "Could not locate end of BuildPacketAndDuplicateToNFL (brace walk failed)" }

$fnBlock = $txt.Substring($braceOpen, ($end - $braceOpen) + 1)
if ($fnBlock -match "\}\s*catch\s*\{") {
  # already has catch; just write back
  [System.IO.File]::WriteAllText($MainPath, $txt.Replace("`r`n","`n").Replace("`r","`n"), (New-Object System.Text.UTF8Encoding($false)))
  "OK: main already has catch"
  exit 0
}

# Insert catch right before the closing brace of the function.
# We also need to close the inserted try { ... } with a '}' before catch.
# We'll insert:
#   }
#   catch { cleanup; throw }
# right before final "}" of the function.

$insert =
@"
  }
  catch {
    try {
      if (`$tmp -and (Test-Path -LiteralPath `$tmp)) { Remove-Item -LiteralPath `$tmp -Recurse -Force }
    } catch { }
    throw
  }

"@

$txt = $txt.Insert($end, $insert)

[System.IO.File]::WriteAllText($MainPath, $txt.Replace("`r`n","`n").Replace("`r","`n"), (New-Object System.Text.UTF8Encoding($false)))
"OK: patched main try/catch + return newline"