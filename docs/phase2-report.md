# Phase 2 Final Report

**Project:** Private Network Service Platform — `app.cn_team.test`
**Team:** Naman (Mac 1, DNS) · Harsha Karthikeya (Mac 2, edge) · Hemanth (Mac 3, Backend A) · Akshay (Mac 4, Backend B)
**Phase 1 completed:** 30 Sep – 4 Oct 2026 **Phase 2:** November 2026

Required contents per spec §9: *what changed from Phase 1 · resilience tests and
results · troubleshooting findings · learning summary (one paragraph per extension).*

---

## 1. What changed from Phase 1

Phase 2 extends the Phase 1 network; nothing was rebuilt. Six concrete changes:

| # | Change | File | Why |
|---|---|---|---|
| 1 | Second authoritative resolver on Mac 3 | `backup-dns/dnsmasq-backup.conf` | Mac 1 was a single point of failure for every name lookup |
| 2 | `local-ttl=30` on both resolvers | `mac1-dns/dnsmasq-phase2.conf` | Phase 1 served TTL 0, so no client ever cached and TTL behaviour could not be demonstrated |
| 3 | `max_fails=2 fail_timeout=10s` per upstream | `mac2-edge/nginx-phase2.conf` | nginx now ejects a failing backend instead of round-robining into it forever |
| 4 | `proxy_connect_timeout 2s` / `read 3s` / bounded retries | `mac2-edge/nginx-phase2.conf` | **the Phase 1 bug fix** — see §2.3 |
| 5 | pf rules restricting :3001/:3002 to the edge | `firewall/pf.anchors.cn-backend` | backends stop being directly reachable from the LAN |
| 6 | Standby edge on Mac 4 with the same cert | `standby-edge/nginx-standby.conf` | lets the service migrate between machines via DNS alone |

One Phase 1 defect was also repaired: **`scripts/test-lb.sh`**. The Phase 1
version wrapped a `curl | grep` pipeline in `set -euo pipefail`. When a request
failed, `grep` matched nothing, exited 1, and `set -e` terminated the script
after printing only its banner — which is why the load-balancing proof showed
**zero lines of output** in the Phase 1 submission video. It now prints one line
per request, failures included. `scripts/test-cache.sh` was also repaired — it
sent `curl -I` (a HEAD request) to backends that only route GET, so it always
returned 404. **The backend application code is unchanged from Phase 1**, as the
spec intends; both fixes were to the test scripts, not the application.

A single `config/ips.env` + `scripts/set-ips.sh` now regenerates every config.
This is not cosmetic: the team is on a shared mobile hotspot that reassigned IPs
twice during Phase 1, and each time a stale IP survived in one file and broke the
system.

---

## 2. Resilience tests and results

Every extension below was run **on the real four-machine LAN on 2026-11-22**,
with all four laptops on the shared hotspot. Raw output for each is in
`evidence/phase2/`. A pre-flight dry run of the same configs on a single laptop
is kept separately in `evidence/phase2/00-preflight-config-check-2026-11-22.txt`;
where a number below comes from that dry run rather than the live LAN, it says so.

Machines as tested: Mac 1 Naman 10.7.20.236 (primary DNS) · Mac 2 Harsha
10.7.11.169 (edge) · Mac 3 Hemanth 10.7.25.47 (Backend A + backup DNS) ·
Mac 4 Akshay 10.7.21.130 (Backend B + standby edge).

### 2.1 Backup DNS failover (Extension A)

| Test | Result (live) |
|---|---|
| Both resolvers queried directly | identical: `app.cn_team.test. 30 IN A 10.7.11.169` from both |
| Primary stopped (`brew services stop dnsmasq` on Mac 1) | backup answered; the client still resolved the name |
| Service reachable **by name** with the primary DNS dead | yes — `HTTP/2 200`, `{"backend":"A","status":"ok"}` |

Getting the backup reachable exposed a real obstacle. Mac 3 is MDM-managed and
refused firewall changes from the command line (*"Firewall settings cannot be
modified from command line on managed Mac computers"*), and the GUI's add button
was locked. dnsmasq served its own loopback but was invisible on the LAN.
Running it in the **foreground** made macOS raise its normal "accept incoming
connections?" prompt, which could be approved; the approval attaches to the
binary, so the background service inherited it. Diagnostically, the backend on
TCP 3001 was reachable from Mac 1 throughout, which proved the host and network
were fine and isolated the fault to one filtered service.

An answer mismatch between the two resolvers would be worse than having no
backup at all, because failover would silently redirect clients. The configs are
generated from the same `config/ips.env`, which makes divergence structurally
difficult rather than a matter of discipline.

### 2.2 TTL behaviour (Extension B)

`dig` now returns `app.cn_team.test. 30 IN A …` where Phase 1 returned `0`.

The record was then changed and the client watched once every two seconds:

```
23:27:06  auth=10.7.21.130  cached=10.7.21.130  served-by=10.7.21.130
23:27:08  auth=10.7.11.169  cached=10.7.21.130  served-by=10.7.21.130   <-- stale
23:27:13  auth=10.7.11.169  cached=10.7.21.130  served-by=10.7.21.130   <-- stale
23:27:17  auth=10.7.11.169  cached=10.7.21.130  served-by=10.7.21.130   <-- stale
23:27:19  auth=10.7.11.169  cached=10.7.11.169  served-by=10.7.11.169
```

For about **eleven seconds** the authoritative record had already changed while
the client kept using its cached answer **and kept sending its HTTPS requests to
the old edge**. Then the entry expired, the client re-resolved on its own, and
traffic moved. Nothing was restarted on the client. That gap is the TTL.

`dig` does not show the TTL counting down because it queries the authoritative
server directly and dnsmasq re-stamps a full 30s on every answer; a TTL only
decrements inside a cache, which on macOS is mDNSResponder — the thing
`dscacheutil`, `ping`, `curl` and the browser all go through.

One honest note: an earlier cut-over in the opposite direction showed **no**
stale window, because that run restarted dnsmasq while the client was mid-poll
and the brief unavailability forced an immediate re-resolve. The window above is
the clean observation.

### 2.3 HA failover (Extension D) — the headline result

Backend A was replaced with a process that accepts the TCP connection and never
answers: the software equivalent of the sleeping laptop that disrupted the
Phase 1 demo. One identical request through each configuration:

| Edge configuration | Result |
|---|---|
| Phase 1 (nginx defaults) | HTTP 200 after **60.008 s** |
| Phase 2 (timeouts + `max_fails`) | HTTP 200 after **0.003 s** |

That before/after pair is from the pre-flight dry run, because deliberately
hanging a teammate's laptop on the night before the demo was not worth the risk.

On the **real LAN**, Backend A was stopped cleanly on Mac 3
(`lsof -ti:3001 | xargs kill`) and eight requests were sent from Mac 1:

```
1  Backend B  HTTP 200   247ms        A=0  B=8  failed=0
2  Backend B  HTTP 200  1054ms
3  Backend B  HTTP 200    45ms
4  Backend B  HTTP 200    60ms
5  Backend B  HTTP 200    42ms
6  Backend B  HTTP 200    59ms
7  Backend B  HTTP 200   110ms
8  Backend B  HTTP 200    43ms
```

Every request succeeded; the client never saw an error. A direct probe to
Backend A at the same moment returned **curl exit 7, connection refused** — the
process was gone, the host was fine. The occasional ~1s figure is this shared
mobile hotspot, not the failover: plain ICMP pings between these machines have
measured over 2s on the same network. A cleanly killed process refuses the TCP
connection instantly, so nginx moves to the next upstream with no measurable
delay; a *hung* backend is the case that must be waited out, and that is what
the 60.012s → 0.004s pair above quantifies.

Backend A was then restarted and ten more requests sent: **A=5, B=5, failed=0**.
nginx re-probes an ejected upstream once `fail_timeout` (10s) has elapsed, so
recovery is automatic — nothing on the edge was reloaded or reconfigured.

With both backends stopped, the edge returns `502 Bad Gateway` in 3 ms. The 502
is generated by nginx itself, so it simultaneously proves the edge is healthy and
that no backend answered — DNS, TCP and TLS all fine, fault isolated to the
application layer.

### 2.4 Service isolation (Extension C)

With pf loaded on Mac 3 and Mac 4, tested from Mac 1 (neither an edge nor a
backend, so the honest tester):

```
Backend A  http://10.7.25.47:3001   -> connection TIMED OUT after 4s
Backend B  http://10.7.21.130:3002  -> connection TIMED OUT after 4s
https://app.cn_team.test/api/status -> {"backend":"A","status":"ok"}
```

The backends are unreachable directly while the same resource through the edge
still works. `block drop` was chosen over `block return` deliberately: a
drop produces a timeout (something is filtering you) rather than a refusal
(nothing is listening), which is how a real firewall behaves and which is a
distinction the diagnosis procedure depends on.

`firewall/enable-isolation.sh` snapshots the existing ruleset and runs
`pfctl -n -f` as a dry run *before* loading anything, so a syntax error cannot
take the machine's firewall down mid-demo; `disable-isolation.sh` restores the
stock macOS ruleset and the original enabled/disabled state.

### 2.5 Edge migration (Extension E)

Primary and standby serve the same name and the **same certificate**; which one
actually answered is read off `curl`'s `%{remote_ip}`, so nothing extra had to be
configured on either server to observe the migration.

`scripts/dns-cutover.sh to-standby` rewrote both A records (after taking a
timestamped backup of `dnsmasq.conf`) and restarted dnsmasq. Watched from Mac 1:

```
23:23:32  authoritative=10.7.11.169  cached=10.7.11.169  served-by=10.7.11.169   (primary)
23:23:35  authoritative=10.7.21.130  cached=10.7.21.130  served-by=10.7.21.130   (STANDBY)
```

The public entry point of the service moved to a different physical machine.
On the client: same URL, same certificate, no warning, no restart, nothing
reconfigured. Only the name was repointed. TLS survived because the certificate
is issued to the **name** `app.cn_team.test`, not to a machine or an IP.

The cut back to the primary is the run quoted in §2.2, where the eleven-second
stale window was visible — during it, new lookups went to the primary while this
client was still reaching the standby. The TTL lag and the migration are the
same phenomenon seen from two angles.

### 2.6 Remaining single point of failure

The edge. Every request still traverses one nginx instance on Mac 2. If it dies,
DNS resolves correctly and both backends are healthy, yet nobody can reach the
service. Eliminating it needs either multiple edges published under one name
(several A records, or an anycast VIP with health checking) or a floating IP that
a standby claims automatically. Extension E is the manual, DNS-driven version of
that idea; its weakness is that the cutover is only as fast as the TTL, which is
precisely why production DNS failover uses short TTLs and why we set 30s.

---

## 3. Troubleshooting findings

### 3.1 Method

`scripts/diagnose.sh` implements the spec's required order — name resolution,
then TCP connectivity, then TLS, then application — and stops at the lowest
broken layer, because everything above a broken layer is meaningless. It
distinguishes failure *modes*, not just failure:

| Symptom | Means |
|---|---|
| TCP **refused** (curl 7) | nothing is listening on that port |
| TCP **timeout** (curl 28) | something is silently dropping packets — firewall, or host off |
| TLS curl 60 | certificate not trusted on *this* client |
| TLS curl 51 | certificate does not cover this hostname |
| HTTP 502 | edge healthy, no backend answered |
| HTTP 504 | a backend accepted the connection then never replied |

The key instrument is the `Server:` response header: any HTTP response at all,
including a 502, is generated by nginx, so receiving one proves the edge is alive
while a 502 body proves no backend answered — the fault is isolated to the
backend layer from a single request.

### 3.2 Bugs found by actually running the Phase 2 tooling

Writing the scripts was not sufficient; executing them surfaced eight defects that
would otherwise have surfaced in front of the evaluator:

1. Three scripts treated `dig`'s diagnostic text as a valid answer, so a **dead
   resolver reported as healthy** — the most dangerous class of bug here, since
   it would have invalidated the Extension A demo while appearing to pass.
2. `diagnose.sh` hard-coded port 443, so any team using the permitted 8443
   fallback would see a spurious "connection refused".
3. `dns-cutover.sh` used `sed 's|…|…|'` while its own pattern contained the
   alternation `(app|api)`; the delimiter collided and the rewrite failed
   silently — the script reported progress while changing nothing.
4. `test-cache.sh` sent a HEAD request (`curl -I`) to backends that only route
   GET, so it always returned 404 — the same 404 that appears in the Phase 1
   submission video. It now uses `-D- -o /dev/null`, a GET that prints headers.
5. Temp files were written to `/tmp` with `$$` and failed in a restricted
   environment; switched to `mktemp`.
6. `config/ips.env` overrode environment variables rather than the reverse,
   making one-off overrides impossible.
7. `test-ha-failover.sh` attributed a 3s delay to `proxy_connect_timeout` when it
   is actually `proxy_read_timeout`. A confidently wrong explanation is worse
   than no explanation in a viva, so the message now distinguishes a hung
   backend (read timeout) from an unreachable one (connect timeout).
8. `set-ips.sh` regenerated the *Phase 1* configs from their templates,
   overwriting their real provenance comments with placeholder boilerplate. Those
   files are a graded deliverable, so the script now rewrites only the IP values
   in them, in place, preserving every comment.

### 3.3 Three real faults diagnosed while bringing the system up

These were not injected. They happened while assembling the live system on
2026-11-22, and each one was isolated by the layered method rather than guessed.

**1. A service that reported success but was dead.** On Mac 3,
`sudo brew services restart dnsmasq` printed *"Successfully started"*, yet
`dig @127.0.0.1` on that same machine timed out. A firewall never filters
loopback, so a localhost timeout eliminated the entire network stack as a
suspect in one step — the service simply was not serving. `brew services`
swallows a daemon's stderr; running the binary in the foreground printed the
cause immediately:

```
dnsmasq: failed to create listening socket for 10.7.20.9: Can't assign requested address
```

`10.7.20.9` was that machine's IP on 4 October. The hotspot had since reassigned
it to `10.7.25.47`, and a process cannot bind an address the host does not own.
The stale value came from a `git pull` taken before the IP table was updated.
Lesson: *"started" means the process was launched, not that it works.*

**2. The same service, blocked only from outside.** Once running, dnsmasq
answered its own loopback but was unreachable from Mac 1, while Backend A on
TCP 3001 on that *same host* answered Mac 1 fine. One port filtered and another
open on one host points at a per-application firewall, not at the host or the
network. Mac 3 is MDM-managed and refused `socketfilterfw` changes from the
command line, and the GUI control was locked. Running dnsmasq in the foreground
triggered macOS's ordinary "accept incoming connections?" prompt, which could be
approved; the approval attaches to the binary, so the background service
inherited it.

Worth noting that the two failures above produced two *different* error strings
for "it will not start", and the string alone identified the cause:

| Error | Meaning |
|---|---|
| `Can't assign requested address` | the IP does not belong to this host |
| `Permission denied` (when run without sudo) | the IP is fine; the user may not bind a port below 1024 |

**3. Two extensions that silently contradicted each other.** The Extension C
firewall originally allowed only Mac 2 to reach the backend ports. That is
correct right up until Extension E moves the edge: the moment the DNS record
pointed at the standby on Mac 4, the standby would have been firewalled out of
both backends and returned 502 for everything, while the firewall looked
perfectly healthy. This was caught by reasoning about the rules before running
the cutover, not by hitting the failure. The fix was to allow the **edge tier**
— primary and standby — rather than one host, which is how a real security group
is written: it permits the load-balancer tier, not a specific load-balancer.
Re-verified afterwards that the backends still time out from a client while the
standby can reach them.

### 3.3 Findings carried over from Phase 1

The most valuable thing Phase 1 produced was an accident: Akshay's laptop slept
mid-test, and the team noticed that nginx's default `proxy_next_upstream` only
fails over on a *clean* error. A backend that accepts the connection and then
goes silent is not an error yet — nginx waits, by default for 60 seconds.
Extension D exists because of that observation, and §2.3 is its measurement.

---

## 4. Learning summary

**Extension A — Backup DNS.** Redundancy is only redundancy if both copies agree.
Standing up a second resolver was trivial; keeping its records identical to the
primary is the real engineering problem, and we solved it by generating both
configs from one source of truth rather than by remembering to edit both. We also
learned to state the difference precisely: a DNS failure means names stop
becoming addresses, so you never reach any server; an application failure means
resolution works perfectly and a healthy edge hands you a 502.

**Extension B — TTL.** A TTL is a promise about *staleness*, not about speed, and
it only exists inside a cache. Our first attempt at this demo failed to show
anything because Phase 1 served TTL 0 and because we were measuring with `dig`,
which bypasses every cache and re-reads the authoritative record each time. Once
we measured through the client's own resolver instead, the lag became visible —
and that lag is exactly the window during which a production DNS cutover is
partially complete, with some users on the old infrastructure and some on the new.

**Extension C — Service isolation.** Defence in depth means the application
servers should be unreachable even from inside the LAN, with the edge as the only
door. Writing the pf rules taught us that rule *order* is the whole game: `quick`
means first match wins, so a `pass` for the edge placed after the `block` would
never be evaluated and we would have locked out nginx along with everyone else.
We also learned to read the failure mode as information — timeout means filtered,
refused means nothing listening — which became a diagnostic tool in Extension F.

**Extension D — HA failover.** Availability is a latency property, not just a
binary one. Phase 1 "worked" in the sense that requests eventually succeeded, but
a 60-second response is an outage from the user's point of view. The fix was not
more infrastructure, it was three timeout directives and a health-check policy.
Measuring before and after — 60.008s versus 0.003s on the identical fault — made
that concrete in a way reading the nginx documentation never did.

**Extension E — Edge migration.** Because clients connect to a *name*, the name
is the real control plane. We moved the entire public entry point to a different
physical machine without touching a single client, without reissuing a
certificate, and without the service changing its address from the user's point
of view. The certificate kept validating because it was issued to
`app.cn_team.test`, not to a host. The cost is that the migration is only as
quick as the TTL, which ties this extension directly back to Extension B.

**Extension F — Troubleshooting.** The useful skill is not knowing the answer, it
is knowing the order of the questions, and refusing to reason about a layer until
the one below it is proven. Encoding that order into a script forced us to be
precise about what each failure mode actually distinguishes, and the act of
running it against deliberately broken systems found six real bugs in our own
tooling — including one that would have made a dead DNS server look alive.

---

## 5. Evidence index

| Extension | Evidence |
|---|---|
| Pre-demo verification of everything | `evidence/phase2/00-preflight-config-check-2026-11-22.txt` |
| A — backup DNS | `evidence/phase2/backup-dns/` |
| B — TTL | `evidence/phase2/ttl/` |
| C — isolation | `evidence/phase2/isolation/` |
| D — HA failover | `evidence/phase2/ha-failover/` |
| E — edge cutover | `evidence/phase2/edge-cutover/` |
| F — troubleshooting | `evidence/phase2/troubleshooting/` |
| Phase 1 baseline | `evidence/dns/`, `evidence/load-balancing/`, `evidence/caching/`, `evidence/tcp-tls-handshake/`, `evidence/failure-demos/` |
