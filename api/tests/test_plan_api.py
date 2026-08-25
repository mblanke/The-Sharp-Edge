"""Meal plan + shopping list endpoints."""

GOULASH_LITE = {
    "slug": "plan-goulash",
    "title": "Plan Goulash",
    "category": "Soups & Stews",
    "base_yield": 6,
    "yield_word": "servings",
    "gf": True,
    "ingredients": [
        {"amount": 2, "unit": "lb", "name": "beef chuck, cubed"},
        {"amount": 3, "unit": "", "name": "yellow onions, diced"},
        {"amount": 1.5, "unit": "tsp", "name": "salt"},
    ],
    "steps": [{"text": "Cook."}],
}

SALAD = {
    "slug": "plan-salad",
    "title": "Plan Salad",
    "category": "Salads",
    "base_yield": 4,
    "yield_word": "servings",
    "ingredients": [
        {"amount": 1, "unit": "", "name": "yellow onions, sliced"},
        {"amount": 0, "unit": "", "name": "salt, to taste"},
    ],
    "steps": [{"text": "Toss."}],
}


async def _seed(client, auth):
    for payload in (GOULASH_LITE, SALAD):
        res = await client.post("/api/v1/recipes", json=payload, headers=auth)
        assert res.status_code == 201


async def test_week_starts_empty_and_normalizes_to_monday(client):
    res = await client.get("/api/v1/plan", params={"week": "2026-08-27"})  # a Thursday
    assert res.status_code == 200
    body = res.json()
    assert body["week"] == "2026-08-24"  # Monday of that week
    assert body["entries"] == [] and body["shopping"] == []


async def test_upsert_replaces_slot_and_requires_auth(client, auth):
    await _seed(client, auth)
    entry = {"date": "2026-08-25", "meal": "dinner", "recipe_slug": "plan-goulash", "scaled_yield": 12}
    assert (await client.post("/api/v1/plan", json=entry)).status_code == 401

    res = await client.post("/api/v1/plan", json=entry, headers=auth)
    assert res.status_code == 200
    assert res.json()["entries"][0]["recipe_title"] == "Plan Goulash"
    assert res.json()["entries"][0]["scaled_yield"] == 12

    # same slot, different recipe → replaced, not duplicated
    res = await client.post(
        "/api/v1/plan",
        json={"date": "2026-08-25", "meal": "dinner", "recipe_slug": "plan-salad"},
        headers=auth,
    )
    entries = res.json()["entries"]
    assert len(entries) == 1
    assert entries[0]["recipe_slug"] == "plan-salad"
    assert entries[0]["scaled_yield"] == 4  # defaulted to base


async def test_unknown_recipe_404(client, auth):
    res = await client.post(
        "/api/v1/plan",
        json={"date": "2026-08-25", "meal": "dinner", "recipe_slug": "ghost"},
        headers=auth,
    )
    assert res.status_code == 404


async def test_shopping_list_merges_across_recipes(client, auth):
    await _seed(client, auth)
    for entry in (
        {"date": "2026-08-25", "meal": "dinner", "recipe_slug": "plan-goulash", "scaled_yield": 12},
        {"date": "2026-08-26", "meal": "dinner", "recipe_slug": "plan-salad"},
    ):
        await client.post("/api/v1/plan", json=entry, headers=auth)

    res = await client.post("/api/v1/plan/shopping-list", params={"week": "2026-08-25"}, headers=auth)
    assert res.status_code == 200
    shopping = {s["name"]: s for s in res.json()["shopping"]}

    # goulash at 2×: 6 onions + salad 1 onion = 7, merged despite prep clauses
    assert shopping["yellow onions"]["amount"] == "7"
    assert shopping["yellow onions"]["recipe_id"] is None  # cross-recipe merge
    # beef only from goulash → provenance kept
    assert shopping["beef chuck"]["amount"] == "4 lb"
    assert shopping["beef chuck"]["recipe_id"] is not None
    # measured salt absorbs the salad's to-taste row
    assert shopping["salt"]["amount"] == "3 tsp"
    assert all(not s["checked"] for s in shopping.values())


async def test_check_and_delete_flow(client, auth):
    await _seed(client, auth)
    await client.post(
        "/api/v1/plan",
        json={"date": "2026-08-25", "meal": "dinner", "recipe_slug": "plan-salad"},
        headers=auth,
    )
    res = await client.post("/api/v1/plan/shopping-list", params={"week": "2026-08-24"}, headers=auth)
    item = res.json()["shopping"][0]

    res = await client.patch(
        f"/api/v1/plan/shopping-list/{item['id']}", json={"checked": True}, headers=auth
    )
    assert res.json()["checked"] is True

    # remove the plan entry; regenerating clears the list
    entry_id = (await client.get("/api/v1/plan", params={"week": "2026-08-24"})).json()["entries"][0]["id"]
    res = await client.delete(f"/api/v1/plan/{entry_id}", headers=auth)
    assert res.json()["entries"] == []
    res = await client.post("/api/v1/plan/shopping-list", params={"week": "2026-08-24"}, headers=auth)
    assert res.json()["shopping"] == []
