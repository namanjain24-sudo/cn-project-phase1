# Protocol Flow & Viva Prep — Task G

This is the "tie it all together" document. Everyone on the team must be able to explain
every row of this from memory for the individual viva (10 marks, Phase 1) — not just the
person who configured that layer.

## OSI / TCP-IP layer mapping

| Protocol in this project | OSI Layer | TCP/IP Layer |
|---|---|---|
| DNS | Application | Application |
| HTTP | Application | Application |
| TLS | Presentation/Session (often taught as sitting between Transport and Application) | sits on top of Transport |
| TCP / UDP | Transport | Transport |
| IP | Network | Internet |
| Ethernet / Wi-Fi | Data Link + Physical | Link |

- DNS query itself typically goes over **UDP port 53** (falls back to TCP if the response is
  too large — not expected to happen here).
- HTTPS goes over **TCP port 443** (or 8443 if you used the fallback port).
- Backends listen on **TCP 3001 / 3002**, but clients never talk to those ports directly —
  only nginx (Mac 2) does. This is a key viva point: *why doesn't the client need to know the
  backend IPs or ports?* Because nginx is the single entry point and hides the backend
  topology — this is literally what a cloud load balancer / API gateway does.

## The full request, step by step

1. **DNS resolution** — client runs `dig app.teamX.test` (or the browser does this
   internally). The query leaves the client on a random high-numbered **ephemeral source
   port** (e.g. 54213), destined for **Mac 1, UDP port 53**. Mac 1's dnsmasq replies with
   Mac 2's IP address. *DNS only resolves a name to an IP — it does not open any connection.*
2. **TCP three-way handshake** — client's OS opens a TCP connection to `<Mac2 IP>:443`
   (another ephemeral source port, e.g. 54891, to Mac 2's well-known port 443):
   - Client → Mac2: **SYN**
   - Mac2 → Client: **SYN-ACK**
   - Client → Mac2: **ACK**
   No application data has been sent yet — this is pure transport-layer connection setup.
3. **TLS handshake** (runs on top of that TCP connection, before any HTTP bytes go out):
   - **ClientHello** — client proposes TLS version + cipher suites it supports.
   - **ServerHello** — Mac 2 (nginx) picks a cipher suite.
   - **Certificate** — Mac 2 sends its cert for `app.teamX.test`. The client checks it's
     signed by a CA it trusts (this is why we install the local CA / self-signed cert into
     every client's trust store — otherwise this step fails with a warning).
   - **Key Exchange** — both sides derive a shared symmetric session key.
   - **Finished** (both directions) — from here on, everything is encrypted.
4. **HTTP request/response** — now encrypted inside the TLS tunnel: `GET /api/status
   HTTP/1.1`, `Host: app.teamX.test`, etc. In Wireshark this shows up as `Application Data` —
   you can prove TCP/TLS worked, but you *cannot* read the HTTP headers in the packet capture
   because they're encrypted. **This is the point of TLS and is exactly what you should say
   when asked "why can't you see the HTTP text in Wireshark?"**
5. **Load balancing** — nginx picks Backend A or Backend B (round-robin) and proxies the
   request over a *separate* TCP connection to Mac 3 or Mac 4 on port 3001/3002. This is a
   second, independent TCP handshake, invisible to the original client.
6. **Response** — backend returns JSON with an `X-Backend: A` (or `B`) header, nginx relays
   it back to the client over the original encrypted connection.

## What to point at in Wireshark (Task G)

Filter suggestions while capturing on the client machine:

```
dns                          # the query + response
tcp.flags.syn==1             # the SYN and SYN-ACK packets (handshake start)
tcp.port == 443              # everything on the HTTPS connection
tls.handshake                # just the TLS handshake messages
tls.handshake.type == 1      # ClientHello specifically
tls.handshake.type == 2      # ServerHello
tls.handshake.type == 11     # Certificate
```

Record, for one full request cycle:
- The DNS query packet and its response (show the answer = Mac 2's IP).
- SYN → SYN-ACK → ACK, with source/destination ports labeled.
- ClientHello → ServerHello → Certificate → (Client Key Exchange /
  ChangeCipherSpec depending on TLS version) → Finished.
- The subsequent `Application Data` packets (point out these are encrypted — no visible
  HTTP text).
- Source port (client's ephemeral port, different every time) vs destination port (server's
  fixed well-known port: 53 for DNS, 443/8443 for HTTPS).

Save capture as a `.pcapng` file into `evidence/tcp-tls-handshake/` and also export a few
annotated screenshots — the evaluator wants to see it in 30 seconds, not scroll for it.

## Caching — the 3-way distinction (Task F)

Be ready to explain the difference between:
- **Fresh cache hit** — client has a cached response and `Cache-Control: max-age=60` hasn't
  expired yet → browser/client uses the local copy, **no request even reaches the server**.
- **Conditional request** — cache expired, client sends `If-None-Match: <etag>` → server
  compares, content unchanged → responds `304 Not Modified` with **no body**, saving
  bandwidth.
- **Full new request** — no valid cache, or content changed → server sends `200 OK` with the
  full body and a new ETag.

## Cloud analogies (for "Devices, Topologies, Cloud Concepts")

| Your local component | Cloud equivalent |
|---|---|
| Mac 1 (dnsmasq) | AWS Route 53 / managed DNS |
| Mac 2 (nginx, TLS termination, round-robin) | AWS ALB / GCP Load Balancer / CDN edge node |
| Mac 3 / Mac 4 (Node.js REST API) | EC2 instances / app server pool behind the LB |
| Self-signed cert + manual trust | ACM-issued cert, automatically trusted by browsers because a public CA signed it |
