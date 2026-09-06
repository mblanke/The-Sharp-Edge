# docs/

Design notes. Each doc states its own status; the table is the summary. The engineering
log that explains *why* things are the way they are is `DECISIONS.md` at the repo root.

| Doc | What it covers | Status |
|---|---|---|
| [`theme-french-kitchen.md`](theme-french-kitchen.md) | Re-theme to a "professional French kitchen" palette | **Built.** iOS is on C · Faïence (`Theme.swift`); the web ships the washi / bottle-green tokens with Faïence aliases (DECISIONS 2026-08-24) |
| [`palette-preview.html`](palette-preview.html) | The three candidate palettes on a real recipe screen — open in a browser | Reference; C was chosen |
| [`voice-recipe-capture.md`](voice-recipe-capture.md) | Add a recipe — typed form first, voice on top | **Built** (`/new`, `web/src/lib/voice.ts`, `ios/…/Capture/`) — plus photo, URL and library-passage import since |
| [`implementation-plan.md`](implementation-plan.md) | Execution plan across both | Executed |
| [`atlas-runbook.md`](atlas-runbook.md) | Operating the RAG stack on Atlas | Live |

## Decisions already made

Don't re-open these; they were settled deliberately.

- **Palette: C · Faïence** — tile blue `#1f4a8f` / deep `#14315f`, ochre accent `#8a5e17`, on a
  `#f4f3ee` ground. Contrast-checked to WCAG AA; the accent is deliberately darker than a
  decorative ochre because the lighter version fails at the 10–11px label sizes the app uses.
- **Both colour schemes ship.** The web has a header toggle (and cook mode defaults to kitchen-dark
  in the evening); iOS follows the OS. Every colour is a token — there are no stray literals left.
- **Add recipe is two stages, one form.** A plain typed form at `/new` first, then voice as a way
  to fill that same form. Not two parallel flows — the "editable draft" voice needs *is* the
  add-recipe form.
- **Voice uses on-device speech recognition and a deterministic parser.** No LLM in the loop.
- **Slug is auto-generated from the title and confirmed before save.** It can never change
  afterwards; QR codes are printed against it.

## Picking up work in a fresh session

The theme and add-recipe docs are kept as the record of what was decided and why; both are
built. Open work lives in `DECISIONS.md` (dated entries, newest last) and the plan for the
current polish pass; the retrieval eval (`api/tests/test_retrieval_eval.py`) is the gate for
anything that touches search.

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
