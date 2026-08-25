"""Turn raw retrieved chunks into something a cook can read.

Retrieval hands back individual chunks ranked by similarity. Two things make that
unusable as a search result:

1. **Index and table-of-contents pages outrank real recipes.** A cookbook index
   contains the line "French Onion Soup" verbatim, so it is a near-perfect lexical
   match for the query "french onion soup" — and it beats the actual recipe, which
   phrases things in prose. Observed on the real corpus: the top three hits for that
   query were all page 53 of The French Laundry, i.e. its index.

2. **A recipe is longer than one chunk.** Chunks land mid-sentence, so a single one
   reads as a fragment. Adjacent chunks from the same document are contiguous text
   and should be shown as one passage.

Both are fixed here, on the read side. Nothing about ingestion changes.
"""

from __future__ import annotations

import re
import statistics
from typing import Any

__all__ = ["Passage", "looks_like_index", "to_passages"]

_SEGMENT_SPLIT = re.compile(r"\n\s*\n")

# Books whose text layer we extracted ourselves carry explicit "[page N]" markers,
# because a plain .txt has no page structure and every chunk would otherwise cite
# page 1 — useless for finding the recipe in the physical book. The marker is read
# back into the page number here and stripped from the displayed text.
_PAGE_MARKER = re.compile(r"\[page\s+(\d+)\]\s*")
# Deliberately no ':' in this class. Cookbook indexes are full of "Soups:",
# "Mousse:", "Mushrooms:" — counting a colon as a sentence ending makes every index
# page look like prose, which is the exact bug this module exists to fix.
_SENTENCE_END = re.compile(r"[.!?](?:\s|$)")


#: A quantity opening a line — digits or a vulgar fraction.
_LEADING_QUANTITY = re.compile(r"^[\d¼½¾⅓⅔⅛⅜⅝⅞]")
#: A page number closing a line.
_TRAILING_PAGE = re.compile(r"\d\s*$")


def _looks_like_contents(text: str) -> bool:
    """A table of contents: dish names with page numbers hanging off the right.

    Split on single newlines rather than blank lines — a contents page is a dense
    column, and the blank-line segmentation used elsewhere collapses it into one blob.
    """
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    if len(lines) < 6:
        return False
    trailing = sum(1 for ln in lines if _TRAILING_PAGE.search(ln)) / len(lines)
    leading = sum(1 for ln in lines if _LEADING_QUANTITY.match(ln)) / len(lines)
    return trailing >= 0.4 and trailing > leading


def looks_like_index(text: str) -> bool:
    """True for index / table-of-contents / recipe-list pages.

    Measured on the real Cooking corpus, three kinds of chunk separate cleanly:

    | kind             | sentences | short segments | segments with digits |
    |------------------|-----------|----------------|----------------------|
    | index / contents | 0         | 70-100%        | 0%                   |
    | ingredient list  | 0-9       | 33-84%         | 40-100%              |
    | prose            | 4-9       | 0-47%          | 0-74%                |

    An ingredient list looks like an index by segment length alone — both are stacks
    of short lines — so digits are the discriminator: quantities. Dropping ingredient
    lists would be worse than keeping a few indexes, hence the digit guard first.
    """
    if not text or not text.strip():
        return True

    # A table of contents is *also* full of digits, so the digit guard further down
    # waves it through as an "ingredient list". Where the digits sit is the
    # discriminator:
    #
    #     contents:        Onion Soup    335        → line ENDS with a page number
    #     ingredient list: 40 grams Vidalia onion   → line STARTS with a quantity
    #
    # Measured on the real corpus for "french onion soup": the CIA's contents page
    # scored 0.78 lines-ending-in-digits against 0.00 for every genuine ingredient list
    # retrieved alongside it. Checked first because a contents page is a dense column
    # with almost no blank lines — it has ~2 blank-line segments, so the segment-count
    # guard below would otherwise return False before this ever ran.
    if _looks_like_contents(text):
        return True

    segments = [s.strip() for s in _SEGMENT_SPLIT.split(text) if s.strip()]
    if not segments:
        return True
    # An index is a *list*. Something with a handful of segments is just a short
    # chunk — let the ranking judge it rather than discarding it here. Every real
    # index chunk observed in the corpus had 16–43 segments.
    if len(segments) < 6:
        return False

    lengths = [len(s.split()) for s in segments]
    median_words = statistics.median(lengths)
    short_fraction = sum(1 for n in lengths if n <= 5) / len(lengths)
    digit_fraction = sum(1 for s in segments if any(c.isdigit() for c in s)) / len(segments)
    sentences = len(_SENTENCE_END.findall(text))

    if digit_fraction >= 0.15:
        return False  # carries quantities — an ingredient list or a real passage

    # A wall of short title-case fragments with nothing resembling a sentence.
    if sentences == 0 and short_fraction >= 0.6 and len(segments) >= 6:
        return True
    # Extremely terse throughout, with at most a stray full stop.
    if median_words <= 3 and short_fraction >= 0.8 and sentences <= 1:
        return True
    return False


class Passage(dict):
    """One contiguous run of text: the merge of one or more adjacent chunks."""


def _key(chunk: dict[str, Any]) -> str:
    return str(chunk.get("doc_id") or chunk.get("source_path") or chunk.get("title") or "")


def _index_of(chunk: dict[str, Any]) -> int | None:
    raw = chunk.get("chunk_index")
    return int(raw) if isinstance(raw, (int, float)) else None


def _score(chunk: dict[str, Any]) -> float:
    for field in ("rerank_score", "score"):
        value = chunk.get(field)
        if isinstance(value, (int, float)):
            return float(value)
    return 0.0


def to_passages(
    chunks: list[dict[str, Any]],
    *,
    keep: int = 8,
    drop_indexes: bool = True,
    max_gap: int = 1,
) -> list[Passage]:
    """Rank-preserving: filter index pages, merge adjacent chunks, keep the best `keep`.

    `max_gap` is how far apart two `chunk_index` values may be and still be treated as
    contiguous — 1 means strictly adjacent.
    """
    usable = [c for c in chunks if not (drop_indexes and looks_like_index(str(c.get("text") or "")))]
    if not usable:
        # Everything looked like an index. Better to show the fragments than nothing.
        usable = list(chunks)

    # Best score per document decides the document's rank; merging happens within it.
    by_doc: dict[str, list[dict[str, Any]]] = {}
    for chunk in usable:
        by_doc.setdefault(_key(chunk), []).append(chunk)

    passages: list[Passage] = []
    for doc_chunks in by_doc.values():
        indexed = [c for c in doc_chunks if _index_of(c) is not None]
        loose = [c for c in doc_chunks if _index_of(c) is None]
        indexed.sort(key=lambda c: _index_of(c) or 0)

        run: list[dict[str, Any]] = []
        for chunk in indexed:
            if run and (_index_of(chunk) or 0) - (_index_of(run[-1]) or 0) > max_gap:
                passages.append(_merge(run))
                run = []
            run.append(chunk)
        if run:
            passages.append(_merge(run))
        passages.extend(_merge([c]) for c in loose)

    passages.sort(key=lambda p: p.get("score") or 0.0, reverse=True)
    return passages[:keep]


def marked_pages(text: str) -> list[int]:
    """Page numbers written into the text by our own PDF text extraction."""
    return [int(n) for n in _PAGE_MARKER.findall(text or "")]


def strip_page_markers(text: str) -> str:
    return _PAGE_MARKER.sub("", text or "").strip()


def _merge(run: list[dict[str, Any]]) -> Passage:
    head = max(run, key=_score)
    pages = sorted({int(c["page"]) for c in run if isinstance(c.get("page"), (int, float))})
    raw = "\n\n".join((c.get("text") or "").strip() for c in run if (c.get("text") or "").strip())

    # An extracted .txt has no page structure, so every chunk reports page 1. When the
    # text carries our own markers, believe those instead — they are the real page.
    marked = marked_pages(raw)
    if marked:
        pages = sorted(set(marked))
        page_start, page_last = pages[0], pages[-1]
    elif pages == [1]:
        # No marker, and the only page claimed is 1. For an extracted text layer that
        # is the placeholder, not a fact — a chunk from page 266 would say the same.
        # A citation of "p.1" sends someone to the title page; no page number at all
        # is honest. Real page-1 content loses its number, which is the cheaper error.
        page_start = page_last = None
    else:
        page_start = pages[0] if pages else head.get("page")
        page_last = pages[-1] if pages else head.get("page")
    text = strip_page_markers(raw)
    return Passage(
        text=text,
        source_path=head.get("source_path"),
        title=head.get("title"),
        heading=head.get("heading") or next((c.get("heading") for c in run if c.get("heading")), None),
        page=page_start,
        page_end=page_last,
        score=_score(head),
        rerank_score=head.get("rerank_score"),
        chunk_count=len(run),
        # Carried so a passage can be expanded into its neighbours later
        # (services/expand.py). The best-scoring chunk of the run is the anchor.
        doc_id=head.get("doc_id"),
        chunk_index=head.get("chunk_index"),
    )
