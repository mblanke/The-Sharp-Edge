"""Round-trip: DB → /export/master.md → importer parsers → identical content.

The seed importer's manifest owns metadata (slugs, yields, GF), so the
meaningful invariant is content fidelity: every exported ingredient bullet,
step, and note must re-parse to exactly what the DB holds — for the full
18-recipe seed corpus, not a toy fixture.
"""

import re
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO / "seed"))

from import_master import parse_ingredient, parse_master  # noqa: E402

from app.models import Recipe, RecipeVersion  # noqa: E402
from app.services.master_export import format_master_amount, render_master  # noqa: E402

MASTER = (REPO / "seed" / "recipes-master.md").read_text(encoding="utf-8")


@pytest.fixture
async def seeded(session_factory):
    """Load the real 18-recipe seed corpus into the test DB."""
    recipes = parse_master(MASTER)
    async with session_factory() as session:
        for r in recipes:
            recipe = Recipe(
                slug=r["slug"], title=r["title"], category=r["category"], meta=r["meta"],
                base_yield=r["base_yield"], yield_word=r["yield_word"], gf=r["gf"],
                noscale=r["noscale"], source=r["source"], status=r["status"],
            )
            recipe.versions.append(
                RecipeVersion(
                    version=1, label=r["label"], ingredients=r["ingredients"],
                    steps=r["steps"], notes=r["notes"], is_current=True,
                )
            )
            session.add(recipe)
        await session.commit()
    return recipes


def _parse_export(text: str) -> dict[str, dict]:
    """Minimal reader of the exported format: title → {ingredients, steps, notes}."""
    out: dict[str, dict] = {}
    current = None
    mode = None
    section = None
    for line in text.splitlines():
        h2 = re.match(r"^## (.+)$", line)
        if h2:
            current = {"ingredients": [], "steps": [], "notes": []}
            out[h2.group(1)] = current
            mode, section = None, None
            continue
        if current is None:
            continue
        h3 = re.match(r"^### (.+)$", line)
        if h3:
            mode = {"Ingredients": "ing", "Instructions": "steps", "Notes": "notes"}[h3.group(1)]
            section = None
            continue
        h4 = re.match(r"^#### (.+)$", line)
        if h4:
            section = h4.group(1)
            continue
        if mode == "ing" and line.startswith("- "):
            current["ingredients"].append(parse_ingredient(line, section))
        elif mode == "steps" and re.match(r"^\d+\. ", line):
            current["steps"].append({"text": re.sub(r"^\d+\.\s+", "", line)})
        elif mode == "notes" and line.startswith("- "):
            current["notes"].append(line[2:].strip())
    return out


async def test_export_round_trips_all_seed_content(client, auth, seeded):
    res = await client.get("/api/v1/export/master.md", headers=auth)
    assert res.status_code == 200
    assert res.headers["content-type"].startswith("text/markdown")
    exported = _parse_export(res.text)

    for r in seeded:
        got = exported[r["title"]]
        want_ings = [
            {"amount": i.get("amount", 0), "unit": i.get("unit", ""), "name": i["name"],
             **({"section": i["section"]} if i.get("section") else {})}
            for i in r["ingredients"]
        ]
        got_ings = [
            {"amount": i["amount"], "unit": i["unit"], "name": i["name"],
             **({"section": i["section"]} if i.get("section") else {})}
            for i in got["ingredients"]
        ]
        assert got_ings == want_ings, f"ingredients drifted for {r['slug']}"
        assert [s["text"] for s in got["steps"]] == [s["text"] for s in r["steps"]], (
            f"steps drifted for {r['slug']}"
        )
        assert got["notes"] == r["notes"], f"notes drifted for {r['slug']}"


async def test_export_structure_and_flags(client, auth, seeded):
    res = await client.get("/api/v1/export/master.md", headers=auth)
    text = res.text
    # category chapters appear in glue-in order
    chapters = re.findall(r"^# (.+)$", text, re.M)[1:]  # skip the file title
    assert chapters.index("Sauces & Salsas") < chapters.index("Marinades") < chapters.index("Reference")
    # GF survives (celiac-critical) and drafts are marked
    goulash = text.split("## Gluten-Free Hungarian Beef Goulash")[1].split("##")[0]
    assert "GF" in goulash
    slaw = text.split("## Pineapple Mango Broccoli Slaw")[1].split("##")[0]
    assert "draft" in slaw
    # marinade version labels survive
    assert "version: quick 4–8 hr" in text
    # never the owner's name (CLAUDE.md core principle)
    assert "marc" not in text.lower()
    assert "blanke" not in text.lower()


async def test_export_requires_auth(client, seeded):
    res = await client.get("/api/v1/export/master.md")
    assert res.status_code == 401


def test_format_master_amount_reparses():
    for value in [1, 2, 0.5, 0.25, 0.75, 1.5, 2.25, 1 / 3, 2 / 3, 0.375, 1.33, 15]:
        rendered = format_master_amount(value)
        line = f"- {rendered} cup broth"
        assert abs(parse_ingredient(line)["amount"] - value) < 1e-9, (value, rendered)


async def test_export_excludes_archived(client, auth, session_factory):
    async with session_factory() as session:
        recipe = Recipe(
            slug="retired", title="Retired Dish", category="Sides",
            base_yield=2, yield_word="servings", status="archived",
        )
        recipe.versions.append(
            RecipeVersion(
                version=1, ingredients=[{"amount": 1, "unit": "g", "name": "salt"}],
                steps=[{"text": "Stir."}], notes=[], is_current=True,
            )
        )
        session.add(recipe)
        await session.commit()
    res = await client.get("/api/v1/export/master.md", headers=auth)
    assert "Retired Dish" not in res.text
