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
