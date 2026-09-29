# Phase 1 Video Submission — Shot List & Script

**This course's Phase 1 deliverable is a recorded video, not a live viva.** That changes one
thing in practice: since no evaluator can stop you and ask a question in person, the video
itself has to do the job the viva would have done — so **every person must speak on camera
and explain their own component in their own words**, not just show a terminal silently
working. Assume the person grading this is watching for two things: (1) does the system
actually work end-to-end, (2) can each teammate clearly explain the part they built. Both
need to be visible in the recording.

## Before you record

- **Tool:** QuickTime Player (free, built into macOS) → File → New Screen Recording. Or OBS
  if you want to combine multiple machines' screens into one view.
- **Audio:** use a real mic if possible (AirPods are fine) — muffled laptop-mic narration
  over a terminal demo is the single biggest way these videos lose marks for clarity.
- **Terminal setup:** bump your terminal font size up (`Cmd +` a few times) before recording
  — small monospace text is unreadable on a compressed video export.
- **Do a full dry run first** without recording. Confirm DNS, TLS, load balancing, and
  caching all actually work before you hit record — don't debug live on camera.
- **Length:** aim for 10–15 minutes total. Long enough to show everything in the checklist
  below, short enough that nobody's watching you type for 3 minutes in silence.

## Recording approach: 4 short screen recordings, then stitch

Each person records their own screen (their own machine, their own voice) doing their own
task. Combine the 4 clips in order afterward (iMovie, or even just `ffmpeg -f concat`) into
one final video. This is much easier logistically than trying to get 4 laptops in frame at
once, and it naturally makes sure everyone actually appears and explains their own part.

---

## Scene 1 — Topology & LAN (whoever wants to open — 1–2 min)

Maps to Demo Steps 1–2 in the spec.

- Show the topology diagram (`docs/topology.md`, redrawn nicely) on screen, narrate the 4
  roles and the request flow in one sentence each.
- Show the filled-in IP table.
- Run `ping` between a couple of machine pairs on screen, narrate: "this proves all 4 Macs
  are reachable on the same LAN before anything else can work."

## Scene 2 — DNS resolution (Person A, Mac 1 — 2 min)

Maps to Demo Step 3.

- On camera: "I'm running dnsmasq, our team's private DNS server, on this machine."
- Show `dnsmasq.conf` briefly (the `address=` lines).
- Run `dig app.teamX.test` from a **client** machine (not Mac 1 itself) — narrate: "this
  resolves to Mac 2's IP, `<ip>`, using our own DNS server, not a public one."
- One sentence distinguishing DNS resolution from the connection that follows it (this is
  explicitly called out in the spec as something you should be able to explain).

## Scene 3 — HTTPS, TLS, and load balancing (Person B, Mac 2 — 3–4 min)

Maps to Demo Steps 4–5.

- "I run nginx as the single entry point — clients never talk to the backends directly."
- Open `https://app.teamX.test/` in a browser on camera — **point at the padlock, no
  warning**. Say out loud: "no `-k` flag, no bypassed certificate — this is a properly
  trusted TLS connection."
- Run `../scripts/test-lb.sh` (or manual repeated `curl`s) — narrate as `X-Backend: A` and
  `X-Backend: B` alternate: "this proves nginx is round-robining across both backends, and
  the client never needs to know either backend's IP."
- Briefly narrate the TLS handshake steps from memory (ClientHello → ServerHello →
  Certificate → Key Exchange → Finished) — this is the single most-asked-about concept, make
  sure whoever owns Mac 2 can say this without reading it off screen.

## Scene 4 — Backends, caching, and packet evidence (Person C + Person D — 3–4 min)

Maps to Demo Steps 6–7, plus Task F.

- Person C or D: "here's our backend code — deliberately simple, a REST API with two
  endpoints and a caching demo." Show `server.js` briefly, point at the `X-Backend` header
  and the `/api/data` cache logic.
- Run `../scripts/test-cache.sh` on camera — narrate the difference between the first
  request (200, fresh) and the second (304, conditional, no body).
- Open the saved Wireshark capture (`evidence/tcp-tls-handshake/`) — narrate, pointing at:
  the DNS query/response, the TCP SYN/SYN-ACK/ACK, the TLS handshake messages, and finally
  the encrypted `Application Data` packets. Say explicitly: **"you can see the handshake
  happened, but you cannot read the HTTP headers here — that's TLS doing its job."**

## Scene 5 — Failure demos (split across whoever owns each layer — 3–4 min)

Maps to §6.3 — this is where "explain your reasoning, not just that it worked" matters most.
Pick at least 3 of the 5 scenarios in `docs/failure-demos.md` to actually show on camera (all
5 if you have time); for each one, the pattern is the same:

1. State what you're about to break and why (which layer it tests).
2. Break it on screen.
3. Show the resulting behavior (`dig`, `curl`, `ping` output).
4. Say **in your own words** why that happened — this is literally graded on methodology,
   not on things going wrong being scary. A calm, correct explanation of a "failure" is worth
   more than a silent success.
5. Undo it, confirm the system is healthy again, move on.

Strongly recommend including scenario #4 (both backends down → 502) since it's the cleanest
one-sentence demonstration of "DNS worked, TLS worked, only the app layer failed."

## Scene 6 — Wrap-up (whoever, 30 sec)

- One sentence recap of the full request path, DNS → TCP → TLS → HTTP → load balancer →
  backend.
- State clearly this is Phase 1 only, and what Phase 2 will add (resilience/failover) — shows
  the evaluator you understand this is a staged build, not that you forgot something.

---

## Checklist before you export/submit

- [ ] Every one of the 4 people speaks on camera and explains at least their own component
- [ ] No `-k` / cert-bypass flags visible anywhere in the final cut
- [ ] X-Backend alternating shown clearly (A and B both visible)
- [ ] Wireshark capture shown with DNS + TCP handshake + TLS handshake pointed out
- [ ] Caching 200 → 304 shown
- [ ] At least 3 of the 5 failure scenarios shown, each with a spoken explanation
- [ ] Video is under whatever length limit your faculty gave you (check the assignment
  portal/instructions — the spec PDF doesn't state one, so confirm separately)
- [ ] Export and also keep the raw screen recordings + this video in `evidence/` or wherever
  your faculty wants it submitted (Drive link, LMS upload, etc.)
