# Private Network Service Platform — Phase 1 + Phase 2

Computer Networks course project. 4 machines, 4 roles, one private service reachable over
HTTPS through a private DNS name, load-balanced across two backends, with full packet
evidence of DNS → TCP → TLS → HTTP.

**Phase 1 ("Build & Observe") is complete and Phase 2 ("Harden & Recover") is
built.** Phase 2 extends the same network — nothing was rebuilt. Start here:

| If you want to... | Read |
|---|---|
| Run the demo tomorrow | **[`docs/phase2-runbook.md`](docs/phase2-runbook.md)** — start at §0 |
| Prepare for the individual viva | **[`docs/phase2-viva.md`](docs/phase2-viva.md)** |
| Hand in the Phase 2 report | **[`docs/phase2-report.md`](docs/phase2-report.md)** |
| Know what was measured and proven | [`evidence/phase2/00-preflight-config-check-2026-11-22.txt`](evidence/phase2/00-preflight-config-check-2026-11-22.txt) |
| Fix an IP that changed | edit [`config/ips.env`](config/ips.env), run `./scripts/set-ips.sh` |
| Work out why something is broken | `./scripts/diagnose.sh` |

Core principle from the spec: *the application stays simple, the network is the project.*
Don't over-engineer the backends — the marks are for the networking, not the code.

## 0. Team domain

This team has no assigned team number, so the private domain is set to:

```
app.cn_team.test
api.cn_team.test
```

This is already applied throughout every config template and script in this repo — nothing
to edit for this step. (Note: DNS labels conventionally use hyphens, not underscores, but
`cn_team.test` is a private `.test` domain used only by your own dnsmasq/nginx/curl/browser —
underscores work fine there. If you ever hit a tool that specifically rejects the underscore,
the one-line fix is: `grep -rl 'cn_team\.test' . --exclude-dir=.git | xargs sed -i '' 's/cn_team\.test/cn-team.test/g'`.)

## 1. Who does what — the 4 roles

| Machine | Person | Role | Runs | Folder | Represents |
|---|---|---|---|---|---|
| **Mac 1** | Naman | Private DNS Server + Test Client | dnsmasq | [`mac1-dns/`](mac1-dns/) | Managed DNS (Route 53) |
| **Mac 2** | Harsha | Edge / Reverse Proxy + Load Balancer + TLS | nginx | [`mac2-edge/`](mac2-edge/) | Cloud LB / CDN edge |
| **Mac 3** | Hemanth | Backend Server A | Node.js on :3001 | [`mac3-backend-a/`](mac3-backend-a/) | App server instance A |
| **Mac 4** | Akshay | Backend Server B + Test Client | Node.js on :3002 | [`mac4-backend-b/`](mac4-backend-b/) | App server instance B |

Request flow: `Client → DNS query (Mac 1) → HTTPS (Mac 2 / nginx) → Backend A (Mac 3) or Backend B (Mac 4)`

**Everyone should clone the whole repo**, but each person's daily work lives in their own
folder. `docs/` and `scripts/` are shared — read them together as a team before recording,
because the video is graded on whether you understand the *whole* system, not just your own
machine — see §7 below, **there's no live viva for Phase 1, the deliverable is a recorded
video**, and each person needs to speak on camera about their own part.

## 1b. Phase 2 roles (each person owns one extension)

| Extension | Spec | Owner | Machine | Files |
|---|---|---|---|---|
| **A** Backup DNS resolver | §7.1 A | Hemanth | Mac 3 | [`backup-dns/`](backup-dns/) |
| **B** DNS TTL + record change | §7.1 B | Naman | Mac 1 | [`mac1-dns/dnsmasq-phase2.conf`](mac1-dns/), [`scripts/test-ttl.sh`](scripts/test-ttl.sh) |
| **C** Service isolation (firewall) | §7.1 C | Hemanth + Akshay | Mac 3, Mac 4 | [`firewall/`](firewall/) |
| **D** HA failover | §7.1 D | Harsha | Mac 2 | [`mac2-edge/nginx-phase2.conf`](mac2-edge/) |
| **E** Edge migration via DNS | §7.1 E | Akshay + Naman | Mac 4, Mac 1 | [`standby-edge/`](standby-edge/), [`scripts/dns-cutover.sh`](scripts/dns-cutover.sh) |
| **F** Troubleshooting challenge | §7.1 F | everyone | any | [`scripts/diagnose.sh`](scripts/diagnose.sh) |

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
8. **Record the video** — see [`docs/video-script.md`](docs/video-script.md). This is the
   actual Phase 1 submission for this course (no live viva) — everything above is prep for
   this recording.

Realistic dependency order: **Mac 1 (partial DNS record for Mac 2) → Mac 3 & Mac 4 in
parallel → Mac 2 (needs Mac 3/4 IPs) → Mac 1 (finish DNS pointing at Mac 2) → everyone tests.**

## 3. Submission format: video, not live viva

This course's Phase 1 evaluation is a **recorded video walkthrough** — there's no live
demo/viva session. That means the video has to carry the weight the viva normally would:
every person must appear on camera and narrate their own component (not just silently type
commands), and you need to actually explain *why* things work, not just show that they do.
Full shot-list and script: [`docs/video-script.md`](docs/video-script.md). Read the general
spec's marks breakdown in §5 below as "what this video needs to prove," not as a literal live
grading session.

## 4. What "done" looks like (Phase 1 gate)

From the spec: *Phase 1 is complete when a client resolves `app.teamX.test`, connects over
HTTPS, and receives responses from both backends through the load balancer.*

Concretely, from any client Mac, this must all work with **no `-k` flag** (i.e. the TLS cert
is actually trusted):

```bash
dig app.cn_team.test                       # resolves to Mac 2's IP via your DNS
curl -sI https://app.cn_team.test/          # no cert warning
for i in $(seq 1 6); do curl -s https://app.cn_team.test/api/status; echo; done
# ^ should alternate "backend":"A" and "backend":"B"
```

## 5. Repo layout

```
CN_project/
├── README.md                  ← you are here
├── docs/
│   ├── topology.md            ← Task A: IP inventory + topology diagram template
│   ├── protocol-flow.md       ← OSI/TCP-IP mapping, TLS handshake, talking-point notes
│   ├── failure-demos.md       ← §6.3 mandatory failure scenarios, exact commands
│   ├── evidence-checklist.md  ← Task G + Section 9 deliverables checklist
│   └── video-script.md        ← Phase 1 video shot-list & script (the actual submission)
│   ├── phase2-runbook.md      ← PHASE 2: the demo-day sequence (open this on the day)
│   ├── phase2-report.md       ← PHASE 2: the Final Report deliverable
│   └── phase2-viva.md         ← PHASE 2: individual viva prep
├── config/ips.env             ← SINGLE SOURCE OF TRUTH for every IP
├── mac1-dns/                  ← Naman: dnsmasq (Phase 1 + Phase 2 configs)
├── mac2-edge/                 ← Harsha: nginx, TLS cert script (Phase 1 + Phase 2 configs)
├── mac3-backend-a/            ← Hemanth: backend A source
├── mac4-backend-b/            ← Akshay: backend B source
├── backup-dns/                ← PHASE 2 Ext A: second resolver, runs on Mac 3
├── standby-edge/              ← PHASE 2 Ext E: standby nginx, runs on Mac 4
├── firewall/                  ← PHASE 2 Ext C: pf rules + enable/disable/rollback
├── scripts/                   ← shared test + diagnosis scripts, run from any machine
└── evidence/                  ← Phase 1 evidence + evidence/phase2/
```

## 6. Marks this repo is aimed at (Review 1, Phase 1 — 50 marks per the general spec)

The spec below assumes a live viva; for this course, the "Individual viva" row is instead
graded from how well each person explains their part **in the video** (see
`docs/video-script.md`).

| Area | Marks | Covered by |
|---|---|---|
| LAN + Private DNS (Task A+B) | 10 | `docs/topology.md`, `mac1-dns/` |
| Backends + Reverse Proxy + LB (Task C+D) | 10 | `mac3-backend-a/`, `mac4-backend-b/`, `mac2-edge/` |
| HTTPS/TLS (Task E) | 8 | `mac2-edge/`, `docs/protocol-flow.md` |
| Packet Analysis (Task G) | 7 | `docs/evidence-checklist.md` |
| HTTP Caching (Task F) | 5 | backend `/api/data` endpoint, `scripts/test-cache.sh` |
| Individual understanding | 10 | shown via each person's narration in the video, not a live viva |

## 7. Getting this into GitHub (do this once, as the team lead)

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
