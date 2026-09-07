"""Batch import lands drafts, survives a bad link, and never touches the index."""

from fastapi import HTTPException

import app.routers.imports as imports_module


def canned(title, ingredients=None):
    return {
        "draft": {
            "title": title,
            "meta": "from the web",
            "base_yield": 4,
            "yield_word": "servings",
            "ingredients": ingredients or [{"amount": 1, "unit": "cup", "name": "stock"}],
            "steps": [{"text": "Simmer."}],
            "notes": [],
        },
        "source": "example.com",
        "gf_risks": [],
    }


async def test_batch_creates_drafts_and_reports_the_link_that_failed(client, auth, monkeypatch):
    async def fake_import(url, provider):
        if "broken" in url:
            raise HTTPException(422, "No recipe on that page")
        return canned("Onion Soup")

    monkeypatch.setattr(imports_module, "import_from_url", fake_import)
    monkeypatch.setattr(imports_module, "get_provider", lambda: object())

    res = await client.post(
        "/api/v1/import/batch",
        json={"urls": ["https://example.com/a", "https://example.com/broken", "https://example.com/a", " https://example.com/b "]},
        headers=auth,
    )
    assert res.status_code == 200, res.text
    body = res.json()
    # two good links (the repeat is skipped), unique slugs, one failure named
    assert [c["slug"] for c in body["created"]] == ["onion-soup", "onion-soup-2"]
    assert body["created"][0]["source"] == "example.com"
    assert body["failed"] == [{"item": "https://example.com/broken", "error": "No recipe on that page"}]

    # drafts are out of the index and in the review queue
    active = (await client.get("/api/v1/recipes")).json()
    assert "onion-soup" not in [r["slug"] for r in active]
    drafts = (await client.get("/api/v1/recipes?status=draft")).json()
    assert {r["slug"] for r in drafts} >= {"onion-soup", "onion-soup-2"}
    full = (await client.get("/api/v1/recipes/onion-soup")).json()
    assert full["status"] == "draft"
    assert full["current_version"]["label"] == "imported from url"
    assert full["current_version"]["ingredients"][0]["name"] == "stock"


async def test_batch_requires_a_token_and_at_least_one_link(client, auth):
    assert (await client.post("/api/v1/import/batch", json={"urls": ["https://x"]})).status_code == 401
    assert (await client.post("/api/v1/import/batch", json={"urls": []}, headers=auth)).status_code == 422


async def test_unique_slug_skips_every_taken_suffix(session_factory):
    from app.models import Recipe
    from app.services.batch_import import unique_slug

    async with session_factory() as session:
        for slug in ("pancakes", "pancakes-2", "pancakes-3"):
            session.add(Recipe(slug=slug, title="Pancakes", category="Breakfast", base_yield=1))
        await session.commit()
        assert await unique_slug(session, "Pancakes") == "pancakes-4"
        assert await unique_slug(session, "Vișinată") == "visinata"
