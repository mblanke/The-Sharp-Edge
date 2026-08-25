"""Retrieval quality harness (D2) — runs against the LIVE Atlas rag-api.

Skipped unless RAG_EVAL=1 (needs the tailnet + a populated references_v2).
Reports per-question hit@8 and asserts a floor; ratchet MIN_HIT_RATE up as
the shelf and golden set grow. This is the safety net for every retrieval
change (book scope, query rewriting, over-fetch tuning).
"""

import json
import os
from pathlib import Path

import pytest

GOLDEN = json.loads((Path(__file__).parent / "golden_questions.json").read_text())["questions"]

MIN_HIT_RATE = 0.5  # starter floor — raise once a baseline is recorded

pytestmark = [
    pytest.mark.slow,
    pytest.mark.skipif(os.environ.get("RAG_EVAL") != "1", reason="live-Atlas eval; set RAG_EVAL=1"),
]


async def test_hit_at_8():
    from app.services.atlas_rag import AtlasRag

    rag = AtlasRag()
    results: list[tuple[str, bool, list[str]]] = []
    for item in GOLDEN:
        chunks = await rag.retrieve(item["q"], top_k=8)
        paths = [str(c.get("source_path") or "").casefold() for c in chunks]
        hit = any(want.casefold() in p for want in item["expect"] for p in paths)
        results.append((item["q"], hit, paths[:3]))
    await rag.aclose()

    hits = sum(1 for _, h, _ in results if h)
    rate = hits / len(results)
    report = "\n".join(
        f"  {'✓' if h else '✗'} {q}" + ("" if h else f"  → top: {top}") for q, h, top in results
    )
    print(f"\nretrieval eval — hit@8 {hits}/{len(results)} ({rate:.0%})\n{report}")
    assert rate >= MIN_HIT_RATE, f"hit@8 {rate:.0%} below floor {MIN_HIT_RATE:.0%}\n{report}"
