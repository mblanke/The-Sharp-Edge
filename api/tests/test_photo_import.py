"""Photo-to-recipe capture (E2) — tier firewall, gating, and parsing."""

import pytest

from app.config import settings
from app.services.llm import TierViolation, ensure_public_tier
from app.services.photo_import import RecipeDraft, parse_photo

PNG = b"\x89PNG\r\n\x1a\nfakebytes"


def test_firewall_refuses_corpus_content():
    with pytest.raises(TierViolation):
        ensure_public_tier(has_corpus_chunks=True)
    ensure_public_tier(has_corpus_chunks=False)  # public tier passes


async def test_disabled_without_key(monkeypatch):
    monkeypatch.setattr(settings, "anthropic_api_key", "")
    from fastapi import HTTPException

    with pytest.raises(HTTPException) as e:
        await parse_photo(PNG, "image/png")
    assert e.value.status_code == 501


async def test_rejects_non_image_media(monkeypatch):
    monkeypatch.setattr(settings, "anthropic_api_key", "sk-test")
    from fastapi import HTTPException

    with pytest.raises(HTTPException) as e:
        await parse_photo(b"%PDF-", "application/pdf")
    assert e.value.status_code == 415


class _FakeResponse:
    def __init__(self, parsed, stop_reason="end_turn"):
        self.parsed_output = parsed
        self.stop_reason = stop_reason


class _FakeMessages:
    def __init__(self, response):
        self._response = response
        self.calls: list[dict] = []

    async def parse(self, **kwargs):
        self.calls.append(kwargs)
        return self._response


class _FakeAnthropic:
    last: "_FakeAnthropic | None" = None

    def __init__(self, response):
        self._response = response

    def __call__(self, **kwargs):  # stands in for the AsyncAnthropic constructor
        _FakeAnthropic.last = self
        self.messages = _FakeMessages(self._response)
        return self

    async def close(self):
        pass


async def test_parses_photo_into_draft(monkeypatch):
    import anthropic

    monkeypatch.setattr(settings, "anthropic_api_key", "sk-test")
    draft = RecipeDraft(
        title="Cast-Iron Cornbread",
        base_yield=8,
        ingredients=[{"amount": 240, "unit": "g", "name": "cornmeal"}],
        steps=[{"text": "Bake 25 minutes.", "timer_seconds": 1500}],
    )
    fake = _FakeAnthropic(_FakeResponse(draft))
    monkeypatch.setattr(anthropic, "AsyncAnthropic", fake)

    out = await parse_photo(PNG, "image/png")
    assert out.title == "Cast-Iron Cornbread"
    assert out.steps[0].timer_seconds == 1500

    call = _FakeAnthropic.last.messages.calls[0]
    assert call["model"] == settings.anthropic_model
    assert call["output_format"] is RecipeDraft
    image_block = call["messages"][0]["content"][0]
    assert image_block["type"] == "image"
    assert image_block["source"]["media_type"] == "image/png"
    # no corpus content anywhere in the request
    assert "Cooking/" not in str(call["messages"])


async def test_refusal_maps_to_422(monkeypatch):
    import anthropic

    monkeypatch.setattr(settings, "anthropic_api_key", "sk-test")
    fake = _FakeAnthropic(_FakeResponse(None, stop_reason="refusal"))
    monkeypatch.setattr(anthropic, "AsyncAnthropic", fake)
    from fastapi import HTTPException

    with pytest.raises(HTTPException) as e:
        await parse_photo(PNG, "image/png")
    assert e.value.status_code == 422


async def test_endpoint_requires_auth_and_returns_draft(client, auth, monkeypatch):
    import app.routers.recipes  # noqa: F401 — route registered

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
