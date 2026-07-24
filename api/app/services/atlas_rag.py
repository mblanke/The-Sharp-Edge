r"""Client for the Atlas rag-api (CLAUDE.md §9 — retrieval is delegated).

Atlas owns ingestion: books dropped in \\Olympus_NAS\Media\References\Cooking
are swept by rag-ingest.timer every 6 h and embedded on the GB10 nodes.
This client only retrieves, filtered to the Cooking source folder.
"""

from typing import Any

import httpx
from fastapi import HTTPException

from app.config import settings


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


class AtlasRag:
    def __init__(self, base_url: str | None = None, client: httpx.AsyncClient | None = None):
        self.base_url = (base_url or settings.rag_api_url).rstrip("/")
        self._client = client

    def _http(self) -> httpx.AsyncClient:
        if self._client is None:
            # generous timeout — retrieval degrades to ~30s while Atlas runs a bulk ingest
            self._client = httpx.AsyncClient(base_url=self.base_url, timeout=60.0)
        return self._client

    async def retrieve(self, question: str, top_k: int | None = None) -> list[dict]:
        """Vector + rerank retrieval, client-side filtered to the Cooking corpus."""
        keep = top_k or settings.rag_top_k
        try:
            res = await self._http().post(
                "/retrieve",
                json={"question": question, "top_k": max(settings.rag_fetch_k, keep)},
            )
            res.raise_for_status()
        except httpx.HTTPError as exc:
            raise HTTPException(502, f"Atlas rag-api unreachable: {exc}") from exc
        chunks = res.json().get("chunks", [])
        scoped = [c for c in chunks if _in_scope(c, settings.rag_source_folder)]
        return scoped[:keep]

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
