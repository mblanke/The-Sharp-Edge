# docs/

Design notes for work that is planned but not yet built. Each doc states its own status.

| Doc | What it covers | Status |
|---|---|---|
| [`theme-french-kitchen.md`](theme-french-kitchen.md) | Re-theme to a "professional French kitchen" palette | Awaiting palette choice (A/B/C) |
| [`palette-preview.html`](palette-preview.html) | The three candidate palettes on a real recipe screen — open it in a browser | Companion to the above |
| [`voice-recipe-capture.md`](voice-recipe-capture.md) | Add a recipe by dictating it | Designed, not built |

## Picking up this work in a fresh session

Both docs are written to be executable without the conversation that produced them: they name the
files to change, the constraints that will bite, and how to verify. Start with the theme — it's
mechanical, and step 2 of it (tokenising the stray colour literals) is a prerequisite for any
future dark mode.

The two are independent; neither blocks the other.

## Open configuration question

`LLM_ROUTER_URL` currently points at the Tailscale IP `http://100.110.190.10:4000/v1`. Pointing it
at `https://ai.guapo613.beer/v1` needs no code change — it's already config
(`api/app/config.py:19`, `.env.example:23`) and `RouterProvider` only assumes an OpenAI-compatible
`/chat/completions` with a bearer token, so the `cluster` alias keeps balancing Wile + RoadRunner.

Two things to note if that switch happens: `RAG_API_URL` is a separate service on `:8099` and
would need its own hostname, and moving to `https://` would let the iOS ATS cleartext exemption
added in `40e6a99` be reverted.

Neither the theme work nor the voice work depends on this.
