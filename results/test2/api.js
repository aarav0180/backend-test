import http from 'k6/http';
import { check } from 'k6';

const baseUrl = (__ENV.BASE_URL || '').replace(/\/$/, '');
const scenario = __ENV.SCENARIO || 'health';
const size = Number(__ENV.PAYLOAD_SIZE || 100);
const duration = __ENV.DURATION || '30s';
const vus = Number(__ENV.VUS || 1);
const numbers = Array.from({ length: size }, (_, i) => ((i * 37) % 2001) - 1000);

export const options = {
  scenarios: {
    comparison: {
      executor: 'constant-vus',
      vus,
      duration,
      gracefulStop: '5s',
    },
  },
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

export default function () {
  if (!baseUrl) throw new Error('Set BASE_URL to a deployed service URL.');

  if (scenario === 'health') {
    const response = http.get(`${baseUrl}/health`, { tags: { endpoint: 'health' } });
    check(response, {
      'health status is 200': (r) => r.status === 200,
      'health body matches contract': (r) => {
        try { return JSON.parse(r.body).status === 'ok'; } catch { return false; }
      },
    });
  } else {
    const response = http.post(`${baseUrl}/calculate`, JSON.stringify({ numbers }), {
      headers: { 'Content-Type': 'application/json' },
      tags: { endpoint: 'calculate', payload_size: String(size) },
    });
    check(response, {
      'calculate status is 200': (r) => r.status === 200,
      'calculate response has expected count': (r) => {
        try { return JSON.parse(r.body).count === size; } catch { return false; }
      },
    });
  }
}

export function handleSummary(data) {
  const name = __ENV.SUMMARY_FILE || 'summary.json';
  return { stdout: textSummary(data), [name]: JSON.stringify(data, null, 2) };
}

function textSummary(data) {
  const metrics = data.metrics || {};
  const durationMetric = metrics.http_req_duration || {};
  const failedMetric = metrics.http_req_failed || {};
  const reqMetric = metrics.http_reqs || {};
  const checkMetric = metrics.checks || {};
  const ms = (value) => Number.isFinite(value) ? `${value.toFixed(2)} ms` : 'n/a';
  return [
    `scenario: ${scenario}${scenario === 'calculate' ? ` (${size} numbers)` : ''}`,
    `requests/sec: ${reqMetric.values?.rate ?? 'n/a'}`,
    `latency: avg ${ms(durationMetric.values?.avg)}, p50 ${ms(durationMetric.values?.med)}, p95 ${ms(durationMetric.values?.['p(95)'])}, p99 ${ms(durationMetric.values?.['p(99)'])}`,
    `failed requests: ${Number.isFinite(failedMetric.values?.rate) ? `${(failedMetric.values.rate * 100).toFixed(2)}%` : 'n/a'}`,
    `checks passed: ${checkMetric.values?.passes ?? 0}; failed: ${checkMetric.values?.fails ?? 0}`,
    '',
  ].join('\n');
}
