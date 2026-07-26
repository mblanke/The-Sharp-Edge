"""POST /api/v1/parse/* — the deterministic helpers behind the add-recipe flow.

Unauthenticated by design: the web client reaches them through a proxy that
forwards no bearer token, and they only transform text the caller already has.
"""

MINIMAL = {
    "slug": "gurkensalat",
    "title": "Gurkensalat",
    "category": "Salads",
    "base_yield": 4,
    "ingredients": [{"amount": 2, "unit": "", "name": "cucumbers"}],
    "steps": [{"text": "Slice thin."}],
}


async def test_parse_ingredients_needs_no_auth(client):
    r = await client.post(
        "/api/v1/parse/ingredients",
        json={"lines": ["2 tablespoons olive oil"], "lang": "en"},
    )
    assert r.status_code == 200


async def test_parse_ingredients_multilingual(client):
    r = await client.post(
        "/api/v1/parse/ingredients",
        json={
            "lines": [
                "zweieinhalb Esslöffel Paprikapulver",
                "1,5 kg Kartoffeln",
                "eine Prise Salz",
            ],
            "lang": "de",
        },
    )
    assert r.status_code == 200, r.text
    ing = r.json()["ingredients"]
    assert ing[0] == {
        "amount": 2.5, "unit": "tbsp", "name": "Paprikapulver", "note": None, "section": None
    }
    assert (ing[1]["amount"], ing[1]["unit"], ing[1]["name"]) == (1500.0, "g", "Kartoffeln")
    # "eine Prise" is the to-taste contract: amount 0, renders as an em dash.
    assert (ing[2]["amount"], ing[2]["unit"], ing[2]["name"]) == (0.0, "", "Salz")


async def test_parse_ingredients_skips_blank_lines(client):
    r = await client.post(
        "/api/v1/parse/ingredients", json={"lines": ["", "   ", "1 cup flour"], "lang": "en"}
    )
    assert len(r.json()["ingredients"]) == 1


async def test_parse_ingredients_only_emits_allowed_units(client):
    """ALLOWED_UNITS is not enforced by the Ingredient schema, so the router gates it."""
    from app.schemas.recipe import ALLOWED_UNITS

    lines = [
        "200 g de făină", "o linguriță de sare", "2 căni de lapte",
        "1 kg de roșii", "500 ml de smântână", "3 cepe",
    ]
    r = await client.post("/api/v1/parse/ingredients", json={"lines": lines, "lang": "ro"})
    assert all(i["unit"] in ALLOWED_UNITS for i in r.json()["ingredients"])


async def test_parse_ingredients_rejects_unknown_lang(client):
    r = await client.post("/api/v1/parse/ingredients", json={"lines": ["1 cup"], "lang": "xx"})
    assert r.status_code == 422


async def test_slug_is_derived_and_available(client):
    r = await client.post("/api/v1/parse/slug", json={"title": "Vișinată"})
    assert r.status_code == 200
    assert r.json() == {"slug": "visinata", "available": True, "valid": True}


async def test_slug_reports_collision_before_save(client, auth):
    assert (await client.post("/api/v1/recipes", json=MINIMAL, headers=auth)).status_code == 201
    r = await client.post("/api/v1/parse/slug", json={"title": "Gurkensalat"})
    assert r.json() == {"slug": "gurkensalat", "available": False, "valid": True}


async def test_slug_unusable_title(client):
    r = await client.post("/api/v1/parse/slug", json={"title": "!!!"})
    assert r.json() == {"slug": "", "available": False, "valid": False}


async def test_slug_rejects_empty_title(client):
    assert (await client.post("/api/v1/parse/slug", json={"title": ""})).status_code == 422


async def test_category_matching(client):
    r = await client.post("/api/v1/parse/category", json={"spoken": "ciorbe", "lang": "ro"})
    assert r.json() == {"category": "Soups & Stews"}

    r = await client.post("/api/v1/parse/category", json={"spoken": "entrée", "lang": "fr"})
    assert r.json() == {"category": "Appetizers & Preserves"}

    r = await client.post("/api/v1/parse/category", json={"spoken": "zzz", "lang": "en"})
    assert r.json() == {"category": None}
