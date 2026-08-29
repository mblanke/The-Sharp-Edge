"""Naming a book you own should make retrieval read that book.

From the real log: "How does the CIA make french onion soup", asked twice, answered
from The Food Lab and The French Laundry while the Professional Chef's onion soup sat
indexed. Prose is a weak signal to a vector search, and it weakens as the shelf grows —
adding Larousse and Modernist made this failure worse, not better.
"""

import httpx
import pytest

from app.config import settings
from app.services.atlas_rag import AtlasRag
from app.services.named_book import RESERVED_SLOTS, merge_named_first, named_book_globs

ROOT = "/mnt/references/Cooking/"


def chunk(path: str, text: str = "x", idx: int = 0) -> dict:
    return {
        "source_path": ROOT + path,
        "source_folder": "Cooking",
        "text": text,
        "chunk_index": idx,
    }


# --- which books a question names ----------------------------------------------------


def test_owned_book_named_in_prose_is_resolved():
    globs = named_book_globs("How does the CIA make french onion soup")
    assert any("culinary institute" in g for g in globs)


def test_absent_authority_scopes_nothing():
    """Asking about Escoffier must not scope retrieval to a book that isn't there —
    that would turn a usable answer into no answer at all."""
    assert named_book_globs("How does Escoffier build an espagnole?") == []


def test_a_question_naming_nobody_scopes_nothing():
    assert named_book_globs("how long should I rest a steak") == []
    assert named_book_globs("maillard reaction temperature") == []


# --- the merge -----------------------------------------------------------------------


def test_named_book_gets_reserved_slots_without_evicting_everything():
    general = [chunk(f"other-{i}.epub", idx=i) for i in range(8)]
    named = [chunk("Culinary Institute of America.pdf", idx=i) for i in range(5)]

    merged = merge_named_first(general, named, keep=8)
    assert len(merged) == 8
    from_named = [c for c in merged if "Culinary" in c["source_path"]]
    assert len(from_named) == RESERVED_SLOTS
    # the rest of the shelf still answers
    assert len(merged) - len(from_named) == 8 - RESERVED_SLOTS


def test_nothing_from_the_named_book_degrades_to_the_general_ranking():
    """The book is on the shelf but has nothing to say here. That is an honest
    outcome, and the attribution note is what explains it."""
    general = [chunk(f"other-{i}.epub", idx=i) for i in range(5)]
    assert merge_named_first(general, [], keep=5) == general


def test_duplicates_are_not_repeated():
    shared = chunk("Culinary Institute of America.pdf", text="onion soup", idx=1)
    merged = merge_named_first([shared] + [chunk("b.epub", idx=2)], [shared], keep=4)
    paths = [(c["source_path"], c["chunk_index"]) for c in merged]
    assert len(paths) == len(set(paths))


# --- end to end through AtlasRag ------------------------------------------------------


def make_client(handler):
    return httpx.AsyncClient(transport=httpx.MockTransport(handler), base_url="http://rag.test")


async def test_retrieve_reserves_slots_for_a_named_book(monkeypatch):
    calls: list[dict] = []

    async def handler(request: httpx.Request) -> httpx.Response:
        import json

        calls.append(json.loads(request.content))
        # the CIA is buried: a vector search alone would not surface it
        chunks = [chunk(f"The Food Lab.epub", idx=i) for i in range(6)]
        chunks += [chunk("Culinary Institute of America - The Professional Chef.pdf",
                         text="Onion Soup: caramelize the onions", idx=99)]
        return httpx.Response(200, json={"chunks": chunks})

    rag = AtlasRag(base_url="http://rag.test", client=make_client(handler))
    # the passage path is the real one; the reservation is applied after ranking,
    # because the passage pipeline re-sorts and would otherwise undo it
    out = await rag.retrieve("How does the CIA make french onion soup", top_k=4)

    assert len([c for c in calls if "question" in c]) >= 2, "a second, named-book search should run"
    assert any("Professional Chef" in str(p.get("source_path")) for p in out), \
        "the book the cook named must appear at all"
    assert "Professional Chef" in str(out[0].get("source_path")), \
        "and it should lead"


async def test_explicit_book_scope_skips_the_named_book_search(monkeypatch):
    """The caller already said what they want; do not second-guess them."""
    calls: list[dict] = []

    async def handler(request: httpx.Request) -> httpx.Response:
        import json

        calls.append(json.loads(request.content))
        return httpx.Response(200, json={"chunks": [chunk("The Food Lab.epub")]})

    rag = AtlasRag(base_url="http://rag.test", client=make_client(handler))
    await rag.retrieve("How does the CIA make french onion soup",
                       top_k=4, books=["The Food Lab.epub"])
    assert len([c for c in calls if "question" in c]) == 1


async def test_a_failing_second_search_never_makes_things_worse():
    state = {"n": 0}

    async def handler(request: httpx.Request) -> httpx.Response:
        state["n"] += 1
        if state["n"] == 1:
            return httpx.Response(200, json={"chunks": [chunk("The Food Lab.epub")]})
        raise httpx.ConnectError("second search died")

    rag = AtlasRag(base_url="http://rag.test", client=make_client(handler))
    out = await rag.retrieve("How does the CIA make french onion soup", top_k=4)
    assert out, "a failing second search must not empty the result"
    assert all("Food Lab" in str(p.get("source_path")) for p in out)
