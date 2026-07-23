"""Seed importer parse tests — pure parsing, no DB."""

import sys
from pathlib import Path

import pytest

SEED_DIR = Path(__file__).resolve().parents[2] / "seed"
sys.path.insert(0, str(SEED_DIR))

from import_master import MANIFEST, parse_ingredient, parse_master  # noqa: E402

MASTER = (SEED_DIR / "recipes-master.md").read_text(encoding="utf-8")


@pytest.fixture(scope="module")
def recipes():
    return {r["slug"]: r for r in parse_master(MASTER)}


def test_all_manifest_recipes_parsed(recipes):
    assert set(recipes) == {m["slug"] for m in MANIFEST}
    assert len(recipes) == 20  # 18 active + 2 drafts


def test_qr_contract_slugs_active(recipes):
    contract = {
        "mango-salsa", "cucumber-dressing", "raspberry-vinaigrette", "bourbon-butter",
        "flank-quick", "flank-overnight", "souvlaki", "tequila-lime", "cucumber-salad-thai",
        "gurkensalat", "watermelon-feta", "goulash", "spaghetti-sauce", "salmon-mango",
        "stirfry", "celeriac", "pancakes", "gf-reference",
    }
    active = {s for s, r in recipes.items() if r["status"] == "active"}
    assert active == contract
    assert {s for s, r in recipes.items() if r["status"] == "draft"} == {"broccoli-slaw", "visinata"}


def test_goulash(recipes):
    g = recipes["goulash"]
    assert g["gf"] is True
    assert g["base_yield"] == 6
    ing = {i["name"]: i for i in g["ingredients"]}
    assert ing["beef chuck, cut into 1-inch cubes"]["amount"] == 2.0
    assert ing["beef chuck, cut into 1-inch cubes"]["unit"] == "lb"
    assert ing["sweet Hungarian paprika (certified GF)"]["amount"] == 3.0
    assert ing["sweet Hungarian paprika (certified GF)"]["unit"] == "tbsp"
    assert len(g["steps"]) == 6


def test_gf_reference_noscale(recipes):
    r = recipes["gf-reference"]
    assert r["noscale"] is True
    assert r["ingredients"] == []
    assert any("Worcestershire" in s["text"] for s in r["steps"])
    assert not any(s["text"] in ("Wheat", "Barley", "Malt") for s in r["steps"])


def test_sections_survive(recipes):
    sections = {i.get("section") for i in recipes["stirfry"]["ingredients"]}
    assert sections == {"Velveting marinade", "Sauce", "Everything else"}


def test_metric_conversion(recipes):
    v = {i["name"]: i for i in recipes["visinata"]["ingredients"]}
    cherries = next(x for x in v.values() if "cherries" in x["name"])
    assert (cherries["amount"], cherries["unit"]) == (2000.0, "g")
    spirit = v["spirit"]
    assert (spirit["amount"], spirit["unit"]) == (1750.0, "ml")  # midpoint of 1.5–2 L


def test_no_owner_name_anywhere(recipes):
    blob = repr(recipes).lower()
    for token in ["marc", "blanke", "anne"]:
        assert token not in blob, f"owner/family name leaked: {token}"


@pytest.mark.parametrize(
    "line,expected",
    [
        ("- 1 1/2 cups all-purpose flour", (1.5, "cup", "all-purpose flour")),
        ("- 3/4 cup olive oil", (0.75, "cup", "olive oil")),
        ("- Juice of 4 lemons", (4.0, "", "lemons, juiced")),
        ("- Freshly ground black pepper, to taste", (0, "", "Freshly ground black pepper, to taste")),
        ("- 1 can diced tomatoes", (1.0, "", "can diced tomatoes")),
        ("- 3–4 celery sticks", (3.5, "", "celery sticks")),
        ("- 1.5–2 lb block feta in brine", (1.75, "lb", "block feta in brine")),
        ("- ~2 kg sour cherries", (2000.0, "g", "sour cherries")),
        ("- 900 g celeriac (celery root), peeled, cut into 2 cm cubes", (900.0, "g", "celeriac (celery root), peeled, cut into 2 cm cubes")),
        ("- 120 ml heavy cream", (120.0, "ml", "heavy cream")),
        ("- Pinch of freshly grated nutmeg", (0, "", "Pinch of freshly grated nutmeg")),
    ],
)
def test_parse_ingredient(line, expected):
    row = parse_ingredient(line)
    assert (row["amount"], row["unit"], row["name"]) == expected
