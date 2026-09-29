# Mac 4 — Backend Server B + Test Client (Task C)

You have two jobs: run Backend B (identical role to Backend A on Mac 3), and act as one of
the team's test client machines (the other is Mac 1).

## 1. Install Node.js

```bash
brew install node
```

## 2. Run the server

```bash
cd mac4-backend-b
node server.js
```

You should see: `Backend B listening on 0.0.0.0:3002`. Leave this terminal open.

## 3. Test it locally first

```bash
curl -s http://localhost:3002/ | jq
curl -s http://localhost:3002/api/status
curl -sI http://localhost:3002/api/status   # check the X-Backend: B header
```

## 4. Test it from another machine on the LAN

```bash
curl http://<MAC4_IP>:3002/api/status
```

Same troubleshooting as Backend A if this fails — check firewall, check it's bound to
`0.0.0.0` not `127.0.0.1`.

## 5. Give Mac 2 your IP

Tell Person B (Mac 2 / nginx) your IP and confirm port 3002.

## Endpoints

Same shape as Backend A, just `"backend": "B"` everywhere:

| Endpoint | Returns |
|---|---|
| `GET /` | JSON confirming the service is up |
| `GET /api/status` | `{ "backend": "B", "status": "ok" }`, header `X-Backend: B` |
| `GET /api/data` | Cacheable response, same caching behavior as Backend A |

## Your other job: test client

Once Mac 1 (DNS) and Mac 2 (edge/TLS) are up, you (and Mac 1) are the machines used to prove
the whole system works end-to-end. Point this machine's DNS at Mac 1
(`mac1-dns/README.md` step 5), install Mac 2's CA/cert into this machine's trust store
(`mac2-edge/README.md`), then run the shared test scripts in `../scripts/` from here:

```bash
cd ../scripts
./test-dns.sh
./test-lb.sh
./test-cache.sh
```

## What NOT to do

Same as Backend A — keep the app minimal. The grading is on the network configuration.
