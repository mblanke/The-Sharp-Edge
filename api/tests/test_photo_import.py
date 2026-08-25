"""Photo-to-recipe capture (E2) — local vision does OCR, our parser does structure."""

import pytest
from fastapi import HTTPException

import app.services.photo_import as photo_module
from app.config import settings
from app.services.llm import TierViolation, ensure_public_tier
from app.services.photo_import import RecipeDraft, parse_photo, parse_transcript

PNG = b"\x89PNG\r\n\x1a\nfakebytes"

FRENCH_PAGE = """LANG: fr
TITLE: Crêpes de Mamie
YIELD: Pour 4 personnes
INGREDIENTS:
- 250 g de farine
- 3 œufs
- 50 cl de lait
- 2 c. à s. de beurre fondu
- 1 pincée de sel
STEPS:
- Mélanger la farine et les œufs.
- Ajouter le lait peu à peu, puis le beurre.
- Laisser reposer 30 minutes.
- Cuire chaque crêpe 1 minute par face.
NOTES:
- Meilleures le lendemain.
"""


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


def test_french_page_structures_correctly():
    """The failure that drove this design: quantities must survive '250 g de farine'."""
    draft = parse_transcript(FRENCH_PAGE)
    assert draft.title == "Crêpes de Mamie"
    assert draft.base_yield == 4
    assert draft.yield_word == "personnes"

    rows = [(i.amount, i.unit, i.name) for i in draft.ingredients]
    assert rows[0][0] == 250 and rows[0][1] == "g"  # not unit="de farine"
    assert rows[1][0] == 3 and rows[1][1] == ""  # countable
    # 50 cl → the shared parser's metric handling, not the model's arithmetic
    assert rows[2][1] in ("ml", "cl")
    assert "lait" in rows[2][2]

    # durations on the page become timers
    assert [s.timer_seconds for s in draft.steps] == [None, None, 1800, 60]
    assert draft.notes == ["Meilleures le lendemain."]


def test_numbered_steps_and_missing_sections():
    draft = parse_transcript(
        """LANG: en
TITLE: Quick Toast
YIELD:
INGREDIENTS:
1. 2 slices bread
STEPS:
1. Toast for 3 minutes.
NOTES:
"""
    )
    assert draft.base_yield == 1  # no yield line → sane default
    assert draft.yield_word == "servings"
    assert draft.ingredients[0].amount == 2  # "1." bullet stripped, not read as amount
    assert draft.steps[0].timer_seconds == 180
    assert draft.notes == []


def test_german_and_romanian_pages():
    de = parse_transcript(
        """LANG: de
TITLE: Kartoffelsalat
YIELD: 6 Portionen
INGREDIENTS:
- 1 kg Kartoffeln
- 2 EL Essig
STEPS:
- 20 Minuten kochen.
"""
    )
    assert de.base_yield == 6 and de.yield_word == "Portionen"
    assert de.ingredients[0].amount in (1, 1000)  # kg handled by the shared parser
    assert de.steps[0].timer_seconds == 1200

    ro = parse_transcript(
        """LANG: ro
TITLE: Ciorbă de legume
YIELD: Pentru 4 persoane
INGREDIENTS:
- 2 morcovi
STEPS:
- Se fierbe 45 minute.
"""
    )
    assert ro.title == "Ciorbă de legume"
    assert ro.base_yield == 4
    assert ro.steps[0].timer_seconds == 2700


async def test_one_call_only_and_nothing_paraphrases_the_page(monkeypatch):
    """A second 'tidy up' model rewrote 50 cl as 50 ml — so there is exactly one."""
    calls: list[tuple[str, list[dict]]] = []

    async def fake_complete(messages, model):
        calls.append((model, messages))
        return FRENCH_PAGE

    monkeypatch.setattr(photo_module, "_complete", fake_complete)
    out = await parse_photo(PNG, "image/png")
    assert out.title == "Crêpes de Mamie"
    assert len(out.ingredients) == 5

    assert len(calls) == 1
    assert calls[0][0] == settings.vision_model_alias
    assert calls[0][1][0]["content"][0]["image_url"]["url"].startswith("data:image/png;base64,")
    # only the photo and the fixed instruction leave — and only to the local router
    assert "Cooking/" not in str(calls)


def test_inline_separators_are_treated_as_line_breaks():
    """A real run returned every ingredient on one pipe-separated line."""
    draft = parse_transcript(
        """LANG: fr
TITLE: Crêpes
YIELD: Pour 4 personnes
INGREDIENTS:
250 g de farine | 3 œufs | 50 cl de lait
STEPS:
Mélanger. | Cuire 1 minute.
"""
    )
    assert len(draft.ingredients) == 3
    assert draft.ingredients[2].amount == 500 and draft.ingredients[2].unit == "ml"
    assert len(draft.steps) == 2
    assert draft.steps[1].timer_seconds == 60


async def test_unreadable_page_maps_to_422(monkeypatch):
    async def fake_complete(messages, model):
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
