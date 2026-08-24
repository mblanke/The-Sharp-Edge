"""Fail-closed auth: the placeholder API_TOKEN must never be a valid credential."""

import pytest

from app.auth import DEFAULT_TOKEN
from app.config import settings

RECIPE = {
    "slug": "auth-probe",
    "title": "Auth Probe",
    "category": "Sauces",
    "base_yield": 1,
    "yield_word": "servings",
    "ingredients": [{"amount": 1, "unit": "g", "name": "salt"}],
    "steps": [{"text": "Stir."}],
}


@pytest.mark.parametrize("token_value", ["", DEFAULT_TOKEN])
async def test_unconfigured_token_disables_writes(client, monkeypatch, token_value):
    monkeypatch.setattr(settings, "api_token", token_value)
    res = await client.post(
        "/api/v1/recipes",
        json=RECIPE,
        headers={"Authorization": f"Bearer {DEFAULT_TOKEN}"},
    )
    assert res.status_code == 503
    assert res.headers["content-type"] == "application/problem+json"
    assert "API_TOKEN" in res.json()["detail"]


async def test_configured_token_allows_writes(client, auth):
    res = await client.post("/api/v1/recipes", json=RECIPE, headers=auth)
    assert res.status_code == 201


async def test_wrong_token_still_401(client):
    res = await client.post(
        "/api/v1/recipes", json=RECIPE, headers={"Authorization": "Bearer nope"}
    )
    assert res.status_code == 401
