GOULASH = {
    "slug": "goulash",
    "title": "GF Hungarian Beef Goulash",
    "category": "Soups & Stews",
    "meta": "Potato-thickened · no flour, no roux",
    "base_yield": 6,
    "yield_word": "servings",
    "gf": True,
    "ingredients": [
        {"amount": 2, "unit": "lb", "name": "beef chuck, 1-inch cubes"},
        {"amount": 3, "unit": "tbsp", "name": "sweet Hungarian paprika (certified GF)"},
        {"amount": 3, "unit": "cup", "name": "beef broth (certified GF)"},
        {"amount": 0, "unit": "", "name": "salt and pepper, to taste"},
    ],
    "steps": [{"text": "Brown the beef."}, {"text": "Simmer 90 minutes."}],
    "notes": ["Hidden gluten: paprika, broth, tomato paste."],
}


async def test_healthz(client):
    r = await client.get("/api/v1/healthz")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert body["photo_import"] in (True, False)


async def test_create_requires_auth(client):
    r = await client.post("/api/v1/recipes", json=GOULASH)
    assert r.status_code == 401
    assert r.headers["content-type"].startswith("application/problem+json")


async def test_create_and_get(client, auth):
    r = await client.post("/api/v1/recipes", json=GOULASH, headers=auth)
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["slug"] == "goulash"
    assert body["current_version"]["version"] == 1
    assert body["gf"] is True

    r = await client.get("/api/v1/recipes/goulash")
    assert r.status_code == 200
    assert r.json()["title"] == "GF Hungarian Beef Goulash"


async def test_list_filters(client, auth):
    await client.post("/api/v1/recipes", json=GOULASH, headers=auth)
    pancakes = {
        **GOULASH,
        "slug": "pancakes",
        "title": "Classic Fluffy Pancakes",
        "category": "Breakfast",
        "gf": False,
    }
    await client.post("/api/v1/recipes", json=pancakes, headers=auth)

    r = await client.get("/api/v1/recipes")
    assert {x["slug"] for x in r.json()} == {"goulash", "pancakes"}

    r = await client.get("/api/v1/recipes", params={"gf": "true"})
    assert {x["slug"] for x in r.json()} == {"goulash"}

    r = await client.get("/api/v1/recipes", params={"category": "Breakfast"})
    assert {x["slug"] for x in r.json()} == {"pancakes"}

    r = await client.get("/api/v1/recipes", params={"q": "goul"})
    assert {x["slug"] for x in r.json()} == {"goulash"}


async def test_404_problem_json(client):
    r = await client.get("/api/v1/recipes/nope")
    assert r.status_code == 404
    body = r.json()
    assert body["status"] == 404
    assert "nope" in body["detail"]


async def test_put_appends_version(client, auth):
    await client.post("/api/v1/recipes", json=GOULASH, headers=auth)
    update = {
        "ingredients": GOULASH["ingredients"],
        "steps": GOULASH["steps"] + [{"text": "Rest 10 minutes."}],
        "notes": GOULASH["notes"],
        "label": "rest step added",
    }
    r = await client.put("/api/v1/recipes/goulash", json=update, headers=auth)
    assert r.status_code == 200
    assert r.json()["current_version"]["version"] == 2

    r = await client.get("/api/v1/recipes/goulash/versions")
    versions = r.json()
    assert len(versions) == 2
    # newest first, with full content for the version switcher
    assert [v["version"] for v in versions] == [2, 1]
    assert [v["is_current"] for v in versions] == [True, False]
    assert [i["name"] for i in versions[1]["ingredients"]] == [
        i["name"] for i in GOULASH["ingredients"]
    ]
    assert versions[0]["steps"][-1]["text"] == "Rest 10 minutes."


async def test_scale_goulash_6_to_14(client, auth):
    await client.post("/api/v1/recipes", json=GOULASH, headers=auth)
    r = await client.post("/api/v1/recipes/goulash/scale", json={"target_yield": 14})
    assert r.status_code == 200
    rows = {i["name"]: i["display"] for i in r.json()["ingredients"]}
    assert rows["beef chuck, 1-inch cubes"] == "4 ⅔ lb"
    assert rows["sweet Hungarian paprika (certified GF)"] == "7 tbsp"
    assert rows["beef broth (certified GF)"] == "7 cup"
    assert rows["salt and pepper, to taste"] == "—"


async def test_scale_bounds(client, auth):
    await client.post("/api/v1/recipes", json=GOULASH, headers=auth)
    r = await client.post("/api/v1/recipes/goulash/scale", json={"target_yield": 25})
    assert r.status_code == 400
    r = await client.post("/api/v1/recipes/goulash/scale", json={"target_yield": 0})
    assert r.status_code == 422


async def test_slug_redirect(client, auth, session_factory):
    await client.post("/api/v1/recipes", json=GOULASH, headers=auth)
    from app.models import Redirect

    async with session_factory() as s:
        s.add(Redirect(old_slug="gulyas", slug="goulash"))
        await s.commit()
    r = await client.get("/api/v1/recipes/gulyas")
    assert r.status_code == 200
    assert r.json()["slug"] == "goulash"


async def test_qr_png(client, auth):
    await client.post("/api/v1/recipes", json=GOULASH, headers=auth)
    r = await client.get("/api/v1/recipes/goulash/qr")
    assert r.status_code == 200
    assert r.headers["content-type"] == "image/png"
    assert r.content[:8] == b"\x89PNG\r\n\x1a\n"


async def test_duplicate_slug_conflict(client, auth):
    await client.post("/api/v1/recipes", json=GOULASH, headers=auth)
    r = await client.post("/api/v1/recipes", json=GOULASH, headers=auth)
    assert r.status_code == 409
