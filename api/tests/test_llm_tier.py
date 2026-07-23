import pytest

from app.services.citations import chunks_block, extract_citations
from app.services.llm import AnthropicProvider, TierViolation


async def test_anthropic_refuses_corpus_chunks():
    provider = AnthropicProvider()
    with pytest.raises(TierViolation):
        async for _ in provider.stream_chat([{"role": "user", "content": "x"}], has_corpus_chunks=True):
            pass


def test_extract_citations_first_use_order_and_bounds():
    chunks = [
        {"title": "A", "source_path": "Cooking/a.pdf", "page": 1},
        {"title": "B", "source_path": "Cooking/b.pdf", "page": 2},
    ]
    answer = "Use B first [2], then A [1], B again [2], bogus [9]."
    cites = extract_citations(answer, chunks)
    assert [c["n"] for c in cites] == [2, 1]
    assert cites[0]["title"] == "B"


def test_chunks_block_numbering():
    block = chunks_block(
        [
            {"title": "Under Pressure", "heading": "Short Ribs", "page": 112, "text": "48h at 62C"},
            {"source_path": "Cooking/x.pdf", "text": "espagnole"},
        ]
    )
    assert block.startswith("[1] Under Pressure — Short Ribs p.112")
    assert "[2] Cooking/x.pdf" in block
