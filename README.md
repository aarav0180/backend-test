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
