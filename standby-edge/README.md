# Standby Edge — Mac 4 (Akshay) — Phase 2 Extension E

A second nginx with the same configuration and the **same certificate** as Mac 2,
so the public entry point can be migrated between machines by changing DNS alone.

Mac 4 ends up running two things, which is worth saying out loud in the viva:

```
:3002   Backend B      (application server)
:443    standby nginx  (edge)
```

## Setup (prepare, but do NOT start it until the demo)

```bash
./scripts/set-ips.sh
sudo cp standby-edge/nginx-standby.conf /opt/homebrew/etc/nginx/servers/cn-project.conf
sudo mkdir -p /opt/homebrew/etc/nginx/certs
# copy fullchain.pem + privkey.pem from Mac 2 -- the SAME cert, not a new one
sudo nginx -t
```

## During the demo

```bash
sudo brew services start nginx                     # Mac 4
# on Mac 1:  ./scripts/dns-cutover.sh to-standby
# on a client: ./scripts/test-edge-cutover.sh      # watch served-by flip
# on Mac 1:  ./scripts/dns-cutover.sh to-primary   # roll back
```

## Why TLS survives the move

The certificate is issued to the **name** `app.cn_team.test`, not to a machine or
an IP. Both edges present the same certificate and the client validates the name
it asked for, so nothing about trust is tied to where the service runs.

## What this does and does not solve

It removes the edge as a *permanent* single point of failure, but the cutover is
manual and is only as fast as the DNS TTL. Real high availability would use
multiple live edges behind one name, or a floating IP a standby claims
automatically.
