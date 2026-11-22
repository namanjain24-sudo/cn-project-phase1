# Phase 2 — Demo Day Runbook

This is the only file you need open during the evaluation. It is ordered the way
the demo is ordered (spec §8, the 11 steps), and every command is copy-pasteable.

**Read §0 first.** The Phase 1 evidence in this repo is from 30 Sep – 4 Oct. The
machines have been off this network for weeks and the team is on a shared mobile
hotspot that reassigns IPs on every reconnect. Nothing will work until §0 is done.

---

## 0. Bring the system back up (budget 20 minutes, do it BEFORE the slot)

### 0.1 Everyone: same network, then collect IPs

```bash
ipconfig getifaddr en0          # run on all four Macs, shout out the answers
```

One person (Naman) puts all four into `config/ips.env`, then:

```bash
./scripts/set-ips.sh            # regenerates EVERY config from that one table
git add -A && git commit -m "Update IPs for Phase 2 demo" && git push
```

Everyone else: `git pull`.

> Do not hand-edit configs. The hotspot already broke this project twice in
> Phase 1 because one file kept a stale IP.

### 0.2 Per machine — copy your config into place and start your service

| Machine | Person | Commands |
|---|---|---|
| **Mac 1** | Naman | `sudo cp mac1-dns/dnsmasq-phase2.conf /opt/homebrew/etc/dnsmasq.conf`<br>`sudo brew services restart dnsmasq`<br>`dig @127.0.0.1 app.cn_team.test` → must show Mac 2's IP **and TTL 30** |
| **Mac 2** | Harsha | `sudo cp mac2-edge/nginx-phase2.conf /opt/homebrew/etc/nginx/servers/cn-project.conf`<br>`sudo nginx -t && sudo brew services restart nginx`<br>`curl -sI https://app.cn_team.test/ --resolve app.cn_team.test:443:127.0.0.1` |
| **Mac 3** | Hemanth | `cd mac3-backend-a && node server.js` (leave open)<br>new tab: `sudo cp backup-dns/dnsmasq-backup.conf /opt/homebrew/etc/dnsmasq.conf && sudo brew services restart dnsmasq`<br>`sudo cp firewall/pf.anchors.cn-backend /etc/pf.anchors/cn-backend` |
| **Mac 4** | Akshay | `cd mac4-backend-b && node server.js` (leave open)<br>new tab: `sudo cp standby-edge/nginx-standby.conf /opt/homebrew/etc/nginx/servers/cn-project.conf && sudo nginx -t`<br>**do not start nginx yet** — Extension E starts it live<br>`sudo cp firewall/pf.anchors.cn-backend /etc/pf.anchors/cn-backend` |

### 0.3 Every client machine: two resolvers + trusted CA

```bash
sudo networksetup -setdnsservers Wi-Fi <MAC1_IP> <MAC3_IP>    # primary, then backup
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain mac2-edge/rootCA.pem   # if not already trusted
```

### 0.4 Prove it before the evaluator walks in

```bash
./scripts/diagnose.sh          # must be PASS at every layer
./scripts/test-lb.sh           # must show A and B alternating
```

If anything is red, `diagnose.sh` names the layer. Fix that layer, not everything.

### 0.5 Sleep settings — this cost you marks in Phase 1

On **every** machine: System Settings → Lock Screen → "Turn display off…" → Never,
and plug in the chargers. Phase 1's load-balancing demo broke because a laptop
slept mid-test.

---

## 1–7. The Phase 1 steps (you still have to show these)

| # | Step | Command | Who |
|---|---|---|---|
| 1 | Topology + IP table | open `docs/topology.md` | Naman |
| 2 | All machines on the LAN | `ping -c 4 <each other IP>` | all |
| 3 | Resolve the private domain | `dig app.cn_team.test` — point at ANSWER SECTION **and** `;; SERVER:` line | Naman |
| 4 | HTTPS by name, no warning | `curl -v https://app.cn_team.test/` — **no `-k`, no `--resolve`, no IP in the URL** | Akshay |
| 5 | Load balancing | `./scripts/test-lb.sh` | Harsha |
| 6 | Wireshark DNS + TCP + TLS | open `evidence/tcp-tls-handshake/cn-project-wireshark.pcapng` | Hemanth |
| 7 | Caching | `./scripts/test-cache.sh` | Hemanth |

> **Three things the Phase 1 video never actually showed on screen** — make sure
> they are shown live this time:
> - step 3: a real `dig` ANSWER SECTION (the video only showed `cat dnsmasq.conf`)
> - step 5: the A/B alternation (`test-lb.sh` printed nothing on camera; fixed)
> - step 7: a genuine 304. In the video the ETag was pasted **without** the
>   `If-None-Match:` header name, so the server answered 200 while the narration
>   said 304. `./scripts/test-cache.sh` builds the header correctly — use the
>   script, don't retype it by hand.
>
> Note on the 304: run `test-cache.sh` against **one backend directly**
> (`http://localhost:3001/api/data` on Mac 3), the way the Phase 1 evidence did.
> Through the load balancer the two backends return different ETags, because
> `/api/data`'s body contains the backend id — so a conditional request that
> lands on the other backend correctly returns 200, not 304. Be ready to explain
> exactly that if asked; it is a good answer, not a defect.

> **Wireshark note:** the Phase 1 capture was filtered with
> `ip.addr==<mac2> and tcp.port==443`, which *excludes the DNS packets* because
> DNS is UDP/53 to Mac 1. Task G asks for DNS too. Either add a second filter
> tab with `dns`, or take a fresh capture using:
> `dns or tcp.port == 443`

---

## 8. Fail one backend, prove the service continues (Extension D)

**Hemanth (Mac 3):** stop Backend A — `Ctrl+C`, or `lsof -ti:3001 | xargs kill`

**Anyone (client):**
```bash
./scripts/test-ha-failover.sh 8
```
Expect: every request succeeds, all from Backend B, latency stays in the
milliseconds.

**Say this:** *"In Phase 1 this same situation hung for 60 seconds per request,
because nginx's default connect timeout is 60s and a sleeping laptop never
refuses the connection — it just doesn't answer. Phase 2 sets
`proxy_connect_timeout 2s`, `proxy_read_timeout 3s` and `max_fails=2
fail_timeout=10s`, so the dead backend is detected in seconds and then ejected
from the pool entirely. We measured 60.0s before versus 0.003s after."*

**Hemanth:** restart Backend A → re-run → A and B alternate again within ~10s
(that is `fail_timeout` expiring and nginx re-probing).

---

## 9. Phase 2 DNS and resilience

### 9A. Backup DNS failover (Extension A) — Naman + Hemanth

```bash
./scripts/test-dns-failover.sh        # on a client: both resolvers answer
```
**Naman (Mac 1):** `sudo brew services stop dnsmasq`
```bash
./scripts/test-dns-failover.sh        # primary FAILS, backup answers, names still resolve
curl -s https://app.cn_team.test/api/status     # service still reachable by NAME
```
**Naman:** `sudo brew services start dnsmasq`

**Say this:** *"A DNS service failure and an application failure look completely
different. With DNS down, nothing resolves — you get NXDOMAIN or a timeout and
you never reach any server. With the app down, resolution works perfectly and
you get a 502 from a healthy edge. Different layer, different symptom."*

### 9B. TTL and cache behaviour (Extension B) — Naman

```bash
./scripts/test-ttl.sh watch           # leave running on a CLIENT
```
**Naman (Mac 1):** `./scripts/dns-cutover.sh to-standby`

Watch the `authoritative` column change immediately while `client-cached` stays
on the old IP — that gap is the TTL. Within 30s it flips by itself.

```bash
./scripts/test-ttl.sh flush           # force it instantly instead of waiting
```

**Expect to be asked:** *"why doesn't `dig` show the TTL counting down?"*
Because `dig` queries the authoritative server directly and dnsmasq stamps a
fresh 30s TTL on every answer. A TTL only counts down inside a **cache** — on
macOS that is mDNSResponder, which is what `dscacheutil`, `ping`, `curl` and the
browser all go through.

### 9C. Edge migration (Extension E) — Akshay + Naman

Continue straight from 9B (the record already points at Mac 4):

**Akshay (Mac 4):** `sudo brew services start nginx`
```bash
./scripts/test-edge-cutover.sh        # on a client
```
The `served-by` column flips from Mac 2's IP to Mac 4's IP. The service never
changed name, never changed certificate, and the client changed nothing.

**Naman:** `./scripts/dns-cutover.sh to-primary` to roll back.

---

## 10. Service isolation (Extension C) — Hemanth + Akshay

**Hemanth (Mac 3) and Akshay (Mac 4):**
```bash
./firewall/enable-isolation.sh
```
**From a client (Mac 1 is the honest tester — it is neither edge nor backend):**
```bash
./scripts/test-isolation.sh
```
Expect: direct connections to `:3001` / `:3002` **time out**, while
`https://app.cn_team.test/api/status` still works.

**Say this:** *"Refused and filtered are different. A refusal means nothing is
listening — the host sends a TCP RST immediately. A timeout means something is
silently dropping our packets. We use `block drop`, so we get the timeout, which
is what a real firewall does."*

**Roll back when done:** `./firewall/disable-isolation.sh` on both machines.

---

## 11. The faculty-injected fault (Extension F)

**Do not guess. Run the script and narrate it.**

```bash
./scripts/diagnose.sh
```

It walks link → network → DNS → transport → TLS → edge → application and stops
you at the lowest broken layer. Say the order out loud as it runs:

> *"Name resolution first — does the name become an IP, and is it the right IP?
> Then transport — is that IP reachable and is the port open? Refused means
> nothing is listening; timeout means something is filtering. Then TLS — does the
> certificate validate without bypassing it? Then the edge itself -- any HTTP
> response at all, even a 502, is generated by nginx and proves the edge is
> alive. Then the application. Everything above a broken layer is meaningless,
> so we fix the lowest one first."*

Common injected faults and their signature:

| Injected fault | What `diagnose.sh` shows | Fix |
|---|---|---|
| dnsmasq stopped on Mac 1 | primary resolver FAIL, backup PASS, system resolution still works | start it, or note the backup covered it |
| `address=` changed to a wrong IP | resolved IP is neither primary nor standby edge | correct the record, restart dnsmasq |
| nginx stopped on Mac 2 | TCP **refused** on 443 | `sudo brew services start nginx` |
| pf rule blocking the edge | TCP **timeout** on 443 | `./firewall/disable-isolation.sh` |
| CA removed from a client's trust store | TLS curl exit 60 | re-add `mac2-edge/rootCA.pem` |
| cert/SAN mismatch | TLS curl exit 51 | regenerate cert for the right name |
| one backend killed | everything PASS, LB shows one letter only | restart that backend |
| both backends killed | edge answers (Server: nginx) but `/api/status` is 502 | restart both |
| backend bound to 127.0.0.1 | 502, and direct probe from a client refused | rebind to `0.0.0.0` |
| wrong upstream port in nginx.conf | 502, backends healthy locally | fix `upstream`, `nginx -s reload` |

---

## 12. Individual viva

Everyone reads `docs/phase2-viva.md` tonight. The rule from the spec: *"every
team member should be able to explain any part of the project, not just the part
they personally configured."*

---

## Emergency recovery

| Symptom | Command |
|---|---|
| Nothing works, don't know why | `./scripts/diagnose.sh` |
| IPs changed again | edit `config/ips.env`, `./scripts/set-ips.sh`, restart your service |
| Firewall locked something out | `./firewall/disable-isolation.sh` |
| DNS record is wrong | `./scripts/dns-cutover.sh status` then `to-primary` |
| Client has a stale DNS answer | `./scripts/test-ttl.sh flush` |
| nginx won't start | `sudo nginx -t` — it names the file and line |
| Backend "address already in use" | `lsof -ti:3001 \| xargs kill` then restart |

---

## 13. Proof collection — exactly what each person runs on their own laptop

Run these **after** §0 is done and the system is live. Each block writes its own
evidence file, so nobody has to remember what to screenshot. Take a screenshot of
the terminal as well — the spec asks for "screenshots or exports".

Everyone first: `cd` into the repo and `git pull`.

### Naman — Mac 1 (primary DNS)

```bash
# Ext B proof 1: the TTL is now 30, not 0
dig app.cn_team.test | tee evidence/phase2/ttl/01-ttl-30.txt

# Ext B proof 2: record change, cached answer lags, then flush forces it
./scripts/test-ttl.sh watch | tee evidence/phase2/ttl/02-ttl-watch.txt
#   ...in a SECOND terminal, while that is running:
./scripts/dns-cutover.sh to-standby
#   watch the two columns diverge, wait for them to converge, then Ctrl+C and:
./scripts/test-ttl.sh flush | tee evidence/phase2/ttl/03-flush.txt
./scripts/dns-cutover.sh to-primary

# Ext A proof: stop the primary resolver and show names still resolve
sudo brew services stop dnsmasq
./scripts/test-dns-failover.sh | tee evidence/phase2/backup-dns/02-primary-down.txt
sudo brew services start dnsmasq

# Ext C proof (Mac 1 is the honest tester: not the edge, not a backend)
./scripts/test-isolation.sh | tee evidence/phase2/isolation/01-from-client.txt
```

### Harsha — Mac 2 (primary edge)

```bash
# Ext D proof 1: the config that implements health detection
sudo nginx -t 2>&1 | tee evidence/phase2/ha-failover/01-nginx-config-ok.txt
grep -A3 'upstream app_backend' /opt/homebrew/etc/nginx/servers/cn-project.conf \
  | tee -a evidence/phase2/ha-failover/01-nginx-config-ok.txt

# Ext D proof 2: baseline, both backends healthy
./scripts/test-ha-failover.sh 8 | tee evidence/phase2/ha-failover/02-both-up.txt

#   ask Hemanth to stop Backend A now, then:
./scripts/test-ha-failover.sh 8 | tee evidence/phase2/ha-failover/03-backend-a-down.txt
#   ask Hemanth to restart it, wait ~10s (fail_timeout), then:
./scripts/test-ha-failover.sh 8 | tee evidence/phase2/ha-failover/04-recovered.txt
```

### Hemanth — Mac 3 (Backend A + backup DNS + firewall)

```bash
# Ext A proof: the backup resolver answers identically to the primary
dig @127.0.0.1 app.cn_team.test | tee evidence/phase2/backup-dns/01-backup-answers.txt

# Task F proof: 200 then 304 against your own backend
./scripts/test-cache.sh http://localhost:3001 \
  | tee evidence/caching/03-200-then-304-phase2.txt

# Ext C proof: load the firewall rules
./firewall/enable-isolation.sh | tee evidence/phase2/isolation/02-rules-loaded-mac3.txt
#   ...Naman now runs test-isolation.sh from Mac 1...
./firewall/disable-isolation.sh | tee evidence/phase2/isolation/04-rollback-mac3.txt
```

### Akshay — Mac 4 (Backend B + standby edge)

```bash
# Ext C proof: same firewall rules on this machine
./firewall/enable-isolation.sh | tee evidence/phase2/isolation/03-rules-loaded-mac4.txt
./firewall/disable-isolation.sh | tee evidence/phase2/isolation/05-rollback-mac4.txt

# Ext E proof: start the standby edge, then watch the cutover from here
sudo brew services start nginx
./scripts/test-edge-cutover.sh | tee evidence/phase2/edge-cutover/01-cutover.txt
#   ...Naman runs ./scripts/dns-cutover.sh to-standby in parallel...
#   when served-by has flipped to Mac 4's IP, Ctrl+C, then ask Naman to run to-primary
sudo brew services stop nginx
```

### Everyone — Ext F, during the evaluation

```bash
./scripts/diagnose.sh | tee evidence/phase2/troubleshooting/01-injected-fault.txt
```

### Finally

```bash
git add evidence/ && git commit -m "Add Phase 2 demo evidence" && git push
```
