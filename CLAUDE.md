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
│   │   ├── services/
│   │   │   ├── scaling.py     # quantity math (port rules in §8)
│   │   │   ├── retrieval.py   # hybrid search + RRF
│   │   │   ├── llm.py         # provider abstraction
│   │   │   └── citations.py
│   │   └── ingest/
│   │       ├── watcher.py     # watches /library drop folder
│   │       ├── extract.py     # pymupdf4llm / ebooklib / plain text
│   │       ├── chunker.py     # recipe-aware chunking (§9)
│   │       └── embed.py
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
├── seed/
│   ├── recipes-master.md      # canonical import source
│   └── import_master.py       # parses master → DB
└── library/                   # book drop folder (gitignored)
    ├── public/                # public-domain / owner content
    └── private/               # owner's copyrighted shelf (never exported)
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

-- RAG library
book(id uuid pk, title text, author text, year int,
     tier text check (tier in ('public','private')),
     source_file text, license text, status text,     -- pending|chunking|embedded|error
     added_at)

chunk(id uuid pk, book_id fk,
      kind text check (kind in ('recipe','technique','essay','reference')),
      chapter text, heading text,
      content text not null,
      page_start int, page_end int,
      tokens int,
      embedding vector(768),
      embed_model text,
      tsv tsvector generated always as (to_tsvector('english', content)) stored)
create index on chunk using gin(tsv);
create index on chunk using hnsw (embedding vector_cosine_ops);

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

**Design tokens ("washi & bottle green")** — in `tokens.css`, used everywhere:
```
--paper #F2F1EC   --ink #20241E    --faint #6B6F63
--green #3E6B4A   --green-deep #2C4F36
--copper #C87A2E  --line #D9D7CC   --card #FAFAF6
```
Type: **Fraunces** (display 650), **Work Sans** (body), **Spline Sans Mono** (all quantities + labels). Quantities are always mono — the app's signature. Scale changes flash quantities copper (~450 ms).

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

## 9. RAG pipeline

**Ingestion (watcher on /library):**
1. New file detected (`pdf`, `epub`, `txt`, `md`) → `book` row `status=pending`, tier from subfolder (`public/` or `private/`).
2. Extract: PDFs via **pymupdf4llm** (handles two-column cookbook layouts); EPUB via ebooklib → markdown.
3. **Chunk by structure, not tokens** (`chunker.py`):
   - Detect recipe boundaries (title / yield / ingredient-list / method patterns; heading heuristics per era — Escoffier numbered sections, Farmer's small-caps titles). One recipe = one chunk, always atomic.
   - Technique/essay prose between recipes → separate chunks (~800–1200 tokens, 150 overlap), `kind=technique|essay`.
   - Tag every chunk: {book, chapter, heading, kind, page range}.
4. Embed via Ollama; write `embedding` + `embed_model`. Status → `embedded`.
5. Idempotent: re-dropping a file re-chunks only if content hash changed.

**Retrieval (`retrieval.py`):**
- Run FTS and vector queries in parallel (top 25 each) → Reciprocal Rank Fusion → top 8 chunks.
- Filters: kind, book, tier. Private tier requires auth — enforced at query level, not just UI.

**Ask (`/ask`):**
- Prompt = system (culinary assistant, cite sources, admit gaps) + retrieved chunks with ids + user question (+ current recipe JSON when scoped).
- Answer streams; citations returned as structured `[{chunk_id, book, heading, pages}]` — the model is instructed to reference chunk ids, the service maps them.
- **Anthropic provider only ever receives public-tier chunks.** Private-tier questions route to Ollama exclusively. Hard rule, enforced in `llm.py`.

**Starting five for the public shelf** (Gutenberg / Internet Archive):
Escoffier *A Guide to Modern Cookery* (1907 EN) · Artusi *Science in the Kitchen* (early EN ed.) · Fannie Farmer 1896 · Jerry Thomas *Bar-Tender's Guide* · USDA canning bulletins. Then Ranhofer *The Epicurean*, Mrs. Beeton technique chapters, Brillat-Savarin, Francatelli, Bullock *The Ideal Bartender*.

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
