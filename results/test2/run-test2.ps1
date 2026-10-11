param(
  [string]$TargetsPath,
  [string]$Duration = '30s'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($TargetsPath)) {
  $TargetsPath = Join-Path $repoRoot 'benchmark/targets.json'
}
$k6Script = Join-Path $PSScriptRoot 'api.js'
if (-not (Get-Command k6 -ErrorAction SilentlyContinue)) { throw 'k6 was not found on PATH. Install k6 and retry.' }
if (-not (Test-Path -LiteralPath $TargetsPath)) { throw "Targets file not found: $TargetsPath. Create it from benchmark/targets.example.json." }

$targets = Get-Content -Raw -LiteralPath $TargetsPath | ConvertFrom-Json
$services = @('fastapi', 'flask', 'express', 'node-http', 'cpp', 'rust')
foreach ($service in $services) {
  $property = $targets.PSObject.Properties[$service]
  if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) { throw "Missing URL for $service in $TargetsPath." }
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$resultDir = Join-Path $PSScriptRoot $timestamp
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
$levels = @(25, 50, 100, 200, 400, 800)
$records = [System.Collections.Generic.List[object]]::new()

foreach ($service in $services) {
  $url = [string]$targets.PSObject.Properties[$service].Value
  Write-Host "`n===== $service ====="
  foreach ($vus in $levels) {
    $label = "$service-v$vus"
    $summaryPath = Join-Path $resultDir "$label.json"
    $logPath = Join-Path $resultDir "$label.log"
    Write-Host "`nRunning $label : 5,000 numbers, $Duration; escalate until HTTP failure ratio reaches 30% or 800 VUs"
    $env:BASE_URL = $url
    $env:SCENARIO = 'calculate'
    $env:PAYLOAD_SIZE = '5000'
    $env:VUS = [string]$vus
    $env:DURATION = $Duration
    $env:SUMMARY_FILE = $summaryPath
    try {
      & k6 run $k6Script 2>&1 | Tee-Object -FilePath $logPath
      $exitCode = $LASTEXITCODE
    }
    finally {
      Remove-Item Env:BASE_URL, Env:SCENARIO, Env:PAYLOAD_SIZE, Env:VUS, Env:DURATION, Env:SUMMARY_FILE -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path -LiteralPath $summaryPath)) {
      Write-Warning "No JSON summary for $label (k6 exit code: $exitCode). Stopping this service and continuing to the next."
      break
    }

    $summary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json
    $metrics = $summary.metrics
    $requests = [int]$metrics.http_reqs.values.count
    $failedRequests = [int]$metrics.http_req_failed.values.passes
    $failureRate = if ($requests -gt 0) { $failedRequests / $requests } else { 0 }
    $failedChecks = [int]$metrics.checks.values.fails
    $records.Add([pscustomobject]@{
      Service = $service
      VUs = $vus
      Requests = $requests
      FailedRequests = $failedRequests
      FailurePercent = [math]::Round(100 * $failureRate, 2)
      FailedChecks = $failedChecks
      RPS = [math]::Round($metrics.http_reqs.values.rate, 2)
      AverageMs = [math]::Round($metrics.http_req_duration.values.avg, 2)
      P95Ms = [math]::Round($metrics.http_req_duration.values.'p(95)', 2)
      P99Ms = [math]::Round($metrics.http_req_duration.values.'p(99)', 2)
    })
    Write-Host ("Stage result: {0} requests; {1} failed HTTP requests ({2:N2}%); {3} failed checks" -f $requests, $failedRequests, (100 * $failureRate), $failedChecks)

    if ($failureRate -ge 0.30) {
      Write-Warning "$service reached the 30% HTTP request failure threshold at $vus VUs. Stopping escalation for this service; proceeding to the next service."
      break
    }
    if ($vus -eq 800) { Write-Host "$service completed all planned load levels without reaching the 30% stop threshold." }
  }
}

$csvPath = Join-Path $resultDir 'results.csv'
$records | Export-Csv -NoTypeInformation -LiteralPath $csvPath -Encoding UTF8
$lines = @(
  '# Test 2 results: 5,000-number calculation load test',
  '',
  "Run: $timestamp",
  '',
  'Each stage used k6 constant VUs for 30 seconds (plus up to 5 seconds graceful stop). A service stopped escalating only when failed HTTP requests divided by all HTTP requests in that stage reached 30%. Failed checks are reported separately. Services ran sequentially.',
  '',
  '| Service | VUs | Requests | Failed requests | Failure % | Failed checks | RPS | Avg ms | P95 ms | P99 ms |',
  '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|'
)
foreach ($record in $records) {
  $lines += ('| {0} | {1} | {2} | {3} | {4:N2} | {5} | {6:N2} | {7:N2} | {8:N2} | {9:N2} |' -f $record.Service, $record.VUs, $record.Requests, $record.FailedRequests, $record.FailurePercent, $record.FailedChecks, $record.RPS, $record.AverageMs, $record.P95Ms, $record.P99Ms)
}
$lines += @(
  '',
  'Raw k6 summaries (`.json`) and full terminal output (`.log`) for each stage are in this folder. The run used URLs from local `benchmark/targets.json`; no target URLs or credentials are copied into this README.',
  '',
  'This hosted comparison includes client network, TLS, Render routing/compute, queueing, JSON parsing, calculation, and response encoding. It is not a framework-only benchmark.'
)
$readmePath = Join-Path $resultDir 'README.md'
Set-Content -LiteralPath $readmePath -Value ($lines -join "`r`n") -Encoding UTF8
$records | Format-Table -AutoSize
Write-Host "`nSaved run README and results under $resultDir"
