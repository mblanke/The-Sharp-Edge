r"""Client for the Atlas rag-api (CLAUDE.md §9 — retrieval is delegated).

Atlas owns ingestion: books dropped in \\Olympus_NAS\Media\References\Cooking
are swept by rag-ingest.timer every 6 h and embedded on the GB10 nodes.
This client only retrieves, filtered to the Cooking source folder.
"""

from typing import Any

import logging

import httpx
from fastapi import HTTPException

from app.config import settings
from app.services.expand import expand_passages
from app.services.lexical import hybrid_order
from app.services.named_book import merge_named_first, named_book_globs
from app.services.passages import to_passages



logger = logging.getLogger("sharp-edge")

class RagChunk(dict):
    """Chunk dict from rag-api /retrieve: text, source_path, page, heading,
    title, score, rerank_score, source_folder, chunk_index, doc_id, ..."""


def _in_scope(chunk: dict[str, Any], folder: str) -> bool:
    if not folder:
        return True
    source_folder = str(chunk.get("source_folder") or "")
    source_path = str(chunk.get("source_path") or "")
    return (
        source_folder == folder
        or source_path.startswith(f"{folder}/")
        or f"/{folder}/" in source_path
    )


def _in_books(chunk: dict[str, Any], books: list[str]) -> bool:
    """Match a chunk to any selected book by source-file name (case-insensitive)."""
    source_path = str(chunk.get("source_path") or "").casefold()
    basename = source_path.rsplit("/", 1)[-1]
    for book in books:
        b = book.strip().casefold()
        if b and (basename == b or b in source_path):
            return True
    return False


class AtlasRag:
    def __init__(self, base_url: str | None = None, client: httpx.AsyncClient | None = None):
        self.base_url = (base_url or settings.rag_api_url).rstrip("/")
        self._client = client

    def _http(self) -> httpx.AsyncClient:
        if self._client is None:
            # generous timeout — retrieval degrades to ~30s while Atlas runs a bulk ingest
            self._client = httpx.AsyncClient(base_url=self.base_url, timeout=60.0)
        return self._client

    async def retrieve(
        self,
        question: str,
        top_k: int | None = None,
        as_passages: bool = True,
        books: list[str] | None = None,
    ) -> list[dict]:
        """Vector + rerank retrieval, client-side filtered to the Cooking corpus.

        `as_passages` post-processes the raw chunks: index and table-of-contents pages
        are dropped and adjacent chunks are merged into continuous text (see
        services/passages.py). Without it, a query like "french onion soup" is topped
        by the *index entry* for that recipe rather than the recipe, because the index
        contains the phrase verbatim. Pass False to see the unprocessed ranking.

        `books` restricts results to the named source files (the /ask shelf selector),
        filtered here — rag-api can scope to a folder but not to a file.

        The folder scope is now server-side: `/retrieve` grew a `source_folder`
        parameter, so the whole `top_k` budget buys cooking results instead of being
        spent and discarded. `_in_scope` stays as a cheap post-filter in case rag-api
        regresses or is rolled back; it costs nothing when the server already did the
        work. Measured honestly, this changed almost no rankings — on six sample queries
        22-24 of 24 raw hits were already in the folder — but it makes `rag_fetch_k` mean
        what it says, and it makes book scope reliable rather than a game of over-fetch.
        """
        keep = top_k or settings.rag_top_k
        fetch = max(settings.rag_fetch_k, keep)
        if books:
            # Still a client-side filter, so keep some extra recall — but the doubled
            # fetch is gone now that every candidate is guaranteed to be from Cooking.
            fetch = max(fetch, 32)
        try:
            res = await self._http().post(
                "/retrieve",
                json={
                    "question": question,
                    "top_k": fetch,
                    "source_folder": settings.rag_source_folder,
                },
            )
            res.raise_for_status()
        except httpx.HTTPError as exc:
            raise HTTPException(502, f"Atlas rag-api unreachable: {exc}") from exc
        chunks = res.json().get("chunks", [])
        scoped = [c for c in chunks if _in_scope(c, settings.rag_source_folder)]
        if books:
            scoped = [c for c in scoped if _in_books(c, books)]

        if not as_passages:
            return scoped[:keep]

        # Merge first, rank second. The unit a cook reads is a passage, not a chunk —
        # ranking chunks and then merging would let four fragments of one recipe occupy
        # four of the eight result slots.
        passages = list(to_passages(scoped, keep=len(scoped) or keep))
        order = hybrid_order(question, passages)
        ranked = [passages[i] for i in order[:keep]]

        # Naming a book in prose is a weak signal to a vector search, and it weakens as
        # the shelf grows: "How does the CIA make french onion soup" was answered from
        # The Food Lab while the Professional Chef's onion soup sat indexed at rank 25.
        # Applied *after* ranking — the passage pipeline re-sorts by score, so a
        # reservation made before it is simply undone. Skipped when the caller scoped
        # explicitly: they have already said what they want.
        if not books:
            ranked = await self._with_named_book(question, ranked, keep)
        # Pull the neighbouring chunks for the best few so a result reads as a recipe
        # rather than a window that starts mid-sentence — and so text-extracted books
        # recover their page numbers from the markers in those neighbours.
        return await expand_passages(ranked, self._http())

    async def _with_named_book(
        self, question: str, general: list[dict], keep: int
    ) -> list[dict]:
        """Blend in a second search scoped to a book the question named.

        Best-effort: any failure returns the general ranking untouched, because a
        retrieval that names a book must never be worse than one that does not.
        """
        globs = named_book_globs(question)
        if not globs:
            return general

        try:
            res = await self._http().post(
                "/retrieve",
                json={
                    "question": question,
                    "top_k": max(settings.rag_named_book_fetch_k, keep),
                    "source_folder": settings.rag_source_folder,
                },
            )
            res.raise_for_status()
            candidates = res.json().get("chunks", [])
        except (httpx.HTTPError, ValueError) as exc:
            logger.warning("named-book retrieval failed, using general ranking: %s", exc)
            return general

        raw = [
            c
            for c in candidates
            if any(g in str(c.get("source_path") or "").casefold() for g in globs)
        ]
        if not raw:
            return general
        # Same treatment the general ranking got: index pages dropped, adjacent chunks
        # merged, then ranked against the question — otherwise the reserved slots would
        # be raw fragments sitting beside finished passages.
        merged = list(to_passages(raw, keep=len(raw)))
        order = hybrid_order(question, merged)
        from_named = [merged[i] for i in order]
        logger.info("question names a shelf book: reserving slots for %d passages", len(from_named))
        return merge_named_first(general, from_named, keep=max(len(general), keep))

    async def health(self) -> dict:
        try:
            res = await self._http().get("/health", timeout=8.0)
            res.raise_for_status()
            return res.json()
        except httpx.HTTPError as exc:
            return {"ok": False, "error": str(exc)}

    async def aclose(self) -> None:
        if self._client is not None:
            await self._client.aclose()


atlas_rag = AtlasRag()
