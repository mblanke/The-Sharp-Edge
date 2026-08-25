"""Cook-session log endpoints (E1) — app-only history."""

from tests.test_tags_pages import _recipe


async def test_log_and_list_sessions(client, auth):
    await client.post("/api/v1/recipes", json=_recipe("weeknight-stew"), headers=auth)

    res = await client.post(
        "/api/v1/recipes/weeknight-stew/sessions",
        json={"scaled_yield": 4, "notes": "  doubled the paprika  "},
        headers=auth,
    )
    assert res.status_code == 201
    body = res.json()
    assert body["scaled_yield"] == 4
    assert body["notes"] == "doubled the paprika"
    assert body["started_at"] == body["finished_at"]  # untimed log

    res = await client.post(
        "/api/v1/recipes/weeknight-stew/sessions",
        json={"scaled_yield": 8, "started_at": "2026-08-24T17:00:00Z"},
        headers=auth,
    )
    assert res.status_code == 201
    assert res.json()["notes"] is None

    res = await client.get("/api/v1/recipes/weeknight-stew/sessions")
    sessions = res.json()
    assert len(sessions) == 2
    # newest first
    assert sessions[0]["scaled_yield"] == 8
    assert sessions[1]["notes"] == "doubled the paprika"


async def test_log_requires_auth_and_known_slug(client, auth):
    await client.post("/api/v1/recipes", json=_recipe("auth-stew"), headers=auth)
    res = await client.post("/api/v1/recipes/auth-stew/sessions", json={"scaled_yield": 2})
    assert res.status_code == 401
    res = await client.post(
        "/api/v1/recipes/ghost/sessions", json={"scaled_yield": 2}, headers=auth
    )
    assert res.status_code == 404
