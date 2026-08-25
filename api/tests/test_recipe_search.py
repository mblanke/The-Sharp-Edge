"""'What can I make' search (E3): q spans titles/tags/ingredients."""


def _recipe(slug, title, ingredients, tags=None):
    return {
        "slug": slug,
        "title": title,
        "category": "Entrées",
        "base_yield": 4,
        "yield_word": "servings",
        "ingredients": ingredients,
        "steps": [{"text": "Cook."}],
        "tags": tags or [],
    }


async def _seed(client, auth):
    await client.post(
        "/api/v1/recipes",
        json=_recipe(
            "beef-stew",
            "Winter Beef Stew",
            [{"amount": 2, "unit": "lb", "name": "beef chuck, cubed"}],
            tags=["comfort"],
        ),
        headers=auth,
    )
    await client.post(
        "/api/v1/recipes",
        json=_recipe(
            "lemon-chicken",
            "Lemon Chicken",
            [{"amount": 4, "unit": "", "name": "chicken thighs"}],
        ),
        headers=auth,
    )


async def test_q_matches_title_ingredient_and_tag(client, auth):
    await _seed(client, auth)

    # title match
    res = await client.get("/api/v1/recipes", params={"q": "lemon"})
    assert [r["slug"] for r in res.json()] == ["lemon-chicken"]

    # ingredient match — "beef" isn't in the stew's title-only searchable past
    res = await client.get("/api/v1/recipes", params={"q": "chuck"})
    assert [r["slug"] for r in res.json()] == ["beef-stew"]

    # tag match
    res = await client.get("/api/v1/recipes", params={"q": "comfort"})
    assert [r["slug"] for r in res.json()] == ["beef-stew"]

    # no match
    res = await client.get("/api/v1/recipes", params={"q": "octopus"})
    assert res.json() == []


async def test_ingredient_param_only_searches_ingredients(client, auth):
    await _seed(client, auth)
    res = await client.get("/api/v1/recipes", params={"ingredient": "chicken"})
    assert [r["slug"] for r in res.json()] == ["lemon-chicken"]
    # a title word that isn't an ingredient must not match
    res = await client.get("/api/v1/recipes", params={"ingredient": "winter"})
    assert res.json() == []


async def test_ingredient_search_uses_current_version_only(client, auth):
    await _seed(client, auth)
    # new version swaps beef for lamb
    await client.put(
        "/api/v1/recipes/beef-stew",
        json={
            "ingredients": [{"amount": 2, "unit": "lb", "name": "lamb shoulder, cubed"}],
            "steps": [{"text": "Cook."}],
            "notes": [],
        },
        headers=auth,
    )
    res = await client.get("/api/v1/recipes", params={"ingredient": "lamb"})
    assert [r["slug"] for r in res.json()] == ["beef-stew"]
    res = await client.get("/api/v1/recipes", params={"ingredient": "chuck"})
    assert res.json() == []
