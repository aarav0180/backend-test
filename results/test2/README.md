# Test 2: 5,000-number load test with 30% stop threshold

## Status

This is the prepared next test; it has **not** completed yet. Run `run-test2.ps1` from PowerShell in the repository. It reads deployed URLs from the local, Git-ignored `benchmark/targets.json`.

## Test plan

- Endpoint: `POST /calculate`.
- Payload: 5,000 integers generated deterministically by the included k6 script.
- Load levels: 25, 50, 100, 200, 400, and 800 constant virtual users (VUs); each stage runs for 30 seconds unless the stop rule is met first.
- Services run sequentially: FastAPI, Flask, Express, Node HTTP, C++, Rust. A service reaching the threshold does not stop testing the remaining services.
- Stop escalating one service only when at least 30% of that stage's HTTP requests fail: failed HTTP requests divided by all HTTP requests is greater than or equal to 0.30. Failures below 30% do not stop escalation. Failed response checks are recorded separately and do not count toward this threshold.
- k6 output streams to the terminal and is also saved in a `.log` file. Per-stage k6 JSON summaries, a CSV, and a result README are written to a timestamped folder.

This measures the complete hosted path: client network, TLS, Render routing and compute, queueing, JSON parsing, calculation, and response encoding. It is not a framework-only laboratory benchmark.

## Run on Windows PowerShell

From the repository root:

```powershell
.\results\test2\run-test2.ps1
```

Requirements: k6 installed and available as `k6` on PATH; `benchmark\targets.json` copied from `benchmark\targets.example.json`. The targets file is ignored by Git. Do not put access tokens, passwords, or other secrets in committed scripts or reports.

Windows PowerShell 5.1 can treat k6's native stderr warnings (for example, a transient `EOF`) as terminating errors when stopping on errors is enabled. The runner temporarily allows those messages through so k6 can finish the stage, save its summary, and let the 30% threshold logic decide whether to continue. If a stage ends before a summary is written, it is incomplete; rerun the test after updating the runner. Each rerun uses a new timestamped folder, so earlier partial output remains available locally.

The exact scripts are [`run-test2.ps1`](run-test2.ps1) and [`api.js`](api.js). The runner creates the actual result README and CSV after a completed run. Generated run folders are ignored by Git until reviewed and intentionally selected for archival.

## k6 terms

- **VU (virtual user):** a worker repeatedly executing the scenario. 800 VUs means up to 800 concurrent workers, not 800 requests per second.
- **RPS:** achieved HTTP requests per second, not the configured VU count.
- **Latency:** elapsed time for an HTTP request from k6's perspective. **p95** is the time at or below which 95% of observed requests completed; the slowest 5% took longer. It is not average latency or a failure percentage.
- **Failed request:** an HTTP request k6 marks failed because of a network/timeout error or unexpected status. The stop threshold is computed per stage from failed requests divided by total requests.
- **Failed check:** a response assertion failure, such as an incorrect status or JSON body. These are reported separately from the stop threshold.
- **Payload size:** number of integers in the JSON array, not the encoded body size in bytes.

## Results

Pending completion. The runner will write the measured table, raw JSON summaries, and logs in the timestamped result folder.
