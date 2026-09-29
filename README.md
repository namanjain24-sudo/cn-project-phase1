# Private Network Service Platform — Phase 1

Computer Networks course project. 4 machines, 4 roles, one private service reachable over
HTTPS through a private DNS name, load-balanced across two backends, with full packet
evidence of DNS → TCP → TLS → HTTP.

**This repo currently covers Phase 1 only** ("Build & Observe"). Phase 2 ("Harden &
Recover") is not started — do that after Phase 1 is demoed and passed.

Core principle from the spec: *the application stays simple, the network is the project.*
Don't over-engineer the backends — the marks are for the networking, not the code.

## 0. Before you touch anything: pick your team domain

The whole project uses a private domain name `app.teamX.test` / `api.teamX.test`. Pick your
actual team number/name (e.g. `team7`) and replace every occurrence of `team1` in this repo
with it. One command does it everywhere (run from the repo root, on any machine, before
copying files out):

```bash
grep -rl 'team1\.test' . --exclude-dir=.git | xargs sed -i '' 's/team1\.test/team7.test/g'
```

Replace `team7` with your real team name. Do this **once**, commit it, then everyone pulls
the updated repo.

## 1. Who does what — the 4 roles

| Machine | Person | Role | Runs | Folder | Represents |
|---|---|---|---|---|---|
| **Mac 1** | Person A | Private DNS Server + Test Client | dnsmasq | [`mac1-dns/`](mac1-dns/) | Managed DNS (Route 53) |
| **Mac 2** | Person B | Edge / Reverse Proxy + Load Balancer + TLS | nginx | [`mac2-edge/`](mac2-edge/) | Cloud LB / CDN edge |
| **Mac 3** | Person C | Backend Server A | Node.js on :3001 | [`mac3-backend-a/`](mac3-backend-a/) | App server instance A |
| **Mac 4** | Person D | Backend Server B + Test Client | Node.js on :3002 | [`mac4-backend-b/`](mac4-backend-b/) | App server instance B |

Request flow: `Client → DNS query (Mac 1) → HTTPS (Mac 2 / nginx) → Backend A (Mac 3) or Backend B (Mac 4)`

**Everyone should clone the whole repo**, but each person's daily work lives in their own
folder. `docs/` and `scripts/` are shared — read them together as a team before the demo,
because the individual viva (10 marks) tests whether you understand the *whole* system, not
just your own machine.

## 2. Order of operations (do these in sequence, as a team)

You need all 4 laptops on the same Wi-Fi/LAN before any of this works.

1. **Task A — LAN setup** (everyone, together first): see [`docs/topology.md`](docs/topology.md).
   Get every machine's IP, ping each other, fill in the IP table. **Do this first** — nothing
   else works until every machine can ping every other machine.
2. **Task B — DNS** (Person A, Mac 1): [`mac1-dns/README.md`](mac1-dns/README.md)
3. **Task C — Backends** (Person C on Mac 3, Person D on Mac 4, can happen in parallel with
   step 2): [`mac3-backend-a/README.md`](mac3-backend-a/README.md), [`mac4-backend-b/README.md`](mac4-backend-b/README.md)
4. **Task D + E — Edge, load balancing, TLS** (Person B, Mac 2, needs Mac 3/4 IPs from step 3
   and needs to happen after step 2 partially): [`mac2-edge/README.md`](mac2-edge/README.md)
5. **Task F — Caching** — already built into the backend code (see step 3 READMEs +
   [`scripts/test-cache.sh`](scripts/test-cache.sh)).
6. **Task G — Capture everything in Wireshark** — see [`docs/evidence-checklist.md`](docs/evidence-checklist.md).
7. **Failure demos (§6.3)** — see [`docs/failure-demos.md`](docs/failure-demos.md).

Realistic dependency order: **Mac 1 (partial DNS record for Mac 2) → Mac 3 & Mac 4 in
parallel → Mac 2 (needs Mac 3/4 IPs) → Mac 1 (finish DNS pointing at Mac 2) → everyone tests.**

## 3. What "done" looks like (Phase 1 gate)

From the spec: *Phase 1 is complete when a client resolves `app.teamX.test`, connects over
HTTPS, and receives responses from both backends through the load balancer.*

Concretely, from any client Mac, this must all work with **no `-k` flag** (i.e. the TLS cert
is actually trusted):

```bash
dig app.team7.test                       # resolves to Mac 2's IP via your DNS
curl -sI https://app.team7.test/          # no cert warning
for i in $(seq 1 6); do curl -s https://app.team7.test/api/status; echo; done
# ^ should alternate "backend":"A" and "backend":"B"
```

## 4. Repo layout

```
CN_project/
├── README.md                  ← you are here
├── docs/
│   ├── topology.md            ← Task A: IP inventory + topology diagram template
│   ├── protocol-flow.md       ← OSI/TCP-IP mapping, TLS handshake, viva prep notes
│   ├── failure-demos.md       ← §6.3 mandatory failure scenarios, exact commands
│   └── evidence-checklist.md  ← Task G + Section 9 deliverables checklist
├── mac1-dns/                  ← Person A: dnsmasq config + setup commands
├── mac2-edge/                 ← Person B: nginx config, TLS cert script, setup commands
├── mac3-backend-a/            ← Person C: backend A source + setup commands
├── mac4-backend-b/            ← Person D: backend B source + test-client commands
├── scripts/                   ← shared test scripts, run from any client machine
└── evidence/                  ← screenshots, curl output, Wireshark captures go here
```

## 5. Marks this repo is aimed at (Review 1, Phase 1 — 50 marks)

| Area | Marks | Covered by |
|---|---|---|
| LAN + Private DNS (Task A+B) | 10 | `docs/topology.md`, `mac1-dns/` |
| Backends + Reverse Proxy + LB (Task C+D) | 10 | `mac3-backend-a/`, `mac4-backend-b/`, `mac2-edge/` |
| HTTPS/TLS (Task E) | 8 | `mac2-edge/`, `docs/protocol-flow.md` |
| Packet Analysis (Task G) | 7 | `docs/evidence-checklist.md` |
| HTTP Caching (Task F) | 5 | backend `/api/data` endpoint, `scripts/test-cache.sh` |
| Individual viva | 10 | know the *whole* system — read every README, not just your own |

## 6. Getting this into GitHub (do this once, as the team lead)

This folder is already its own local git repo with one commit (the Phase 1 scaffold). You
just need to create the GitHub repo and push:

```bash
cd /Users/naman./Desktop/CN_project
gh repo create <your-repo-name> --private --source=. --remote=origin
git push -u origin main
```

If you don't have `gh` (GitHub CLI): create an empty repo on github.com first (**don't**
initialize it with a README/license — this folder already has one), then:

```bash
git remote add origin https://github.com/<your-username>/<your-repo-name>.git
git branch -M main
git push -u origin main
```

**This repo is already live and pushed:** https://github.com/namanjain24-sudo/cn-project-phase1
(private). Add your 3 teammates as collaborators: Settings → Collaborators on that repo page.
Each of them then runs:

```bash
git clone https://github.com/namanjain24-sudo/cn-project-phase1.git
cd cn-project-phase1
```

Everyone should `git pull` before starting work each session, and commit+push their own
folder's progress (config files, screenshots into `evidence/`) as they go.
