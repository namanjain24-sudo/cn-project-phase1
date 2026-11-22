# Backup DNS Resolver — Mac 3 (Hemanth) — Phase 2 Extension A

A second authoritative resolver carrying the **same records** as Mac 1, so that
stopping dnsmasq on Mac 1 does not stop name resolution for the whole team.

## Setup

```bash
./scripts/set-ips.sh                                       # generates dnsmasq-backup.conf
sudo cp backup-dns/dnsmasq-backup.conf /opt/homebrew/etc/dnsmasq.conf
sudo brew services restart dnsmasq
dig @127.0.0.1 app.cn_team.test                            # must match Mac 1's answer exactly
```

Then on **every client**, list both resolvers, primary first:

```bash
sudo networksetup -setdnsservers Wi-Fi <MAC1_IP> <MAC3_IP>
```

## Demonstrating it

```bash
./scripts/test-dns-failover.sh     # before: both answer
# on Mac 1:  sudo brew services stop dnsmasq
./scripts/test-dns-failover.sh     # after: primary dead, names still resolve
# on Mac 1:  sudo brew services start dnsmasq
```

## The point

If the two resolvers ever disagree, failover silently sends clients to a
different machine — which is worse than having no backup at all. Both configs are
generated from `config/ips.env`, so they cannot drift apart by accident.

macOS tries the resolvers in order and falls back when the first does not
answer. Because a stopped dnsmasq leaves the port closed, the machine replies
ICMP port-unreachable and the fallback is fast rather than waiting for a timeout.
