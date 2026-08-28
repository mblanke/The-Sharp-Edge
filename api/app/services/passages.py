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
from difflib import SequenceMatcher
from typing import Any

from app.services.shelf import resolve_path

__all__ = ["Passage", "looks_like_index", "to_passages", "is_media"]

#: Sources with no page structure at all — a "page" on these is a chunking artefact.
_MEDIA_TYPES = frozenset({"mkv", "mp4", "webm", "avi", "mov", "m4v", "mp3", "wav", "m4a"})


def is_media(file_type: str | None) -> bool:
    """True for a transcript source, where a page number would be meaningless."""
    return str(file_type or "").lower().lstrip(".") in _MEDIA_TYPES

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
#: A segment ending in real sentence punctuation.
_TERMINAL = re.compile(r"[.!?][\"')\]]?\s*$")
#: The cross-reference that only ever appears in a back-of-book index.
_SEE_ALSO = re.compile(r"\bsee also\b|\bsee\s+[A-Z]", re.I)


def _first_letter(segment: str) -> str:
    for ch in segment:
        if ch.isalpha():
            return ch.lower()
    return ""


def _looks_alphabetical(segments: list[str]) -> bool:
    """A back-of-book index whose page numbers didn't survive extraction.

    The contents detector keys on trailing page numbers and the generic detector keys on
    short segments with no sentences. An alphabetical index from an EPUB defeats both: the
    page numbers are gone, the entries run long ("Black Pepper-Crusted Filet Mignon with
    Goat Cheese and Roasted Red Pepper-Ancho Chile Vinaigrette"), and one stray "Squash.
    See also Zucchini" is enough to make `sentences == 0` false. That is how the FCI index
    kept winning "onion soup gratinée" — it contains the dish name verbatim.

    What actually separates it from prose is that every entry is a *heading*: title-case
    start, no terminal punctuation, and first letters that broadly climb the alphabet.
    """
    if len(segments) < 8:
        return False

    starts = [_first_letter(s) for s in segments]
    if not all(starts):
        return False

    titlecase = sum(1 for s in segments if s[:1].isupper()) / len(segments)
    terminal = sum(1 for s in segments if _TERMINAL.search(s)) / len(segments)
    pairs = list(zip(starts, starts[1:]))
    monotone = sum(1 for a, b in pairs if b >= a) / len(pairs)

    if titlecase < 0.85 or terminal > 0.1:
        return False
    # "See also" is decisive on its own — nothing but an index says it.
    if _SEE_ALSO.search(" ".join(segments)):
        return monotone >= 0.5
    return monotone >= 0.7


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

    # An alphabetical index survives the digit guard (its page numbers were stripped by
    # extraction) and the shape guards below (its entries are long). Checked before the
    # digit guard so an index that kept a few numbers is still caught.
    if _looks_alphabetical(segments):
        return True

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
    return _drop_duplicate_editions(passages)[:keep]


#: How alike two passage openings must be before the lower-scoring one is a duplicate.
_DUPLICATE_RATIO = 0.9
_DUPLICATE_PREFIX = 200


def _normalise(text: str) -> str:
    return " ".join((text or "").split()).casefold()[:_DUPLICATE_PREFIX]


def _drop_duplicate_editions(passages: list[Passage]) -> list[Passage]:
    """Collapse one *work* that is indexed twice under two folder names.

    The shelf holds several books twice — Franklin Barbecue and Medium Raw are each
    indexed under two directories, 726 and 907 chunks apiece. Both copies match equally
    well, so they arrive as two passages saying the same thing from two `doc_id`s: on one
    real query six of twenty-four candidate slots went to two identical copies of one
    book. The cook reads the same paragraph twice and the pool is a quarter smaller than
    it looks.

    Deliberately narrow. Two passages are only ever collapsed when `shelf.resolve_path`
    says they are the same work; near-identical text from two genuinely different books
    is kept, because that is a real corroboration between sources and not a duplicate.
    Same-document repetition is left to merging.
    """
    kept: list[Passage] = []
    for passage in passages:
        prefix = _normalise(str(passage.get("text") or ""))
        book = resolve_path(str(passage.get("source_path") or ""))
        if not prefix or not book:
            kept.append(passage)
            continue
        duplicate = any(
            k.get("doc_id") != passage.get("doc_id")
            and resolve_path(str(k.get("source_path") or "")) == book
            and SequenceMatcher(None, prefix, _normalise(str(k.get("text") or ""))).ratio()
            >= _DUPLICATE_RATIO
            for k in kept
        )
        if not duplicate:
            kept.append(passage)
    return kept


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
    # A transcript has no pages. Whisper chunks still carry a `page`, so the Keller
    # sous-vide lesson cites "p.2" and the UI offers to open page 2 of a book that is an
    # .mkv — a link that can only 404. Confident and wrong is worse than silent.
    file_type = str(head.get("file_type") or "").lower().lstrip(".")
    if file_type in _MEDIA_TYPES:
        page_start = page_last = None

    text = strip_page_markers(raw)
    return Passage(
        text=text,
        source_path=head.get("source_path"),
        title=head.get("title"),
        file_type=head.get("file_type"),
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
