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

## Step 6 is a hypothesis, not a certainty

Deleting the `.txt` twins should make docling read the PDFs and record real pages. It is
worth doing — the flagship reference currently cannot be cited to a page — but confirm
before assuming: after the sweep, a retrieval for a Professional Chef topic should return
`file_type: pdf` with plausible page numbers. If it comes back pageless or the PDF fails
to extract, restore the `.txt` from a backup rather than leaving the book unsearchable.

Note also that a recorded page is a **PDF page index**, not the printed page number — one
CIA chunk's marker read 311 while its own running footer read 287. That is correct for
`/library/source`, which slices by PDF index, and wrong for a cook holding the book. How
general the offset is across the shelf is not yet known; it needs its own investigation
before anything tries to "correct" it.
