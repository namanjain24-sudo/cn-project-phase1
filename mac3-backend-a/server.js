// Backend A — Task C
// Deliberately minimal: the network config is what's being graded, not this code.
// Zero external dependencies — just Node's built-in http module.

const http = require('http');
const crypto = require('crypto');

const BACKEND_ID = 'A';
const PORT = 3001;

// Fixed payload for the caching demo (Task F) so the ETag is stable between requests
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

  // Task F — HTTP caching demonstration
  if (url.pathname === '/api/data' && req.method === 'GET') {
    // Conditional request support: client sends If-None-Match, we compare to our ETag
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

// Bind to 0.0.0.0, NOT 127.0.0.1 — must be LAN-accessible so Mac 2 (nginx) can reach it.
server.listen(PORT, '0.0.0.0', () => {
  console.log(`Backend ${BACKEND_ID} listening on 0.0.0.0:${PORT}`);
});
