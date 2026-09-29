# Task A — Establish the Private LAN

Do this together, all 4 people in the same room, before anything else. Nothing else in this
project works until every machine can ping every other machine.

## 1. Connect every Mac to the same network

Use one shared network for all 4 laptops:
- Lab Wi-Fi, or
- One person's phone hotspot, or
- A home router — anything works, as long as all 4 machines are on the same subnet.

## 2. Record each machine's network info

On **every** Mac, run:

```bash
# Active interface + IPv4 address
ipconfig getifaddr en0   # try en0 first; if empty, try en1 (Wi-Fi is usually en0 on Mac laptops)

# Full details: IP, subnet mask, interface name
ifconfig en0 | grep -E 'inet |ether'

# Default gateway
netstat -rn -f inet | grep default

# Or all-in-one:
networksetup -getinfo Wi-Fi
```

Fill this in as a team (this table **is** your Architecture Document's IP/service table —
keep it in this file and commit it):

| Machine | Person | Role | IPv4 Address | Subnet Mask/Prefix | Gateway | Interface | MAC Address |
|---|---|---|---|---|---|---|---|
| Mac 1 | | DNS Server | | | | | |
| Mac 2 | | Edge/LB/TLS | | | | | |
| Mac 3 | | Backend A | | | | | |
| Mac 4 | | Backend B + Client | | | | | |

Get the MAC address from `ifconfig en0 | grep ether`.

## 3. Verify reachability — ping every pair

From each machine, ping the other three:

```bash
ping -c 4 <other-mac-ip>
```

Run this 12 times total (4 machines × 3 targets each, or 6 unique pairs checked from both
sides). Save terminal output/screenshots into `evidence/` — this is part of your Phase 1
evidence folder ("Confirm all machines are on the private LAN" is demo step 2).

If ping fails between two specific machines:
- Check both are actually on the same SSID/network (not one on Wi-Fi, one on Ethernet, on
  different subnets).
- Check macOS Firewall isn't blocking ICMP: System Settings → Network → Firewall → Options.
  Either turn the firewall off for the demo, or allow incoming connections for the relevant
  apps.

## 4. Topology diagram

This is a straight line, not a mesh — clients never talk to backends directly, everything
goes through Mac 2.

```
                         ┌─────────────────────────┐
                         │   Mac 1 — DNS Server     │
                         │   dnsmasq :53            │
                         │   app.teamX.test → Mac2  │
                         │   api.teamX.test → Mac2  │
                         └────────────┬─────────────┘
                                      │ (1) DNS query
                                      │
   ┌───────────────┐   (2) HTTPS :443/8443   ┌──────────────────────────┐
   │  Client        │ ───────────────────────▶│   Mac 2 — Edge / LB      │
   │  (Mac 1 or     │ ◀─────────────────────── │   nginx: TLS termination │
   │   Mac 4)        │      HTTPS response      │   round-robin upstream  │
   └───────────────┘                           └──────┬─────────┬────────┘
                                                        │(3)      │(3)
                                          ┌─────────────▼──┐  ┌───▼─────────────┐
                                          │ Mac 3           │  │ Mac 4            │
                                          │ Backend A       │  │ Backend B        │
                                          │ Node.js :3001   │  │ Node.js :3002    │
                                          └─────────────────┘  └──────────────────┘
```

All 4 machines also sit on the same LAN segment (same Wi-Fi router), which is what makes
step (1)'s DNS query and steps (2)/(3)'s TCP connections possible in the first place — draw
that flat LAN as the "backing" of the diagram in your actual submission (a single switch/AP
icon with all 4 laptops hanging off it), then overlay the request-flow arrows above it.

Redraw this (by hand, in draw.io, Excalidraw, or similar) with your real IPs filled in for
the Architecture Document deliverable — a text diagram is fine for this repo, but bring a
clean visual one to the demo.
