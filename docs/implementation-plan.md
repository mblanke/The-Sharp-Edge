# The Sharp Edge — re-theme + voice recipe capture

> Execution plan for the two docs in this folder. Approved 2026-07-25.

## Context

Two pieces of work on the household recipe app (FastAPI + SvelteKit web + native SwiftUI iOS,
`mblanke/The-Sharp-Edge`):

1. **Re-theme.** The app currently ships "washi & bottle green" (CLAUDE.md §7). The owner wants it
   to read as a professional French kitchen. Light theme only this pass.
2. **Add a recipe by voice.** Dictate a recipe standing in the kitchen — name, ingredients, method
   — landing on an editable draft, because dictation is never 100% right.

Design notes are already committed on `claude/theme-voice-recipe-input-f9wdov` (commit `ad080c7`):
`docs/theme-french-kitchen.md`, `docs/voice-recipe-capture.md`, `docs/palette-preview.html`,
`docs/README.md`. This plan is the execution layer on top of those.

**Palette decided: C · Faïence** — blue-and-white kitchen tile with an ochre mustard accent.

```
--paper #f4f3ee   --card #fdfcf8   --line #d9d7cd
--primary #1f4a8f --primary-deep #14315f
--accent #8a5e17  --ink #14161c    --faint #666a72   --off-white #f6f5ef
```

Measured contrast on `--paper`: accent 5.1:1 · primary 7.8:1 · faint 4.9:1 · off-white on
primary-deep 13.9:1. All meet WCAG AA for small text, which matters because the app sets 10–11px
uppercase mono labels. The accent is deliberately darker than a decorative ochre — the lighter
version lands at ~3.4:1 and fails.

## Part 1 — Re-theme

Do this first. It's mechanical, and step 2 is the prerequisite for any future dark mode.

### Step 1: rename the tokens

`--green`/`--green-deep` → `--primary`/`--primary-deep`; `--copper` → `--accent`. The names will
lie about their contents after any re-theme. Mechanical find-and-replace across `web/src/**`
(109 refs) and `ios/TheSharpEdge/DesignSystem/Theme.swift`.

### Step 2: tokenise the 16 stray literals

These bypass `tokens.css` today and would survive as leftovers of the old scheme. 12 of the 16
assume a light ground, which is exactly why dark mode is currently intractable.

| Literal | Count | Becomes | Representative paths |
|---|---|---|---|
| `#F4F3EC` | 9 | `--off-white` (mirrors existing `Theme.offWhite`, which web lacks) | `routes/+page.svelte:32,40,83`, `routes/r/[slug]/+page.svelte:63,79,185` |
| `rgba(255,255,255,.14\|.4)` | 3 | `--btn-ghost`, `--btn-outline` | `routes/r/[slug]/+page.svelte:85,94,102` |
| `#FBF0E6` | 1 | `--accent-wash` | `routes/r/[slug]/edit/+page.svelte:104` |
| `bg-white` | 8 | `--card` | `routes/r/[slug]/edit/+page.svelte` (form inputs) |

### Step 3: swap values, then the peripherals

`web/src/lib/tokens.css` and `Theme.swift` take the chosen palette. Then:
`ios/.../Assets.xcassets/AccentColor.colorset/Contents.json` (duplicates the primary, updated
separately), `web/src/app.html` `theme-color` meta, `web/static/manifest.webmanifest`,
`web/static/logo.svg` (4 fills), regenerated raster icons, `api/app/routers/recipes.py:180` QR
`fill_color`, and the palette block in CLAUDE.md §7.

Tailwind is v4 via the Vite plugin with **no config file and no `@theme` block** — tokens are plain
custom properties applied through inline `style=`. There are zero `<style>` blocks in any
`.svelte`. The token file really is the single lever.

## Part 2 — Add a recipe (manual), then voice on top

**No add-a-recipe UI exists on either client.** Web has no `/new` route; iOS `RecipeEditorView`
only edits existing recipes. `Endpoints.swift:30` defines `createRecipe()` and nothing calls it.
`POST /api/v1/recipes` itself exists and is covered by `api/tests/test_recipes_api.py`.

So the create path is built once, plainly, and voice becomes a way to *fill* it. Two shippable
stages — 2a is useful on its own and is the prerequisite for 2b.

### 2a — Add recipe, typed

**Extract the form first.** `web/src/routes/r/[slug]/edit/+page.svelte` is 351 lines of inline
form — metadata fields, ingredient rows (amount / unit `<select>` / name, with ↑/↓/✕ reorder),
step rows with timer-seconds, note rows. Lift it into `web/src/lib/components/RecipeForm.svelte`
taking an optional initial recipe and a mode flag, then:

- `/r/[slug]/edit` renders it populated (behaviour unchanged — verify against the existing screen)
- `/new` renders it empty, plus the slug field that edit doesn't need

`web/src/routes/new/+page.server.ts` mirrors the existing edit action: hidden JSON input,
`use:enhance`, server-side `createRecipe()` via `lib/api.ts`, `redirect(303, '/r/{slug}')`.
Add an "Add recipe" entry to `+layout.svelte`, which currently has exactly three links.

**iOS:** give `RecipeEditorView` a create mode, add the missing `RecipeCreate` Codable and
`createRecipe` on the `DataSource` protocol, and wire the already-defined `Endpoints.createRecipe()`.

### 2b — Voice as an input mode

Four dictated prompts — title (slug derived live beneath it), category (matched against
`CATEGORY_ORDER`, `web/src/lib/types.ts:64`), ingredients, method — which prefill the **same**
`RecipeForm` from 2a. Everything stays editable before saving; that review step is the entire
answer to imperfect dictation, not optional polish.

Reached from a mic button on `/new`, so there is one create path with two ways to fill it — no
parallel flow to keep in sync.

### Reuse, don't rewrite

`seed/import_master.py` `parse_ingredient()` (≈150–202) already handles unicode/ASCII ranges, mixed
fractions, `~` approximations, spelled-out units via `UNIT_MAP`, metric promotion, and
"Juice of 1 lime" → `{name: "lime, juiced"}`. Tested in `api/tests/test_import_master.py`.

**Promote it to `api/app/services/ingredients.py`**, expose `POST /api/v1/parse/ingredients`
taking `{lines: [str]}`, and keep the seed script importing from the new home so there is one copy.
Add a `normalise_spoken()` pre-pass in front of it — speech yields "two and a half pounds",
"a pinch of", "a quarter" — tested separately.

### Data model rules the parser must honour

From `api/app/schemas/recipe.py`: `amount == 0` means *to taste* (em dash, never scales) — map
"to taste"/"a pinch" onto `0`, never a guess. `unit == ""` means countable with the noun inside
`name`. `ALLOWED_UNITS` is declared but **not enforced by Pydantic**, so the voice path must
enforce it like the UIs do. `steps` are `{text, timer_seconds}` objects; leave the timer null.

### Slug — the irreversible bit

QR codes are printed against slugs; the `redirect` table exists precisely because renames must
never break them. **No slugify helper exists anywhere in the repo.** Write one beside the parser so
both clients get identical behaviour via the API: validate `^[a-z0-9][a-z0-9-]*$`, strip accents
("Vișinată" → `visinata`, matching existing data), show it in an edit field on review, and surface
the 409 collision as a fixable inline error.

### Client wiring

**Web:** `routes/api/[...path]/+server.ts` forwards only `content-type`, no `Authorization` — a
client-side POST gets 401. The parse endpoint can use the proxy (unauthenticated, like `/ask`), but
**every save must be a SvelteKit form action** where `env.API_TOKEN` is injected (`lib/api.ts:44`).
This applies to 2a as much as 2b. Capture via `SpeechRecognition` / `webkitSpeechRecognition`,
degrading to plain typing when unavailable — which is just 2a, so there is no fallback to build.

**iOS:** `SFSpeechRecognizer` + `AVAudioEngine`, `requiresOnDeviceRecognition` where supported.
Add `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` to `Info.plist`
(neither present).

Save as `status: "draft"` — an existing lever (the seeder uses it for `broccoli-slaw`, `visinata`)
that keeps half-dictated recipes out of the index. There is no DELETE endpoint, so an accidental
recipe is currently permanent; drafts soften that.

## Verification

- `cd api && pytest` — new tests for `normalise_spoken`, the promoted `parse_ingredient`, slugify
  (accents, collisions, the regex contract), and the parse endpoint. CLAUDE.md §13 requires a
  pytest per endpoint. Mock pattern to copy: `api/tests/test_ask.py:18-51`.
- `cd web && npm test && npm run build && npm run dev` — walk all five routes; nothing should render
  in bottle green.
- `rg -i '#[0-9a-f]{6}|rgba\(|bg-white' web/src --glob '!lib/tokens.css'` → expect no matches.
- `rg -i 'green|copper' web/src ios/TheSharpEdge` → no matches outside comments.
- Build iOS; confirm the home-screen icon tint picks up the new `AccentColor`.
- `GET /api/v1/recipes/{slug}/qr` still returns a scannable PNG.
- **Regression check after the form extraction:** `/r/{slug}/edit` must behave exactly as before —
  same fields, reorder buttons, unit whitelist, and append-a-version save. This is the riskiest
  refactor in the plan.
- Type a recipe end to end at `/new`, including a deliberate slug collision, and confirm the 409
  surfaces inline as a fixable error rather than a dead end.
- On a phone: dictate a real recipe, deliberately mis-say one quantity, confirm review catches it
  and the saved recipe scales. Confirm "to taste" lands as `amount: 0` and renders as an em dash.

## Notes for whoever executes

`web/src/lib/scaling.ts` mirrors `api/app/services/scaling.py` by hand with matching test tables —
any ingredient maths lands in both. Web has **no component tests and no Playwright** despite
CLAUDE.md §3 promising them, so keep voice logic in testable `.ts` modules outside components
rather than standing up a harness mid-feature.

## Out of scope

**Dark mode.** Zero infrastructure exists (`prefers-color-scheme`, `data-theme`, `dark:`,
`color-scheme` → no hits anywhere). Part 1 step 2 is the prerequisite; dark mode becomes tractable
afterwards as its own piece of work.

**`design_handoff_sharp_edge/`.** Byte-identical duplicates of the repo root, speccing an "Organic
design system" (terracotta/sage, Caprasimo/Figtree) that was never built. Stale and superseded —
not a target.

**Atlas / `LLM_ROUTER_URL`.** Pointing at `https://ai.guapo613.beer/v1` needs no code change — it's
already config (`api/app/config.py:19`). Neither workstream depends on it; the chosen voice
approach uses on-device speech and a deterministic parser, so no LLM is in the loop at all. Note
`RAG_API_URL` is a separate service on `:8099` needing its own hostname, and moving to `https://`
would let the iOS ATS cleartext exemption from `40e6a99` be reverted.
