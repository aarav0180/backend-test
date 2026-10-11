const http = require('node:http');

const port = Number(process.env.PORT || 8000);
const ERROR_MESSAGE = 'numbers must be a non-empty array of at most 10000 integers between -1000000000 and 1000000000.';

function send(res, status, body) {
  const output = JSON.stringify(body);
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'content-length': Buffer.byteLength(output) });
  res.end(output);
}

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') return send(res, 200, { status: 'ok' });
  if (req.method !== 'POST' || req.url !== '/calculate') {
    return send(res, 404, { error: { code: 'not_found', message: 'Route not found.' } });
  }

  let body = '';
  req.on('data', (chunk) => {
    body += chunk;
    if (Buffer.byteLength(body) > 256 * 1024) {
      send(res, 413, { error: { code: 'invalid_input', message: ERROR_MESSAGE } });
      req.destroy();
    }
  });
  req.on('end', () => {
    if (res.writableEnded) return;
    let parsed;
    try { parsed = JSON.parse(body); } catch {
      return send(res, 400, { error: { code: 'invalid_json', message: 'Request body must be valid JSON.' } });
    }
    const values = parsed && !Array.isArray(parsed) && typeof parsed === 'object' ? parsed.numbers : undefined;
    if (!Array.isArray(values) || values.length < 1 || values.length > 10000 ||
        values.some((value) => !Number.isSafeInteger(value) || Math.abs(value) > 1_000_000_000)) {
      return send(res, 400, { error: { code: 'invalid_input', message: ERROR_MESSAGE } });
    }
    const ordered = [...values].sort((a, b) => a - b);
    const middle = Math.floor(ordered.length / 2);
    const median = ordered.length % 2 ? ordered[middle] : ordered[middle - 1] / 2 + ordered[middle] / 2;
    const sum = values.reduce((total, value) => total + value, 0);
    return send(res, 200, { count: values.length, sum, min: ordered[0], max: ordered[ordered.length - 1], mean: sum / values.length, median });
  });
});

server.listen(port, '0.0.0.0');
