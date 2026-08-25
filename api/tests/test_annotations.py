"""Technique auto-linking (F5): scoring, dedupe, caching."""

import app.services.annotate as annotate_module
from tests.test_tags_pages import _recipe

CHUNK_SEAR = {
    "text": "Searing builds fond; deglaze to capture it…",
    "source_path": "Cooking/professional-chef.pdf",
    "title": "The Professional Chef",
    "heading": "Searing",
    "page": 210,
    "rerank_score": 0.82,
}
CHUNK_WEAK = {
    "text": "vaguely related",
    "source_path": "Cooking/misc.pdf",
    "title": "Misc",
    "heading": "Other",
    "page": 1,
    "rerank_score": 0.1,
}


class FakeRag:
    def __init__(self, by_query):
        self.by_query = by_query
        self.calls: list[str] = []

    async def retrieve(self, question, top_k=None, books=None):
        self.calls.append(question)
        for needle, chunks in self.by_query.items():
            if needle in question:
                return chunks
        return []


async def test_annotate_caches_and_dedupes(client, auth, monkeypatch):
    recipe = _recipe(
        "annotated-stew",
        steps=[
            {"text": "Sear the beef hard in batches until deeply browned."},
            {"text": "Deglaze and sear the second batch the same way."},  # same ref → dedupe
            {"text": "Serve."},  # too short — skipped entirely
        ],
    )
    await client.post("/api/v1/recipes", json=recipe, headers=auth)

    rag = FakeRag({"Sear": [CHUNK_SEAR, CHUNK_WEAK], "Deglaze": [CHUNK_SEAR]})
    monkeypatch.setattr(annotate_module, "atlas_rag", rag)

    assert (await client.post("/api/v1/recipes/annotated-stew/annotate")).status_code == 401
    res = await client.post("/api/v1/recipes/annotated-stew/annotate", headers=auth)
    body = res.json()
    assert body["annotated"] is True
    # both matching steps hit the same source/page — one note survives
    assert len(body["annotations"]) == 1
    note = body["annotations"][0]
    assert note["phrase"] == "Searing"
    assert note["page"] == 210
    assert "fond" in note["snippet"]
    # the short step never went to retrieval
    assert all("Serve" not in q for q in rag.calls)

    # second call reuses the cache — zero retrieval
    rag.calls.clear()
    res = await client.post("/api/v1/recipes/annotated-stew/annotate", headers=auth)
    assert res.json()["annotations"][0]["phrase"] == "Searing"
    assert rag.calls == []

    # public read returns the cached notes
    res = await client.get("/api/v1/recipes/annotated-stew/annotations")
    assert res.json()["annotated"] is True


async def test_weak_matches_are_dropped(client, auth, monkeypatch):
    await client.post(
        "/api/v1/recipes",
        json=_recipe("plain-dish", steps=[{"text": "Stir everything together gently."}]),
        headers=auth,
    )
    monkeypatch.setattr(annotate_module, "atlas_rag", FakeRag({"Stir": [CHUNK_WEAK]}))
    res = await client.post("/api/v1/recipes/plain-dish/annotate", headers=auth)
    assert res.json() == {"annotated": False, "annotations": []}
