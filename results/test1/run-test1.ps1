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
$resultDir = Join-Path $PSScriptRoot (Join-Path 'replays' $timestamp)
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
$levels = @(25, 50, 100, 200, 400, 800)

foreach ($service in $services) {
  $url = [string]$targets.PSObject.Properties[$service].Value
  Write-Host "`n===== $service ====="
  foreach ($vus in $levels) {
    $label = "$service-v$vus"
    $summaryPath = Join-Path $resultDir "$label.json"
    $logPath = Join-Path $resultDir "$label.log"
    Write-Host "`nRunning $label : 10,000 numbers, $Duration, stop on any request/check failure"
    $env:BASE_URL = $url
    $env:SCENARIO = 'calculate'
    $env:PAYLOAD_SIZE = '10000'
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
    $failedChecks = [int]$metrics.checks.values.fails
    Write-Host ("Stage: {0} requests, {1} failed HTTP requests, {2} failed checks, {3:N2}% HTTP request failures" -f $requests, $failedRequests, $failedChecks, (100 * $metrics.http_req_failed.values.rate))
    if ($failedRequests -gt 0 -or $failedChecks -gt 0) {
      Write-Warning "$label had failures; historical Test 1 stopped escalation on the first failed request or check."
      break
    }
  }
}
Write-Host "`nReplay files saved under $resultDir"
