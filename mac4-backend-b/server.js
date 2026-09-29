// Backend B — Task C
// Identical to Backend A except for BACKEND_ID and PORT — this is intentional.
// Two independent, interchangeable instances is exactly what a load-balanced pool is.

const http = require('http');
const crypto = require('crypto');

const BACKEND_ID = 'B';
const PORT = 3002;

const CACHE_PAYLOAD = JSON.stringify({
  backend: BACKEND_ID,
  message: 'This response is cacheable for 60 seconds.',
});
const ETAG = '"' + crypto.createHash('sha1').update(CACHE_PAYLOAD).digest('hex') + '"';

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  console.log(`[Backend ${BACKEND_ID}] ${req.method} ${url.pathname}`);

  res.setHeader('X-Backend', BACKEND_ID);

  if (url.pathname === '/' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      message: `Backend ${BACKEND_ID} is running`,
      backend: BACKEND_ID,
      timestamp: new Date().toISOString(),
    }));
    return;
  }

  if (url.pathname === '/api/status' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ backend: BACKEND_ID, status: 'ok' }));
    return;
  }

  if (url.pathname === '/api/data' && req.method === 'GET') {
    if (req.headers['if-none-match'] === ETAG) {
      res.writeHead(304, {
        'Cache-Control': 'max-age=60',
        'ETag': ETAG,
      });
      res.end();
      return;
    }

    res.writeHead(200, {
      'Content-Type': 'application/json',
      'Cache-Control': 'max-age=60',
      'ETag': ETAG,
    });
    res.end(CACHE_PAYLOAD);
    return;
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'not found', backend: BACKEND_ID }));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Backend ${BACKEND_ID} listening on 0.0.0.0:${PORT}`);
});
