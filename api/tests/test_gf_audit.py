"""Hidden-gluten audit rules (F3) — celiac safety is load-bearing."""

from app.services.gf_audit import scan_ingredients


def ing(name, note=None):
    return {"amount": 1, "unit": "", "name": name, **({"note": note} if note else {})}


def test_classic_hidden_gluten_terms_flag():
    for name in [
        "soy sauce",
        "Worcestershire sauce",
        "malt vinegar",
        "all-purpose flour",
        "panko",
        "hoisin sauce",
        "oyster sauce",
        "beer (for the batter)",
        "chicken bouillon cube",
        "wasabi oil",
    ]:
        assert scan_ingredients([ing(name)]), f"{name} should be flagged"


def test_cleared_phrasings_pass():
    for name in [
        "GF tamari",
        "gluten-free soy sauce",
        "soy sauce (certified GF)",
        "rice flour",
        "almond flour",
        "buckwheat flour",
        "sweet Hungarian paprika (certified GF)",
    ]:
        assert scan_ingredients([ing(name)]) == [], f"{name} should pass"


def test_note_can_clear_a_risky_name():
    assert scan_ingredients([ing("soy sauce", note="use GF tamari")]) == []


def test_safe_ingredients_never_flag():
    for name in ["beef chuck, cubed", "sweet paprika", "yellow onions", "butter", "salt"]:
        assert scan_ingredients([ing(name)]) == [], name


def test_word_boundaries_avoid_false_positives():
    # 'ryegrass honey' shouldn't flag 'rye'? — it would ('rye' word)… but
    # 'cauliflower' must not flag 'flour', 'wheatgrass-free' edge left strict.
    assert scan_ingredients([ing("cauliflower florets")]) == []
    assert scan_ingredients([ing("maltodextrin-free cocoa")]) == []


async def test_audit_endpoint_reports_warning_and_candidate(client, auth):
    base = {
        "category": "Entrées",
        "base_yield": 4,
        "yield_word": "servings",
        "steps": [{"text": "Cook."}],
    }
    # flagged GF but contains soy sauce → warning
    await client.post(
        "/api/v1/recipes",
        json={**base, "slug": "bad-gf", "title": "Mislabeled Stirfry", "gf": True,
              "ingredients": [ing("soy sauce")]},
        headers=auth,
    )
    # not flagged GF and totally clean → candidate
    await client.post(
        "/api/v1/recipes",
        json={**base, "slug": "clean", "title": "Plain Roast", "gf": False,
              "ingredients": [ing("chicken thighs")]},
        headers=auth,
    )
    # correctly-GF recipe → ok
    await client.post(
        "/api/v1/recipes",
        json={**base, "slug": "good-gf", "title": "Tamari Stirfry", "gf": True,
              "ingredients": [ing("GF tamari")]},
        headers=auth,
    )

    assert (await client.get("/api/v1/admin/gf-audit")).status_code == 401
    res = await client.get("/api/v1/admin/gf-audit", headers=auth)
    body = res.json()
    assert [w["slug"] for w in body["warnings"]] == ["bad-gf"]
    assert "soy sauce" in body["warnings"][0]["risks"][0]["ingredient"]
    assert [c["slug"] for c in body["candidates"]] == ["clean"]
    assert body["ok"] == 1
