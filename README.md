# The Sharp Edge

Self-hosted recipe + culinary-RAG web application — the digital side of a physical
recipe notebook. Printed recipe cards carry QR codes that deep-link into the app;
a library of chunked cookbooks is searchable and answerable through local models.

Paper is the permanent record; the app is the calculator and the library.

## Stack

- **web/** — SvelteKit + TypeScript PWA (Tailwind, "washi & bottle green" tokens), port 3010
- **api/** — FastAPI (Python 3.12, Pydantic v2, async SQLAlchemy), port 8010
- **db** — Postgres 16, port 5442
- **RAG** — delegated to the Atlas home-lab stack (Qdrant + GB10 nodes via rag-api
  and a LiteLLM router); this app is a consumer, not an indexer. See CLAUDE.md §9.
- **seed/** — canonical `recipes-master.md` + importer

`CLAUDE.md` is the authoritative build spec (architecture, schema, contracts,
conventions). `DECISIONS.md` records choices the spec doesn't cover.

## Running

```sh
cp .env.example .env        # set API_TOKEN (required — writes are disabled without it)
docker compose up -d        # db + api + web
# on Atlas, add the override: docker compose -f docker-compose.yml -f docker-compose.atlas.yml up -d
```

Migrations run with Alembic from `api/`; seed the 18 notebook recipes with
`seed/import_master.py`. iPad/phone access is over Tailscale; install from the
browser as a home-screen PWA.

## Development

```sh
# API tests
cd api && uv run --extra dev pytest

# Web tests + type check
cd web && npm ci && npx vitest run && npx svelte-check
```

Conventions: conventional commits, one feature per commit; every endpoint gets a
pytest; config only via env; no secrets, no owner name, no editorializing in
user-facing strings.
