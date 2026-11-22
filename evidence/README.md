# Evidence Index

Spec §9: *"The evaluator should be able to find any piece of evidence within 30 seconds."*
Every file is named `<nn>-<machine>-<what>`, so who produced it is visible at a glance.

| Machine | Person | Role |
|---|---|---|
| Mac 1 | Naman | primary DNS |
| Mac 2 | Harsha | edge / nginx / TLS / load balancer |
| Mac 3 | Hemanth | Backend A :3001 + backup DNS + firewall |
| Mac 4 | Akshay | Backend B :3002 + standby edge + firewall |

## Phase 1

| Folder | What is in it |
|---|---|
| `dns/` | dnsmasq install + config, resolution after restart, both clients using Mac 1, ping matrix, `dig @8.8.8.8` NXDOMAIN |
| `load-balancing/` | backends confirmed, end-to-end HTTPS success, A/B alternation, recovery after a backend slept |
| `caching/` | `Cache-Control` + `ETag`, conditional request → 304 |
| `tcp-tls-handshake/` | Wireshark `.pcapng` + packet-by-packet analysis of DNS, TCP handshake, TLS handshake |
| `http-headers/` | *(empty — covered by the `curl -v` output inside `load-balancing/`)* |
| `edge/` | nginx config validation, including the cert-path bug and its fix |
| `failure-demos/` | all five §6.3 scenarios |

## Phase 2

| Folder | Extension | What is in it |
|---|---|---|
| `phase2/00-lan-reachability-*.txt` | Task A | all four machines pinged, 0% loss, backend reachable across the LAN |
| `phase2/00-preflight-config-check-*.txt` | all | dry run of every Phase 2 config and script before the demo, with measurements |
| `phase2/backup-dns/` | **A** | second resolver on Mac 3, record and TTL matching the primary |
| `phase2/ttl/` | **B** | `local-ttl=30` live (Phase 1 served 0), record change and cache expiry |
| `phase2/isolation/` | **C** | pf rules loaded, backend ports unreachable from a client, edge still working |
| `phase2/ha-failover/` | **D** | one backend stopped, all requests still served, latency measured |
| `phase2/edge-cutover/` | **E** | DNS repointed to the standby edge, TTL lag visible |
| `phase2/troubleshooting/` | **F** | faults found and diagnosed layer by layer |
