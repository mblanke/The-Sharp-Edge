"""Library passage → notebook draft. The fixture is the CIA's actual onion soup.

The deterministic path must handle a real cookbook page: imperial/metric twin
quantities, a "Makes 1 gal" yield line, numbered steps with durations, a NOTE. The
model fallback only runs when the passage is prose-shaped, and it must never be needed
for a page this clean — that is asserted, because the fallback costs seconds and the
deterministic path costs nothing.
"""

import pytest

import app.services.passage_import as passage_module
from app.services.passage_import import parse_passage, passage_to_draft

# Printed page 335 of The Professional Chef, left column, as the book actually reads.
CIA_ONION_SOUP = """
Onion Soup
Makes 1 gal/3.84 L

5 lb/2.27 kg thinly sliced onions
2 oz/57 g clarified or whole butter
4 fl oz/120 mL Calvados or sherry
1 gal/3.84 L Chicken or White Beef Stock, warm
1 Standard Sachet d'Epices
Salt, as needed
Ground black pepper, as needed

1. In a large sauce pot or rondeau, caramelize the onions in the butter over medium-high heat, stirring occasionally, until browned, 25 to 30 minutes.
2. Deglaze the pan with the Calvados and reduce over medium-high to high heat until it reaches a syrupy consistency.
3. Add the stock and the sachet and simmer until the onions are tender and the soup is properly flavored, 30 to 35 minutes.
4. To finish the soup for service, return it to a boil. Season with salt and pepper and serve in heated bowls or cups.

NOTE: If sherry is used, add it to the soup at the end of cooking time.
"""


def test_cia_onion_soup_structures_deterministically():
    draft = parse_passage(CIA_ONION_SOUP)

    assert draft.title == "Onion Soup"
    assert draft.base_yield == 1 and draft.yield_word == "gal"
    assert draft.meta.startswith("Makes 1 gal")

    rows = [(i.amount, i.unit, i.name) for i in draft.ingredients]
    # metric twins stripped, first reading kept
    assert rows[0][0] == 5 and rows[0][1] == "lb"
    assert "2.27" not in rows[0][2] and "onions" in rows[0][2]
    assert rows[1][0] == 2 and rows[1][1] == "oz"
    # "Salt, as needed" → to taste
    salt = next(r for r in rows if r[2] == "Salt")
    assert salt[0] == 0  # name trimmed of ", as needed", amount 0 = em dash
    pepper = next(r for r in rows if "pepper" in r[2])
    assert pepper[0] == 0

    assert len(draft.steps) == 4
    # "25 to 30 minutes" → a timer at the range's top end, ready to tap
    assert draft.steps[0].timer_seconds == 30 * 60
    assert draft.steps[2].timer_seconds == 35 * 60

    assert draft.notes and draft.notes[0].startswith("If sherry is used")


def test_fractions_survive_the_metric_twin_stripper():
    draft = parse_passage("Test\nMakes 4 servings\n1/2 cup heavy cream\n1 lb/450 g flour\nStir together until combined.")
    rows = [(i.amount, i.unit, i.name) for i in draft.ingredients]
    assert (0.5, "cup") == rows[0][:2]  # 1/2 must NOT be read as a metric twin
    assert rows[1][0] == 1 and rows[1][1] == "lb" and "450" not in rows[1][2]


def test_ingredient_sections_are_carried():
    draft = parse_passage(
        "Ribollita\nServes 6\n2 cup beans\nFOR THE BROTH:\n1 gal stock\n2 bay leaves\nSimmer everything for 1 hour."
    )
    assert draft.ingredients[0].section is None
    assert draft.ingredients[1].section == "Broth" or draft.ingredients[1].section == "For The Broth"
    assert draft.ingredients[2].section == draft.ingredients[1].section


def test_editorial_prose_before_the_recipe_is_dropped():
    """CLAUDE.md §1: method and function only — a book's introduction stays in the book."""
    text = (
        "There is nothing quite like the smell of onions slowly giving up their sugars "
        "on a winter afternoon, a smell my grandmother knew well.\n" + CIA_ONION_SOUP
    )
    draft = parse_passage(text)
    assert draft.title == "Onion Soup"
    assert all("grandmother" not in s.text for s in draft.steps)
    assert all("grandmother" not in n for n in draft.notes)


async def test_clean_passage_never_touches_the_model(monkeypatch):
    async def boom(messages, model):
        raise AssertionError("deterministic path must not call the model")

    monkeypatch.setattr(passage_module, "_complete", boom)
    draft = await passage_to_draft(CIA_ONION_SOUP)
    assert len(draft.ingredients) == 7


async def test_prose_passage_falls_back_to_local_reformat(monkeypatch):
    """A technique discussion has no ingredient lines; the local model reformats
    (never summarises) and parse_transcript structures its output."""
    calls: list[str] = []

    async def fake_complete(messages, model):
        calls.append(model)
        assert "Reformat" in messages[0]["content"]
        return (
            "LANG: en\nTITLE: Beurre Blanc\nYIELD: Makes 8 servings\n"
            "INGREDIENTS:\n- 2 shallots\n- 250 g butter\nSTEPS:\n- Reduce wine with shallots.\n"
        )

    monkeypatch.setattr(passage_module, "_complete", fake_complete)
    draft = await passage_to_draft(
        "A beurre blanc begins, as so many things do, with a careful reduction. "
        "The butter must be very cold and worked in gradually off the heat."
    )
    assert calls  # fallback ran, on the local chat alias
    assert draft.title == "Beurre Blanc"
    assert draft.ingredients[1].amount == 250 and draft.ingredients[1].unit == "g"


async def test_fallback_that_finds_less_than_the_deterministic_pass_loses(monkeypatch):
    async def worse(messages, model):
        return "LANG: en\nTITLE: X\nINGREDIENTS:\n- 1 thing\nSTEPS:\n"

    monkeypatch.setattr(passage_module, "_complete", worse)
    # deterministic finds 2 ingredients but no steps → fallback runs → loses on count
    draft = await passage_to_draft("T\n1 cup milk\n2 tbsp sugar\n")
    assert len(draft.ingredients) == 2


def test_chunk_heading_backstops_a_missing_title():
    draft = parse_passage("1 cup milk\n2 tbsp sugar\nWarm gently until dissolved.", fallback_title="Sweet Milk")
    assert draft.title == "Sweet Milk"


# --- the endpoint and the tier ---------------------------------------------------------


async def test_endpoint_marks_the_draft_private_and_carries_the_source(client, auth, monkeypatch):
    body = {
        "text": CIA_ONION_SOUP,
        "source_title": "The Professional Chef",
        "page": 335,
    }
    assert (await client.post("/api/v1/recipes/parse-passage", json=body)).status_code == 401

    res = await client.post("/api/v1/recipes/parse-passage", json=body, headers=auth)
    assert res.status_code == 200
    out = res.json()
    assert out["private"] is True
    assert out["source"] == "The Professional Chef · p.335"
    assert out["draft"]["title"] == "Onion Soup"
    assert len(out["draft"]["ingredients"]) == 7


async def test_private_recipe_never_reaches_the_public_exports(client, auth):
    """CLAUDE.md §1: corpus-drafted recipes stay inside this deployment. master.md is
    the public tier — one private recipe leaking into it is the failure this exists
    to prevent."""
    create = {
        "slug": "cia-onion-soup",
        "title": "Onion Soup",
        "category": "Soups",
        "base_yield": 1,
        "yield_word": "gal",
        "source": "The Professional Chef · p.335",
        "private": True,
        "ingredients": [{"amount": 5, "unit": "lb", "name": "onions"}],
        "steps": [{"text": "Caramelize."}],
    }
    assert (await client.post("/api/v1/recipes", json=create, headers=auth)).status_code == 201

    public = {**create, "slug": "own-goulash", "title": "Goulash", "private": False}
    assert (await client.post("/api/v1/recipes", json=public, headers=auth)).status_code == 201

    master = (await client.get("/api/v1/export/master.md", headers=auth)).text
    assert "Goulash" in master
    assert "Onion Soup" not in master and "cia-onion-soup" not in master

    # but the recipe itself is fully usable inside the app
    res = await client.get("/api/v1/recipes/cia-onion-soup")
    assert res.status_code == 200
    assert res.json()["private"] is True
