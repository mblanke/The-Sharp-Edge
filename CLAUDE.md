# CLAUDE.md — The Sharp Edge (Full Webapp)

Build spec for a self-hosted recipe + culinary-RAG application. This file is the source of truth for architecture, schema, contracts, and conventions. Read fully before writing code. Keep user-facing content clean and tight — no editorializing, no anecdotes, no provenance stories beyond a bare source line.

---

## 1. What this is

**The Sharp Edge** is a self-hosted web application that is the digital side of a physical recipe notebook (Knifewear Cook's Notebook, 5" × 7.5"). Printed recipe cards carry QR codes that deep-link into the app. The app is also a culinary research tool: a RAG library of chunked cookbooks queried through a local LLM.

Core principles:
- **Paper is the permanent record; the app is the calculator and the library.**
- **Never surface the owner's name** in app content, titles, or metadata. The app is "The Sharp Edge".
- **Two content tiers:** public-domain / owner-authored content is unrestricted; copyrighted books the owner has ingested stay private to the local deployment and are never exposed on any public route or export.
- GF (gluten-free) status is load-bearing — a household member has celiac. GF tags, tamari/Worcestershire checks, and the hidden-gluten reference must survive every refactor.

## 2. Deployment target

- Home server, same box that already runs **Ollama**.
- **Docker Compose** stack; iPad and phones reach it over **Tailscale** (no public exposure required, but routes are designed so a public read-only mode is possible later).
- iPad experience = **PWA**: manifest + service worker + Add to Home Screen. Kitchen-first UI.

```
docker-compose services:
  web       → frontend (SvelteKit, node adapter)        :3000
  api       → FastAPI (Python 3.12, uvicorn)            :8000
  db        → postgres:16 + pgvector extension          :5432
  ollama    → existing service (external or in-compose) :11434
  ingest    → same image as api; runs the folder watcher
volumes:
  pgdata, library (book drop folder), covers/uploads
```

If Ollama already runs on the host, reference it via `host.docker.internal:11434` (or the Tailscale IP) instead of adding the service.

## 3. Stack

| Layer | Choice | Notes |
|---|---|---|
| Frontend | **SvelteKit** + TypeScript | Fast, small, ideal for a single-purpose app. Tailwind for styling with the design tokens below. |
| Backend | **FastAPI** (Python 3.12) | Shares code with the chunking pipeline. Pydantic v2 models everywhere. |
| DB | **Postgres 16 + pgvector** | One store for relational + vectors. No second vector DB. |
| Search | **Hybrid**: Postgres FTS (BM25-ish via `ts_rank`) + pgvector cosine | Reciprocal Rank Fusion to merge. Exact-term culinary queries ("beurre blanc") must win. |
| Embeddings | Ollama `nomic-embed-text` (768-dim) | Configurable via env. Store model name per chunk for re-embedding migrations. |
| LLM | Ollama chat model (default `llama3.1:8b`, configurable) + optional Anthropic API tier | Provider abstraction: `LLMProvider` interface with `ollama` and `anthropic` implementations. Anthropic key via env, never in code or client. |
| Auth | Single-user token auth (bearer) for write/admin + private library routes; read-only recipe routes optionally anonymous | Keep it simple; it's a household app behind Tailscale. |
| Migrations | Alembic | |
| Tests | pytest (api), vitest + playwright (web) | |

## 4. Repo layout

```
sharp-edge/
├── CLAUDE.md                  ← this file
├── docker-compose.yml
├── .env.example
├── api/
│   ├── pyproject.toml
│   ├── app/
│   │   ├── main.py            # FastAPI app factory, routers
│   │   ├── config.py          # pydantic-settings, all env config
│   │   ├── db.py              # async SQLAlchemy engine/session
│   │   ├── models/            # SQLAlchemy models (below)
│   │   ├── schemas/           # Pydantic request/response models
│   │   ├── routers/           # recipes, search, ask, library, admin, qr
│   │   └── services/
│   │       ├── scaling.py     # quantity math (port rules in §8)
│   │       ├── atlas_rag.py   # client for Atlas rag-api (§9 — retrieval delegated)
│   │       ├── llm.py         # provider abstraction + tier firewall
│   │       └── citations.py
│   ├── alembic/
│   └── tests/
├── web/
│   ├── package.json
│   ├── src/
│   │   ├── routes/
│   │   │   ├── +layout.svelte         # shell, nav, PWA
│   │   │   ├── +page.svelte           # home: category index
│   │   │   ├── r/[slug]/+page.svelte  # recipe view (QR target)
│   │   │   ├── r/[slug]/edit/
│   │   │   ├── r/[slug]/cook/         # cook mode
│   │   │   ├── library/               # search + book browser
│   │   │   ├── ask/                   # chat with the library
│   │   │   ├── plan/                  # meal plan + shopping list
│   │   │   └── admin/                 # ingestion status, settings
│   │   └── lib/ (api client, stores, components, tokens.css)
│   └── static/ (manifest, icons — logo.jpg, logo.svg)
└── seed/
    ├── recipes-master.md      # canonical import source
    └── import_master.py       # parses master → DB

# Book drop folder is NOT in this repo: \\Olympus_NAS\Media\References\Cooking (§9)
```

## 5. Database schema (Postgres)

```sql
-- recipes
recipe(id uuid pk, slug text unique not null,        -- QR contract: slugs are permanent
       title text, category text, meta text,
       base_yield int, yield_word text,              -- "servings", "coins", "cucumbers"
       gf bool default false, noscale bool default false,
       source text,                                   -- bare source line only
       status text default 'active',                  -- active|draft|archived
       created_at, updated_at)

recipe_version(id uuid pk, recipe_id fk, version int, -- v1, v2… marinade pattern
       label text,                                    -- "quick 4–8 hr", "overnight"
       ingredients jsonb,                             -- [{amount, unit, name, note?}]
       steps jsonb,                                   -- [{text, timer_seconds?}]
       notes jsonb,                                   -- [text]
       is_current bool,
       created_at)

tag(id, name unique); recipe_tag(recipe_id, tag_id)

-- notebook mapping
notebook_page(recipe_id fk, page_number int, section text)

-- RAG library: NO book/chunk tables — vectors live in Atlas's Qdrant
-- (collection references_v2); see §9. Local Postgres holds only app state.

-- planning
meal_plan(id, date date, recipe_id fk, meal text, scaled_yield int)
shopping_item(id, plan_week date, name text, amount text, checked bool, recipe_id fk null)

-- chat
conversation(id uuid pk, title, created_at)
message(id, conversation_id fk, role text, content text,
        citations jsonb,                              -- [{chunk_id, book, heading, pages}]
        created_at)
```

Rules:
- **Slugs are a public contract** once QR codes are printed. New slugs freely; never rename existing ones. Renames require a `redirect(old_slug → slug)` table entry instead.
- `ingredients[].amount = 0` means "to taste" → renders as em dash, never scales.
- Units: `g, ml, cup, tbsp, tsp, lb, oz, ""` (empty = countable; counting noun lives in `name`).

## 6. API contract (FastAPI, `/api/v1`)

```
GET    /recipes?category=&q=&gf=          list (cards)
GET    /recipes/{slug}                    full recipe, current version
GET    /recipes/{slug}/versions           version history
POST   /recipes                           create (auth)
PUT    /recipes/{slug}                    creates new version (auth) — versions are append-only
POST   /recipes/{slug}/scale              {target_yield} → scaled ingredient list (server-side math)
GET    /recipes/{slug}/qr                 PNG QR pointing at /r/{slug}

GET    /library/books                     list with status (tier-filtered by auth)
POST   /library/rescan                    trigger ingest pass (auth)
GET    /search?q=&kind=&book=&tier=       hybrid search → ranked chunks with highlights

POST   /ask                               {question, conversation_id?, scope: {books?, tier?, recipe_slug?}}
                                          → streamed answer + citations[]
GET    /conversations /conversations/{id}

GET    /plan?week=                        meal plan
POST   /plan  /plan/shopping-list         generate list from week's plan (merges duplicate ingredients)

GET    /export/master.md                  regenerates recipes-master.md from DB (public tier only)
GET    /export/cards.pdf                  regenerates the print-card PDF (see §10)
GET    /healthz
```

Conventions: Pydantic schemas for every request/response; errors as RFC-7807 problem+json; all write routes require bearer token; `/ask` streams Server-Sent Events.

## 7. Frontend requirements

**Design tokens ("C · Faïence" — blue-and-white kitchen tile, ochre accent)** — in `tokens.css`, used everywhere:
```
--paper #F2F3F5   --ink #14161C    --faint #5F6570
--primary #1F4A8F --primary-deep #14315F
--accent #8A5E17  --line #DCDEE3   --card #FBFCFD
--off-white #F7F8FA  --btn-ghost rgba(255,255,255,.14)
--btn-outline rgba(255,255,255,.4)  --accent-wash #F4EFE6
```
Both schemes ship and follow the OS; there is no in-app toggle. `--primary-deep` is a *fill* carrying `--off-white` text, `--ink-accent` is that same blue used *as* text — they are identical in light and diverge in dark, so a `color:` must never use `--primary-deep`. Dark: `--paper #101319 --card #171B22 --line #2A2F39 --ink #E6E9EE --faint #98A0AD --primary #7BA6E2 --primary-deep #2F5F9E --ink-accent #8FB6EE --accent #D9A441 --accent-wash #2A2113`. The light ground is a cool porcelain, not a warm off-white — a warm ground reads yellow next to the iPad's own grey sidebar, and ochre should be the only warm thing on screen. The accent is darker than a decorative ochre because the lighter version fails WCAG AA at the 10–11px label sizes this app uses. `Theme.swift` mirrors these names exactly.

Type: **Fraunces** (display 650), **Work Sans** (body), **Spline Sans Mono** (all quantities + labels). Quantities are always mono — the app's signature. Scale changes flash quantities accent (~450 ms).

Pages:
- **Home** — category chip index + recipe cards. GF filter toggle.
- **Recipe `/r/{slug}`** — the QR landing. Title, meta, GF tag, scale stepper (min 1, max 4× base, reset-to-base), ingredients, steps, notes, version switcher, "Ask about this recipe" (opens /ask scoped to the recipe + library). Must be excellent on a phone: ≥44 px touch targets, single column, readable with flour on your hands.
- **Cook mode `/r/{slug}/cook`** — one step per screen, huge type, swipe/tap advance, wake-lock, inline timers from `timer_seconds`, current-step ingredient amounts shown scaled.
- **Editor** — structured form (not raw JSON): ingredient rows with amount/unit/name, drag-reorder steps, timer field per step. Saving creates a new version.
- **Library** — book list with ingest status; search box with kind/book filters; result cards show book · chapter · heading · page range.
- **Ask** — chat UI; every answer renders its citations as tappable chips that open the source chunk. Scope selector (whole library / one book / one tier / current recipe context).
- **Plan** — week grid, drag recipes on, one-tap shopping list with checkboxes.
- **Admin** — drop-folder status, re-embed button, token settings, export buttons.

PWA: manifest (name "The Sharp Edge", icons from logo.jpg/logo.svg), service worker caching app shell + last-viewed recipes for offline cooking.

## 8. Scaling rules (do not regress)

Port these exactly; they exist so scaled output reads like a cook wrote it:
- factor = target_yield / base_yield; per-ingredient scaled = amount × factor.
- `g`/`ml` → integer; values ≥ 200 round to nearest 5.
- All other units and counts → nearest kitchen fraction of {⅛, ¼, ⅓, ⅜, ½, ⅝, ⅔, ¾, ⅞} rendered as unicode glyphs; never raw decimals (0.75 is a bug; ¾ is correct).
- amount 0 → em dash, unscaled.
- Server implements the math (`services/scaling.py`); client mirrors for instant UI but server response is canonical (used by shopping list + cards export).

## 9. RAG — delegated to the Atlas stack (implemented 2026-07-23)

The in-app ingestion/embedding pipeline originally specced here was **replaced by
the existing home-lab RAG infrastructure** (see D:\Projects\Home Setup). The app
is a consumer, not an indexer.

**Ingestion (owned by Atlas — zero code in this repo):**
- Corpus drop folder: **`\\Olympus_NAS\Media\References\Cooking`** (= `/mnt/media/References/Cooking/` on Atlas, `/mnt/references/Cooking/` inside rag-api). Drop pdf/epub/txt/md there; done.
- `rag-ingest.timer` on Atlas sweeps every 6 h → docling extraction → chunking → `mxbai-embed-large` embeddings on the GB10 nodes (Wile `100.110.190.12`, RoadRunner `100.110.190.11`) → Qdrant collection `references_v2`.
- Force an immediate sweep: `ssh soadmin@100.110.190.10 sudo systemctl start rag-ingest.service`.

**Retrieval (`services/atlas_rag.py`):**
- POST `{RAG_API_URL}/retrieve` (`http://100.110.190.10:8099`, or `http://rag-api:8099` on Atlas) with over-fetch `top_k=24`, then **client-side filter to `RAG_SOURCE_FOLDER=Cooking`** (rag-api has no server-side filter), keep top 8.
- Chunks carry `text, source_path, page, heading, title, score, rerank_score`.

**Ask (`routers/ask.py` → SSE):**
- Prompt = system (culinary assistant, cite `[n]`, admit gaps) + retrieved numbered chunks + conversation history + user question (+ current recipe JSON when scoped via `scope.recipe_slug`).
- Streams via the **LiteLLM router** (`LLM_ROUTER_URL=http://100.110.190.10:4000/v1`, scoped key `LLM_ROUTER_KEY`, model alias **`cluster`** which load-balances both GB10s). Citations parsed from `[n]` references → `[{n, title, source_path, heading, page}]`.
- **Tier firewall:** the Cooking shelf is copyrighted/private — corpus chunks go to **local models only**. `AnthropicProvider` in `services/llm.py` raises `TierViolation` on any corpus-bearing request. Hard rule; unit-tested.
- **GPU contention:** no batch embedding from this app, ever; interactive asks use `cluster` so the router balances load off Wile's assistants.

## 10. Print & QR pipeline

- `/export/cards.pdf`: 4.5" × 6.75" cards, 2-up on landscape letter, dashed cut lines, category eyebrow on each card, first two cards = Page Allocation table + glue-in index. Reportlab card pages → pypdf 2-up imposition (working generator exists as `make_cards.py`; port into `api/app/services/cards.py`).
- Card order = glue-in order = category order. Content voice: ingredients, method, functional notes only.
- QR per recipe: `{BASE_URL}/r/{slug}`, high error correction, ~0.6". Endpoint renders PNG; cards embed them bottom-right corner.
- Page allocation reference (184-page notebook): Sauces 20p · Marinades 18 · Salads 16 · Soups 10 · Sandwiches 8 · Pasta 8 · Entrées 20 · Sides 10 · Breakfast 8 · Baking/Desserts 8 · Drinks 6 · Apps/Preserves 6 · ~46 overflow at back.

## 11. Seed data

`seed/import_master.py` parses `recipes-master.md` (18 recipes) into the DB: category headers → `category`, versioned marinades → two `recipe_version` rows on one recipe, GF markers → `gf=true`, "Hidden Gluten" → `noscale=true, kind reference`. Slugs: `mango-salsa, cucumber-dressing, raspberry-vinaigrette, bourbon-butter, flank-quick, flank-overnight, souvlaki, tequila-lime, cucumber-salad-thai, gurkensalat, watermelon-feta, goulash, spaghetti-sauce, salmon-mango, stirfry, celeriac, pancakes, gf-reference` — these match already-generated QR expectations; do not change.

Known gaps to leave as editable placeholders: spaghetti-sauce herb quantities, broccoli-slaw quantities, vișinată quantities.

## 12. Build phases

**Phase 1 — Skeleton (ship first):** compose stack up; schema + migrations; seed import; recipe list/detail API; frontend home + recipe view with working scaler; PWA manifest. *Done when: iPad home-screen app shows all 18 recipes and scales the goulash.*

**Phase 2 — Editing & versions:** editor UI, append-only versions, version switcher, tags, notebook page mapping, master.md export. *Done when: a recipe can be corrected on the iPad and exported back to markdown.*

**Phase 3 — RAG:** ingest watcher, chunker, embeddings, hybrid search, library UI, /ask with citations, provider abstraction + tier firewall. *Done when: "how does Escoffier build an espagnole?" answers with page-cited chunks.*

**Phase 4 — Kitchen features:** cook mode with timers + wake-lock, meal plan, shopping list, cards.pdf + QR export, offline caching. *Done when: a full cook happens without touching paper except by choice.*

## 13. Conventions for Claude Code sessions

- Work phase by phase; don't scaffold Phase 3 code during Phase 1.
- Every endpoint gets a pytest; scaling and chunker get exhaustive unit tests (fraction table, boundary detection on real Escoffier excerpts).
- Conventional commits; one feature per commit.
- Config only via env (`config.py`); `.env.example` stays current.
- No secrets, no owner name, no editorializing in user-facing strings.
- If a decision isn't covered here, prefer the boring option and note it in a `DECISIONS.md`.
