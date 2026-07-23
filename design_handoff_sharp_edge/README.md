# The Sharp Edge — Build Spec for Claude Code

A pocket recipe master built to live beside a paper cookbook. Scan a QR code glued into the notebook, land on that exact recipe on your phone, scale it, cook.

**This bundle contains no prototype — it is a full product spec plus the complete recipe dataset (`recipes-data.js`). Build the app from scratch to this spec.** The deliverable is a **single self-contained HTML file** (inline CSS + JS + data; no build step, no dependencies, no accounts, no tracking). It must work opened from disk or any static host.

---

## Product principles

- **Paper is the permanent record; the screen is the calculator.** The notebook holds the canon — this holds the math. No editing, no adding recipes in-app.
- **Phone-first, kitchen-first.** One column, large touch targets (≥44px), quantities in high-contrast monospace type readable with flour on your hands. Fine on iPad/desktop (cap content width ~680px, centered).
- **QR deep links.** Each recipe is addressable by `#<recipe-id>` (ids in the data file, e.g. `#goulash`). Loading with a hash scrolls straight to that recipe with no interstitial. The printed cards already carry these anchors — **do not change the ids.**
- **Installable.** Include meta tags so add-to-home-screen opens full-screen like a native app: `viewport-fit=cover`, `apple-mobile-web-app-capable`, `apple-mobile-web-app-status-bar-style`, `theme-color: #f5ead8`, a `<title>` of "The Sharp Edge". Respect safe-area insets.

## Data

`recipes-data.js` (included) is the single source of truth: 19 recipes across 10 categories, plus a hidden-gluten guide.

```js
export const CATS = [/* ordered category names */];
export const RECIPES = [{
  id,          // stable slug — QR anchor target
  cat,         // one of CATS
  title,
  gf,          // true | false | "check" (GF with label caveats)
  gfNote,      // present when gf === "check"
  base,        // baseline yield number
  unit,        // yield unit label ("servings", "cups", "coins", …)
  meta,        // one-line yield/pairing note
  prov,        // optional provenance line (family recipe, source, version notes)
  ing: [       // ingredient rows:
    [qty, unit, name],      // qty: number | [lo,hi] range | null (to taste — never scales)
    ["H", "Section name"],  // section header row (e.g. "Salmon" / "Mango salsa")
  ],
  steps: [/* strings; some begin with a "Verb: " lead-in — render that lead-in bold */],
  notes: [/* optional strings */],
}];
export const GLUTEN_GUIDE = [{h: "Section", items: [/* strings */]}];
```

Inline this data into the final single file (or keep it as the one sibling module during dev and inline for the shipped artifact).

## Features

### 1. Index (top of page)
- App name + one-line tagline ("Scan a card, scale the dish, cook.").
- Recipes grouped by category in `CATS` order; each entry is one large tap target linking to `#<id>`.
- Each entry shows title + GF status (see badges below).
- **GF filter**: a toggle/segmented control — "All" / "GF" (shows `gf: true` and `gf: "check"` entries; hides `gf: false`). Persist choice in `localStorage`.
- A persistent **"↑ Index" floating button** (or sticky mini-header) on every recipe for one-tap return.

### 2. Recipe view (all recipes on one page, anchored sections)
Each recipe section renders:
- Title, category kicker, `meta` line, `prov` line (styled as a quiet footnote) when present.
- **GF badge**: `gf: true` → sage "GF" tag; `gf: "check"` → outlined "GF — check labels" tag with `gfNote` shown beneath; `gf: false` → no badge (optionally a neutral "contains gluten" note for Breakfast/pancakes).
- **Serving scaler**: stepper `− [n unit] +` scaling from `base`. Range 1–4× down/up sensibly (min 1, max ~4× base; step 1 for counts, sensible steps otherwise). All quantities re-render instantly.
- **Ingredients**: checkable list (tap row toggles a strikethrough/dim check state — ephemeral, resets on reload is fine). Quantity in **monospace, bold, high-contrast**, right-or-left aligned consistently; name in body type. Section header rows (`["H", …]`) render as small caps dividers, no checkbox.
- **Steps**: numbered. Bold any "Lead-in:" prefix.
- **Notes**: bulleted, visually quieter.
- **Ask Claude button**: opens `https://claude.ai/new?q=<encodeURIComponent(prompt)>` where the prompt embeds the recipe title, current scaled serving count, and full scaled ingredient list, e.g. "I'm cooking <title> for <n> <unit>. Ingredients: … Help me tweak, substitute, or troubleshoot."
- **Add to groceries** button (see §5).
- **Cook mode** button (see §4).

### 3. Scaling math — "kitchen-sane rounding" (the heart of the app)
Scale factor `f = current / base`. For each ingredient:
- `qty === null` → render name only, never scale ("to taste", "a drizzle").
- Range `[lo,hi]` → scale both ends, format as "lo–hi".
- **Volume units (tsp/tbsp/cup)**: render as kitchen fractions — snap to nearest of ⅛, ¼, ⅓, ½, ⅔, ¾ (use real Unicode vulgar fractions: ¼ ½ ¾ ⅓ ⅔ ⅛ ⅜ ⅝ ⅞). Promote units when sane: ≥3 tsp → tbsp conversion only if it lands on a clean fraction; 4 tbsp → ¼ cup, etc. Never output "0.75 cup" — always "¾ cup".
- **Weights (g, kg, ml, L, lb, oz)**: round to weighable numbers — g/ml: nearest 5 below 100, nearest 10 to 1000, nearest 25 above; kg/L/lb: 1 decimal max, drop trailing zero.
- **Counts (unit `""`, "can", "bag")**: round to nearest ¼ for things divisible (onions, lemons: "1½ onions"), but whole numbers for eggs/cans/bags (ceil to nearest ½ or 1 — use judgment: eggs whole, garlic cloves whole, limes halves OK).
- Numbers ≤ 2 may show halves/quarters; never show more than 2 significant decimals anywhere.
- Show the scale state near the stepper ("scaled from 6") when `f ≠ 1`.

Write unit tests-by-hand in a comment block or a dev-only console assert set for: ¾ cup × 2 = 1½ cups; 250 g × 1.5 = 375 g; 3.5 tsp × 2 = 2 tbsp + 1 tsp or 7 tsp → "2⅓ tbsp" (pick cleanest); null stays null.

### 4. Cook mode
Full-screen overlay, one step at a time:
- Step text huge (≥28px), current step number / total, big prev/next tap zones (left/right halves or fat buttons).
- Ingredients accessible via a pull-up/accordion within cook mode (scaled quantities).
- Keep-awake: request a screen wake lock (`navigator.wakeLock.request('screen')`) with graceful fallback.
- Exit button top corner. Progress persists per-recipe in `localStorage` while cooking.

### 5. Groceries list
- "Add to groceries" on each recipe adds its **currently-scaled** ingredient list (skipping `null` and header rows) to a persistent list in `localStorage`.
- A groceries view (slide-over or anchored section reachable from the index) shows items grouped by recipe, checkable, with clear-all and per-recipe remove.
- **Export**: "Share / copy" button — `navigator.share` when available, else copy plain text to clipboard: one item per line, grouped under recipe headings.

### 6. Hidden-gluten reference card
Render `GLUTEN_GUIDE` as its own anchored card (`#gluten-guide`), linked from the index and from every `gf: "check"` badge. Three sections (grill, pantry traps, goulash checkpoints) as list groups.

## Design — Organic design system (binding)

Tokens (inline these; the shipped file must be self-contained — copy values, load Google Fonts via `<link>`):

- Fonts: **Caprasimo** (headings, weight 400) over **Figtree** (body 400/600/700). Quantities: any good monospace stack (`ui-monospace, "SF Mono", Menlo, monospace`) — bold, `--color-text`.
- Ground `#f5ead8`, surface `#ebddc5`, text `#201e1d`, accent (terracotta) `#c67139`, accent-2 (sage) `#7a8a5e`.
- Accent ramp: 100 `#fff2eb`, 200 `#ffe1d0`, 300 `#ffc6a5`, 400 `#f6a06b`, 500 `#d67f48`, 600 `#b2622d`, 700 `#8c491a`, 800 `#643312`, 900 `#402310`.
- Sage ramp: 100 `#f0fae1`, 200 `#e1eecc`, 300 `#ccdbb2`, 400 `#aebf92`, 500 `#8fa073`, 600 `#728157`, 700 `#56633f`, 800 `#3d472b`, 900 `#272e1b`.
- Neutral ramp: 100 `#f9f4ed` … 900 `#2e2b25` (300 `#dcd3c4`, 500 `#a19786`, 700 `#645c50`).
- Radii: sm 8px, md 16px, lg 28px; buttons/inputs are **pills** (`border-radius: 999px`).
- Spacing scale: 4.4 / 8.8 / 13.2 / 17.6 / 26.4 / 35.2 px.
- Shadows: sm `0 1px 2px rgba(46,43,37,.14)`, md `0 3px 10px rgba(46,43,37,.16)`, lg `0 12px 32px rgba(46,43,37,.22)`.
- Icons: Lucide, stroke-width 2.75 (inline the few SVGs needed: plus, minus, chevrons, cart, flame/chef-hat, x, share, check).

Usage rules:
- Warm, rounded, a little playful. Left-aligned asymmetric layout; whitespace right.
- Recipe sections are `.card`-style surfaces (`#ebddc5`, radius-lg, shadow-sm).
- Primary actions (stepper, Ask Claude): terracotta fill, white text; hover/pressed one ramp step darker (600). GF tags: sage 200 fill / 800 text. "Check labels": sage outline.
- Accent as **text** only at ramp 700+ on this ground (contrast). Focus: `outline: 2px solid #c67139; outline-offset: 2px` — never default blue.
- Disabled: 45% opacity. `::selection` accent tint.
- No sharp corners, no grey desaturation, no emoji, no other display faces.

## State & storage

`localStorage` keys (namespace `sharpedge.*`): `sharpedge.gfFilter`, `sharpedge.groceries` (JSON), `sharpedge.scale.<id>` (persist per-recipe scale), `sharpedge.cookpos.<id>`. All optional-graceful if storage unavailable.

## Acceptance checklist

- [ ] Opens from `file://` with no console errors; single file.
- [ ] `#goulash` (and every other id) deep-links correctly on load.
- [ ] Goulash 6 → 14: 2 lb beef → 4.7 lb; 3 tbsp paprika → 7 tbsp; "to taste" rows unchanged; fractions render as vulgar-fraction glyphs.
- [ ] GF filter hides pancakes only; persists across reloads.
- [ ] Cook mode: one step per screen, wake lock attempted, position survives reload.
- [ ] Groceries: add two scaled recipes, share/copy produces grouped plain text.
- [ ] Every tap target ≥44px; quantities monospace bold; Lighthouse a11y contrast passes.
- [ ] Ask Claude opens claude.ai with the scaled ingredient list embedded.

## Files in this bundle

- `README.md` — this spec.
- `recipes-data.js` — complete dataset: 19 recipes, 10 categories, gluten guide. Source of truth; do not re-transcribe from elsewhere.
