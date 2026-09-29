# §6.3 — Phase 1 Required Failure Demonstrations

You must deliberately break the setup in each of these 5 ways, observe what happens, and be
able to explain *why*. This is graded on understanding, not on the setup working perfectly —
the point is proving you know which layer each failure lives in.

For each one: do it, screenshot the output, write one or two sentences explaining it, save
into `evidence/failure-demos/`. Then **undo the change immediately** before moving to the
next test or the live demo.

---

## 1. Wrong DNS server configured on a client

**Setup:** On a client Mac, temporarily point DNS at something that doesn't have your
records (e.g. `8.8.8.8` only, or a nonexistent IP).

```bash
# See current DNS servers first (so you can restore them)
networksetup -getdnsservers Wi-Fi

# Set to a public resolver that has never heard of app.teamX.test
sudo networksetup -setdnsservers Wi-Fi 8.8.8.8

dig app.teamX.test          # expect: NXDOMAIN / no answer
ping <Mac2-actual-IP>       # expect: this still works! direct IP connectivity is fine
```

**Expected observation:** Name lookup fails (`dig` returns no answer / `NXDOMAIN`), but
`ping` to Mac 2's raw IP still succeeds. **Why:** DNS and IP-layer reachability are
completely independent. DNS failing doesn't mean the network is down — it means the
*directory service* that maps names to IPs is unreachable or doesn't have the record.

**Restore:**
```bash
sudo networksetup -setdnsservers Wi-Fi <Mac1-IP>
```

---

## 2. DNS record points to the wrong IP

**Setup:** On Mac 1, temporarily edit the dnsmasq config to point `app.teamX.test` at the
wrong machine (e.g. Mac 3's IP instead of Mac 2's), then restart dnsmasq.

```bash
# On Mac 1 — edit /opt/homebrew/etc/dnsmasq.conf (Apple Silicon) or
# /usr/local/etc/dnsmasq.conf (Intel), change the address= line temporarily, then:
sudo brew services restart dnsmasq
```

From a client:
```bash
dig app.teamX.test          # now resolves — but to the wrong IP
curl -k https://app.teamX.test/    # connects, but to the wrong service (cert/app mismatch)
```

**Expected observation:** DNS resolution *succeeds* and returns an answer — just the wrong
one. The client happily connects to the wrong machine. **Why:** DNS is a directory, not a
connection — it will confidently hand back whatever answer is configured, correct or not.
Nothing validates that the IP is "the right one" except your own configuration correctness.

**Restore:** put the correct IP back, restart dnsmasq.

---

## 3. One backend is stopped

```bash
# On Mac 3, stop backend A (Ctrl+C in its terminal, or:)
lsof -ti:3001 | xargs kill
```

From a client, repeat requests:
```bash
for i in $(seq 1 6); do curl -s https://app.teamX.test/api/status; echo; done
```

**Expected observation:** All responses now come from Backend B only (`"backend":"B"`).
nginx's default upstream behavior retries the next server in the pool when one connection
attempt fails, so the client sees no errors — just no more `"backend":"A"` in the mix.

**Restore:**
```bash
# On Mac 3
node server.js
```

---

## 4. Both backends are stopped

Stop Backend A (as above) **and** Backend B:
```bash
# On Mac 4
lsof -ti:3002 | xargs kill
```

From a client:
```bash
curl -v https://app.teamX.test/api/status
```

**Expected observation:** DNS still resolves fine, the TLS handshake still completes fine
(you'll see the padlock / successful handshake in `curl -v`) — but you get **`502 Bad
Gateway`** from nginx. **Why this matters for the viva:** this precisely shows where the edge
(Mac 2) ends and the backend begins. DNS worked, TCP worked, TLS worked — the failure is
purely at the application/upstream layer, and nginx is the one reporting it, not the backend
itself (the backend is dead, it can't report anything).

**Restore:** restart both backends (`node server.js` on Mac 3 and Mac 4).

---

## 5. Wrong destination port on the client

```bash
curl -v --connect-timeout 5 https://app.teamX.test:9999/
```

**Expected observation:** The host resolves fine (DNS worked) and the IP is reachable
(`ping` still works) — but the TCP connection to port 9999 hangs and times out /
connection-refused, because nothing is listening there. **Why:** an IP address gets you to a
*machine*; a port gets you to a specific *service* on that machine. They're independent
identifiers — a reachable host with the wrong port is not a reachable service.

---

## Quick summary table (bring this to the demo)

| Scenario | DNS | TCP/IP reachability | Result |
|---|---|---|---|
| Wrong DNS server on client | ❌ fails | ✅ still works | Proves DNS ≠ IP connectivity |
| DNS record → wrong IP | ✅ "succeeds" (wrongly) | ✅ connects to wrong host | Proves DNS is a directory, not a connection |
| One backend down | ✅ | ✅ | LB quietly routes around it |
| Both backends down | ✅ | ✅ (edge reachable) | 502 — isolates the failure to the app layer |
| Wrong port | ✅ | ✅ (host), ❌ (port) | Proves IP ≠ port/service |
