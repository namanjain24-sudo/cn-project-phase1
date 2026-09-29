# Mac 3 — Backend Server A (Task C)

You run one of the two interchangeable REST API instances that Mac 2 load-balances across.

## 1. Install Node.js

```bash
brew install node
```

## 2. Run the server

```bash
cd mac3-backend-a
node server.js
```

You should see: `Backend A listening on 0.0.0.0:3001`. Leave this terminal open — this is
your running service. Every request that hits it will print a log line, which is useful
during the live load-balancing demo.

## 3. Test it locally first

```bash
curl -s http://localhost:3001/ | jq
curl -s http://localhost:3001/api/status
curl -sI http://localhost:3001/api/status   # check the X-Backend: A header
```

## 4. Test it from another machine on the LAN

From any other Mac (once you know Mac 3's IP from `docs/topology.md`):
```bash
curl http://<MAC3_IP>:3001/api/status
```

If this fails but `localhost` worked on Mac 3 itself, the server isn't actually reachable
from the LAN — check `server.js` is bound to `0.0.0.0` (it is, by default, in this repo —
don't change it to `127.0.0.1` or `localhost`), and check macOS Firewall isn't blocking
incoming connections to `node` (System Settings → Network → Firewall → Options, allow
incoming for `node` if prompted).

## 5. Give Mac 2 your IP

Tell Person B (Mac 2 / nginx) your IP address and confirm port 3001 — they need it for the
upstream config in `mac2-edge/nginx.conf`.

## Endpoints

| Endpoint | Returns |
|---|---|
| `GET /` | JSON confirming the service is up |
| `GET /api/status` | `{ "backend": "A", "status": "ok" }`, header `X-Backend: A` |
| `GET /api/data` | Cacheable response — `Cache-Control: max-age=60`, `ETag`, supports `If-None-Match` → `304` (Task F) |

## What NOT to do

Don't add a database, don't add npm dependencies, don't add auth. The grading is about the
network path (DNS → TLS → LB → backend), not the app's features. Keep this file exactly as
simple as it is unless your team specifically wants to extend it.
