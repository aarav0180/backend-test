param(
  [ValidateSet('all', 'smoke', 'load')]
  [string]$Only = 'all',
  [int]$Repetitions = 3,
  [string]$TargetsPath = (Join-Path $PSScriptRoot 'targets.json')
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$k6Script = Join-Path $PSScriptRoot 'k6/api.js'
if (-not (Get-Command k6 -ErrorAction SilentlyContinue)) { throw 'k6 was not found on PATH. Install k6 and retry.' }
if (-not (Test-Path -LiteralPath $TargetsPath)) {
  throw "Targets file not found: $TargetsPath. Copy benchmark/targets.example.json to benchmark/targets.json and enter the deployed URLs."
}

$targets = Get-Content -Raw -LiteralPath $TargetsPath | ConvertFrom-Json -AsHashtable
$expectedNames = @('fastapi', 'flask', 'express', 'node-http', 'cpp', 'rust')
foreach ($name in $expectedNames) {
  if (-not $targets.ContainsKey($name) -or [string]::IsNullOrWhiteSpace($targets[$name])) { throw "Missing service URL for '$name' in $TargetsPath." }
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$resultDir = Join-Path (Join-Path $repoRoot 'results') $timestamp
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
$records = [System.Collections.Generic.List[object]]::new()

function ConvertTo-MarkdownTable([object[]]$items) {
  $items = @($items)
  if ($items.Count -eq 0) { return '' }
  $propertyNames = $items[0].PSObject.Properties.Name
  $header = '| ' + ($propertyNames -join ' | ') + ' |'
  $separator = '| ' + (($propertyNames | ForEach-Object { '---' }) -join ' | ') + ' |'
  $rows = foreach ($item in $items) { '| ' + (($propertyNames | ForEach-Object { [string]$item.$_ }) -join ' | ') + ' |' }
  return (@($header, $separator) + @($rows)) -join "`n"
}

function Invoke-Smoke($name, $url) {
  $timer = [System.Diagnostics.Stopwatch]::StartNew()
  $health = Invoke-WebRequest -Uri "$url/health" -Method Get -TimeoutSec 180
  $timer.Stop()
  $healthBody = $health.Content | ConvertFrom-Json
  if ($health.StatusCode -ne 200 -or $healthBody.status -ne 'ok') { throw "$name health response did not match the API contract." }
  $body = @{ numbers = @(4, 1, 7, 2) } | ConvertTo-Json -Compress
  $actual = Invoke-RestMethod -Uri "$url/calculate" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 180
  if ($actual.count -ne 4 -or $actual.sum -ne 14 -or $actual.min -ne 1 -or $actual.max -ne 7 -or $actual.mean -ne 3.5 -or $actual.median -ne 3) {
    throw "$name calculation response did not match the API contract."
  }
  $invalidStatus = 0
  $invalidResponse = Invoke-WebRequest -Uri "$url/calculate" -Method Post -ContentType 'application/json' -Body '{"numbers":[]}' -TimeoutSec 30 -SkipHttpErrorCheck -StatusCodeVariable invalidStatus
  $invalidBody = $invalidResponse.Content | ConvertFrom-Json
  if ($invalidStatus -ne 400 -or $invalidBody.error.code -ne 'invalid_input') { throw "$name invalid-input response did not match the API contract." }
  $records.Add([pscustomobject]@{
    Service = $name; Scenario = 'first-request'; PayloadSize = '-'; VUs = 1; Duration = '-'; ColdFirstRequestMs = [math]::Round($timer.Elapsed.TotalMilliseconds, 2)
    RequestsPerSecond = '-'; AvgMs = '-'; P50Ms = '-'; P95Ms = '-'; P99Ms = '-'
    FailedRate = 0; CheckFailures = 0; SummaryFile = "First request: $([math]::Round($timer.Elapsed.TotalMilliseconds, 2)) ms"
  })
}

function Invoke-Load($name, $url, $scenario, $size, $vus, $duration, $runLabel) {
  $safeName = $runLabel -replace '[^a-zA-Z0-9_-]', '_'
  $summaryPath = Join-Path $resultDir "$safeName.json"
  $env:BASE_URL = $url
  $env:SCENARIO = $scenario
  $env:PAYLOAD_SIZE = [string]$size
  $env:VUS = [string]$vus
  $env:DURATION = $duration
  $env:SUMMARY_FILE = $summaryPath
  try { & k6 run $k6Script; if ($LASTEXITCODE -ne 0) { throw "k6 returned exit code $LASTEXITCODE for $runLabel." } }
  finally {
    Remove-Item Env:BASE_URL, Env:SCENARIO, Env:PAYLOAD_SIZE, Env:VUS, Env:DURATION, Env:SUMMARY_FILE -ErrorAction SilentlyContinue
  }
  $summary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json
  $metrics = $summary.metrics
  $records.Add([pscustomobject]@{
    Service = $name; Scenario = $scenario; PayloadSize = if ($scenario -eq 'calculate') { $size } else { '-' }; ColdFirstRequestMs = '-'
    VUs = $vus; Duration = $duration; RequestsPerSecond = [math]::Round($metrics.http_reqs.values.rate, 2)
    AvgMs = [math]::Round($metrics.http_req_duration.values.avg, 2)
    P50Ms = [math]::Round($metrics.http_req_duration.values.'med', 2)
    P95Ms = [math]::Round($metrics.http_req_duration.values.'p(95)', 2)
    P99Ms = [math]::Round($metrics.http_req_duration.values.'p(99)', 2)
    FailedRate = [math]::Round($metrics.http_req_failed.values.rate, 5)
    CheckFailures = $metrics.checks.values.fails
    SummaryFile = [IO.Path]::GetFileName($summaryPath)
  })
}

if ($Only -in @('all', 'smoke')) {
  Write-Host "Smoke checks (first request may include Render cold start)"
  foreach ($name in $expectedNames) { $null = Invoke-Smoke $name $targets[$name]; Write-Host "  $name PASS" }
}

if ($Only -in @('all', 'load')) {
  $scenarios = @(
    [pscustomobject]@{ Name = 'health'; Size = 100; VUs = 1; Duration = '30s' },
    [pscustomobject]@{ Name = 'calculate'; Size = 10; VUs = 1; Duration = '30s' },
    [pscustomobject]@{ Name = 'calculate'; Size = 100; VUs = 5; Duration = '30s' },
    [pscustomobject]@{ Name = 'calculate'; Size = 1000; VUs = 10; Duration = '30s' }
  )
  for ($round = 1; $round -le $Repetitions; $round++) {
    $ordered = @($expectedNames | Select-Object -Skip (($round - 1) % $expectedNames.Count)) + @($expectedNames | Select-Object -First (($round - 1) % $expectedNames.Count))
    foreach ($scenario in $scenarios) {
      foreach ($name in $ordered) {
        $label = "r$round-$name-$($scenario.Name)-n$($scenario.Size)-v$($scenario.VUs)"
        Write-Host "Running $label"
        Invoke-Load $name $targets[$name] $scenario.Name $scenario.Size $scenario.VUs $scenario.Duration $label
      }
    }
  }
}

if ($records.Count -gt 0) {
  $records | Export-Csv -NoTypeInformation -LiteralPath (Join-Path $resultDir 'comparison.csv')
  $columns = @('Service', 'Scenario', 'PayloadSize', 'VUs', 'ColdFirstRequestMs', 'RequestsPerSecond', 'AvgMs', 'P50Ms', 'P95Ms', 'P99Ms', 'FailedRate', 'CheckFailures')
  $table = ConvertTo-MarkdownTable -items @($records | Select-Object $columns)
  $header = @('# Backend benchmark results', '', "Run: $timestamp", '', 'Latency is measured from the benchmark machine and includes network and Render overhead.', '', $table, '') -join "`n"
  Set-Content -LiteralPath (Join-Path $resultDir 'report.md') -Value $header -Encoding utf8
  $records | Format-Table -AutoSize
  Write-Host "Saved report to $resultDir"
}

