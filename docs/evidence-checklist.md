# Task G + Section 9 — Evidence Checklist

The evaluator should be able to find any piece of evidence within 30 seconds. Keep this
folder structure and don't dump everything loose into one folder.

## Folder map (already created in `evidence/`)

- `evidence/dns/` — `dig`/`nslookup` output (screenshot or `.txt` from `dig ... > file.txt`)
  showing `app.teamX.test` and `api.teamX.test` resolving to Mac 2's IP.
- `evidence/tcp-tls-handshake/` — Wireshark `.pcapng` capture(s) + annotated screenshots of
  the SYN/SYN-ACK/ACK and ClientHello/ServerHello/Certificate/Finished sequence. See
  `docs/protocol-flow.md` for exact filters to use.
- `evidence/http-headers/` — `curl -v` and `curl -I` output showing request/response headers,
  including `X-Backend` and `Cache-Control`.
- `evidence/caching/` — `curl -I` twice + a 304 conditional request (see
  `scripts/test-cache.sh`).
- `evidence/load-balancing/` — repeated `curl` output showing `X-Backend: A` and
  `X-Backend: B` alternating (see `scripts/test-lb.sh`).
- `evidence/failure-demos/` — one screenshot + short explanation per scenario in
  `docs/failure-demos.md` (5 scenarios total).

## Phase 1 checklist (map to the Task G table in the spec)

- [ ] DNS query/response for `app.teamX.test` captured and saved
- [ ] TCP three-way handshake captured, source/destination ports labeled
- [ ] TLS handshake captured: ClientHello, ServerHello, Certificate, Finished
- [ ] `curl -v` output showing request + response headers, no `-k` flag used
- [ ] Screenshot/explanation of why HTTP payload is encrypted in the Wireshark capture
  (`Application Data` records, not readable HTTP text)
- [ ] Repeated requests showing `X-Backend: A` / `X-Backend: B` alternating
- [ ] Ephemeral client port vs well-known server port identified for both DNS (53/UDP) and
  HTTPS (443 or 8443/TCP)
- [ ] All 5 failure-demo scenarios from `docs/failure-demos.md` documented

## Other Phase 1 deliverables (Section 9)

- [ ] **Architecture Document** — `docs/topology.md` (topology + IP table) +
  `docs/protocol-flow.md` (request-flow/protocol-layer diagram), filled in with real IPs
- [ ] **Configuration Bundle** — `mac1-dns/dnsmasq.conf` (your actual working copy, not just
  the template), `mac2-edge/nginx.conf` (actual working copy), TLS cert setup notes, backend
  launch instructions — all already in this repo, just make sure your real configs (with real
  IPs, not placeholders) are committed
- [ ] **Backend Source Code** — `mac3-backend-a/server.js`, `mac4-backend-b/server.js` — this
  repo, hosted on GitHub, satisfies this directly
- [ ] **Evidence Folder** — the `evidence/` tree above

## How to capture Wireshark evidence (quick guide)

1. Install Wireshark: `brew install --cask wireshark`
2. Open Wireshark on the **client** machine, select your active interface (`en0`), start
   capture.
3. Run `dig app.teamX.test` and then `curl -v https://app.teamX.test/api/status` in a
   terminal.
4. Stop the capture in Wireshark.
5. Apply filter `dns or tls or (tcp.flags.syn==1)` to narrow the view, screenshot the DNS and
   handshake packets.
6. Save the whole capture: File → Save As → `evidence/tcp-tls-handshake/phase1-capture.pcapng`

If your traffic doesn't show up on `en0`, check you selected the right interface (Wi-Fi vs
loopback) — Wireshark lists all interfaces with live packet counts, pick the one that's
actually moving.
