# Backend framework comparison

Six implementations of the same small HTTP API, intended for deployment as separate Render web services and comparison with the shared k6 benchmark.

## Implementations

| Folder | Runtime | Server |
|---|---|---|
| `apps/fastapi` | Python | FastAPI + Uvicorn |
| `apps/flask` | Python | Flask + Waitress |
| `apps/express` | Node.js | Express |
| `apps/node-http` | Node.js | built-in `http` module |
| `apps/cpp` | C++ | Crow |
| `apps/rust` | Rust | Axum + Tokio |

All implementations follow [`contract/api-spec.yaml`](contract/api-spec.yaml). They expose `GET /health` and `POST /calculate`; the latter summarizes an array of integers with count, sum, minimum, maximum, mean, and median.

## Deploy to Render

Connect this GitHub repository to Render and create a Blueprint from `render.yaml`. It defines six independent web services, all with the `free` plan, the same region, and the same health check path. Native runtimes are used where Render provides them. The C++ service uses its Dockerfile. Render currently assigns each Free web service 0.1 CPU and 512 MB RAM, independently; the monorepo does not divide those resources between services.

Each service has its own `onrender.com` URL. Copy `benchmark/targets.example.json` to `benchmark/targets.json`, replace the example URLs with the deployed URLs, then run the PowerShell benchmark runner from the repository root:

```powershell
./benchmark/run-benchmarks.ps1
```

Requires PowerShell 7+ and k6. Use `-Only smoke` for request/response checks or `-Only load` to skip the smoke checks. Results are written beneath `results/<timestamp>/`, with a combined Markdown and CSV report plus the individual k6 JSON summaries.

## Fair comparison procedure

1. Deploy all six services in the same Render region and wait until each deploy succeeds.
2. Add the deployed base URLs to `benchmark/targets.json`.
3. Run the benchmark from the same computer and network each time.
4. To measure cold starts, leave each service idle for at least 15 minutes before the run. The runner records first-request latency separately; it includes a cold start only if Render actually spun that service down.
5. Compare the same scenario, payload size, virtual-user count, duration, and repetitions. The runner rotates service order between repetitions.

The benchmark measures the complete hosted request path, including network and Render behavior. It is useful for comparing these deployments on Render's Free plan, but it is not a framework-only laboratory benchmark. Render Free services can spin down after 15 idle minutes and share a monthly workspace allowance of 750 instance hours. Keep cold-start results separate from warm performance results.

## Understanding the k6 measurements

- **VU (virtual user):** one k6 worker repeatedly runs the scenario. `VUS=25` means up to 25 iterations can be in flight concurrently; it does not mean 25 requests per second. Each VU waits for its request to finish before starting its next iteration, so slow responses reduce the achieved request rate.
- **Request rate / RPS:** HTTP requests completed per second (`http_reqs` rate). It is an observed result, not a target or a configured limit.
- **Latency:** time for one HTTP request, measured by k6 from the load generator. It includes internet/network/TLS and Render processing, not just application code. The summary reports average, median (p50), p95, and p99.
- **Percentile (p95):** the 95th percentile means 95% of measured requests finished in that time or less, while the slowest 5% took longer. For example, p95 = 500 ms means 95 out of 100 requests completed in 500 ms or less. It is not the average and does not mean 95% of requests failed.
- **Failure rate:** share of HTTP requests k6 considers failed, such as network errors, timeouts, or unexpected HTTP statuses. The raw JSON stores this in `http_req_failed.values.rate`; multiply by 100 for percent. Failed checks are a separate count of assertion failures (for example, a wrong JSON response), and one request can fail more than one check.
- **Payload size:** for `/calculate`, the number of integers in the JSON array, not the number of bytes. Larger arrays take more bandwidth and require more parsing/calculation work.
- **Stage:** a fixed combination of payload size, VU count, and duration. Compare frameworks only at matching stages. A run that stops at the first failed stage has no result for later VU levels.

The scripts in [`results/test1`](results/test1/README.md) replay the original 10,000-number test. The planned 5,000-number test, which escalates through 800 VUs and stops a service once its HTTP request failure ratio reaches 30%, is documented in [`results/test2`](results/test2/README.md). Each test folder contains its PowerShell runner and k6 script reference; run-specific JSON, logs, and a generated result README are saved under a timestamped subfolder. Keep `benchmark/targets.json` local: it is ignored by Git so deployment URLs or future credentials are not accidentally committed.

## API contract

### `GET /health`

Returns HTTP 200 and `{"status":"ok"}`.

### `POST /calculate`

Request:

```json
{"numbers":[4, 1, 7, 2]}
```

Response:

```json
{"count":4,"sum":14,"min":1,"max":7,"mean":3.5,"median":3}
```

The `numbers` field must be a non-empty array of at most 10,000 integers. Each integer must be between -1,000,000,000 and 1,000,000,000 inclusive. Errors use `{"error":{"code":"...","message":"..."}}`; see the OpenAPI contract for exact status codes and messages.

## Local run

Each app folder has its own README with its local start command. Every server reads `PORT` (default 8000) and listens on `0.0.0.0` so the same app can run locally and on Render.
