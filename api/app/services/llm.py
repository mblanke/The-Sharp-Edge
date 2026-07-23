"""LLM provider abstraction (CLAUDE.md §3, §9).

Hard rule: the Cooking corpus is the owner's private shelf. Corpus chunks may
only ever be sent to local models (the GB10 cluster via the LiteLLM router).
The Anthropic provider refuses any request that carries corpus chunks.
"""

import json
from collections.abc import AsyncIterator
from typing import Protocol

import httpx
from fastapi import HTTPException

from app.config import settings


class TierViolation(RuntimeError):
    """Private-tier content routed toward a cloud provider."""


class LLMProvider(Protocol):
    async def stream_chat(
        self, messages: list[dict], *, has_corpus_chunks: bool
    ) -> AsyncIterator[str]: ...


class RouterProvider:
    """OpenAI-compatible streaming chat against the Atlas LiteLLM router.

    Model alias 'cluster' load-balances Ollama on Wile and RoadRunner.
    """

    def __init__(self, base_url: str | None = None, client: httpx.AsyncClient | None = None):
        self.base_url = (base_url or settings.llm_router_url).rstrip("/")
        self._client = client

    def _http(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(
                base_url=self.base_url,
                timeout=httpx.Timeout(120.0, connect=10.0),
                headers={"Authorization": f"Bearer {settings.llm_router_key}"},
            )
        return self._client

    async def stream_chat(
        self, messages: list[dict], *, has_corpus_chunks: bool = False
    ) -> AsyncIterator[str]:
        payload = {
            "model": settings.chat_model_alias,
            "messages": messages,
            "stream": True,
        }
        try:
            async with self._http().stream("POST", "/chat/completions", json=payload) as res:
                if res.status_code != 200:
                    body = (await res.aread()).decode(errors="replace")[:300]
                    raise HTTPException(502, f"llm-router error {res.status_code}: {body}")
                async for line in res.aiter_lines():
                    if not line.startswith("data:"):
                        continue
                    data = line[5:].strip()
                    if data == "[DONE]":
                        break
                    try:
                        delta = json.loads(data)["choices"][0]["delta"].get("content")
                    except (KeyError, IndexError, json.JSONDecodeError):
                        continue
                    if delta:
                        yield delta
        except httpx.HTTPError as exc:
            raise HTTPException(502, f"llm-router unreachable: {exc}") from exc


class AnthropicProvider:
    """Cloud tier — public content only. Not yet implemented beyond the firewall."""

    async def stream_chat(
        self, messages: list[dict], *, has_corpus_chunks: bool = False
    ) -> AsyncIterator[str]:
        if has_corpus_chunks:
            raise TierViolation(
                "Corpus chunks are private-tier and never leave the local deployment"
            )
        raise HTTPException(501, "Anthropic provider not enabled; local cluster handles /ask")
        yield ""  # pragma: no cover — makes this an async generator


def get_provider() -> RouterProvider:
    """The /ask path always uses the local cluster (private-tier corpus)."""
    return RouterProvider()
