"""URL recipe import (F4): JSON-LD parsing, LLM fallback, SSRF guard."""

import json

import pytest
from fastapi import HTTPException

import app.services.import_url as import_url_module
from app.services.import_url import (
    _check_url,
    _find_recipe_node,
    draft_from_jsonld,
    import_from_url,
)

JSONLD_PAGE = """<html><head>
<script type="application/ld+json">
{"@context":"https://schema.org","@type":"Recipe",
 "name":"Skillet Chicken Thighs",
 "description":"Weeknight <b>crispy</b> thighs",
 "recipeYield":"4 servings",
 "recipeIngredient":["4 chicken thighs","2 tablespoons olive oil","1/2 teaspoon salt","1 kg potatoes","Soy sauce, to taste"],
 "recipeInstructions":[{"@type":"HowToStep","text":"Sear skin-side down."},{"@type":"HowToStep","text":"Roast 25 minutes."}]}
</script></head><body>hi</body></html>"""

GRAPH_PAGE = """<html><script type="application/ld+json">
{"@graph":[{"@type":"WebSite","name":"x"},{"@type":["Recipe","Thing"],"name":"Graph Soup",
 "recipeYield":["6"],"recipeIngredient":["3 cups broth"],
 "recipeInstructions":"Simmer everything. Serve hot."}]}
</script></html>"""


def test_find_recipe_node_direct_and_graph():
    assert _find_recipe_node(JSONLD_PAGE)["name"] == "Skillet Chicken Thighs"
    assert _find_recipe_node(GRAPH_PAGE)["name"] == "Graph Soup"
    assert _find_recipe_node("<html><body>plain page</body></html>") is None


def test_draft_normalizes_units_and_yields():
    draft = draft_from_jsonld(_find_recipe_node(JSONLD_PAGE))
    assert draft.title == "Skillet Chicken Thighs"
    assert draft.meta == "Weeknight crispy thighs"
    assert draft.base_yield == 4
    rows = {i.name: i for i in draft.ingredients}
    assert rows["chicken thighs"].amount == 4 and rows["chicken thighs"].unit == ""
    assert rows["olive oil"].unit == "tbsp" and rows["olive oil"].amount == 2
    assert rows["salt"].unit == "tsp" and rows["salt"].amount == 0.5
    # kg converts to the §5 unit set
    assert rows["potatoes"].unit == "g" and rows["potatoes"].amount == 1000
    # to-taste line keeps amount 0
    assert rows["Soy sauce, to taste"].amount == 0
    assert [s.text for s in draft.steps] == ["Sear skin-side down.", "Roast 25 minutes."]


class FakeProvider:
    def __init__(self, tokens):
        self.tokens = tokens

    async def stream_chat(self, messages, *, has_corpus_chunks=False):
        assert has_corpus_chunks is False
        for t in self.tokens:
            yield t


async def test_import_jsonld_page_with_gf_scan(monkeypatch):
    async def fake_fetch(url):
        return JSONLD_PAGE

    monkeypatch.setattr(import_url_module, "_fetch", fake_fetch)
    monkeypatch.setattr(import_url_module, "_check_url", lambda url: "www.seriouseats.com")

    out = await import_from_url("https://www.seriouseats.com/x", FakeProvider([]))
    assert out["source"] == "seriouseats.com"  # bare domain, no editorializing
    assert out["draft"]["title"] == "Skillet Chicken Thighs"
    # the soy-sauce line was flagged by the gluten scan
    assert any("Soy sauce" in r["ingredient"] for r in out["gf_risks"])


async def test_fallback_uses_local_llm(monkeypatch):
    async def fake_fetch(url):
        return "<html><body><h1>Nana's Beans</h1><p>Cook 2 cups beans.</p></body></html>"

    monkeypatch.setattr(import_url_module, "_fetch", fake_fetch)
    monkeypatch.setattr(import_url_module, "_check_url", lambda url: "example.com")

    draft_json = json.dumps(
        {
            "title": "Nana's Beans",
            "base_yield": 4,
            "yield_word": "servings",
            "ingredients": [{"amount": 2, "unit": "cup", "name": "beans"}],
            "steps": [{"text": "Cook the beans."}],
            "notes": [],
        }
    )
    out = await import_from_url("https://example.com/x", FakeProvider([draft_json]))
    assert out["draft"]["title"] == "Nana's Beans"

    with pytest.raises(HTTPException) as e:
        await import_from_url("https://example.com/x", FakeProvider(["no json here"]))
    assert e.value.status_code == 422


def test_ssrf_guard():
    for url in [
        "ftp://example.com/x",
        "https://localhost/x",
        "https://127.0.0.1/x",
        "https://192.168.1.10/recipes",
    ]:
        with pytest.raises(HTTPException) as e:
            _check_url(url)
        assert e.value.status_code == 400


async def test_endpoint_requires_auth(client, monkeypatch):
    res = await client.post("/api/v1/recipes/import-url", json={"url": "https://example.com/x"})
    assert res.status_code == 401
