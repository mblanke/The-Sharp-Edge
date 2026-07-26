"""/api/v1/shopping — the running list.

The behaviour that matters: adding a second recipe adds to existing lines.
"""

GOULASH = {
    "slug": "goulash", "title": "Goulash", "category": "Soups & Stews",
    "base_yield": 6, "yield_word": "servings", "gf": True,
    "ingredients": [
        {"amount": 2, "unit": "lb", "name": "beef chuck, cubed"},
        {"amount": 3, "unit": "tbsp", "name": "sweet Hungarian paprika"},
        {"amount": 3, "unit": "cup", "name": "beef broth"},
        {"amount": 0, "unit": "", "name": "salt and pepper, to taste"},
    ],
    "steps": [{"text": "Brown the beef."}],
}

RUB = {
    "slug": "paprika-rub", "title": "Paprika Rub", "category": "Marinades",
    "base_yield": 1, "yield_word": "batch",
    "ingredients": [
        {"amount": 2, "unit": "tbsp", "name": "sweet Hungarian paprika"},
        {"amount": 1, "unit": "tsp", "name": "caraway seeds"},
    ],
    "steps": [{"text": "Mix."}],
}


async def seed(client, auth, *recipes):
    for r in recipes:
        assert (await client.post("/api/v1/recipes", json=r, headers=auth)).status_code == 201


def by_name(items, fragment):
    return next(i for i in items if fragment.lower() in i["name"].lower())


async def test_list_starts_empty(client):
    r = await client.get("/api/v1/shopping")
    assert r.status_code == 200
    assert r.json()["items"] == []


async def test_add_requires_auth(client, auth):
    await seed(client, auth, GOULASH)
    assert (await client.post("/api/v1/shopping/add", json={"slug": "goulash"})).status_code == 401


async def test_reading_the_list_needs_no_token(client, auth):
    """You should be able to pull the list up in a shop without pasting a token."""
    await seed(client, auth, GOULASH)
    await client.post("/api/v1/shopping/add", json={"slug": "goulash"}, headers=auth)
    assert (await client.get("/api/v1/shopping")).status_code == 200
    assert (await client.get("/api/v1/shopping/text")).status_code == 200


async def test_add_uses_scaled_quantities(client, auth):
    await seed(client, auth, GOULASH)
    r = await client.post("/api/v1/shopping/add",
                          json={"slug": "goulash", "target_yield": 12}, headers=auth)
    assert r.status_code == 200
    beef = by_name(r.json()["items"], "beef chuck")
    assert beef["amount"] == 4          # 2 lb at 6 servings → 4 lb at 12
    assert beef["display"] == "4 lb"


async def test_a_second_recipe_adds_rather_than_replaces(client, auth):
    """The requirement in one line."""
    await seed(client, auth, GOULASH, RUB)
    await client.post("/api/v1/shopping/add", json={"slug": "goulash"}, headers=auth)
    r = await client.post("/api/v1/shopping/add", json={"slug": "paprika-rub"}, headers=auth)
    paprika = by_name(r.json()["items"], "paprika")
    assert paprika["amount"] == 5       # 3 tbsp + 2 tbsp
    assert paprika["display"] == "5 tbsp"
    assert set(paprika["recipes"]) == {"goulash", "paprika-rub"}


async def test_adding_the_same_recipe_twice_doubles_it(client, auth):
    """Two batches means twice the shopping."""
    await seed(client, auth, RUB)
    await client.post("/api/v1/shopping/add", json={"slug": "paprika-rub"}, headers=auth)
    r = await client.post("/api/v1/shopping/add", json={"slug": "paprika-rub"}, headers=auth)
    assert by_name(r.json()["items"], "paprika")["amount"] == 4


async def test_to_taste_items_carry_no_quantity(client, auth):
    await seed(client, auth, GOULASH)
    r = await client.post("/api/v1/shopping/add", json={"slug": "goulash"}, headers=auth)
    salt = by_name(r.json()["items"], "salt")
    assert salt["to_taste"] and salt["amount"] == 0
    assert salt["display"] == "to taste"


async def test_hidden_gluten_items_are_flagged(client, auth):
    await seed(client, auth, GOULASH)
    r = await client.post("/api/v1/shopping/add", json={"slug": "goulash"}, headers=auth)
    items = r.json()["items"]
    assert by_name(items, "beef broth")["check_gluten"] is True
    assert by_name(items, "paprika")["check_gluten"] is True
    assert by_name(items, "beef chuck")["check_gluten"] is False


async def test_checking_an_item_survives_a_later_add(client, auth):
    await seed(client, auth, GOULASH, RUB)
    added = await client.post("/api/v1/shopping/add", json={"slug": "goulash"}, headers=auth)
    beef_id = by_name(added.json()["items"], "beef chuck")["id"]
    assert (await client.patch(f"/api/v1/shopping/{beef_id}",
                               json={"checked": True}, headers=auth)).status_code == 200
    r = await client.post("/api/v1/shopping/add", json={"slug": "paprika-rub"}, headers=auth)
    assert by_name(r.json()["items"], "beef chuck")["checked"] is True


async def test_text_export_omits_checked_items(client, auth):
    await seed(client, auth, GOULASH)
    added = await client.post("/api/v1/shopping/add", json={"slug": "goulash"}, headers=auth)
    beef_id = by_name(added.json()["items"], "beef chuck")["id"]
    await client.patch(f"/api/v1/shopping/{beef_id}", json={"checked": True}, headers=auth)
    text = (await client.get("/api/v1/shopping/text")).text
    assert "beef chuck" not in text
    assert "beef broth" in text


async def test_delete_one_item(client, auth):
    await seed(client, auth, GOULASH)
    added = await client.post("/api/v1/shopping/add", json={"slug": "goulash"}, headers=auth)
    item_id = added.json()["items"][0]["id"]
    assert (await client.delete(f"/api/v1/shopping/{item_id}", headers=auth)).status_code == 204
    assert all(i["id"] != item_id for i in (await client.get("/api/v1/shopping")).json()["items"])


async def test_clear_checked_only(client, auth):
    await seed(client, auth, GOULASH)
    added = await client.post("/api/v1/shopping/add", json={"slug": "goulash"}, headers=auth)
    beef_id = by_name(added.json()["items"], "beef chuck")["id"]
    await client.patch(f"/api/v1/shopping/{beef_id}", json={"checked": True}, headers=auth)
    assert (await client.delete("/api/v1/shopping?checked_only=true", headers=auth)).status_code == 204
    remaining = (await client.get("/api/v1/shopping")).json()["items"]
    assert remaining and all(not i["checked"] for i in remaining)


async def test_clear_everything(client, auth):
    await seed(client, auth, GOULASH)
    await client.post("/api/v1/shopping/add", json={"slug": "goulash"}, headers=auth)
    assert (await client.delete("/api/v1/shopping", headers=auth)).status_code == 204
    assert (await client.get("/api/v1/shopping")).json()["items"] == []


async def test_unknown_recipe_is_404(client, auth):
    r = await client.post("/api/v1/shopping/add", json={"slug": "nope"}, headers=auth)
    assert r.status_code == 404
