"""CORS is restricted to the app's own origins, not the whole tailnet."""

from app.config import settings


async def test_preflight_allows_base_url(client):
    res = await client.options(
        "/api/v1/recipes",
        headers={
            "Origin": settings.base_url,
            "Access-Control-Request-Method": "GET",
        },
    )
    assert res.headers.get("access-control-allow-origin") == settings.base_url


async def test_preflight_rejects_foreign_origin(client):
    res = await client.options(
        "/api/v1/recipes",
        headers={
            "Origin": "https://evil.example",
            "Access-Control-Request-Method": "GET",
        },
    )
    assert res.headers.get("access-control-allow-origin") is None


def test_extra_origins_parse(monkeypatch):
    monkeypatch.setattr(settings, "cors_origins", "http://atlas:3010, http://spare:3010")
    assert settings.cors_origin_list == [
        settings.base_url,
        "http://atlas:3010",
        "http://spare:3010",
    ]
