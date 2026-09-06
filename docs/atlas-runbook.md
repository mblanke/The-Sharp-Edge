# Atlas runbook — making the shelf searchable

Ingestion belongs to Atlas, not to this app (CLAUDE.md §9). No code here extracts an
archive or embeds anything, and none should: `include_whisper=true` on a single Whisper
node is hours of GPU, and the no-batch-embedding rule exists to keep this app from
competing with the assistants for it.

What this app *does* do is notice. `/admin/library/coverage` reconciles the shelf against
the index, and each problem below carries its command. Everything here was measured with
a Qdrant payload facet over `source_path` filtered to `source_folder = Cooking`.

## Why this document exists

The book list read from a mounted directory and the vectors lived in Qdrant, and the two
were never compared. A book that failed to ingest looked exactly like one that worked, so
several had been broken in silence for months:

| Book | State | Consequence |
|---|---|---|
| **Under Pressure** (Keller, sous vide) | 6 split `.zip`, never extracted | the sous-vide reference is absent; "sous vide short ribs" answers from elsewhere |
| **The Flavor Bible** | 4 split `.zip`, never extracted | no pairing source at all |
| **Modernist Cuisine Vol 1–6** | 875 MB of PDFs, **2 chunks** — from a 1 KB blurb `.txt` | looks present, searches empty |
| **Modernist Cuisine (HQ)** | 8 × `.rar`, never extracted | — |
| **Modernist Bread** (449 MB), **Fat Duck** (489 MB), **Japanese Cooking** (50 MB) | PDFs present, zero chunks, **absent from `/failed`** — never attempted | — |
| **Hamelman's Bread** | only download-stub `.txt` files indexed | — |
| **Kitchen Confidential** | corrupt EPUB, **426 failed retries** | burns retry budget every sweep |
| **Franklin Barbecue**, **Medium Raw** | each indexed **twice** under two folders | duplicate results; mitigated in-app, but the index is still doubled |
| **Great Courses** | 36 `.mkv` lectures untranscribed (the guidebook PDF *is* indexed) | 18 h of technique lost |
| **CIA Professional Chef**, **Bocuse**, **Culinary Scrapbook** | indexed from pageless `.txt` twins beside their PDFs | every citation reports `page: 1`, so it is suppressed and cannot be opened |

Escoffier and Larousse are genuinely not on the shelf. Nothing to fix — the app now says
so rather than answering in Escoffier's name from someone else's book.

## Commands

Run on Atlas (`ssh soadmin@100.110.190.10`). Paths are under
`/mnt/media/References/Cooking` on the host, `/mnt/references/Cooking` inside rag-api.

```bash
cd /mnt/media/References/Cooking

# 1. Unseal the split archives. Under Pressure is the one that closes a real eval gap.
cd "Thomas.Keller.Under.Pressure.Cooking.Sous.Vide.2016.RETAiL.EPUB.eBook-NODE" && 7z x eykfxera.zip && cd -
cd "Karen.Page.And.Andrew.Dornenburg.-.The.Flavor.Bible.The.Essential.Guide.To.Culinary.Creativity.Based.On.The.Wisdom.Of.Americas.Most.Imaginative.Chefs.2008.RETAIL.EPUB.eBook-CTO" && 7z x kpadfb8a.zip && cd -
# ~2 GB free needed; extracting part1 pulls the rest of the set
cd "Modernist Cuisine - The Art and Science of Cooking [Vol 1-6] (HQ)" && unrar x "Modernist Cuisine - The Art and Science of Cooking.part1.rar" && cd -

# 2. Remove the stubs that are standing in for real books, so the PDFs get read
rm "Modernist Cuisine Volume 1-6/Modernist Cuisine.txt"           # 1 KB blurb, 2 chunks
rm -f "[food] Bread_ A Baker's Book"*/"_ DOWNLOAD.txt" "[food] Bread_ A Baker's Book"*/"_ upload"*

# 3. Force-ingest the PDFs that were never attempted (they are not in /failed)
for f in "Japanese Cooking - A Simple Art.pdf" \
         "The Fat Duck Cookbook @ Heston Blumenthal [SCAN].pdf" \
         "Nathan Myhrvold - Modernist Bread = The Art and Science - 2017.pdf"; do
  curl -s -X POST localhost:8099/ingest -H 'Content-Type: application/json' \
       -d "{\"file_path\":\"/mnt/references/Cooking/$f\"}"
done

# 4. Kitchen Confidential: corrupt EPUB, 426 retries. Replace the file or delete it.
# 5. Delete one copy each of the duplicated Franklin Barbecue / Medium Raw folders.

# 6. Give the flagship reference real page numbers. These .txt files are pageless
#    extracts sitting next to their own PDFs, which is why their citations say page 1
#    and cannot be opened. Delete the twin, let docling read the PDF.
rm "Culinary Institute of America - The Professional Chef (9th edition).txt"
rm "Institut Paul Bocuse Gastronomique- The definitive step-by-step guide to culinary excellence.txt"
rm "The Culinary Scrapbook By Chefs of Google- Bon Appetit- Caterspan and Restaurant Associates.txt"

# 7. Sweep
sudo systemctl start rag-ingest.service

# 8. Separately, overnight — one Whisper node, 36 lectures. Keller's MasterClass is
#    already transcribed and the output is clean, so this is worth the GPU time.
curl -X POST 'localhost:8099/ingest-all?include_whisper=true'
```

## Verifying

```bash
# per-book chunk counts, straight from the index
curl -s -X POST http://localhost:6333/collections/references_v2/facet \
  -H 'Content-Type: application/json' \
  -d '{"key":"source_path","filter":{"must":[{"key":"source_folder","match":{"value":"Cooking"}}]},"limit":500,"exact":true}'
```

Then from the app: `GET /api/v1/admin/library/coverage?refresh=true`, and re-run the
retrieval eval — the questions expecting Under Pressure should flip from `ABSENT` to
`HIT`:

```bash
cd api && RAG_EVAL=1 uv run --extra dev pytest tests/test_retrieval_eval.py -s
```

Re-record the baseline **on purpose** once the shelf settles:

```bash
RAG_EVAL=1 RAG_EVAL_WRITE_BASELINE=1 uv run --extra dev pytest tests/test_retrieval_eval.py
```

## Why step 6 matters more than any ranking change

The `.txt` twins are not merely pageless — **their two-column pages are interleaved line
by line**, which silently shreds every recipe in the book.

Printed page 335 of the Professional Chef carries two recipes side by side, Onion Soup in
the left column and Tortilla Soup in the right. The extracted text reads:

```
Onion Soup                                    Tortilla Soup
Makes 1 gal/3.84 L                            Makes 1 gal/3.84 L
    5 lb/2.27 kg thinly sliced onions             12 plum tomatoes, cored
    2 oz/57 g clarified or whole butter           1 white onion, halved and peeled
    4 fl oz/120 mL Calvados or sherry             4 garlic cloves, unpeeled
```

Every chunk covering this page is therefore half onion soup and half tortilla soup. That
explains a failure that looked like a ranking bug: asking for the CIA's onion soup returns
Tortilla Soup passages about "chile slices … not smoking", and a retrieval for "french
onion soup" scoped to this book surfaces **zero** relevant chunks even though the complete
recipe — caramelize 25–30 min, deglaze with Calvados, Gruyère crouton gratinée — is
sitting right there in the file.

No amount of query rewriting, fusion tuning or over-fetching fixes a chunk that is two
unrelated recipes braided together. The embedding is diluted at ingestion time. Docling
does layout-aware extraction and reads columns in order, which is the actual fix.

Confirm rather than assume: after the sweep, a Professional Chef retrieval should return
`file_type: pdf` with plausible pages, and the onion soup query should return onion soup.
If the PDF fails to extract, restore the `.txt` from backup rather than leaving the book
unsearchable — a shredded book still beats no book.

Note also that a recorded page is a **PDF page index**, not the printed page number — one
CIA chunk's marker read 311 while its own running footer read 287. That is correct for
`/library/source`, which slices by PDF index, and wrong for a cook holding the book. How
general the offset is across the shelf is not yet known; it needs its own investigation
before anything tries to "correct" it.

---

## The base64 poisoning (2026-08-28)

The single worst defect found on the stack, and it was never a Sharp Edge bug — it was
in rag-api's docling client, and it affected **every corpus on Atlas**.

`docling_client._call_docling` extracts embedded images so a vision model can describe
them. It never removed them from the text it returned. Worse, `_IMG_RE` didn't allow
whitespace inside the base64 group, and docling line-wraps its base64 — so the regex
matched *nothing*: no image was ever described, and every byte of every embedded image
was chunked and embedded as if it were prose.

Measured on a 10,000-point random sample of `references_v2`:

| corpus | poisoned |
|---|---|
| Networking | 96% |
| threat-intel | 92% |
| Hacking | 81% |
| NIST | 70% |
| AI | 66% |
| **Cooking** | **67%** |
| **whole collection** | **73%** (~1.7M of 2.33M points) |

Symptoms this explains, all of which looked like unrelated problems:

* Ingest runs that "hung" and died before reaching the back of the queue. *Japanese
  Cooking — A Simple Art* (507 illustrated pages) produced **56,200 chunks of pure
  base64** in 100 minutes of GPU time.
* The Great Courses guidebook's 10,145 "passages" — all base64.
* Retrieval quality across every corpus, fighting through noise on every query.
* No image was ever actually described, despite `IMAGE_EXTRACTION_ENABLED=true`.

### The fix

`/opt/ai-stack/rag-api-src/docling_client.py` (backup: `.bak-imagescrub`):

1. `_IMG_RE` now allows `\s` inside the base64 group, so it matches real docling output.
2. New `_scrub_images()` replaces each image with `[image: caption]` in `full_text` and
   in every page before chunking — the position of a figure stays readable, the pixels
   go to the vision model as originally intended.
3. `_extract_images` strips whitespace from the base64 before handing it to the vision
   client.
4. The convert request now sends `md_page_break_placeholder="\f"`. `_parse_docling_response`
   already split pages on `\f`; nothing had ever asked docling to emit it, which is why
   **every docling-ingested PDF reported page 1**.

### Remediation

`/tmp/remediate_corpus.py` (source kept in the repo's scratchpad):

```bash
python3 -u /tmp/remediate_corpus.py scan   # read-only: classify + write ids/report
python3 -u /tmp/remediate_corpus.py purge  # delete what scan found
```

Two passes, so scroll pagination never races its own deletes. The classifier is
deliberately conservative: a chunk counts as poison only if, after removing long base64
runs, under 40 characters of prose remain — a security doc quoting a base64 payload
*inside real prose* is kept. Outputs `/tmp/rag-poison-ids.txt` and a per-source report at
`/tmp/rag-remediate-report.json`.

After purging, re-ingest with `docs/rebuild_corpus.py` (`plan` to preview, `run` to do
it, optional folder names to scope). It clears each file's row in `processed_files`
(`/data/state.db`) first — otherwise `is_changed` sees an unchanged mtime/size and skips
the file — and works one file at a time so the GB10s stay available for the assistants.

### Measured outcome (2026-08-28)

* Scan: **1,703,946 of 2,354,545 points poisoned (72%)** across 743 sources.
  Networking 99% · threat-intel 95% · Hacking 93% · Project Management 92% ·
  Cooking 80% · Coding 79% · NIST 75% · AI 67%. 277 sources were >98% poison.
* Purge: 1,703,946 points removed in 51s → **653,162 real points remain**.
* Rebuild: 529 sources re-read through the fixed pipeline, Cooking first.
* Proof the fix works: *Japanese Cooking — A Simple Art* went from **56,200 chunks of
  base64** to **2,268 chunks of real text**; the Culinary Scrapbook came back with real
  page numbers (50, 74, 59, 28…) instead of `page: 1`.

### Two traps worth remembering

**Qdrant point ids here are integers.** Sending them quoted is an HTTP 400 that deletes
nothing — silent if you do not read the log.

**Point ids are deterministic** (`make_point_id` over doc_id + chunk_index), so a file
re-ingested *before* its old poisoned ids are purged will have its fresh chunks deleted
by that purge. Purge first, then rebuild — which is the order `rebuild_corpus.py`
assumes.


---

## Ingestion performance (2026-08-28)

The repair surfaced why ingestion never finished. Three causes, none of them the GPUs.

### 1. Atlas has no GPU, and docling was doing GPU work on a Xeon D

`ghcr.io/docling-project/docling-serve:latest` ships `torch 2.13.0+cu130` and reports
`cuda available: False` on Atlas — there is no card in the box. Layout detection, table
structure and OCR have been running on 16 low-power Xeon cores. Measured during a real
ingest: **docling ~500-800% CPU, rag-api 0.26%**. Embedding was never the constraint, so
adding GB10 capacity would have accelerated nothing.

### 2. OCR was running on PDFs that already had text

Same 12 pages, same file, measured on both workers:

| worker | OCR on | OCR off |
|---|---|---|
| Atlas | 118.8s | **55.1s** |
| Cerberus | 46.7s | **18.8s** |

The markdown differs by 0.01% (1,614,292 vs 1,614,131 chars) — on a text-layer PDF, OCR
costs half the runtime and contributes nothing. `docling_client._has_text_layer` now
samples the file's own content streams and sets `do_ocr` per file.

It is dependency-free because rag-api's image has no pypdf, and it **fails safe**: only a
confident text-layer reading skips OCR; scans and anything ambiguous keep it. Two traps
found while writing it — counting `Tf` (font *selection*, present on scanned pages too)
and running the operator regex over raw compressed bytes (4 MB of JPEG contains "Tj" by
chance ~60 times) both misread a pure scan as having text, which is the dangerous
direction.

### 3. One worker, and the slower one

**Cerberus** (`192.168.1.22`, 16 cores, 499 GB) runs a second docling and is **2.5×
faster than Atlas at the same core count**. An nginx least-connections balancer
(`docling-lb` on the `ai` network, weight 3:1 toward Cerberus) fronts both;
`DOCLING_URL` points at it.

### Result

*Japanese Cooking — A Simple Art* (517 pages): **4+ hours → 15 minutes**. The three
poisoned Cooking sources rebuilt in **23 minutes total**.

## Whisper was never broken

Every `.webm` failure was Whisper correctly refusing a corrupt file:

```
[matroska,webm] EBML header parsing failed
Error opening input: Invalid data found when processing input
```

The SANS `.webm` files begin with megabytes of zero bytes (`file` reports `data`). A
header scan of the whole video library:

| corpus | valid | zero-filled |
|---|---|---|
| Cooking | **89** | 0 |
| Hacking | 9,047 | 98 |

Every Cooking video is valid; a Great Courses lecture transcribes to 42 chunks.

`whisper_client.transcribe` now checks the container header before uploading (12 bytes of
I/O against a 78 MB upload and a GPU slot), and `main.py` treats a container-parse
failure as **permanent**. Previously these retried forever: 1,479 failed attempts in one
day, one file at 435 retries.

## Machine roles

| machine | role |
|---|---|
| **Atlas** (16-core Xeon D, no GPU) | qdrant, rag-api, docling worker #2, the app |
| **Cerberus** (16 cores, 499 GB) | docling worker #1 — 2.5× Atlas, weighted accordingly |
| **Stronghold** (RTX 3060 Ti, 8 cores) | Docker installed; best used as a second Whisper node — documents are no longer the bottleneck, transcription is |
| **Wile / RoadRunner** (GB10) | embeddings, vision, chat. Deliberately left alone: they serve the assistants and embedding was never the constraint |

Stronghold's Tailscale ACL blocks SSH as `guapo`; reach it as `soadmin` over the LAN
(`192.168.1.31`). Atlas's key is installed there.

---

## Repair complete (2026-08-29)

All 529 poisoned sources rebuilt through the fixed pipeline — Hacking 126, Networking
159, AI/NIST/Coding/threat-intel/PM/MITRE 241, Cooking 3 — with **zero failures**.

| | before | after |
|---|---|---|
| index poison | **72%** (1,703,946 of 2,354,545) | **0.1%** (sampled 8,000) |
| Cooking shelf | ~18 entries, half unreadable | **23 of 28 searchable, 50,825 passages** |

The scheduled sweep is re-enabled. Its first run failed 99 files: 98 are the corrupt
SANS `.webm`s, now rejected by the header check in twelve bytes rather than a 78 MB
upload and a GPU slot, and one is Modernist Bread — a 471 MB scan that 502'd through the
load balancer.

Two things learned re-enabling it, both worth repeating:

* **`systemctl enable --now` fires a sweep immediately.** Retrieval then runs ~31s
  instead of ~4s for the duration, exactly as `atlas_rag`'s 60s timeout comment
  predicted, and a retrieval eval run during it will time out. Enable without `--now`
  unless you want the sweep.
* **nginx buffered whole conversion responses to disk.** `proxy_request_buffering off`
  covered uploads; responses need `proxy_buffering off` and
  `proxy_max_temp_file_size 0` as well. A 500 MB scan converts to a very large body
  (images arrive base64-embedded before rag-api scrubs them), and spooling it gave a
  worker restart a window to become a 502 for the whole document.

## Still not searchable, and why

Four books are scans docling's OCR cannot read — proven on Institut Paul Bocuse: 13
words per three pages, identical across `auto`/`easyocr`/`tesseract` and across render
scales 2/4/6/8. The pages are legible; the vision model transcribes them perfectly from
the same images ("Makes 425 g. Preparation: 10 minutes • Chilling: at least 1 hour…").

That leaves one route: transcribe scans with the vision model instead of OCR, at roughly
one GB10 call per page — Bocuse 721pp, Modernist Bread 804pp, Fat Duck 527pp, Modernist
vols ~2,000pp. Ten-plus hours of GPU that competes with the assistants, so it is a
deliberate decision rather than something to switch on. Worth doing one book first.

The fifth entry, *Parts Unknown*, contains only a `.nfo` — there is no video to index.

## The retrieval eval, nightly (2026-09-06)

The eval (`api/tests/test_retrieval_eval.py`) only runs with `RAG_EVAL=1` against the live
rag-api, and it only grows when somebody adds a question. Two things close that loop:

- **Questions come from use.** Every answer in Ask takes a thumbs up or down (stored on
  `message.feedback`). `uv run python scripts/promote_golden.py` turns thumbs-up answers into
  golden questions with `expect_any` filled from the books the cook saw cited — the verdict is
  the label that `harvest_questions.py` deliberately refuses to invent. `--write` appends; then
  re-record the baseline on purpose.
- **The ratchet runs without anyone remembering.** On Atlas, a timer beside `rag-ingest.timer`:

  ```
  # /etc/systemd/system/sharp-edge-eval.service
  [Service]
  Type=oneshot
  WorkingDirectory=/opt/sharp-edge/api
  Environment=RAG_EVAL=1
  ExecStart=/usr/bin/env uv run --extra dev pytest tests/test_retrieval_eval.py -q
  ```
  ```
  # /etc/systemd/system/sharp-edge-eval.timer
  [Timer]
  OnCalendar=*-*-* 04:30
  Persistent=true
  [Install]
  WantedBy=timers.target
  ```

  `journalctl -u sharp-edge-eval` shows the per-question outcomes; a HIT that became a MISS
  fails the unit, which is the only alarm this needs. Operator action — nothing in this repo
  installs it.
