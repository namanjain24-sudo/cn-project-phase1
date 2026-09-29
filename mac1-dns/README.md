# Mac 1 — Private DNS Server + Test Client (Task B)

You run the team's private DNS resolver using `dnsmasq`. This is the "AWS Route 53" of the
project — every other machine asks you to translate `app.teamX.test` into Mac 2's IP.

**Prerequisite:** Task A done — you know your own IP and Mac 2's IP
(`docs/topology.md`).

## 1. Install dnsmasq

```bash
brew install dnsmasq
```

## 2. Configure it

```bash
cd mac1-dns
cp dnsmasq.conf.template dnsmasq.conf
```

Edit `dnsmasq.conf` and replace:
- `team1.test` → your real team domain
- `<MAC2_IP>` → Mac 2's actual LAN IP (the edge/nginx machine — DNS should point here, since
  clients connect to Mac 2, not directly to backends)
- `<MAC1_IP>` → this machine's own LAN IP

Copy it into place (path differs by chip):

```bash
# Apple Silicon:
cp dnsmasq.conf /opt/homebrew/etc/dnsmasq.conf
# Intel:
cp dnsmasq.conf /usr/local/etc/dnsmasq.conf
```

## 3. Start dnsmasq

Port 53 needs root, so start it with `sudo`:

```bash
sudo brew services start dnsmasq
```

To apply a config change later without a full restart:
```bash
sudo brew services restart dnsmasq
```

Check it's actually listening:
```bash
sudo lsof -i :53
```

## 4. Test locally on Mac 1 first

```bash
dig @127.0.0.1 app.team1.test
dig @127.0.0.1 api.team1.test
```

Both should return Mac 2's IP in the `ANSWER SECTION`. If this fails, dnsmasq isn't running
or the config has a typo — fix this before touching any other machine.

## 5. Point client machines at this DNS server

On **at least two other Macs** (the spec requires it — do it on all of them for the real
demo): System Settings → Network → Wi-Fi → Details → DNS → add this Mac's IP, **as the first
entry**, above any existing DNS servers.

Or from the terminal on each client machine:
```bash
networksetup -setdnsservers Wi-Fi <MAC1_IP>
```

(Note down what `networksetup -getdnsservers Wi-Fi` showed *before* you changed it, so it's
easy to restore afterwards.)

## 6. Verify from a client machine

```bash
dig app.team1.test
nslookup app.team1.test
```

Should resolve to Mac 2's IP without needing `@127.0.0.1` — proving the client is actually
using your DNS server as its default resolver, not just querying it manually.

## 7. Never use raw IPs in the demo

Once DNS works, always access the service as `https://app.team1.test/...` — never type Mac
2's IP directly. Typing the IP defeats the entire point of this task.

## Troubleshooting

- **Port 53 already in use**: something else (rarely, an old dnsmasq/mDNSResponder
  instance) is bound. Check with `sudo lsof -i :53` and kill the conflicting process, or
  reboot.
- **dig from another Mac hangs/fails but works locally**: check macOS Firewall on Mac 1
  isn't blocking incoming UDP 53 (System Settings → Network → Firewall), and check
  `listen-address` includes Mac 1's real LAN IP, not just `127.0.0.1`.
- Remember: **don't use `.local`** as your domain suffix — it conflicts with macOS's built-in
  Bonjour/mDNS. Stick to `.test`.
