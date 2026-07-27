"""Expand a retrieval hit into the surrounding text, and recover its page.

A hit is one ~3200-character chunk, so it lands mid-recipe: the ingredients arrive
without the method, or the method without its heading. The complaint that prompted this
was exact — *"in a perfect app it would give me the entire recipe not this garbage"*.

Atlas's rag-api gained a read-only ``POST /chunks`` endpoint that returns a contiguous
window by ``(doc_id, chunk_index)``. Pulling that window fixes two things at once:

1. **The passage becomes readable.** Six neighbouring chunks are ~5 000 characters of
   continuous text rather than a 900-character fragment.

2. **The page number comes back.** Books whose text layer we extracted ourselves carry
   ``[page N]`` markers only at page boundaries, so a chunk sitting inside a page has no
   marker and would otherwise be cited with no page at all. Measured before this: 23% of
   hits had no page. The marker is nearly always in a neighbour.
"""

from __future__ import annotations

import asyncio
from typing import Any

import httpx

from app.services.passages import _PAGE_MARKER

__all__ = ["expand_passages", "infer_page"]


def _markers_with_positions(chunks: list[dict[str, Any]]) -> list[tuple[int, int]]:
    """(chunk_index, page) for every ``[page N]`` marker in the window, in order."""
    found: list[tuple[int, int]] = []
    for chunk in chunks:
        index = chunk.get("chunk_index")
        if index is None:
            continue
        for page in _PAGE_MARKER.findall(str(chunk.get("text") or "")):
            found.append((int(index), int(page)))
    return sorted(found)


def infer_page(window: list[dict[str, Any]], hit_index: int) -> int | None:
    """The page the hit sits on, read from markers in the surrounding chunks.

    ``[page N]`` marks where page N *begins*, so:

    * the nearest marker at or before the hit is the page the hit is on;
    * if every marker is after the hit, the hit precedes the start of that page, so it
      is on the page before.

    Returns None when the window carries no marker at all — better no page than a wrong
    one, since a citation is used to find the passage in a physical book.
    """
    markers = _markers_with_positions(window)
    if not markers:
        return None

    before = [page for index, page in markers if index <= hit_index]
    if before:
        return before[-1]

    first_page = markers[0][1]
    return max(1, first_page - 1)


async def _window(
    client: httpx.AsyncClient, doc_id: str, chunk_index: int, before: int, after: int
) -> list[dict[str, Any]]:
    try:
        res = await client.post(
            "/chunks",
            json={"doc_id": doc_id, "chunk_index": chunk_index,
                  "before": before, "after": after},
        )
        res.raise_for_status()
        return res.json().get("chunks", [])
    except httpx.HTTPError:
        # The endpoint is an enhancement, not a dependency. An older rag-api without it
        # 404s and search keeps working on the unexpanded passages.
        return []


async def expand_passages(
    passages: list[dict[str, Any]],
    client: httpx.AsyncClient,
    limit: int = 4,
    before: int = 4,
    after: int = 4,
) -> list[dict[str, Any]]:
    """Fetch neighbours for the best `limit` passages and stitch them into place.

    Only the top few are expanded: each is one request, and nobody reads result eight in
    full. The rest keep their original text and page.
    """
    if not passages:
        return passages

    targets = [
        (i, p) for i, p in enumerate(passages[:limit])
        if p.get("doc_id") and p.get("chunk_index") is not None
    ]
    if not targets:
        return passages

    windows = await asyncio.gather(*[
        _window(client, str(p["doc_id"]), int(p["chunk_index"]), before, after)
        for _, p in targets
    ])

    out = list(passages)
    for (position, passage), window in zip(targets, windows):
        if len(window) <= 1:
            continue
        merged = dict(passage)
        merged["text"] = _stitch(window)
        merged["chunk_count"] = len(window)
        merged["expanded"] = True

        page = infer_page(window, int(passage["chunk_index"]))
        if page is not None:
            merged["page"] = page
            merged.setdefault("page_end", page)
        out[position] = merged
    return out


def _stitch(window: list[dict[str, Any]]) -> str:
    """Join a window into continuous text, dropping the page markers themselves.

    Chunks overlap by design (rag-api uses a 480-character overlap on 3200-character
    chunks), so the tail of one repeats the head of the next. Left in, a recipe reads
    with every few lines duplicated.
    """
    parts: list[str] = []
    for chunk in sorted(window, key=lambda c: c.get("chunk_index") or 0):
        text = _PAGE_MARKER.sub("", str(chunk.get("text") or "")).strip()
        if not text:
            continue
        if parts:
            text = _drop_overlap(parts[-1], text)
        if text:
            parts.append(text)
    return "\n\n".join(parts).strip()


def _drop_overlap(previous: str, current: str, max_overlap: int = 700) -> str:
    """Remove the longest suffix of `previous` that starts `current`."""
    window = min(len(previous), len(current), max_overlap)
    for size in range(window, 40, -1):
        if previous.endswith(current[:size]):
            return current[size:].lstrip()
    return current
