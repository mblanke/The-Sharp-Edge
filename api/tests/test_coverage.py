"""Coverage reconciliation — offline. The facet call itself is mocked.

The behaviour that matters most here is the failure mode: coverage is a badge on a page,
and an unreachable Qdrant must degrade to "unknown" rather than to "nothing is indexed".
Getting that backwards would mark every book missing the first time the tailnet blinked.
"""

import httpx
import pytest

import app.services.coverage as coverage_module
from app.services.coverage import (
    THIN_CHUNKS,
    book_coverage,
    describe,
    indexed_book_ids,
    indexed_chunk_counts,
)

ROOT = "/mnt/references/Cooking/"

FACET = {
    "result": {
        "hits": [
            {"value": ROOT + "Culinary Institute of America - The Professional Chef.txt", "count": 5423},
            {"value": ROOT + "_acquired/On Food and Cooking.epub", "count": 3126},
            # two folders, one work — must sum, not compete
            {"value": ROOT + "Franklin Barbecue - Aaron Franklin/x.epub", "count": 726},
            {"value": ROOT + "Franklin Barbecue_ A Meat-Smoking Manifesto EPUB/y.epub", "count": 726},
            # 875 MB of PDFs on the shelf, represented by a 1 KB blurb file
            {"value": ROOT + "Modernist Cuisine Volume 1-6/Modernist Cuisine.txt", "count": 2},
            # indexed, belongs to no book
            {"value": ROOT + "_acquired/_sourcing-report.md", "count": 13},
        ]
    }
}


@pytest.fixture(autouse=True)
def _clear_cache():
    coverage_module._cache = None
    yield
    coverage_module._cache = None


def _client(handler):
    transport = httpx.MockTransport(handler)

    class _AC(httpx.AsyncClient):
        def __init__(self, *a, **kw):
            kw["transport"] = transport
            super().__init__(*a, **kw)

    return _AC


def _ok(request):
    return httpx.Response(200, json=FACET)


async def test_counts_and_book_rollup(monkeypatch):
    monkeypatch.setattr(httpx, "AsyncClient", _client(_ok))
    counts = await indexed_chunk_counts()
    assert counts[ROOT + "_acquired/On Food and Cooking.epub"] == 3126

    books = await book_coverage()
    assert books["professional-chef"].status == "indexed"
    # the two Franklin folders are one book
    assert books["franklin-barbecue"].chunks == 1452
    # present in name only
    assert books["modernist-cuisine"].status == "thin"
    assert books["modernist-cuisine"].chunks == 2
    # on the shelf, nothing indexed
    assert books["under-pressure"].status == "missing"
    assert books["flavor-bible"].chunks == 0


async def test_only_real_books_are_searchable(monkeypatch):
    monkeypatch.setattr(httpx, "AsyncClient", _client(_ok))
    ids = await indexed_book_ids()
    assert "professional-chef" in ids
    assert "on-food-and-cooking" in ids
    # a stub file is not a book you can search
    assert "modernist-cuisine" not in ids
    assert "under-pressure" not in ids


async def test_unreachable_qdrant_means_unknown_not_empty(monkeypatch):
    """The important failure mode: never report every book as missing."""

    def boom(request):
        raise httpx.ConnectError("no route to host")

    monkeypatch.setattr(httpx, "AsyncClient", _client(boom))
    assert await indexed_chunk_counts() == {}
    assert await book_coverage() == {}
    assert await indexed_book_ids() == set()


async def test_result_is_cached(monkeypatch):
    calls = {"n": 0}

    def counting(request):
        calls["n"] += 1
        return httpx.Response(200, json=FACET)

    monkeypatch.setattr(httpx, "AsyncClient", _client(counting))
    await indexed_chunk_counts()
    await indexed_chunk_counts()
    assert calls["n"] == 1
    await indexed_chunk_counts(force=True)
    assert calls["n"] == 2


def test_describe_is_honest_about_stubs():
    assert "not indexed" in describe("under-pressure", 0)
    assert "probably not indexed" in describe("modernist-cuisine", 2)
    assert "5,423 passages" in describe("professional-chef", 5423)
    assert THIN_CHUNKS > 2
