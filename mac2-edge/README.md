# Mac 2 — Edge / Reverse Proxy / Load Balancer / TLS (Tasks D + E)

You run nginx as the **single public entry point**. Clients only ever talk to you — never
directly to Mac 3 or Mac 4. You terminate TLS and round-robin requests across both backends.

**Prerequisite:** Mac 3 and Mac 4 are running and you know their IPs (`docs/topology.md`).

## 1. Install nginx

```bash
brew install nginx
```

Find your config location (differs by chip):
```bash
nginx -V   # look at the --conf-path in the output, or just check:
ls /opt/homebrew/etc/nginx/    # Apple Silicon
ls /usr/local/etc/nginx/       # Intel
```

## 2. Generate the TLS certificate (Task E)

Recommended: install `mkcert` first — it handles trust-store installation automatically on
this machine:
```bash
brew install mkcert nss   # nss needed if you also use Firefox
```

Then from this folder:
```bash
cd mac2-edge
chmod +x generate-cert.sh
./generate-cert.sh app.cn_team.test api.cn_team.test
```

(Replace `cn_team.test` with your real domain.) This creates `certs/fullchain.pem` and
`certs/privkey.pem`. If `mkcert` isn't installed, the script automatically falls back to a
plain OpenSSL self-signed cert instead — either is acceptable per the spec.

## 3. Install the config

```bash
cp nginx.conf.template nginx.conf
```

Edit `nginx.conf`: replace `cn_team.test`, `<MAC3_IP>`, `<MAC4_IP>` with your real values.

Homebrew's nginx auto-includes anything in its `servers/` folder, so drop your config there:
```bash
# Apple Silicon:
cp nginx.conf /opt/homebrew/etc/nginx/servers/cn-project.conf
# Intel:
cp nginx.conf /usr/local/etc/nginx/servers/cn-project.conf
```

**If you're using the 8080/8443 fallback ports**, comment out or delete the default
`server { listen 8080; ... }` block in the main `nginx.conf` (the top-level one Homebrew
installed) first — otherwise you'll get a port conflict on 8080.

**If you're using 80/443**, you'll need `sudo` to start nginx (ports below 1024 require
root):

## 4. Start nginx

```bash
sudo nginx -t                # validates config syntax first — fix any errors it reports
sudo brew services start nginx
# or, to restart after a config change:
sudo nginx -s reload
```

## 5. Test locally on Mac 2 first

```bash
curl -sI https://app.cn_team.test/ --resolve app.cn_team.test:443:127.0.0.1
```

(The `--resolve` flag fakes DNS locally so you can test before Mac 1's DNS is even involved.)
You should see a `200`/`301` response with no `-k` needed if you used mkcert (it auto-trusts
on this machine). If you used the OpenSSL fallback, trust the cert here too:
```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain certs/fullchain.pem
```

## 6. Trust the certificate on EVERY other client machine

This step is what makes the demo curl/browser work **without `-k`** — required by the spec.

**If you used mkcert:** copy the root CA to every other Mac and trust it there:
```bash
# On Mac 2, find the CA root file:
mkcert -CAROOT
# copy that folder's rootCA.pem to each other Mac (AirDrop, scp, USB, whatever), then on
# EACH other machine:
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain rootCA.pem
```

**If you used the OpenSSL fallback:** copy `certs/fullchain.pem` to every other Mac and run
the same `security add-trusted-cert` command there, pointed at that file.

## 7. Verify load balancing (Task D)

Once DNS (Mac 1) is also pointed at your IP, from any client:
```bash
for i in $(seq 1 6); do curl -s https://app.cn_team.test/api/status; echo; done
```
You should see `"backend":"A"` and `"backend":"B"` alternating. Also check the header:
```bash
curl -sI https://app.cn_team.test/api/status | grep -i x-backend
```

## Troubleshooting

- **`nginx: [emerg] bind() to 0.0.0.0:443 failed (13: Permission denied)`** — you forgot
  `sudo`, or use the 8080/8443 fallback instead.
- **502 Bad Gateway** — nginx can't reach a backend. Check Mac 3/Mac 4 are actually running
  (`curl http://<MAC3_IP>:3001/` from Mac 2 directly) and that the IPs in `nginx.conf` are
  correct and current (LAN IPs can change if a laptop reconnects to Wi-Fi).
- **Certificate warning in browser/curl** — the CA wasn't trusted on that specific client
  machine (step 6 is per-machine, not automatic).
- **Only ever seeing one backend** — check both Mac 3 and Mac 4 are actually up; if one
  crashed, nginx will silently favor the other (this is expected — it's also §6.3 failure
  demo #3).
