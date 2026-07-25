# docs/

Design notes for work that is planned but not yet built. Each doc states its own status.

| Doc | What it covers | Status |
|---|---|---|
| [`theme-french-kitchen.md`](theme-french-kitchen.md) | Re-theme to a "professional French kitchen" palette | **Decided: C · Faïence.** Ready to build |
| [`palette-preview.html`](palette-preview.html) | The three candidate palettes on a real recipe screen — open in a browser | Reference; C was chosen |
| [`voice-recipe-capture.md`](voice-recipe-capture.md) | Add a recipe — typed form first, voice on top | Designed, not built |
| [`implementation-plan.md`](implementation-plan.md) | Approved execution plan across both | Approved, not started |

## Decisions already made

Don't re-open these; they were settled deliberately.

- **Palette: C · Faïence** — tile blue `#1f4a8f` / deep `#14315f`, ochre accent `#8a5e17`, on a
  `#f4f3ee` ground. Contrast-checked to WCAG AA; the accent is deliberately darker than a
  decorative ochre because the lighter version fails at the 10–11px label sizes the app uses.
- **Light theme only** this pass. Dark mode is explicitly out of scope, but tokenising the 16 stray
  colour literals (theme doc, step 2) is its prerequisite and happens now.
- **Add recipe is two stages, one form.** A plain typed form at `/new` first, then voice as a way
  to fill that same form. Not two parallel flows — the "editable draft" voice needs *is* the
  add-recipe form.
- **Voice uses on-device speech recognition and a deterministic parser.** No LLM in the loop.
- **Slug is auto-generated from the title and confirmed before save.** It can never change
  afterwards; QR codes are printed against it.

## Picking up this work in a fresh session

Both docs name the files to change, the constraints that will bite, and how to verify — they're
written to be executed without the conversation that produced them.

Start with the theme. It's mechanical, self-contained, and its step 2 unblocks dark mode later.
The two workstreams are otherwise independent.

## Atlas / deployment

`LLM_ROUTER_URL` currently points at the Tailscale IP `http://100.110.190.10:4000/v1`. Pointing it
at `https://ai.guapo613.beer/v1` needs **no code change** — it's already config
(`api/app/config.py:19`, `.env.example:23`), and `RouterProvider` only assumes an OpenAI-compatible
`/chat/completions` with a bearer token, so the `cluster` alias keeps balancing Wile + RoadRunner.

Two notes if that switch happens: `RAG_API_URL` is a separate service on `:8099` and needs its own
hostname, and moving to `https://` would let the iOS ATS cleartext exemption added in `40e6a99` be
reverted.

Neither the theme work nor the add-recipe work depends on any of this.

### Reaching Atlas from a Claude Code cloud session

Recorded because it cost a session to work out. A cloud sandbox is **not** a member of the tailnet,
so `100.110.190.10` is unreachable from one — the egress gateway intercepts it and returns
`403 x-deny-reason: private_dest_ip`. Port 443 appears open, but the TLS certificate is issued by
`Anthropic Egress Gateway SDS Issuing CA`, not by Atlas; the connection never leaves Anthropic's
network. Reachability over a VPN is not transitive, however reachable Atlas is from an iPad.

What *is* true: the sandbox has `/dev/net/tun`, `NET_ADMIN`, and working UDP, so joining the tailnet
is mechanically possible. The blocker is the environment's egress allowlist, which defaults to
**Trusted** and denies both `*.guapo613.beer` and `login.tailscale.com`. To make a cloud session
work with Atlas:

1. Environment → **Network access** → **Custom** with `*.guapo613.beer` and `*.tailscale.com`
   (keep the default package-manager list ticked), or just **Full**.
2. An ephemeral, tagged, short-expiry Tailscale auth key, supplied via environment secrets — never
   pasted into a session transcript.
3. A fresh session for the setting to take effect.

Simpler alternative: run the work from the local CLI on a machine already on the tailnet, where
none of the above applies.
