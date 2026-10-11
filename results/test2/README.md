# Test 2: 5,000-number Render load test

## Purpose

Test 2 compares the six API implementations under the same JSON workload and increasing concurrency. It is a hosted-service stress test: measurements include the client machine and network, TLS, Render routing and compute, request queueing, JSON parsing, the calculation, and response serialization. It does not isolate language or framework performance alone.

The complete stage-by-stage result table is in [`RESULTS.md`](RESULTS.md). The raw summaries, console logs, generated CSV, and run-specific report are in [`20261012-005754`](20261012-005754/README.md).

## Services and deployment

Each API is a separate Render web service from this repository's `render.yaml`. The services use the same configured Free plan and Singapore region, with separate per-service instances. The benchmark ran against their public Render URLs from a Windows computer. Test 2 did not run all six services at the same instant; it finished all stages for one service before moving to the next.

The load generator used k6 v2.2.0. The six tested implementations were FastAPI, Flask, Express, bare Node HTTP, C++/Crow, and Rust/Axum. The local target file (`benchmark/targets.json`) supplied each base URL and is excluded from Git. It contains no credentials in this setup; do not place credentials or private tokens in target URLs.

## Request and workload

Every iteration sent one `POST /calculate` request with JSON shaped like `{"numbers":[...]}`. The `numbers` array had 5,000 integers, generated deterministically by the included k6 script using `((i * 37) % 2001) - 1000`. All six services used the same generated payload for each request. The API validates the input and returns count, sum, minimum, maximum, mean, and median.

The k6 script made two checks per response: HTTP status must be 200, and the response `count` must equal 5,000. The script did not set a request-rate limit or add think time between iterations.

## Load stages and stop rule

For each service, k6 used the `constant-vus` executor at 25, 50, 100, 200, 400, then 800 virtual users (VUs). Each stage ran for 30 seconds and allowed up to 5 seconds of graceful stop so in-flight iterations could finish. A VU repeatedly sent the next request after its previous iteration completed; VUs are concurrent workers, not requests per second.

After every stage, the PowerShell runner read the raw k6 summary and calculated:

`HTTP failure ratio = failed HTTP requests / total HTTP requests`

If that ratio was **at least 30%**, the runner stopped escalating that service and moved to the next service. If it was below 30%, even when some requests failed, the runner continued to the next VU level. Failed response checks were reported separately and did not activate this stop rule. The services were processed in this fixed order: FastAPI, Flask, Express, Node HTTP, C++, Rust.

The first attempt on this test was interrupted by Windows PowerShell treating a k6 stderr warning as a fatal error. That partial attempt is not included in the published run. The completed run used the corrected runner, which allows k6 to finish stages when it emits transient stderr warnings.

## What was saved

The completed run directory contains a JSON summary and a full terminal log for every stage that ran. It also contains a CSV and a generated README with the results. The persistent `RESULTS.md` at this folder's root gives a readable table across all six services. The runner and exact k6 scenario are [`run-test2.ps1`](run-test2.ps1) and [`api.js`](api.js).

## How to reproduce

From the repository root in Windows PowerShell, with k6 on `PATH` and a local `benchmark/targets.json` present:

```powershell
.\results\test2\run-test2.ps1
```

The script creates a new timestamped directory each time. Generated run folders are excluded from Git by default to prevent accidental publication; review output before explicitly including a new run in a commit. This completed run was explicitly selected for archival.

## Interpreting the measurements

- **Requests/RPS:** number of HTTP requests k6 completed and the achieved requests per second. RPS is an observed rate, not the VU setting.
- **Failed requests:** network errors, timeouts, or unexpected HTTP responses as counted by k6. The 30% stop condition uses this count divided by all HTTP requests in that same stage.
- **Failed checks:** assertion failures about the response. One request can fail both checks, so failed checks can be roughly twice the number of failed requests.
- **Average / p95 / p99 latency:** request duration in milliseconds. p95 is the point at or below which 95% of requests completed; the slowest 5% took longer. It is not the average and does not mean 95% failed.
- **Payload size:** 5,000 array elements, not 5,000 bytes.

## Limits

This was one sequential run with one 30-second measurement stage per VU level and no dedicated warm-up or rotated service order. Early requests may include service wake-up or connection setup. There can also be variation from the public network and Render's shared Free-tier host environment. A high p95 or a small number of failures in one stage should not be treated as a stable ranking. The results show what happened in this run; repeated runs with randomized service order and warm-up would be needed for a stronger comparison.
