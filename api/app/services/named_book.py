"""When a question names a book you own, actually go and read that book.

The conversation log is unambiguous about this: "How does **the CIA** make french
onion soup", asked twice. The Professional Chef is on the shelf, its onion soup is
indexed, and retrieval still answered from The Food Lab and The French Laundry —
because naming a book in prose is a weak signal to a vector search, and gets weaker
as the shelf grows. Adding Larousse and Modernist made it worse, not better.

`services/shelf.authorities_in` already resolves "the CIA" to `professional-chef` for
the attribution note. This reuses that resolution for retrieval: run a *second*,
book-scoped search alongside the normal one and merge.

Second search rather than a hard scope, deliberately. A cook who names a book usually
wants that book but not exclusively — "how does the CIA make onion soup" is still well
served by a neighbouring source if the CIA turns out to be thin on it. Hard scoping
would turn a partial answer into no answer, and a book with nothing to say on the
subject would answer with silence.
"""

from __future__ import annotations

import logging

from app.services.shelf import authorities_in, book_by_id

logger = logging.getLogger("sharp-edge")

__all__ = ["named_book_globs", "merge_named_first"]

#: How many of the merged results are reserved for the named book. Enough that it is
#: genuinely represented, small enough that the rest of the shelf still answers.
RESERVED_SLOTS = 3


def named_book_globs(question: str) -> list[str]:
    """Path fragments for books this question names *and* the shelf actually holds.

    Empty when the question names nobody, or names only absent authorities — asking
    about Escoffier must not scope retrieval to nothing.
    """
    globs: list[str] = []
    for _display, book_ids in authorities_in(question):
        for book_id in book_ids:
            book = book_by_id(book_id)
            if book:
                globs.extend(book.globs)
    return list(dict.fromkeys(globs))


def merge_named_first(
    general: list[dict], from_named: list[dict], keep: int
) -> list[dict]:
    """Blend the two rankings, guaranteeing the named book a few slots.

    Order is preserved within each list, and anything already present in `general` is
    not repeated. When the named book returns nothing — it is on the shelf but has
    nothing to say here — this degrades to exactly the general ranking, which is the
    honest outcome and the one the attribution note then explains.
    """
    if not from_named:
        return general[:keep]

    def key(chunk: dict) -> tuple:
        return (
            str(chunk.get("source_path") or ""),
            chunk.get("chunk_index"),
            str(chunk.get("text") or "")[:80],
        )

    seen = set()
    merged: list[dict] = []
    reserved = min(RESERVED_SLOTS, keep)

    for chunk in from_named[:reserved]:
        merged.append(chunk)
        seen.add(key(chunk))

    for chunk in general:
        if len(merged) >= keep:
            break
        if key(chunk) not in seen:
            merged.append(chunk)
            seen.add(key(chunk))

    # Still short (a small shelf, or heavy overlap): top up from the named book.
    for chunk in from_named[reserved:]:
        if len(merged) >= keep:
            break
        if key(chunk) not in seen:
            merged.append(chunk)
            seen.add(key(chunk))

    return merged[:keep]
