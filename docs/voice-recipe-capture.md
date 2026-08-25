# Add a recipe — typed, then by voice

Status: **designed, not built.** Decisions locked; implementation not started.

## Why

Adding a recipe today means either `POST /api/v1/recipes` by hand or editing `seed/import_master.py`.
There is no way to add one from either app.

Two things are wanted, and they are one feature:

1. **Add a recipe** — a plain form, reachable from the nav.
2. **Add a recipe by voice** — dictate it standing in the kitchen ("what's it called",
   "ingredients", "method") and land on an editable draft, because dictation is never 100% right.

They share a screen. The "editable draft" that voice needs *is* the add-recipe form, so building
them separately would mean two forms to keep in sync. Build the form once; make voice a way to fill
it. That also means the degraded path when speech recognition is unavailable is simply stage 2a,
with no fallback UI to write.

## The headline finding

**There is no "add a recipe" UI anywhere in the product today.** Not on web, not on iOS. The only
authoring surface is the *edit* screen for a recipe that already exists.

- Web routes are `/`, `/r/[slug]`, `/r/[slug]/edit`, `/library`, `/ask`. There is no `/new` and no
  "+ Add" in `+layout.svelte`.
- iOS `RecipeEditorView` only edits an existing `RecipeFull`. Tellingly,
  `Networking/Endpoints.swift:30` defines `func createRecipe() -> URL?` and **nothing calls it** —
  there's no `RecipeCreate` Swift struct and no `createRecipe` on the `DataSource` protocol.

So this is "build add-a-recipe, with voice as one way to fill it", not "bolt a mic onto a form".
`POST /api/v1/recipes` itself already exists and is covered by `api/tests/test_recipes_api.py`.

## Decisions

| Question | Decision |
|---|---|
| Scope | **Typed form first (2a), voice on top of it (2b)** — one shared form, not two |
| Platform | **Both** web and iOS |
| Transcription | **Browser / OS speech-to-text**, guided prompts, on-device |
| LLM involvement | **None.** Deterministic parser, not a model |
| Slug | **Auto-generate from the title, show for confirmation** before save |

Speech never leaves the device, and there is no new backend dependency. That also sidesteps the
tier firewall in `api/app/services/llm.py` entirely.

## Stage 2a — Add recipe, typed

Ships on its own, and is the prerequisite for voice.

**Extract the form first.** `web/src/routes/r/[slug]/edit/+page.svelte` is 351 lines of inline form
— metadata fields, ingredient rows (amount / unit `<select>` / name with ↑/↓/✕ reorder), step rows
with timer-seconds, note rows. Lift it into `web/src/lib/components/RecipeForm.svelte` taking an
optional initial recipe and a mode flag:

- `/r/[slug]/edit` renders it populated — **behaviour must be unchanged**
- `/new` renders it empty, plus the slug field that edit doesn't need

`web/src/routes/new/+page.server.ts` mirrors the existing edit action: hidden JSON input,
`use:enhance`, server-side `createRecipe()` via `lib/api.ts`, `redirect(303, '/r/{slug}')`.
Add an "Add recipe" entry to `+layout.svelte`, which currently has exactly three links.

This extraction is the riskiest change in the feature — the edit screen is the only working
authoring surface in the product, and it must come out the other side identical.

**iOS:** give `RecipeEditorView` a create mode, add the missing `RecipeCreate` Codable and a
`createRecipe` method on the `DataSource` protocol, and wire the already-defined
`Endpoints.createRecipe()`.

## Stage 2b — Voice as an input mode

Reached from a mic button on `/new`. Four prompts, each dictated, each landing in an editable field:

1. **"What's the recipe called?"** → title. Slug is derived live and shown underneath.
2. **"What category?"** → matched against `CATEGORY_ORDER` (`web/src/lib/types.ts:64`), picker as fallback.
3. **"What are the ingredients?"** → one utterance per line, or a continuous take split on pauses.
4. **"What are the instructions?"** → one utterance per step.

These prefill the **same `RecipeForm`** from 2a, where everything stays editable before saving.
One create path, two ways to fill it — no parallel flow to keep in sync.

## Reuse — do not write a new parser

`seed/import_master.py` already turns free text into structured ingredients. `parse_ingredient()`
(≈lines 150–202) handles unicode and ASCII ranges, mixed fractions (`1 1/2`), `~` approximations, a
`UNIT_MAP` of spelled-out words (`tablespoons`→`tbsp`, `pounds`→`lb`), metric promotion
(`kg`→`g ×1000`), "Juice of 1 lime" → `{name: "lime, juiced"}`, and the fallback where an
unrecognised word after a number joins the name (`"1 can diced tomatoes"`). It is tested in
`api/tests/test_import_master.py`.

**Promote it to `api/app/services/ingredients.py`** and expose it as
`POST /api/v1/parse/ingredients` taking `{lines: [str]}`. Today it lives in `seed/` and isn't
importable — the test loads it via a path hack. Keep the seed script importing from the new home so
there's one copy.

Spoken input needs a small pre-pass the printed-text parser doesn't: numbers arrive as words ("two
and a half pounds"), and "half" / "a quarter" / "a pinch of" are common. Add a
`normalise_spoken()` in front of `parse_ingredient()`, tested separately.

## Data model constraints to respect

From `api/app/schemas/recipe.py`:

- `amount == 0` means **"to taste"** — renders as an em dash and never scales. Map "to taste",
  "a pinch", "season to taste" onto `0`, not onto a guess.
- `unit == ""` means **countable**, with the counting noun inside `name` — `{amount: 2, unit: "",
  name: "lemons"}`, never `unit: "lemons"`.
- `ALLOWED_UNITS = {"g","ml","cup","tbsp","tsp","lb","oz",""}` is a closed set. Note it is
  **declared but not enforced** by Pydantic — `unit` is a plain `str`, so the API will happily
  accept "pinch". The UIs enforce it via `<select>` / `Picker`; the voice path must too.
- `steps` are objects `{text, timer_seconds}`, not strings. Voice fills `text`; leave
  `timer_seconds` null and let the review screen set it.
- Bold lead-ins use a `**Verb:**` prefix convention.

## Slug — the one irreversible decision

Slug immutability is the hardest constraint in the codebase: QR codes are printed against it,
there's a `redirect(old_slug → slug)` table specifically because renames must never break them, and
CLAUDE.md §5 plus DECISIONS.md both reinforce it.

**No slugify helper exists anywhere** (`slugify|toSlug|generateSlug` → zero hits). Write one, put it
next to the parser so web and iOS get identical behaviour via the API, and:

- validate against the API's own `^[a-z0-9][a-z0-9-]*$`
- strip accents — "Vișinată" → `visinata`, which is exactly what the existing data does
- show it prominently on the review screen with an edit field
- check for collision before save and surface the 409 as a fixable inline error, not a toast

## Web wiring — the gotcha

`web/src/routes/api/[...path]/+server.ts` is a same-origin proxy that forwards **only**
`content-type` — no `Authorization`. A client-side `fetch('/api/recipes', {method: 'POST'})` reaches
the API unauthenticated and gets a 401.

So: the parse endpoint can go through the proxy (it needs no auth, like `/ask`), but **every save
must be a SvelteKit form action**, where `env.API_TOKEN` is injected server-side by
`web/src/lib/api.ts:44`. This applies to the typed form in 2a as much as to voice. Clone the
pattern in `web/src/routes/r/[slug]/edit/+page.server.ts` — hidden JSON input, `use:enhance`,
`redirect(303, '/r/{slug}')`.

Capture uses the Web Speech API (`SpeechRecognition` / `webkitSpeechRecognition`). It must degrade
to plain typing when unavailable — that's not a fallback, it's the same form.

## iOS wiring

`SFSpeechRecognizer` + `AVAudioEngine`, with `requiresOnDeviceRecognition` where supported.
Needs `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` in `Info.plist`
(neither is present today). Then the missing plumbing: a `RecipeCreate` Codable struct, a
`createRecipe` method on the `DataSource` protocol, and an `APIClient` implementation wiring up the
already-defined `Endpoints.createRecipe()`.

## Suggested landing state

Save as `status: "draft"` rather than `"active"`. It's an existing lever — the seeder already uses
it for `broccoli-slaw` and `visinata` — and it keeps half-dictated recipes out of the main index
until reviewed on a bigger screen. There is no DELETE endpoint, so a recipe created by accident is
currently permanent; drafts soften that.

## Verification

- `cd api && pytest` — new tests for `normalise_spoken`, the promoted `parse_ingredient`, slugify
  (accents, collisions, the `^[a-z0-9][a-z0-9-]*$` contract), and the parse endpoint. Per CLAUDE.md
  §13 every endpoint gets a pytest. Mock pattern to copy: `api/tests/test_ask.py:18-51`.
- `cd web && npm test` — vitest for the client-side slug preview and utterance splitting.
- **Regression check after the form extraction (2a):** `/r/{slug}/edit` must behave exactly as
  before — same fields, reorder buttons, unit whitelist, append-a-version save. It is the only
  working authoring surface in the product; this is the riskiest change in the feature.
- Type a recipe end to end at `/new`, including a deliberate slug collision, and confirm the 409
  surfaces inline as a fixable error rather than a dead end.
- Manual, on a phone: dictate a short real recipe end to end, deliberately mis-say one quantity,
  confirm the review screen catches it and the saved recipe scales correctly.
- Confirm `to taste` dictation lands as `amount: 0` and renders as an em dash, not `0 g`.

## Note for whoever builds this

`web/src/lib/scaling.ts` is a hand-maintained mirror of `api/app/services/scaling.py`, with matching
vitest/pytest tables. Any ingredient maths has to land in both. There are currently **no component
tests and no Playwright** in web despite CLAUDE.md §3 promising them, so there's no existing harness
for testing a multi-step Svelte flow — budget for standing one up, or keep the logic in testable
`.ts` modules outside the components.
