"""Expanding a hit into the surrounding text, and recovering its page.

A retrieval hit is one ~3200-character window, so a recipe arrives as a fragment —
ingredients without the method, or method without its heading. The reported complaint
was exact: "in a perfect app it would give me the entire recipe not this garbage".
"""

import httpx
import pytest

from app.services.expand import expand_passages, infer_page


def chunk(index, text, page=1):
    return {"chunk_index": index, "text": text, "page": page,
            "doc_id": "d1", "title": "Book"}


# ----------------------------------------------------------------- page recovery

def test_the_marker_before_the_hit_is_the_page_it_is_on():
    """"[page N]" marks where page N begins, so the nearest marker at or before the
    hit is the page the hit sits on."""
    window = [chunk(10, "[page 358] start of the page"), chunk(11, "middle"),
              chunk(12, "[page 359] next page")]
    assert infer_page(window, 11) == 358


def test_a_marker_only_after_the_hit_means_the_page_before_it():
    """Measured on the real corpus: the hit at chunk 1467 had no marker, and 1469
    carried [page 359] — so 1467 is on 358."""
    window = [chunk(1467, "no marker here"), chunk(1468, "nor here"),
              chunk(1469, "[page 359] Onion Soup Gratinee")]
    assert infer_page(window, 1467) == 358


def test_the_nearest_preceding_marker_wins_not_the_first():
    window = [chunk(1, "[page 10] a"), chunk(2, "[page 11] b"), chunk(3, "c")]
    assert infer_page(window, 3) == 11


def test_no_marker_means_no_page_rather_than_a_guess():
    """A citation is used to find the passage in a physical book. Wrong is worse than
    absent — it sends someone to the wrong page of a 1,200-page textbook."""
    assert infer_page([chunk(1, "a"), chunk(2, "b")], 1) is None


def test_page_never_goes_below_one():
    assert infer_page([chunk(0, "[page 1] opening")], 0) == 1
    assert infer_page([chunk(5, "[page 1] opening")], 0) == 1


# ----------------------------------------------------------------- stitching

def _transport(window):
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/chunks"
        return httpx.Response(200, json={"chunks": window})
    return httpx.MockTransport(handler)


@pytest.mark.asyncio
async def test_a_fragment_becomes_a_readable_passage():
    window = [chunk(4, "FOR THE SOUP"), chunk(5, "Sweat the onions slowly."),
              chunk(6, "[page 359] Portion into crocks and brown.")]
    async with httpx.AsyncClient(transport=_transport(window),
                                 base_url="http://rag") as client:
        out = await expand_passages(
            [{"doc_id": "d1", "chunk_index": 5, "text": "Sweat the onions slowly.",
              "page": 1}], client)

    assert out[0]["expanded"] is True
    assert "FOR THE SOUP" in out[0]["text"]
    assert "Portion into crocks" in out[0]["text"]
    assert "[page 359]" not in out[0]["text"], "markers are plumbing, not content"
    # The hit is chunk 5; page 359 begins at chunk 6, so the hit is on 358.
    assert out[0]["page"] == 358


@pytest.mark.asyncio
async def test_chunk_overlap_is_not_shown_twice():
    """rag-api chunks overlap by 480 characters. Left in, a recipe reads with every few
    lines repeated."""
    tail = "Simmer for forty minutes until the onions are deeply caramelised."
    window = [chunk(1, f"Begin the soup. {tail}"),
              chunk(2, f"{tail} Then add the stock.")]
    async with httpx.AsyncClient(transport=_transport(window),
                                 base_url="http://rag") as client:
        out = await expand_passages(
            [{"doc_id": "d1", "chunk_index": 1, "text": "x"}], client)

    assert out[0]["text"].count("deeply caramelised") == 1


@pytest.mark.asyncio
async def test_only_the_best_few_are_expanded():
    """One request each, and nobody reads result eight in full."""
    calls = []

    def handler(request):
        calls.append(request)
        return httpx.Response(200, json={"chunks": [chunk(1, "a"), chunk(2, "b")]})

    passages = [{"doc_id": "d1", "chunk_index": i, "text": "x"} for i in range(8)]
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler),
                                 base_url="http://rag") as client:
        out = await expand_passages(passages, client, limit=3)

    assert len(calls) == 3
    assert len(out) == 8, "unexpanded results are still returned"


# ----------------------------------------------------------------- degradation

@pytest.mark.asyncio
async def test_search_survives_a_rag_api_without_the_endpoint():
    """The /chunks endpoint is an enhancement, not a dependency. An older rag-api 404s
    and search must keep working on the unexpanded passages."""
    def handler(request):
        return httpx.Response(404, json={"detail": "Not Found"})

    original = [{"doc_id": "d1", "chunk_index": 1, "text": "the original text",
                 "page": 12}]
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler),
                                 base_url="http://rag") as client:
        out = await expand_passages(original, client)

    assert out[0]["text"] == "the original text"
    assert out[0]["page"] == 12
    assert "expanded" not in out[0]


@pytest.mark.asyncio
async def test_passages_without_an_anchor_are_left_alone():
    def handler(request):
        raise AssertionError("should not be called")

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler),
                                 base_url="http://rag") as client:
        out = await expand_passages([{"text": "no doc_id or chunk_index"}], client)
    assert out[0]["text"] == "no doc_id or chunk_index"


@pytest.mark.asyncio
async def test_nothing_in_nothing_out():
    async with httpx.AsyncClient(base_url="http://rag") as client:
        assert await expand_passages([], client) == []


@pytest.mark.asyncio
async def test_an_index_neighbour_is_not_stitched_into_a_good_passage():
    """A recipe near the back of a book sits next to the index.

    Seen live in the app before this guard: a real CIA passage came back with
    "Soup, 335 / Soup Gratinée, 335 / Blackberry and Port-Poac…" welded onto the end —
    the contamination the read-side filter removes from the *ranking*, reappearing
    inside a single result.
    """
    index_page = "\n".join([
        "Passion and Mango-Poached 982-983", "Relish, Curried, 961",
        "Coconut Spicy, 442-443", "Butter, 300", "Soup, 335",
        "Soup Gratinee, 335", "Pear(s) 1148-1150", "Blackberry and Port-Poached 44",
    ])
    window = [chunk(5, "Sweat the onions slowly until deeply caramelised."),
              chunk(6, index_page)]
    async with httpx.AsyncClient(transport=_transport(window),
                                 base_url="http://rag") as client:
        out = await expand_passages(
            [{"doc_id": "d1", "chunk_index": 5, "text": "x"}], client)

    assert "deeply caramelised" in out[0]["text"]
    assert "Soup Gratinee, 335" not in out[0]["text"]


@pytest.mark.asyncio
async def test_the_anchor_is_kept_even_if_it_trips_the_index_check():
    """It earned its place in the ranking; dropping it would return an empty result."""
    listish = "\n".join(f"Ingredient {i}" for i in range(12))
    window = [chunk(3, listish)]
    async with httpx.AsyncClient(transport=_transport(window),
                                 base_url="http://rag") as client:
        out = await expand_passages(
            [{"doc_id": "d1", "chunk_index": 3, "text": listish}], client)
    assert out[0]["text"]
