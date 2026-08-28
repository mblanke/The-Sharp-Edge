"""What is actually searchable, as opposed to what is sitting on the shelf.

`/library/books` lists files on a mounted directory. The vectors live in Atlas's Qdrant.
Nothing ever compared the two, so a book that failed to ingest looked exactly like a book
that indexed cleanly — and several had failed silently for months: *Under Pressure* and
*The Flavor Bible* still sealed in split `.zip` parts, *Modernist Cuisine* represented by
2 chunks off a 1 KB blurb file next to 875 MB of unread PDFs, *Kitchen Confidential* a
corrupt EPUB that had retried 426 times.

The count comes from a Qdrant **payload facet** on `source_path`: an indexed keyword
field, filtered by `source_folder`. That reads no vector, computes no embedding and takes
no GPU — which is what keeps it on the right side of CLAUDE.md §9. Similarity search from
this app would be a different thing entirely and stays forbidden; see DECISIONS.md.
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass

import httpx

from app.config import settings
from app.services.shelf import BOOKS, book_by_id, resolve_path

logger = logging.getLogger("sharp-edge")

__all__ = ["indexed_chunk_counts", "indexed_book_ids", "book_coverage", "BookCoverage"]

_TIMEOUT = 20.0
_TTL_SECONDS = 900  # 15 min: the shelf changes on a 6-hour ingest timer
_FACET_LIMIT = 500

# Below this, a book is present in name only — a stub .txt, a "free audiobook version"
# placeholder, a download-instructions file. Deliberately crude and deliberately visible.
THIN_CHUNKS = 20

_cache: tuple[float, dict[str, int]] | None = None
_lock = asyncio.Lock()


@dataclass(frozen=True)
class BookCoverage:
    book_id: str
    title: str
    chunks: int
    status: str  # indexed | thin | missing

    @property
    def searchable(self) -> bool:
        return self.status == "indexed"


async def indexed_chunk_counts(*, force: bool = False) -> dict[str, int]:
    """``source_path`` → chunk count for the cooking corpus. Empty dict if unreachable.

    Never raises: coverage is a badge on a page, and a badge must not be able to take the
    library down. Callers treat `{}` as "unknown", not as "nothing is indexed".
    """
    global _cache
    now = time.monotonic()
    if not force and _cache and now - _cache[0] < _TTL_SECONDS:
        return _cache[1]

    async with _lock:
        if not force and _cache and time.monotonic() - _cache[0] < _TTL_SECONDS:
            return _cache[1]
        try:
            async with httpx.AsyncClient(timeout=httpx.Timeout(_TIMEOUT, connect=5.0)) as client:
                res = await client.post(
                    f"{settings.qdrant_url.rstrip('/')}"
                    f"/collections/{settings.qdrant_collection}/facet",
                    json={
                        "key": "source_path",
                        "filter": {
                            "must": [
                                {
                                    "key": "source_folder",
                                    "match": {"value": settings.rag_source_folder},
                                }
                            ]
                        },
                        "limit": _FACET_LIMIT,
                        "exact": True,
                    },
                )
                res.raise_for_status()
                hits = res.json().get("result", {}).get("hits", [])
        except (httpx.HTTPError, KeyError, ValueError) as exc:
            logger.warning("coverage: qdrant facet unavailable (%s)", exc)
            return {}

        counts = {str(h["value"]): int(h["count"]) for h in hits if h.get("value")}
        _cache = (time.monotonic(), counts)
        return counts


async def book_coverage(*, force: bool = False) -> dict[str, BookCoverage]:
    """Per-book coverage keyed by canonical id. Empty when Qdrant is unreachable."""
    counts = await indexed_chunk_counts(force=force)
    if not counts:
        return {}

    totals: dict[str, int] = {}
    for path, count in counts.items():
        book_id = resolve_path(path)
        if book_id:
            totals[book_id] = totals.get(book_id, 0) + count

    out: dict[str, BookCoverage] = {}
    for book in BOOKS:
        n = totals.get(book.id, 0)
        status = "indexed" if n >= THIN_CHUNKS else ("thin" if n else "missing")
        out[book.id] = BookCoverage(book.id, book.title, n, status)
    return out


async def indexed_book_ids(*, force: bool = False) -> set[str]:
    """Book ids with enough chunks to be genuinely searchable.

    The retrieval eval uses this to separate "we own this and retrieval missed it" from
    "this book is not in the index" — the distinction that made the old hit-rate
    meaningless. Empty set means "could not determine", and callers must not read that as
    "nothing is indexed".
    """
    return {c.book_id for c in (await book_coverage(force=force)).values() if c.searchable}


def describe(book_id: str, chunks: int) -> str:
    """One human line for the admin/library UI."""
    book = book_by_id(book_id)
    title = book.title if book else book_id
    if chunks >= THIN_CHUNKS:
        return f"{title} — {chunks:,} passages indexed"
    if chunks:
        return f"{title} — only {chunks} passages; the book itself is probably not indexed"
    return f"{title} — not indexed"
