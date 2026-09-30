# Phase 1 Video Submission — Shot List & Script (with exact commands)

**This course's Phase 1 deliverable is a recorded video, not a live viva.** That means the
video itself has to do the job the viva would have done — so **every person must speak on
camera and explain their own component in their own words**, not just show a terminal
silently working. Copy-paste the commands below exactly, but say the "SAY THIS" lines in your
own words, not word-for-word — sounding like you're reading a script is worse than sounding a
bit rough but genuine.

## Before you record

- **Tool:** QuickTime Player (already on every Mac) → File → New Screen Recording → red
  record button → pick your screen → click to start.
- **Audio:** speak clearly, close to the mic. Test one 10-second recording first and play it
  back before doing the real take.
- **Terminal font size:** bump it up first (`Cmd +` a few times) — small text is unreadable
  once the video is compressed.
- **Do a silent dry run of your commands first**, without recording, so you're not debugging
  live on camera.
- Each person records their own clip separately, on their own machine. They get combined into
  one final video afterward (iMovie, or ask if you want help stitching them).

Wherever a command below has `<...>` in it, replace it with the real value from
[`docs/topology.md`](topology.md) (everyone's current IP).

---

## Scene 1 — Topology & LAN (Naman — 1–2 min)

**SHOW:** the topology diagram from `docs/topology.md` (open the file, or redraw it on paper/
a slide first — up to you) and the filled-in IP table.

**SAY:** "This is our network — 4 laptops, 4 roles. Mac 1 is DNS, Mac 2 is the edge/load
balancer with HTTPS, Mac 3 and Mac 4 are the two backend servers. A client asks Mac 1 for the
address, then talks to Mac 2, which forwards to Mac 3 or Mac 4."

**RUN THIS on screen** (proves all 4 machines can reach each other):
```bash
ping -c 4 10.7.11.169   # Harsha's Mac
ping -c 4 10.7.12.33    # Hemanth's Mac
ping -c 4 10.7.1.139    # Akshay's Mac
```
**SAY:** "This proves all 4 machines are on the same network before anything else can work."

---

## Scene 2 — DNS resolution (Naman — 2 min)

**SAY:** "I'm running dnsmasq, our team's private DNS server, on this machine — this is the
same role AWS Route 53 plays in the cloud."

**RUN THIS:**
```bash
cat /opt/homebrew/etc/dnsmasq.conf
```
**SAY (while pointing at the `address=` lines):** "This record says `app.cn_team.test` should
resolve to Mac 2's IP address — that's Harsha's machine, the edge server."

**RUN THIS:**
```bash
dig app.cn_team.test
```
**SAY (pointing at the ANSWER SECTION):** "This proves the name resolves to Mac 2's IP using
our own DNS server, not a public one like Google's. DNS only translates the name to an IP —
it doesn't open any connection by itself, that happens in the next step."

---

## Scene 3 — HTTPS, TLS, and load balancing (Harsha — 3–4 min)

**SAY:** "I run nginx — the single entry point for the whole system. Clients never talk to
the backend servers directly, only to me."

**RUN THIS** (open in a browser, or run this in terminal):
```bash
curl -vI https://app.cn_team.test/
```
**SAY (point at the terminal or the browser padlock):** "No `-k` flag, no certificate
warning — this is a properly trusted TLS connection, not a bypassed one."

**RUN THIS** (from this repo's `scripts/` folder, on any client machine):
```bash
cd scripts
./test-lb.sh
```
**SAY (as A and B alternate on screen):** "This proves nginx is round-robin load balancing
across both backend servers — the client never needs to know either backend's IP address."

**SAY (from memory, no notes — this is the single most commonly asked question):** "The TLS
handshake goes: ClientHello, where the client proposes what encryption it supports; ServerHello,
where I pick one; Certificate, where I send my cert and the client checks it's trusted; Key
Exchange, where we agree on a shared secret; then Finished — after that, everything is
encrypted."

---

## Scene 4 — Backends, caching, and packet evidence (Hemanth + Akshay — 3–4 min)

**Hemanth or Akshay, SAY:** "Here's our backend code — deliberately simple, just a REST API
with two endpoints, since the network is what's being graded, not the app."

**RUN THIS** (from your own backend folder, e.g. `mac3-backend-a` or `mac4-backend-b`):
```bash
cat server.js
```
**SAY (point at the `X-Backend` header and the `/api/data` route):** "Every response carries
an `X-Backend` header so we can see which server answered. This one endpoint also supports
caching."

**RUN THIS** (from `scripts/`):
```bash
./test-cache.sh
```
**SAY (as the output scrolls):** "The first request is a fresh 200 with a `Cache-Control`
header and an ETag. The second request sends that ETag back with `If-None-Match`, and the
server replies `304 Not Modified` with no body — that's a conditional request, saving
bandwidth because the content hasn't changed."

**Then, whoever captured the Wireshark trace, RUN/SHOW THIS** (open the saved capture file
from `evidence/tcp-tls-handshake/`):
- Point at the DNS query and response packet.
- Point at the TCP SYN → SYN-ACK → ACK sequence.
- Point at the TLS ClientHello → ServerHello → Certificate → Finished messages.
- Point at the `Application Data` packets that follow.

**SAY:** "You can see the handshake happened step by step, but from here on you cannot read
the actual HTTP headers or content in the capture — that's TLS doing its job. The connection
is proven, but the data inside it is encrypted."

---

## Scene 5 — Failure demos (split across whoever owns each layer — 3–4 min)

Full details and exact commands for all 5 scenarios: [`docs/failure-demos.md`](failure-demos.md).
Pick at least 3 to show on camera. For each: say what you're breaking and why, break it, show
the result, explain why in your own words, then fix it. Recommended picks:

**Naman — wrong DNS server on a client:**
```bash
networksetup -getdnsservers Wi-Fi          # note the current value first (for Naman's Mac
                                            # right now this says "There aren't any DNS
                                            # Servers set" — i.e. automatic/DHCP)
sudo networksetup -setdnsservers Wi-Fi 8.8.8.8
dig app.cn_team.test                        # SAY: fails / no answer
ping 10.7.11.169                            # SAY: but this still works!
sudo networksetup -setdnsservers Wi-Fi empty   # restore to automatic (what it was before)
```
**SAY:** "DNS failed, but direct IP connectivity still works — this proves DNS and IP
reachability are independent layers."

**Hemanth or Akshay — one backend stopped:**
```bash
# On Mac 3 (or Mac 4), stop the server: Ctrl+C in its terminal, or:
lsof -ti:3001 | xargs kill      # (use :3002 on Mac 4)
```
Then, from a client:
```bash
cd scripts && ./test-lb.sh
```
**SAY:** "Now only one backend answers — nginx quietly routed around the dead one, the client
never saw an error." Then restart the server (`node server.js`) to fix it.

**Harsha — both backends stopped:**
```bash
# after both Mac 3 and Mac 4 servers are stopped
curl -v https://app.cn_team.test/api/status
```
**SAY:** "DNS still resolved, TLS still handshaked fine — but now we get a 502 Bad Gateway.
This proves exactly where the edge ends and the application layer begins." Then have Hemanth/
Akshay restart their servers.

---

## Scene 6 — Wrap-up (whoever, 30 sec)

**SAY:** "To recap: a request goes DNS, then TCP, then TLS, then HTTP, then the load balancer
picks a backend. This was Phase 1 — Build and Observe. Phase 2 will add resilience: backup
DNS, failover, and firewall isolation between the edge and the backends."

---

## Checklist before you export/submit

- [ ] All 4 people speak on camera and explain their own component
- [ ] No `-k` / cert-bypass flags visible anywhere in the final cut
- [ ] X-Backend alternating shown clearly (A and B both visible)
- [ ] Wireshark capture shown with DNS + TCP handshake + TLS handshake pointed out
- [ ] Caching 200 → 304 shown
- [ ] At least 3 of the 5 failure scenarios shown, each with a spoken explanation
- [ ] Check your faculty's length limit (not stated in the spec PDF — confirm separately)
- [ ] Keep the raw clips + final video somewhere safe (Drive/LMS) in addition to submitting
