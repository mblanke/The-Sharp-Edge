"""Tags + notebook-page mapping (Phase 2 — feeds home chips and cards.pdf)."""


def _recipe(slug: str, **extra) -> dict:
    return {
        "slug": slug,
        "title": slug.title(),
        "category": "Sides",
        "base_yield": 2,
        "yield_word": "servings",
        "ingredients": [{"amount": 1, "unit": "g", "name": "salt"}],
        "steps": [{"text": "Stir."}],
        **extra,
    }


async def test_create_with_tags_and_pages(client, auth):
    res = await client.post(
        "/api/v1/recipes",
        json=_recipe(
            "buttered-corn",
            tags=["grill", "summer", "Grill", "  "],
            pages=[{"page_number": 84, "section": "Sides"}],
        ),
        headers=auth,
    )
    assert res.status_code == 201
    body = res.json()
    # case-insensitive dedupe, blanks dropped, order preserved
    assert body["tags"] == ["grill", "summer"]
    assert body["pages"] == [{"page_number": 84, "section": "Sides"}]


async def test_put_replaces_tags_and_pages_but_none_leaves_unchanged(client, auth):
    await client.post(
        "/api/v1/recipes",
        json=_recipe("mash", tags=["comfort"], pages=[{"page_number": 90, "section": "Sides"}]),
        headers=auth,
    )
    # PUT without tags/pages keys → unchanged
    res = await client.put(
        "/api/v1/recipes/mash",
        json={
            "ingredients": [{"amount": 2, "unit": "g", "name": "salt"}],
            "steps": [{"text": "Mash."}],
            "notes": [],
        },
        headers=auth,
    )
    assert res.json()["tags"] == ["comfort"]
    assert res.json()["pages"] == [{"page_number": 90, "section": "Sides"}]

    # PUT with explicit lists → replaced
    res = await client.put(
        "/api/v1/recipes/mash",
        json={
            "ingredients": [{"amount": 2, "unit": "g", "name": "salt"}],
            "steps": [{"text": "Mash."}],
            "notes": [],
            "tags": ["weeknight"],
            "pages": [],
        },
        headers=auth,
    )
    assert res.json()["tags"] == ["weeknight"]
    assert res.json()["pages"] == []


async def test_tag_filter_and_cards_carry_tags(client, auth):
    await client.post("/api/v1/recipes", json=_recipe("slaw", tags=["summer"]), headers=auth)
    await client.post("/api/v1/recipes", json=_recipe("stew", tags=["winter"]), headers=auth)

    res = await client.get("/api/v1/recipes", params={"tag": "Summer"})
    assert [r["slug"] for r in res.json()] == ["slaw"]
    assert res.json()[0]["tags"] == ["summer"]

    res = await client.get("/api/v1/recipes")
    by_slug = {r["slug"]: r["tags"] for r in res.json()}
    assert by_slug == {"slaw": ["summer"], "stew": ["winter"]}


async def test_shared_tags_reuse_rows(client, auth, session_factory):
    from sqlalchemy import func, select

    from app.models import Tag

    await client.post("/api/v1/recipes", json=_recipe("dish-a", tags=["grill"]), headers=auth)
    await client.post("/api/v1/recipes", json=_recipe("dish-b", tags=["Grill"]), headers=auth)
    async with session_factory() as session:
        count = (await session.execute(select(func.count()).select_from(Tag))).scalar_one()
    assert count == 1
