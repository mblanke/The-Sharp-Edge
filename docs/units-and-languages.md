# Unit conversion and multi-language ingest

> Status: **investigated, not scheduled.** Neither is designed to the depth of the theme or
> add-recipe docs — this records the findings and the traps so the questions don't have to be
> re-answered from scratch.

Two questions raised while scoping the voice work. They look similar and are not: one is a display
concern with the groundwork already laid, the other is open-ended linguistic work.

---

## A. Imperial ↔ metric

**Verdict: about a day, low risk.** It never touches the database or the API contract.

### What already exists

`api/app/services/scaling.py` (`format_amount`, line 32) already branches on unit:

- `METRIC_UNITS = {"g", "ml"}` → integer rounding, nearest 5 above 200
- everything else → snapped to kitchen fractions `⅛ ¼ ⅓ ⅜ ½ ⅝ ⅔ ¾ ⅞` as unicode glyphs
- `amount == 0` → em dash, never scaled

`seed/import_master.py` already converts metric multiples via `METRIC_FACTOR` (`kg → g ×1000`,
`l → ml ×1000`). The recipe page calls `scaledDisplay()` from `web/src/lib/scaling.ts` client-side,
so on web a unit toggle is purely a browser concern.

The conversion therefore slots in immediately before formatting: transform `(amount, unit)` into the
target system, then hand off to the existing formatter. The fraction snapper does the hard part.

### Rules that keep it honest

1. **Volume stays volume; weight stays weight.** Exact factors, no judgement calls:

   | From | To | Factor |
   |---|---|---|
   | cup | ml | 236.588 |
   | tbsp | ml | 14.7868 |
   | tsp | ml | 4.92892 |
   | lb | g | 453.592 |
   | oz | g | 28.3495 |

2. **No density conversions.** "1 cup flour → 120 g" crosses from volume to weight and needs a
   per-ingredient density table — different for flour, sugar, butter, and nuts. That is a separate,
   much fuzzier feature. Refusing it is what keeps this one exact.
3. **Metric → imperial is the ugly direction** — 750 ml is 3.17 cups — but `format_amount` already
   snaps to `3 ⅛ cups`. This is the app's existing design principle doing the work.
4. **`unit == ""` (countable) and `amount == 0` (to taste) pass through untouched.** Already true;
   no special-casing needed.

### The actual cost

The scaling logic exists in **three hand-mirrored implementations**, deliberately, with matching
test tables:

- `api/app/services/scaling.py` (canonical)
- `web/src/lib/scaling.ts` + `web/src/lib/scaling.test.ts`
- `ios/TheSharpEdge/Domain/ScalingEngine.swift`

Any conversion table lands in all three, with the same vectors. That mirroring is the cost, not the
maths. Note the existing half-up rounding comment in `scaling.py:37` — Python's banker's rounding
diverges from the JS mirror on exact halves, and the same class of bug is easy to reintroduce here.

### Where the preference lives

A display preference, not recipe data: `localStorage` under the existing `sharpedge.*` namespace on
web, `UserDefaults` on iOS. If `POST /api/v1/recipes/{slug}/scale` should agree with the client, it
takes an optional `units` parameter — but nothing currently requires that, since the web recipe page
formats client-side.

### Verification

Test vectors in all three suites, both directions, including: `1 cup → 237 ml`; `750 ml → 3 ⅛ cups`;
`2 lb → 907 g`; `900 g → 2 lb`; `amount 0` unchanged in both systems; `unit ""` unchanged. Then
scale a converted recipe and confirm conversion and scaling compose in either order.

---

## B. Multi-language ingest

**Verdict: capture is nearly free; parsing is linear work per language and never quite finished.**

### Capture is trivial

`SpeechRecognition.lang = 'fr-FR'` on web; `SFSpeechRecognizer(locale:)` on iOS. A dropdown and one
property. On iOS, `requiresOnDeviceRecognition` needs the language pack installed — without it,
recognition falls back to Apple's servers, which is a privacy change worth surfacing rather than
doing silently.

### Parsing is the whole job

`UNIT_MAP` (`seed/import_master.py:112`) is 20 English entries. Each added language needs its own:

- **Unit words** — "cuillère à soupe" → tbsp, "Esslöffel" → tbsp, "Tasse" → cup, "Gramm" → g
- **Number words** — the planned `normalise_spoken()` pre-pass ("two and a half") is English-only
- **Decimal commas** — `NUM = r"\d+(?:\.\d+)?"` (`import_master.py:126`) does not match `1,5 kg`.
  This mis-parses *silently* rather than failing, so it is the trap most likely to reach production
- **"To taste" equivalents** → `amount: 0` ("nach Geschmack", "au goût"), and range separators
  ("bis", "à") alongside the existing `RANGE_SEP`

Structure it as `LOCALES = {"en": {...}, "de": {...}}` with an explicit `lang` parameter — **not** one
merged dictionary. Merged tables create cross-language ambiguity and make failures hard to attribute.

### Two constraints that bite

**Slugs must stay ASCII.** `^[a-z0-9][a-z0-9-]*$` is enforced at `api/app/schemas/recipe.py:69`, and
QR codes are printed against slugs. The existing data already proves the need — `Vișinată` is stored
as `visinata`. German `ü` → "ue" or "u" is a real decision to make once; non-Latin scripts need
transliteration or a manual fallback.

**There is no `lang` column on `recipe`.** Titles are already multilingual (`Gurkensalat`,
`Vișinată`) so nothing is broken today, but knowing which locale to dictate in when *editing* would
need a migration. `Ingredient` and `Step` have `extra="allow"` and could carry it without one;
recipe-level metadata could not.

### The cheap 80%

Don't parse non-English at all. Dictate in any language, let the words land verbatim in the
ingredient `name` field, and set amount and unit from the dropdowns that already exist. Roughly an
hour, works in every language immediately, trades typing for engineering. Worth shipping first
regardless — it is also the honest fallback whenever parsing misses.

### Tension with the no-LLM decision

`docs/README.md` records: voice uses on-device speech and a deterministic parser, no LLM. That holds
well for English — testable, offline, no dependency.

Multilingual parsing is the case where it stops holding. Handling arbitrary languages is what an LLM
is good at and hand-maintained unit tables are bad at, and the infrastructure already exists
(`RouterProvider`, the `cluster` alias balancing Wile + RoadRunner). If multi-language ingest becomes
a real requirement rather than a nice-to-have, revisit that decision deliberately — don't drift into
maintaining a dozen locale tables by accident.
