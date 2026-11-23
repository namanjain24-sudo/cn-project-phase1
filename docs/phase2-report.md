# Phase 2 Final Report

**Project** Private Network Service Platform — `app.cn_team.test`
**Team** Naman (Mac 1, DNS) · Harsha Karthikeya (Mac 2, edge) · Hemanth (Mac 3, Backend A) · Akshay (Mac 4, Backend B)
**Phase 1** 30 September – 4 October 2026 **Phase 2** 22–23 November 2026

Machines as tested: Mac 1 `10.7.20.236` · Mac 2 `10.7.11.169` · Mac 3 `10.7.25.47` ·
Mac 4 `10.7.21.130`. Gateway `10.7.0.1`, mask `255.255.224.0`, one shared Wi-Fi segment.

---

## 1. What changed from Phase 1

Phase 2 extends the Phase 1 network. Nothing was rebuilt, and **the backend
application code is unchanged** — every change is network configuration.

| # | Change | File | Why it was needed |
|---|---|---|---|
| 1 | Second authoritative DNS resolver on Mac 3 | `backup-dns/dnsmasq-backup.conf` | Mac 1 was a single point of failure for every name lookup |
| 2 | `local-ttl=30` on both resolvers | `mac1-dns/dnsmasq-phase2.conf` | Phase 1 served TTL 0, so no client ever cached and TTL behaviour could not be shown |
| 3 | `max_fails=2 fail_timeout=10s` per upstream | `mac2-edge/nginx-phase2.conf` | nginx had no way to stop sending traffic to a failing backend |
| 4 | `proxy_connect_timeout 2s`, `proxy_read_timeout 3s`, bounded retries | `mac2-edge/nginx-phase2.conf` | nginx's defaults are 60s, so an unresponsive backend stalled every request |
| 5 | pf rules restricting ports 3001 and 3002 to the edge tier | `firewall/pf.anchors.cn-backend` | Any machine on the LAN could reach the backends directly and bypass the edge |
| 6 | Standby edge on Mac 4 with the same certificate | `standby-edge/nginx-standby.conf` | The edge could not be moved without reconfiguring clients |

One operational change supports all six: `config/ips.env` holds every IP in one
table and `scripts/set-ips.sh` regenerates every config from it. The shared
hotspot reassigns addresses on each reconnect, and a stale IP left in a single
file had already broken the setup twice.

---

## 2. Resilience tests and results

All results below were measured on the live four-machine network on 22 November 2026.
Raw output for each is in `evidence/phase2/`.

### 2.1 Extension A — backup DNS resolver

| Test | Result |
|---|---|
| Both resolvers queried directly | Identical answer from each: `app.cn_team.test. 30 IN A 10.7.11.169` |
| Primary stopped (`brew services stop dnsmasq` on Mac 1) | Backup answered; the client still resolved the name |
| Service reached **by name** with the primary DNS dead | `HTTP/2 200`, `{"backend":"A","status":"ok"}` |

The two resolvers returning an identical record *and* an identical TTL is the
property that makes failover safe. A disagreement would silently redirect
clients, which is worse than having no backup. Both configs are generated from
one IP table, so they cannot drift apart.

**DNS service failure vs application failure.** With DNS down, names cannot
become addresses at all and no server is reached. With the application down,
resolution works perfectly and a healthy edge returns 502. Different layer,
different symptom.

### 2.2 Extension B — TTL and a controlled record change

`dig` now returns `app.cn_team.test. 30 IN A …` where Phase 1 returned `0`.
After changing the record, the client was sampled every two seconds:

```
23:27:06  authoritative=10.7.21.130  client-cached=10.7.21.130  served-by=10.7.21.130
23:27:08  authoritative=10.7.11.169  client-cached=10.7.21.130  served-by=10.7.21.130   <- stale
23:27:13  authoritative=10.7.11.169  client-cached=10.7.21.130  served-by=10.7.21.130   <- stale
23:27:17  authoritative=10.7.11.169  client-cached=10.7.21.130  served-by=10.7.21.130   <- stale
23:27:19  authoritative=10.7.11.169  client-cached=10.7.11.169  served-by=10.7.11.169
```

For about **eleven seconds** the authoritative record had already changed while
the client kept its cached answer **and kept sending requests to the old edge**.
It then expired and moved on its own, with nothing restarted on the client.

A manual flush (`dscacheutil -flushcache` followed by `killall -HUP mDNSResponder`)
discards the entry immediately instead of waiting.

`dig` does not show the TTL counting down because it queries the authoritative
server directly, which stamps a fresh 30 seconds on every answer. A TTL only
decrements inside a cache — on macOS, mDNSResponder.

### 2.3 Extension C — service isolation

Tested from Mac 1, which is neither an edge nor a backend:

```
Backend A  http://10.7.25.47:3001   -> connection TIMED OUT after 4s
Backend B  http://10.7.21.130:3002  -> connection TIMED OUT after 4s
https://app.cn_team.test/api/status -> {"backend":"A","status":"ok"}
```

`block drop` was chosen over `block return` deliberately: a drop produces a
timeout (something is filtering) rather than a refusal (nothing is listening).

`firewall/enable-isolation.sh` snapshots the existing ruleset and runs
`pfctl -n` as a dry run before loading anything, so a syntax error cannot take
the firewall down. `disable-isolation.sh` restores the stock ruleset and the
original enabled state, satisfying the brief's requirement to keep a rollback
copy and restore the original configuration afterwards.

### 2.4 Extension D — high-availability failover

Backend A was stopped on Mac 3 and eight requests were sent from a client:

```
A=0   B=8   failed=0
```

Every request succeeded; the client saw no error. A direct probe to Backend A at
the same moment returned **connection refused** — the process was gone, the host
was fine. After restarting Backend A, ten further requests gave **A=5, B=5**.
nginx re-probes an ejected upstream once `fail_timeout` elapses, so recovery is
automatic with nothing reloaded on the edge.

**Quantifying the change.** On a controlled bench test, a backend that accepts
the TCP connection and then never answers — the software equivalent of the
sleeping laptop that disrupted Phase 1 — produced:

| Edge configuration | Result |
|---|---|
| Phase 1 (nginx defaults) | HTTP 200 after **60.012 s** |
| Phase 2 (timeouts + `max_fails`) | HTTP 200 after **0.004 s** |

A *cleanly stopped* backend fails over with no measurable delay, because a
refusal is immediate. A *hung* backend must be waited out, and that wait is what
the Phase 2 timeouts bound.

### 2.5 Extension E — controlled edge migration

`scripts/dns-cutover.sh to-standby` rewrote both A records, after taking a
timestamped backup of `dnsmasq.conf`, and reloaded the resolver:

```
23:23:32  resolved=10.7.11.169  served-by=10.7.11.169   (primary, Mac 2)
23:23:35  resolved=10.7.21.130  served-by=10.7.21.130   (standby, Mac 4)
```

The public entry point of the service moved to a different physical machine. On
the client: same URL, same certificate, no warning, no restart, nothing
reconfigured — only the name was repointed. This required no new hardware.

TLS survived because the certificate is issued to the **name**
`app.cn_team.test`, not to a machine or an IP. Both edges present it and the
client validates the name it asked for.

Cutting back produced the eleven-second stale window in §2.2: during a
migration, clients holding a cached answer keep reaching the old edge while new
lookups go to the standby.

### 2.6 The remaining single point of failure

**The edge.** Every request still passes through one nginx on Mac 2. If it
fails, DNS resolves correctly and both backends are healthy, yet the service is
unreachable. DNS is now redundant and the backends are redundant; the edge is
not.

Extension E makes the edge **recoverable**, not redundant — the cutover is
manual and is bounded by the DNS TTL. Eliminating it would require either
several edges published under one name (multiple A records, or an anycast
address with health checking) or a floating IP that a standby claims
automatically.

---

## 3. Troubleshooting findings

### 3.1 Method

`scripts/diagnose.sh` implements the order the brief specifies — name
resolution, then TCP connectivity, then TLS, then the application — and stops at
the lowest broken layer, because nothing above a broken layer is meaningful.

It distinguishes failure *modes*, not merely failure:

| Symptom | What it means |
|---|---|
| NXDOMAIN or a DNS timeout | The name never became an address; no server was reached |
| TCP refused | The host is up and nothing is listening on that port |
| TCP timeout | Packets are being dropped — a firewall, or the host is off |
| Certificate not trusted | Transport is fine; the CA is missing from this client |
| Certificate name mismatch | The certificate does not cover the name requested |
| HTTP 502 | The edge is healthy and generated this itself; no backend answered |
| HTTP 504 | A backend accepted the connection and then never replied |

Any HTTP response at all — including a 502 — is generated by nginx, so receiving
one proves the edge is alive. Pairing that with the body isolates the fault to
the backend layer from a single request.

### 3.2 Faults diagnosed while bringing the system up

These were not injected. Each was isolated by the layered method rather than guessed.

**A service that reported success but was dead.** On Mac 3,
`brew services restart dnsmasq` printed *"Successfully started"*, yet
`dig @127.0.0.1` on that same machine timed out. A firewall never filters
loopback, so a localhost timeout eliminated the entire network stack in one step
— the service was not serving. `brew services` swallows a daemon's stderr;
running the binary in the foreground printed the cause immediately:

```
dnsmasq: failed to create listening socket for 10.7.20.9: Can't assign requested address
```

`10.7.20.9` was that machine's address in October. The hotspot had since
reassigned it, and a process cannot bind an address the host does not own. The
stale value came from a `git pull` taken before the IP table was updated.

**The same service, blocked only from outside.** Once running, dnsmasq answered
its own loopback but was unreachable from Mac 1 — while Backend A on TCP 3001 on
that *same host* answered Mac 1 normally. One port filtered and another open on
one host points at a per-application firewall, not at the host or the network.
Mac 3 is an MDM-managed machine and refused firewall changes from the command
line. Running dnsmasq in the foreground triggered macOS's standard "accept
incoming connections?" prompt, which could be approved; the approval attaches to
the binary, so the background service inherited it.

Note that these two failures to start produced two *different* error strings,
and the string alone identified the cause:

| Error | Cause |
|---|---|
| `Can't assign requested address` | The IP does not belong to this host |
| `Permission denied` | The IP is fine; binding a port below 1024 needs root |

**Two extensions that contradicted each other.** The Extension C firewall
originally admitted only Mac 2. That is correct until Extension E moves the
edge: the moment the DNS record pointed at the standby on Mac 4, the standby
would have been firewalled out of both backends and returned 502 for everything,
while the firewall itself looked healthy. This was caught by reasoning about the
rules before running the cutover. The fix was to admit the **edge tier** rather
than one host — which is how a production security group is written: it permits
the load-balancer tier, not one specific load balancer.

---

## 4. Learning summary

**Extension A — Backup DNS.** Redundancy is only redundancy if both copies
agree. Standing up a second resolver was straightforward; keeping its records
identical to the primary is the real engineering problem, and we solved it by
generating both configurations from one source of truth rather than by
remembering to edit both. We also learned to state the difference precisely: a
DNS failure means names stop becoming addresses, so no server is reached at all,
whereas an application failure means resolution works perfectly and a healthy
edge hands back a 502.

**Extension B — TTL.** A TTL is a promise about staleness, not about speed, and
it exists only inside a cache. Our first attempt showed nothing, because Phase 1
served TTL 0 and because we were measuring with `dig`, which bypasses every cache
and re-reads the authoritative record each time. Measuring through the client's
own resolver made the lag visible, and that lag is exactly the window during
which a production DNS cutover is partially complete, with some users on the old
infrastructure and some on the new.

**Extension C — Service isolation.** Defence in depth means the application
servers should be unreachable even from inside the LAN, with the edge as the only
door. Writing the pf rules taught us that rule *order* is the whole game:
`quick` means first match wins, so a `pass` placed after the `block` would never
be evaluated and we would have locked out nginx along with everyone else. We also
learned to read the failure mode as information — a timeout means filtered, a
refusal means nothing is listening — which then became a diagnostic tool in
Extension F.

**Extension D — HA failover.** Availability is a latency property, not merely a
binary one. Phase 1 "worked" in the sense that requests eventually succeeded, but
a sixty-second response is an outage from the user's point of view. The fix was
not more infrastructure; it was three timeout directives and a health-check
policy. Measuring the same fault before and after made that concrete in a way
that reading the nginx documentation did not.

**Extension E — Edge migration.** Because clients connect to a *name*, the name
is the real control plane. We moved the entire public entry point to a different
physical machine without touching a single client, without reissuing a
certificate, and without the service changing address from the user's point of
view. The certificate kept validating because it was issued to
`app.cn_team.test` and not to a host. The cost is that the migration is only as
quick as the TTL, which ties this extension directly back to Extension B.

**Extension F — Troubleshooting.** The useful skill is not knowing the answer but
knowing the order of the questions, and refusing to reason about a layer until
the one below it is proven. Encoding that order into a script forced us to be
precise about what each failure mode actually distinguishes, and running it
against a deliberately broken system found real faults — including one where a
service manager reported success for a process that had already exited.

---

## 5. Where the evidence is

| Extension | Folder |
|---|---|
| A — backup DNS | `evidence/phase2/backup-dns/` |
| B — TTL | `evidence/phase2/ttl/` |
| C — isolation | `evidence/phase2/isolation/` |
| D — HA failover | `evidence/phase2/ha-failover/` |
| E — edge migration | `evidence/phase2/edge-cutover/` |
| F — troubleshooting | `evidence/phase2/troubleshooting/` |
| Phase 1 baseline | `evidence/dns/`, `evidence/load-balancing/`, `evidence/caching/`, `evidence/tcp-tls-handshake/`, `evidence/failure-demos/` |

Configuration bundle: `mac1-dns/`, `mac2-edge/`, `backup-dns/`, `standby-edge/`,
`firewall/`, with every IP generated from `config/ips.env`.
