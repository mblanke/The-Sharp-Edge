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
    assert body["entries"] == []


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


async def test_week_pushes_into_the_running_shopping_list(client, auth):
    """The plan feeds the one running list the iPad app shares (/shopping)."""
    await _seed(client, auth)
    for entry in (
        {"date": "2026-08-25", "meal": "dinner", "recipe_slug": "plan-goulash", "scaled_yield": 12},
        {"date": "2026-08-26", "meal": "dinner", "recipe_slug": "plan-salad"},
    ):
        await client.post("/api/v1/plan", json=entry, headers=auth)

    res = await client.post("/api/v1/plan/shopping-list", params={"week": "2026-08-25"}, headers=auth)
    assert res.status_code == 200
    def by_prefix(items, prefix):
        return next(i for i in items if i["name"].startswith(prefix))

    items = res.json()["items"]

    # goulash at 2×: 6 onions + salad 1 onion = 7, merged despite prep clauses
    # (the merge keys on the singularised head; the first-seen name is displayed)
    onions = by_prefix(items, "yellow onion")
    assert onions["display"] == "7"
    assert sorted(onions["recipes"]) == ["plan-goulash", "plan-salad"]
    # beef only from goulash → provenance kept
    beef = by_prefix(items, "beef chuck")
    assert beef["display"] == "4 lb"
    assert beef["recipes"] == ["plan-goulash"]
    # to-taste rows never join the list; measured salt is the goulash's 2× only
    assert by_prefix(items, "salt")["display"] == "3 tsp"
    # the same list is what /shopping serves
    listed = (await client.get("/api/v1/shopping")).json()["items"]
    for prefix in ("yellow onion", "beef chuck", "salt"):
        assert by_prefix(listed, prefix)


async def test_push_merges_into_existing_lines_and_keeps_checked(client, auth):
    await _seed(client, auth)
    # the running list already has onions from an earlier add, checked off
    await client.post(
        "/api/v1/shopping/add", json={"slug": "plan-salad"}, headers=auth
    )
    onion = next(
        i for i in (await client.get("/api/v1/shopping")).json()["items"]
        if i["name"].startswith("yellow onion")
    )
    await client.patch(f"/api/v1/shopping/{onion['id']}", json={"checked": True}, headers=auth)

    await client.post(
        "/api/v1/plan",
        json={"date": "2026-08-25", "meal": "dinner", "recipe_slug": "plan-goulash"},
        headers=auth,
    )
    res = await client.post("/api/v1/plan/shopping-list", params={"week": "2026-08-24"}, headers=auth)
    onions = next(i for i in res.json()["items"] if i["name"].startswith("yellow onion"))
    # 1 (already there) + 3 (goulash at base) = 4, still one line, checked survives
    assert onions["display"] == "4"
    assert onions["checked"] is True


async def test_remove_entry_and_empty_week_push(client, auth):
    await _seed(client, auth)
    await client.post(
        "/api/v1/plan",
        json={"date": "2026-08-25", "meal": "dinner", "recipe_slug": "plan-salad"},
        headers=auth,
    )
    entry_id = (await client.get("/api/v1/plan", params={"week": "2026-08-24"})).json()["entries"][0]["id"]
    res = await client.delete(f"/api/v1/plan/{entry_id}", headers=auth)
    assert res.json()["entries"] == []
    # pushing an empty week is a no-op on the (empty) running list
    res = await client.post("/api/v1/plan/shopping-list", params={"week": "2026-08-24"}, headers=auth)
    assert res.json()["items"] == []
