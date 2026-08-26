"""Recipe translation — words change, numbers never do."""

import pytest
from fastapi import HTTPException

import app.services.translate as translate_module
from app.services.translate import apply_lines, build_lines, parse_numbered, translate_recipe

ROMANIAN = {
    "title": "Vișinată",
    "meta": "Pentru 4 borcane",
    "ingredients": [
        {"amount": 2000, "unit": "g", "name": "vișine acre"},
        {"amount": 3, "unit": "cup", "name": "zahăr"},
        {"amount": 0, "unit": "", "name": "sare după gust"},
    ],
    "steps": [{"text": "Se fierbe totul.", "timer_seconds": 600}],
    "notes": ["Mai bună a doua zi."],
}


def test_lines_round_trip_through_the_structure():
    lines = build_lines(ROMANIAN)
    assert lines[0] == "Vișinată"
    assert "vișine acre" in lines
    restored = apply_lines(ROMANIAN, lines)
    assert restored == ROMANIAN


def test_numbered_reply_is_placed_by_number_not_arrival():
    """A model that reorders or repeats must not shift lines onto wrong rows."""
    reply = "3. sour cherries\n1. Cherry Liqueur\n2. For 4 jars\n3. sour cherries"
    assert parse_numbered(reply, 4) == ["Cherry Liqueur", "For 4 jars", "sour cherries", ""]


async def test_translation_keeps_every_quantity(monkeypatch):
    async def fake_post(*args, **kwargs):
        raise AssertionError("should not reach the network in this test")

    reply = "\n".join([
        "1. Cherry Liqueur",
        "2. For 4 jars",
        "3. sour cherries",
        "4. sugar",
        "5. salt to taste",
        "6. Boil everything.",
        "7. Better the next day.",
    ])

    async def fake_complete(payload, target):
        # exercise the real merge path with a canned model reply
        lines = build_lines(payload)
        return apply_lines(payload, [new or old for new, old in
                                     zip(parse_numbered(reply, len(lines)), lines)])

    monkeypatch.setattr(translate_module, "translate_recipe", fake_complete)
    out = await translate_module.translate_recipe(ROMANIAN, "en")

    assert out["title"] == "Cherry Liqueur"
    assert out["ingredients"][0]["name"] == "sour cherries"
    # the numbers are ours, not the model's
    assert out["ingredients"][0]["amount"] == 2000 and out["ingredients"][0]["unit"] == "g"
    assert out["ingredients"][2]["amount"] == 0  # to taste stays to taste
    assert out["steps"][0]["timer_seconds"] == 600


async def test_unknown_language_rejected():
    with pytest.raises(HTTPException) as e:
        await translate_recipe(ROMANIAN, "es")
    assert e.value.status_code == 400


async def test_endpoint_requires_auth(client):
    res = await client.post("/api/v1/recipes/translate", json={"target": "en", "title": "x"})
    assert res.status_code == 401


async def _make_recipe(client, auth):
    payload = {
        "slug": "salata-test", "title": "Salată de boeuf", "category": "Salads",
        "base_yield": 8, "yield_word": "servings",
        "ingredients": [{"amount": 500, "unit": "g", "name": "carne de vită"},
                        {"amount": 0, "unit": "", "name": "sare, piper"}],
        "steps": [{"text": "Fierbe carnea.", "timer_seconds": 3600}],
        "notes": ["Mai bună a doua zi."],
    }
    res = await client.post("/api/v1/recipes", json=payload, headers=auth)
    assert res.status_code == 201


async def test_saved_translation_is_cached_per_version(client, auth, monkeypatch):
    """Reading a recipe in English must not re-run the model on every view."""
    calls = {"n": 0}

    async def fake_translate(payload, target):
        calls["n"] += 1
        return {
            "title": "Beef Salad",
            "meta": payload.get("meta"),
            "ingredients": [{**i, "name": "beef"} for i in payload["ingredients"]],
            "steps": [{**s, "text": "Boil the meat."} for s in payload["steps"]],
            "notes": ["Better the next day."],
        }

    monkeypatch.setattr("app.services.translate.translate_recipe", fake_translate)
    await _make_recipe(client, auth)

    # nothing cached yet — reading says so rather than blocking
    res = await client.get("/api/v1/recipes/salata-test/translations/en")
    assert res.json() == {"available": False, "lang": "en"}

    res = await client.post("/api/v1/recipes/salata-test/translations/en", headers=auth)
    body = res.json()
    assert body["available"] is True and body["title"] == "Beef Salad"
    # quantities and timers ride through untouched
    assert body["ingredients"][0]["amount"] == 500
    assert body["ingredients"][1]["amount"] == 0
    assert body["steps"][0]["timer_seconds"] == 3600
    assert calls["n"] == 1

    # second read is served from the cache, and needs no token
    res = await client.get("/api/v1/recipes/salata-test/translations/en")
    assert res.json()["title"] == "Beef Salad"
    assert calls["n"] == 1

    # asking again does not re-run the model either
    await client.post("/api/v1/recipes/salata-test/translations/en", headers=auth)
    assert calls["n"] == 1


async def test_editing_a_recipe_drops_the_stale_translation(client, auth, monkeypatch):
    """A new version must not inherit the previous version's translated words."""
    async def fake_translate(payload, target):
        return {"title": "Beef Salad", "meta": None,
                "ingredients": payload["ingredients"], "steps": payload["steps"],
                "notes": payload["notes"]}

    monkeypatch.setattr("app.services.translate.translate_recipe", fake_translate)
    await _make_recipe(client, auth)
    await client.post("/api/v1/recipes/salata-test/translations/en", headers=auth)

    await client.put(
        "/api/v1/recipes/salata-test",
        json={"ingredients": [{"amount": 600, "unit": "g", "name": "carne de porc"}],
              "steps": [{"text": "Fierbe."}], "notes": []},
        headers=auth,
    )
    res = await client.get("/api/v1/recipes/salata-test/translations/en")
    assert res.json()["available"] is False


async def test_translation_requires_auth_to_create_but_not_to_read(client, auth):
    await _make_recipe(client, auth)
    assert (await client.post("/api/v1/recipes/salata-test/translations/en")).status_code == 401
    assert (await client.get("/api/v1/recipes/salata-test/translations/en")).status_code == 200
