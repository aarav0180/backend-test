# Test 1: 10,000-number calculation stress run

## Purpose and scope

This is the first high-load comparison of the six independently deployed Render services. It measures the full HTTP request path from k6 running on a Windows PC to each public Render URL, not framework execution in isolation.

The benchmark called `POST /calculate`. Each request sent one JSON body containing an array of 10,000 integers. All implementations ran the same calculation and returned the same response contract. The k6 checks required HTTP 200 and a response `count` of 10,000.

## Environment and procedure

- Host: Render Free web services in the Singapore region, one service tested at a time.
- Load generator: Windows PC, k6 v2.2.0.
- Scenario: k6 `constant-vus`, fixed VU stages of 25, 50, 100, 200, and 400 where reached.
- Each stage ran for 30 seconds, followed by up to 5 seconds of graceful stop.
- Request body: 10,000 integers, generated deterministically by the included `api.js` script.
- Service order in this run: FastAPI, Flask, Express, Node HTTP, C++, Rust.
- Escalation rule used for this run: stop testing a service at the first stage with a failed request or failed check. Consequently, not every service reached every VU level, and this run did not test 800 VUs.
- No warm-up or randomized/rotated service order was applied. Each service was tested sequentially; this makes the run useful as an exploratory stress test, but less controlled than a repeated, randomized comparison.

To replay an individual stage, use k6 from the repository root. Replace the URL with the appropriate deployed service URL and choose the desired VU count:

```powershell
k6 run `
  -e "BASE_URL=https://backend-bench-fastapi.onrender.com" `
  -e "SCENARIO=calculate" `
  -e "PAYLOAD_SIZE=10000" `
  -e "VUS=25" `
  -e "DURATION=30s" `
  -e "SUMMARY_FILE=results/test1/replay-fastapi-v25.json" `
  benchmark/k6/api.js
```

The exact k6 script used is saved as [`api.js`](api.js). The JSON files in this folder are the raw k6 summaries captured for the run; their filenames identify service and VU stage.

## Results

`Failed requests` is the number of failed HTTP requests. `Failed checks` counts individual checks; each request has two checks, so a failed request can contribute two failed checks. P95 is milliseconds. RPS is the achieved request rate, not a configured rate.

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

## Reading these results

The first observed failures occurred at 50 VUs for Flask and C++, 25 VUs for Rust, and 200 VUs for Express. FastAPI and bare Node HTTP passed through 200 VUs and then had substantial failures at 400 VUs. These are observed outcomes of this run, not general rankings of the languages or frameworks.

The p95 values are roughly 12–21 seconds, which indicates the services were already queueing heavily under these large requests. This workload combines network/TLS time, JSON parsing, sorting/calculation, and response encoding. A small difference in this one run cannot isolate framework speed. Free-tier host variability, sequential run order, the client machine/network, warm/cold service state, and only one short stage per load level all affect results. Rust and C++ reached fewer requests before failure, so their measurements are especially noisy.

This run used a stop-on-first-failure rule and did not implement a 30% failure threshold. A later test should state that threshold explicitly, continue through intermediate failures until the failure ratio reaches 30%, and repeat stages in a rotated service order. Compare only stages each service actually completed, and record the precise threshold rule in that run's README.
