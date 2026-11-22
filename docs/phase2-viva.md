# Individual Viva Prep — Phase 2 (10 marks per person)

The spec is explicit: *"every team member should be able to explain any part of
the project, not just the part they personally configured."* So read all of it,
not only your own section. Answers must come from understanding, not notes.

---

## Part 1 — The ten questions everyone will be asked

**1. Walk me through one request, end to end.**
> The client asks our DNS server on Mac 1 for `app.cn_team.test`. That query
> leaves on a random high-numbered ephemeral port and goes to UDP port 53 on
> Mac 1. dnsmasq answers with Mac 2's IP. DNS has now finished — it has only
> translated a name into an address, it has opened nothing. The client's OS then
> opens a TCP connection from another ephemeral port to port 443 on Mac 2:
> SYN, SYN-ACK, ACK. On top of that connection, TLS: ClientHello, ServerHello,
> Certificate, key exchange, Finished — after which everything is encrypted.
> Only then does the HTTP request go out, inside the tunnel. nginx terminates
> TLS, picks Backend A or B round-robin, and opens a **separate, plain-HTTP TCP
> connection** to that backend on 3001 or 3002. The backend's JSON comes back,
> nginx relays it to the client over the original encrypted connection.

**2. Why can't you read the HTTP headers in Wireshark?**
> Because TLS encrypted them. We can see the TCP metadata — ports, sequence
> numbers, flags — and we can see TLS record types like `Application Data`, but
> the payload is ciphertext. That is TLS doing its job. The handshake itself is
> partly visible because it happens before the keys exist; the SNI in ClientHello
> is in plaintext, which is how nginx knows which `server_name` to answer as.

**3. Why does the client never need to know the backend IPs?**
> Because the edge is the single entry point and hides the backend topology.
> The client only ever resolves and connects to one name. We can add, remove or
> move backends without any client knowing. That is exactly what a cloud load
> balancer or API gateway does.

**4. What is the difference between DNS resolution and the connection?**
> DNS is a directory lookup, nothing more. It will confidently return a wrong
> answer if we configure a wrong answer — we demonstrated that in Phase 1 by
> pointing the record at Mac 3, where resolution succeeded and the connection
> was then refused. Resolution succeeding tells you nothing about whether the
> service is up.

**5. DNS failure vs application failure — how do they look different?**
> DNS failure: nothing resolves, you get NXDOMAIN or a timeout, you never reach
> any server. Application failure: resolution works, TCP works, TLS works, and a
> perfectly healthy edge returns 502 because the thing behind it is dead. We can show both.

**6. Refused versus timed out — what does each tell you?**
> Refused means the host is alive and sent back a TCP RST: nothing is listening
> on that port. Timed out means our packets are vanishing — a firewall dropping
> them, or the host is off or asleep. We rely on this distinction in Extension C,
> where `block drop` deliberately produces timeouts.

**7. Which component is still a single point of failure?**
> The edge, nginx on Mac 2. Everything funnels through it. DNS is now redundant
> and the backends are redundant, but the edge is not. To fix it you would
> publish several edges under the same name, or use a floating IP a standby
> claims. Extension E is the manual DNS version of that.

**8. Why didn't TLS break when you moved the edge to Mac 4?**
> Because the certificate is issued to the **name** `app.cn_team.test`, not to a
> machine or an IP. Both edges present the same certificate and the client is
> validating the name it asked for. Nothing about the certificate is tied to
> where the service runs.

**9. Why is this `.test` and not `.local`?**
> `.test` is reserved by the IETF for exactly this: private/testing names that
> will never collide with a real public domain. `.local` is claimed by mDNS /
> Bonjour on macOS and would be intercepted before our resolver ever saw it.
> We proved it is genuinely private by querying 8.8.8.8 and getting NXDOMAIN.

**10. What changed between Phase 1 and Phase 2?**
> Backup DNS on Mac 3; a 30-second TTL where Phase 1 served TTL 0; real health
> detection and short proxy timeouts on nginx; firewall isolation so only the
> edge can reach the backends; a standby edge on Mac 4 we can cut over to via
> DNS; and a scripted layered diagnosis. Plus two Phase 1 defects fixed — the
> caching demo now works through the load balancer, and the load-balancing
> script no longer dies silently on a failed request.

---

## Part 2 — Your own area (know this cold)

### Naman — DNS (Mac 1)
- What `address=/app.cn_team.test/<ip>` does, and why `listen-address` must
  include the LAN IP and not just `127.0.0.1`.
- Why `local-ttl` matters and why Phase 1's TTL of 0 made the Extension B demo
  impossible.
- Why `dig` does not show a TTL counting down (it queries authoritatively and
  bypasses every cache; TTLs only count down inside caches — on macOS,
  mDNSResponder).
- `server=8.8.8.8` is a *forwarder* for everything that isn't ours, so clients
  using our resolver still reach the normal internet.
- How a DNS-based cutover works and why TTL bounds how fast it can be.

### Harsha — Edge / TLS / Load balancing (Mac 2)
- The five TLS handshake steps and what each accomplishes.
- TLS termination: the backends never see TLS; the edge re-originates plain HTTP
  to them over a separate TCP connection.
- `upstream` + default round-robin; what `least_conn` would change.
- `max_fails` / `fail_timeout` — how nginx decides a backend is dead and for how
  long it stays ejected.
- `proxy_connect_timeout` vs `proxy_read_timeout`: connect covers the TCP
  handshake (machine off/asleep/filtered), read covers waiting for a response
  from a backend that accepted the connection (hung process). Phase 1 used the
  60s defaults for both — that is why a sleeping laptop hung the demo.
- Why the edge is the remaining SPOF.

### Hemanth — Backend A + backup DNS + firewall (Mac 3)
- Why the backend binds `0.0.0.0` and not `127.0.0.1`.
- `Cache-Control: max-age=60` vs `ETag` vs `If-None-Match` → 304, and the three
  distinct cases: fresh cache hit (no request at all), conditional request (304,
  no body), full request (200 + body).
- **Why the 304 demo is run against one backend directly** — the ETag is a hash
  of the body, and `/api/data`'s body contains the backend id, so Backend A and
  Backend B produce different ETags. Through round-robin, a conditional request
  can land on the other backend, whose ETag does not match, so it correctly
  returns 200 rather than 304. This is caching working as specified, not a bug.
- Running a second authoritative resolver and why its records must match Mac 1's
  exactly.
- pf rule ordering: `quick` = first match wins, so `pass` must precede `block`.

### Akshay — Backend B + standby edge + test client (Mac 4)
- Everything in Hemanth's backend list (the two backends are identical by design
  — that is what makes them an interchangeable pool).
- The Phase 1 sleeping-laptop incident, what it revealed about nginx's default
  failover, and how Extension D fixes it. **This is your strongest story — you
  already explained it well in the Phase 1 video.**
- Running a standby edge alongside a backend on the same machine (two ports, two
  roles) and why that is acceptable here but not in production.
- Being a real test client: resolving by name, trusting the CA, no `-k`.

---

## Part 3 — Questions designed to catch you out

**"Your `curl` used `--resolve`. Is your DNS actually working?"**
> `--resolve` was a Phase 1 testing shortcut that bypasses DNS to test the edge
> in isolation. For the demo we resolve genuinely — the client's resolver is set
> to Mac 1 and Mac 3, and `curl -v` prints `Host app.cn_team.test:443 was
> resolved` with no override. We can show both and explain why each exists.

**"Why did `curl -I` return 404?"**
> `-I` sends a HEAD request, and our minimal backend only special-cases GET, so
> HEAD falls through to the 404 handler. The TLS handshake and routing were
> completely successful — a 404 is an *application* response, which itself proves
> every layer below it worked. `curl -v` with a GET returns 200.

**"Round-robin gave you two A's in a row. Is it broken?"**
> No. Browsers and keep-alive connections reuse one TCP connection, which stays
> pinned to one upstream, and `max_fails` ejection also skews the sequence. With
> fresh connections over a run of requests the distribution is even — our run of
> 8 gave exactly 4 and 4.

**"Is a self-signed CA secure?"**
> Not for the public internet — it is only trusted because we manually installed
> it in each machine's trust store. A public CA is trusted because browsers ship
> its root. The cryptography is identical; what differs is who vouches for the
> identity. In cloud terms, ACM or Let's Encrypt replaces our manual step.

**"Your ping times were over 2 seconds. Is your network broken?"**
> We are on a shared mobile hotspot rather than a router, which is high-latency
> and reassigns IPs on reconnect. It does not affect correctness — 0% packet
> loss across all six machine pairs — but it does affect timing, which is why we
> report failover latency relative to a baseline rather than as absolute numbers.

**"Show me the DNS packets in your Wireshark capture."**
> Be honest: the saved Phase 1 capture was filtered `ip.addr==<mac2> and
> tcp.port==443`, which excludes DNS because DNS is UDP/53 to Mac 1. Either
> switch the filter to `dns` on the same capture file, or take a fresh capture
> with `dns or tcp.port == 443`. **Do this before the demo so you are not
> fumbling with filters live.**

**"What would you do differently?"**
> Put the machines on a stable router rather than a hotspot; add active health
> checks instead of relying on passive `max_fails`; make the edge redundant;
> and keep the backends' cacheable payload identical from the start, since
> making the ETag depend on which server answered defeated the point of caching.
