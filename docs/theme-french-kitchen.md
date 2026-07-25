# Re-theme: "professional French kitchen"

Status: **awaiting palette choice**. Everything below is decided except which of A/B/C ships.

## Why

The current palette is "washi & bottle green" (CLAUDE.md §7) — warm off-white ground, bottle
green primary, copper accent. The owner wants the app to read as a professional French kitchen
instead. Light theme only for now; no dark mode in this pass (see "Deliberately not doing").

## Where colour actually lives

Good news first: this is a small, well-centralised change.

| Surface | File | Notes |
|---|---|---|
| Web tokens | `web/src/lib/tokens.css` | 8 variables, 66 lines, drives **165** `var(--…)` uses across 6 screens |
| iOS tokens | `ios/TheSharpEdge/DesignSystem/Theme.swift` | 9 hex values — the **only** colour literals in all 37 Swift files |
| iOS accent | `ios/TheSharpEdge/Assets.xcassets/AccentColor.colorset/Contents.json` | duplicates `Theme.green`, must be updated separately |
| PWA chrome | `web/src/app.html` (`theme-color` meta), `web/static/manifest.webmanifest` | both `#F2F1EC` |
| Logo | `web/static/logo.svg` | fills `#20241E`, `#2C4F36`, `#C87A2E`, `#F2F1EC` |
| App icons | `web/static/icon-192.png`, `icon-512.png`, `apple-touch-icon.png`, `ios/.../icon-1024.png` | raster, need regenerating |
| QR codes | `api/app/routers/recipes.py:180` | `fill_color="#20241E"` — the only colour in the API |
| Spec | `CLAUDE.md` §7 | restates the palette; update alongside |

Tailwind is v4 via the Vite plugin, with **no `tailwind.config.js` and no `@theme` block** — the
tokens are plain CSS custom properties applied through inline `style=` attributes. There are zero
`<style>` blocks in any `.svelte` file. So the tokens genuinely are the single lever.

## The candidate palettes

All three are contrast-checked against their own ground; every value below meets WCAG AA (≥4.5:1)
for small text, which matters because the app uses 10–11px uppercase mono labels.

### A · Brasserie
Oxblood banquette leather, aged brass, menu on bone stock. Warmest, closest to the current app.

```
--paper #f3f0e7   --card #fbf9f3   --line #ddd7c8
--primary #7d2231 --primary-deep #57121f
--accent #7f611e  --ink #191512    --faint #6d6459   --off-white #f8f4ea
```
accent 5.1:1 · primary 8.6:1 · faint 5.1:1 · off-white on deep 12.5:1

### B · Batterie
The working line, not the dining room: zinc counter, white enamel, copper as the only warm thing.

```
--paper #eceef0   --card #fbfcfd   --line #ccd2d8
--primary #3d4a53 --primary-deep #26313a
--accent #9c4f1c  --ink #15181b    --faint #5f6870   --off-white #f3f6f8
```
accent 5.1:1 · primary 7.8:1 · faint 4.9:1 · off-white on deep 11.8:1

### C · Faïence
Blue-and-white kitchen tile, ochre mustard accent. Boldest, furthest from today.

```
--paper #f4f3ee   --card #fdfcf8   --line #d9d7cd
--primary #1f4a8f --primary-deep #14315f
--accent #8a5e17  --ink #14161c    --faint #666a72   --off-white #f6f5ef
```
accent 5.1:1 · primary 7.8:1 · faint 4.9:1 · off-white on deep 13.9:1

Note the accents are deliberately darker than a "pretty" brass/copper/ochre would be. They carry
11px text on a light ground, and the lighter versions land at ~3.4:1 — under AA.

## Implementation

### 1. Rename the tokens (do this first, mechanically)

`--green` / `--green-deep` become `--primary` / `--primary-deep`; `--copper` becomes `--accent`.
The names currently lie about what they hold, and will lie harder after a re-theme. Straight
find-and-replace across `web/src/**` (109 refs) and `Theme.swift` (`green`→`primary`,
`greenDeep`→`primaryDeep`, `copper`→`accent`).

### 2. Tokenise the 16 stray literals

These bypass the token file today and would survive a re-theme as leftovers from the old scheme:

- **`#F4F3EC` ×9** — off-white text on the green fills. Add `--off-white` to `tokens.css`,
  mirroring the `Theme.offWhite` that iOS already has and web lacks.
  `routes/+page.svelte:32,40,83`, `routes/library/+page.svelte:128`,
  `routes/ask/+page.svelte:120,184`, `routes/r/[slug]/+page.svelte:63,79,185`,
  `routes/r/[slug]/edit/+page.svelte:339`
- **`rgba(255,255,255,.14)` ×2, `rgba(255,255,255,.4)` ×1** — translucent chips on the scale bar,
  `routes/r/[slug]/+page.svelte:85,94,102`. Become `--btn-ghost` / `--btn-outline` tokens.
- **`#FBF0E6` ×1** — copper-tinted warning banner, `routes/r/[slug]/edit/+page.svelte:104`.
  Becomes `--accent-wash`.
- **`bg-white` ×8** — literal white form inputs in the editor
  (`routes/r/[slug]/edit/+page.svelte` lines 193, 199, 210, 219, 226, 280, 291, 321).
  Become `--card`.

This step is what makes a future dark mode a small job rather than a rewrite — 12 of these 16
assume a light ground and would break on a flip.

### 3. Swap the values

`tokens.css` and `Theme.swift` get the chosen palette. Then the peripherals: manifest, `app.html`
meta, `AccentColor.colorset`, `logo.svg`, regenerated raster icons, QR `fill_color`, CLAUDE.md §7.

## Verification

- `cd web && npm run build && npm run dev` — walk all five routes (`/`, `/r/{slug}`,
  `/r/{slug}/edit`, `/library`, `/ask`) and confirm nothing renders in bottle green.
- `rg -i '#[0-9a-f]{6}|rgba\(|bg-white' web/src --glob '!lib/tokens.css'` should return **nothing**.
- `rg -i 'green|copper' web/src ios/TheSharpEdge` should return nothing outside comments.
- Build the iOS app; check the home screen icon tint picks up the new `AccentColor`.
- `GET /api/v1/recipes/{slug}/qr` still returns a scannable PNG.
- Lighthouse accessibility pass on `/r/goulash` — contrast is the check that matters.

## Deliberately not doing

**Dark mode.** There is currently *no* infrastructure for it anywhere — repo-wide grep for
`prefers-color-scheme`, `data-theme`, `dark:`, `color-scheme` returns zero hits in web, api and
ios. Adding it means a second token set plus a root attribute plus a persisted toggle on two
platforms. Step 2 above is the prerequisite; once the literals are tokenised, dark mode becomes a
tractable follow-up rather than a rewrite.

**`design_handoff_sharp_edge/`.** Both files in it are byte-identical duplicates of the repo root
(`README.md`, `recipes-data.js`), and the README specs an entirely different "Organic design
system" (terracotta/sage, Caprasimo/Figtree) that was never built. It is a stale superseded
handoff — not a target, and not to be confused with the live palette.
