# DECISIONS.md

Decisions not covered by CLAUDE.md, boring option preferred.

- **2026-07-23 — Flank marinade slugs vs versions.** §11 lists `flank-quick` and `flank-overnight` as two slugs, while §11 prose says versioned marinades become two `recipe_version` rows on one recipe. Slug list wins (QR contract): imported as two recipes, each with one v1 version. The version mechanism stays available for future edits of either.
- **2026-07-23 — pgvector extension enabled in the initial migration** even though `chunk`/`book` tables arrive in Phase 3 — enabling an extension is idempotent and avoids a superuser step mid-project. No Phase 3 tables scaffolded.
- **2026-07-23 — Ollama not in compose.** Host already runs it; referenced via `OLLAMA_URL` env (`host.docker.internal:11434` default).
- **2026-07-23 — Reference Docs/ kept in repo** as historical source material (v1 single-file prototype, master file original, print PDF, logo source). The zip is gitignored.
- **2026-07-23 — Categories follow recipes-master.md headers** (e.g. "Sauces, Dressings & Salsas"); empty categories (Appetizers, Baking, Desserts, Preserves) are not imported as recipes and simply don't appear until they have one.
