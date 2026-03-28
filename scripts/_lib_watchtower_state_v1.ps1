param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function WT-Die([string]$m){ throw ("WATCHTOWER_STATE_FAIL: " + $m) }

function WT-EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function WT-WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $dir = Split-Path -Parent $Path
  if($dir){ WT-EnsureDir $dir }
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function WT-ReadUtf8NoBomLf([string]$Path){
  return [System.IO.File]::ReadAllText($Path,[System.Text.Encoding]::UTF8).Replace("`r`n","`n").Replace("`r","`n")
}

function WT-ToIsoUtc([datetime]$dt){
  return $dt.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

function WT-ParseIsoUtc([string]$s){
  return [datetime]::Parse(
    $s,
    [System.Globalization.CultureInfo]::InvariantCulture,
    [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
  )
}

function WT-AppendNdjson([string]$Path,[string]$Line){
  $dir = Split-Path -Parent $Path
  if($dir){ WT-EnsureDir $dir }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::AppendAllText($Path,(($Line -replace "`r`n","`n") -replace "`r","`n") + "`n",$enc)
}

function WT-ReadNdjsonObjects([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ return @() }
  $raw = WT-ReadUtf8NoBomLf $Path
  $out = New-Object System.Collections.Generic.List[object]
  foreach($ln in ($raw -split "`n")){
    $t = $ln.Trim()
    if($t.Length -eq 0){ continue }
    [void]$out.Add(($t | ConvertFrom-Json))
  }
  return @($out)
}

function WT-ValidateTelemetryObject([object]$o){
  if($null -eq $o){ WT-Die "NULL_TELEMETRY" }
  if([string]::IsNullOrWhiteSpace([string]$o.schema)){ WT-Die "MISSING_SCHEMA" }
  if([string]::IsNullOrWhiteSpace([string]$o.device_id)){ WT-Die "MISSING_DEVICE_ID" }
  if([string]::IsNullOrWhiteSpace([string]$o.observed_utc)){ WT-Die "MISSING_OBSERVED_UTC" }

  $schema = [string]$o.schema
  if(
    ($schema -ne "watchtower.heartbeat.v1") -and
    ($schema -ne "watchtower.health_report.v1") -and
    ($schema -ne "watchtower.policy_attest.v1")
  ){
    WT-Die ("UNSUPPORTED_SCHEMA: " + $schema)
  }

  [void](WT-ParseIsoUtc ([string]$o.observed_utc))
}

function WT-NewVerifyReceipt([object]$o,[string]$status,[string]$reason){
  return [pscustomobject]@{
    schema             = "watchtower.telemetry.verify.receipt.v1"
    device_id          = [string]$o.device_id
    telemetry_schema   = [string]$o.schema
    observed_utc       = [string]$o.observed_utc
    verify_status      = $status
    reason             = $reason
    source_object_json = ($o | ConvertTo-Json -Compress -Depth 20)
  } | ConvertTo-Json -Compress -Depth 20
}

function WT-ComputeState(
  [object[]]$Telemetry,
  [string]$ExpectedPolicyHash,
  [int]$HeartbeatStaleMinutes
){
  if($HeartbeatStaleMinutes -le 0){ WT-Die "INVALID_STALE_MINUTES" }

  if($null -eq $Telemetry -or $Telemetry.Count -eq 0){
    return [pscustomobject]@{
      state        = "unknown"
      reason       = "no telemetry"
      device_id    = ""
      observed_utc = "1970-01-01T00:00:00Z"
    }
  }

  $deviceId = [string]$Telemetry[0].device_id
  $latestHeartbeat = $null
  $latestHealth    = $null
  $latestPolicy    = $null

  foreach($t in $Telemetry){
    WT-ValidateTelemetryObject $t
    if([string]$t.device_id -ne $deviceId){ WT-Die "MIXED_DEVICE_IDS" }

    $schema = [string]$t.schema
    $cur    = WT-ParseIsoUtc ([string]$t.observed_utc)

    if($schema -eq "watchtower.heartbeat.v1"){
      if(($null -eq $latestHeartbeat) -or ($cur -gt (WT-ParseIsoUtc ([string]$latestHeartbeat.observed_utc)))){
        $latestHeartbeat = $t
      }
    }
    elseif($schema -eq "watchtower.health_report.v1"){
      if(($null -eq $latestHealth) -or ($cur -gt (WT-ParseIsoUtc ([string]$latestHealth.observed_utc)))){
        $latestHealth = $t
      }
    }
    elseif($schema -eq "watchtower.policy_attest.v1"){
      if(($null -eq $latestPolicy) -or ($cur -gt (WT-ParseIsoUtc ([string]$latestPolicy.observed_utc)))){
        $latestPolicy = $t
      }
    }
  }

  if($null -eq $latestHeartbeat){
    return [pscustomobject]@{
      state        = "unknown"
      reason       = "missing heartbeat"
      device_id    = $deviceId
      observed_utc = "1970-01-01T00:00:00Z"
    }
  }

  $hbUtc  = WT-ParseIsoUtc ([string]$latestHeartbeat.observed_utc)
  $maxUtc = $hbUtc

  if($latestHealth){
    $hUtc = WT-ParseIsoUtc ([string]$latestHealth.observed_utc)
    if($hUtc -gt $maxUtc){ $maxUtc = $hUtc }
  }

  if($latestPolicy){
    $pUtc = WT-ParseIsoUtc ([string]$latestPolicy.observed_utc)
    if($pUtc -gt $maxUtc){ $maxUtc = $pUtc }
  }

  $ageMin = [math]::Floor(($maxUtc - $hbUtc).TotalMinutes)
  if($ageMin -ge $HeartbeatStaleMinutes){
    return [pscustomobject]@{
      state        = "stale"
      reason       = ("heartbeat age minutes=" + $ageMin)
      device_id    = $deviceId
      observed_utc = WT-ToIsoUtc $hbUtc
    }
  }

  if(-not [bool]$latestHeartbeat.heartbeat_ok){
    return [pscustomobject]@{
      state        = "broken"
      reason       = "heartbeat marked failed"
      device_id    = $deviceId
      observed_utc = [string]$latestHeartbeat.observed_utc
    }
  }

  if($latestHealth){
    if((-not [bool]$latestHealth.health_ok) -or ([int]$latestHealth.failure_count -gt 0)){
      return [pscustomobject]@{
        state        = "broken"
        reason       = "health report indicates failure"
        device_id    = $deviceId
        observed_utc = [string]$latestHealth.observed_utc
      }
    }

    if([bool]$latestHealth.degraded){
      return [pscustomobject]@{
        state        = "degraded"
        reason       = "health report indicates degraded"
        device_id    = $deviceId
        observed_utc = [string]$latestHealth.observed_utc
      }
    }
  }

  if($latestPolicy){
    $actual = [string]$latestPolicy.policy_hash
    $expected = $ExpectedPolicyHash

    if([string]::IsNullOrWhiteSpace($expected) -and ($latestPolicy.PSObject.Properties.Name -contains "expected_policy_hash")){
      $expected = [string]$latestPolicy.expected_policy_hash
    }

    if((-not [bool]$latestPolicy.policy_ok) -or ((-not [string]::IsNullOrWhiteSpace($expected)) -and ($actual -ne $expected))){
      return [pscustomobject]@{
        state        = "drift"
        reason       = "policy hash drift"
        device_id    = $deviceId
        observed_utc = [string]$latestPolicy.observed_utc
      }
    }
  }

  return [pscustomobject]@{
    state        = "ok"
    reason       = "all checks green"
    device_id    = $deviceId
    observed_utc = WT-ToIsoUtc $maxUtc
  }
}

function WT-NewStateJson([object]$StateObj){
  return [pscustomobject]@{
    schema       = "watchtower.state.v1"
    device_id    = [string]$StateObj.device_id
    observed_utc = [string]$StateObj.observed_utc
    state        = [string]$StateObj.state
    reason       = [string]$StateObj.reason
  } | ConvertTo-Json -Compress -Depth 10
}

function WT-NewAlertsFromState([object]$StateObj){
  $state = [string]$StateObj.state
  if($state -eq "ok"){ return @() }

  $sev = "warning"
  $type = "telemetry_unknown"

  if($state -eq "stale"){
    $sev = "warning"
    $type = "heartbeat_stale"
  }
  elseif($state -eq "drift"){
    $sev = "warning"
    $type = "policy_drift"
  }
  elseif($state -eq "degraded"){
    $sev = "warning"
    $type = "health_degraded"
  }
  elseif($state -eq "broken"){
    $sev = "critical"
    $type = "health_failed"
  }
  elseif($state -eq "unknown"){
    $sev = "warning"
    $type = "telemetry_unknown"
  }

  $alert = [pscustomobject]@{
    schema       = "watchtower.alert.v1"
    device_id    = [string]$StateObj.device_id
    observed_utc = [string]$StateObj.observed_utc
    alert_type   = $type
    severity     = $sev
    state        = $state
    reason       = [string]$StateObj.reason
  } | ConvertTo-Json -Compress -Depth 10

  return @($alert)
}
