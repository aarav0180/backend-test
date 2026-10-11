const express = require('express');

const app = express();
const port = Number(process.env.PORT || 8000);
const ERROR_MESSAGE = 'numbers must be a non-empty array of at most 10000 integers between -1000000000 and 1000000000.';
app.disable('x-powered-by');
app.use(express.json({ limit: '256kb', strict: true }));

app.get('/health', (_req, res) => res.status(200).json({ status: 'ok' }));

app.post('/calculate', (req, res) => {
  const values = req.body && !Array.isArray(req.body) ? req.body.numbers : undefined;
  if (!Array.isArray(values) || values.length < 1 || values.length > 10000 ||
      values.some((value) => !Number.isSafeInteger(value) || Math.abs(value) > 1_000_000_000)) {
    return res.status(400).json({ error: { code: 'invalid_input', message: ERROR_MESSAGE } });
  }

  const ordered = [...values].sort((a, b) => a - b);
  const middle = Math.floor(ordered.length / 2);
  const median = ordered.length % 2
    ? ordered[middle]
    : ordered[middle - 1] / 2 + ordered[middle] / 2;
  const sum = values.reduce((total, value) => total + value, 0);
  return res.status(200).json({
    count: values.length,
    sum,
    min: ordered[0],
    max: ordered[ordered.length - 1],
    mean: sum / values.length,
    median,
  });
});

app.use((error, _req, res, _next) => {
  if (error instanceof SyntaxError || error.type === 'entity.parse.failed') {
    return res.status(400).json({ error: { code: 'invalid_json', message: 'Request body must be valid JSON.' } });
  }
  return res.status(500).json({ error: { code: 'internal_error', message: 'An internal error occurred.' } });
});

app.listen(port, '0.0.0.0');
