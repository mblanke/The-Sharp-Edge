"""Photo-to-recipe capture (E2) — fully local via the router's vision alias."""

import json

import pytest
from fastapi import HTTPException

import app.services.photo_import as photo_module
from app.config import settings
from app.services.llm import TierViolation, ensure_public_tier
from app.services.photo_import import RecipeDraft, parse_photo

PNG = b"\x89PNG\r\n\x1a\nfakebytes"

DRAFT_JSON = json.dumps(
    {
        "title": "Cast-Iron Cornbread",
        "meta": None,
        "base_yield": 8,
        "yield_word": "servings",
        "ingredients": [{"amount": 240, "unit": "g", "name": "cornmeal", "section": None}],
        "steps": [{"text": "Bake 25 minutes.", "timer_seconds": 1500}],
        "notes": [],
    }
)


def test_cloud_firewall_still_holds():
    # unrelated to photo import now (it never leaves the house), but the
    # AnthropicProvider firewall must survive this refactor
    with pytest.raises(TierViolation):
        ensure_public_tier(has_corpus_chunks=True)
    ensure_public_tier(has_corpus_chunks=False)


async def test_disabled_without_alias(monkeypatch):
    monkeypatch.setattr(settings, "vision_model_alias", "")
    with pytest.raises(HTTPException) as e:
        await parse_photo(PNG, "image/png")
    assert e.value.status_code == 501


async def test_rejects_non_image_media():
    with pytest.raises(HTTPException) as e:
        await parse_photo(b"%PDF-", "application/pdf")
    assert e.value.status_code == 415


async def test_rejects_oversized_image():
    with pytest.raises(HTTPException) as e:
        await parse_photo(b"x" * (15 * 1024 * 1024 + 1), "image/png")
    assert e.value.status_code == 413


async def test_parses_photo_into_draft(monkeypatch):
    seen: list[list[dict]] = []

    async def fake_complete(messages):
        seen.append(messages)
        return "Here you go:\n" + DRAFT_JSON

    monkeypatch.setattr(photo_module, "_complete", fake_complete)

    out = await parse_photo(PNG, "image/png")
    assert out.title == "Cast-Iron Cornbread"
    assert out.steps[0].timer_seconds == 1500

    content = seen[0][0]["content"]
    assert content[0]["type"] == "image_url"
    assert content[0]["image_url"]["url"].startswith("data:image/png;base64,")
    # nothing but the photo and the fixed instruction goes out — and only locally
    assert "Cooking/" not in str(seen)


async def test_metric_multiples_convert_in_code(monkeypatch):
    """'50 cl de lait' must become 500 ml — arithmetic is ours, not the model's."""
    draft = json.dumps(
        {
            "title": "Crêpes",
            "base_yield": 4,
            "yield_word": "personnes",
            "ingredients": [
                {"amount": 50, "unit": "cl", "name": "lait"},
                {"amount": 1, "unit": "kg", "name": "farine"},
                {"amount": 2, "unit": "dl", "name": "crème"},
                {"amount": 1.5, "unit": "L", "name": "bouillon"},
                {"amount": 250, "unit": "g", "name": "beurre"},
            ],
            "steps": [],
            "notes": [],
        }
    )

    async def fake_complete(messages):
        return draft

    monkeypatch.setattr(photo_module, "_complete", fake_complete)
    out = await parse_photo(PNG, "image/png")
    rows = {i.name: (i.amount, i.unit) for i in out.ingredients}
    assert rows["lait"] == (500, "ml")
    assert rows["farine"] == (1000, "g")
    assert rows["crème"] == (200, "ml")
    assert rows["bouillon"] == (1500, "ml")
    assert rows["beurre"] == (250, "g")  # already base — untouched


async def test_garbage_output_maps_to_422(monkeypatch):
    async def fake_complete(messages):
        return "I see a lovely handwritten page but cannot read it."

    monkeypatch.setattr(photo_module, "_complete", fake_complete)
    with pytest.raises(HTTPException) as e:
        await parse_photo(PNG, "image/png")
    assert e.value.status_code == 422


async def test_endpoint_requires_auth_and_returns_draft(client, auth, monkeypatch):
    async def fake_parse(image, media_type):
        assert media_type == "image/jpeg"
        return RecipeDraft(title="From Photo", base_yield=2)

    monkeypatch.setattr("app.services.photo_import.parse_photo", fake_parse)

    files = {"photo": ("page.jpg", b"binary", "image/jpeg")}
    res = await client.post("/api/v1/recipes/parse-photo", files=files)
    assert res.status_code == 401

    res = await client.post("/api/v1/recipes/parse-photo", files=files, headers=auth)
    assert res.status_code == 200
    assert res.json()["title"] == "From Photo"


async def test_tolerates_messy_model_output(monkeypatch):
    """Real vision models emit nulls and strings where the schema wants values."""
    messy = json.dumps(
        {
            "title": "Ciorbă de legume",
            "meta": None,
            "base_yield": None,  # page had no serving count
            "yield_word": None,
            "ingredients": [
                {"amount": "2", "unit": None, "name": "morcovi"},
                {"amount": None, "unit": "", "name": "sare"},
                {"amount": 1, "unit": "", "name": ""},  # nameless → dropped
                "not even a dict",
            ],
            "steps": ["Se fierbe totul.", {"text": "Se servește.", "timer_seconds": "600"}],
            "notes": [None, "", "Mai bună a doua zi."],
        }
    )

    async def fake_complete(messages):
        return messy

    monkeypatch.setattr(photo_module, "_complete", fake_complete)
    out = await parse_photo(PNG, "image/png")
    assert out.title == "Ciorbă de legume"
    assert out.base_yield == 1  # defaulted, not 422
    assert out.yield_word == "servings"
    assert [i.name for i in out.ingredients] == ["morcovi", "sare"]
    assert out.ingredients[0].amount == 2
    assert out.steps[0].text == "Se fierbe totul."
    assert out.steps[1].timer_seconds == 600
    assert out.notes == ["Mai bună a doua zi."]
