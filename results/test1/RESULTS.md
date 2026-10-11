# Test 1 results: 10,000-number stress run

- **Run date:** 2026-10-12 (local timestamps in source files)
- **Tool:** k6 v2.2.0, run from Windows PowerShell against the six public Render services.
- **Endpoint/workload:** `POST /calculate`, 10,000 integers per JSON request.
- **Stages:** constant 25, 50, 100, 200, 400, then 800 VUs, 30 seconds per stage plus up to 5 seconds graceful stop; stages only appear below if they actually ran.
- **Escalation:** historical run stopped a service after its first failed request or failed check. The C++/Rust/other partial ladders therefore are not directly comparable at later stages. Test 1 did not reach 800 VUs.

The table lists observed requests, failed HTTP requests, failed response checks, achieved RPS, and P95 request latency. P95 is in milliseconds. Each request has two checks, so one failed request can contribute two failed checks.

| Service | VUs | Requests | Failed requests | Failed checks | RPS | P95 (ms) |
|---|---:|---:|---:|---:|---:|---:|
| FastAPI | 25 | 142 | 0 | 0 | 4.06 | 17,964.10 |
| FastAPI | 50 | 307 | 0 | 0 | 8.77 | 14,361.66 |
| FastAPI | 100 | 647 | 0 | 0 | 18.48 | 15,743.43 |
| FastAPI | 200 | 799 | 0 | 0 | 22.82 | 19,880.19 |
| FastAPI | 400 | 1,869 | 812 | 1,624 | 53.37 | 18,013.84 |
| Flask | 25 | 158 | 0 | 0 | 4.51 | 13,154.01 |
| Flask | 50 | 300 | 1 | 2 | 8.57 | 15,885.32 |
| Express | 25 | 156 | 0 | 0 | 4.46 | 12,031.46 |
| Express | 50 | 279 | 0 | 0 | 7.97 | 18,118.91 |
| Express | 100 | 625 | 0 | 0 | 17.86 | 16,128.64 |
| Express | 200 | 929 | 1 | 2 | 26.54 | 18,837.68 |
| Node HTTP | 25 | 169 | 0 | 0 | 4.83 | 15,186.45 |
| Node HTTP | 50 | 264 | 0 | 0 | 7.54 | 18,260.20 |
| Node HTTP | 100 | 662 | 0 | 0 | 18.91 | 12,645.78 |
| Node HTTP | 200 | 786 | 0 | 0 | 22.45 | 20,937.03 |
| Node HTTP | 400 | 1,878 | 933 | 1,866 | 53.64 | 16,670.21 |
| C++ | 25 | 168 | 0 | 0 | 4.80 | 14,462.52 |
| C++ | 50 | 267 | 11 | 22 | 7.63 | 13,626.01 |
| Rust | 25 | 114 | 2 | 4 | 3.26 | 14,581.23 |

## Reading Test 1

FastAPI and Node HTTP reached 400 VUs and then had high failure counts. Express first failed at 200 VUs; Flask, C++, and Rust stopped earlier under the run's stop-on-first-failure rule. This is an exploratory stress result, not proof that one language or framework is generally faster. The workload included a large body, Render and network overhead, no warm-up, and sequential service ordering. See [`README.md`](README.md) for the complete procedure and [`run-test1.ps1`](run-test1.ps1) for a replay runner.
