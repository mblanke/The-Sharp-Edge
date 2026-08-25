"""Seed importer: parses seed/recipes-master.md into the DB (CLAUDE.md §11).

Run inside the api container (app package installed, master mounted at /seed):
    python /seed/import_master.py            # imports missing recipes
    python /seed/import_master.py --force    # re-imports everything (replaces)

The master file is canonical prose; numeric base yields, slugs, categories and
GF flags come from the manifest below (they are not derivable from prose).
Slugs are the QR contract — never change them.
"""

import argparse
import asyncio
import re
import sys
from fractions import Fraction
from pathlib import Path

DEFAULT_MASTER = Path(__file__).resolve().parent / "recipes-master.md"

# ---------------------------------------------------------------- manifest

# Section-name → role defaults; per-recipe overrides in the manifest.
DEFAULT_ROLES = {
    "Ingredients": "ing",
    "Instructions": "steps",
    "Method": "steps",
    "Method outline": "steps",
    "Notes": "notes",
}

MANIFEST: list[dict] = [
    dict(slug="mango-salsa", heading="Mango Salsa", category="Sauces & Salsas",
         base=8, yield_word="servings", gf=True,
         meta="About 2 cups · salmon, seafood, chicken, tacos, chips"),
    dict(slug="cucumber-dressing", heading="Thai-Japanese Cucumber Dressing", category="Sauces & Salsas",
         base=2, yield_word="cucumbers", gf=True,
         meta="Enough for 2 large cucumbers"),
    dict(slug="raspberry-vinaigrette", heading="Raspberry Vinaigrette", category="Sauces & Salsas",
         base=4, yield_word="servings", gf=True,
         meta="For the chilled chicken, goat cheese & raspberry salad"),
    dict(slug="bourbon-butter", heading="Bourbon-Shallot Seafood Butter", category="Sauces & Salsas",
         base=12, yield_word="coins", gf=True,
         meta="One ~250 g log · chargrilled oysters & lobster"),
    dict(slug="flank-quick", heading="Flank Steak Marinade — Quick (4–8 hr)", category="Marinades",
         base=15, yield_word="servings", gf=True,
         meta="4–8 hr · coats 5–6 lb flank · v1", label="quick 4–8 hr"),
    dict(slug="flank-overnight", heading="Flank Steak Marinade — Overnight (12–18 hr)", category="Marinades",
         base=15, yield_word="servings", gf=True,
         meta="12–18 hr · coats 5–6 lb flank · v2", label="overnight 12–18 hr"),
    dict(slug="souvlaki", heading="Chicken Souvlaki Marinade", category="Marinades",
         base=15, yield_word="servings", gf=True,
         meta="For 5 lb boneless skinless thighs"),
    dict(slug="cucumber-salad-thai", heading="Thai-Japanese Cucumber Salad", category="Salads",
         base=4, yield_word="servings", gf=True,
         meta="Side · 15 min + draining",
         roles={"Optional Additions": "note_join:Add-ins"}),
    dict(slug="watermelon-feta", heading="Watermelon-Feta-Mint Salad", category="Salads",
         base=15, yield_word="servings", gf=True,
         meta="Assemble day-of only"),
    dict(slug="gurkensalat", heading="German Creamy Cucumber-Dill Salad (Gurkensalat)", category="Salads",
         base=6, yield_word="servings", gf=True,
         meta="Gurkensalat · sour cream + Greek yogurt · BBQ side"),
    dict(slug="broccoli-slaw", heading="Pineapple Mango Broccoli Slaw", category="Salads",
         base=15, yield_word="servings", gf=True, status="draft",
         meta="Side for ~15 · dressing quantities pending"),
    dict(slug="goulash", heading="Gluten-Free Hungarian Beef Goulash", category="Soups & Stews",
         base=6, yield_word="servings", gf=True,
         meta="Potato-thickened · no flour, no roux"),
    dict(slug="tequila-lime", heading="Tequila Lime Chicken — Tacos or Club", category="Sandwiches",
         base=4, yield_word="servings", gf=True, source="food.com #493784",
         meta="House use: taco filling · original: the club sandwich",
         roles={"Tequila lime marinade": "ing",
                "Taco build (house version)": "step_para",
                "Club build (original)": "step_para"}),
    dict(slug="spaghetti-sauce", heading="Family Spaghetti Sauce (2009)", category="Pasta",
         base=8, yield_word="servings", source="family recipe, 2009",
         meta="Big batch · freezes well",
         notes_override=["Herb quantities pending transcription from the paper original."]),
    dict(slug="salmon-mango", heading="Salmon with Mango Salsa", category="Entrées",
         base=4, yield_word="servings", gf=True,
         meta="15 min prep · 10–14 min cook",
         roles={"Recommended Sides": "note_join:Sides",
                "Grill Method": "note_join:Grill"}),
    dict(slug="stirfry", heading="Flank Steak Stir-Fry with Black Bean–Hoisin Sauce", category="Entrées",
         base=4, yield_word="servings",
         meta="Black bean–hoisin · tested at 800 g (sear in batches)"),
    dict(slug="celeriac", heading="Celeriac Purée with Infused Milk & Cream", category="Sides",
         base=4, yield_word="servings", gf=True,
         meta="Silky · pairs with steak"),
    dict(slug="pancakes", heading="Classic Fluffy Pancakes", category="Breakfast",
         base=4, yield_word="servings",
         meta="~10 medium pancakes",
         roles={"Optional Additions": "note_join:Add after pouring",
                "Serving Ideas": "note_join:Serving"}),
    dict(slug="visinata", heading="Vișinată (Romanian Sour Cherry Liqueur)", category="Drinks",
         base=1, yield_word="jars (4 L)", gf=True, status="draft",
         meta="Per 4 L jar batch · 6–8 weeks minimum",
         roles={"Standard framework (per 4 L jar batch)": "ing"},
         notes_override=[
             "Starting proof matters: 76% spirit lands near the traditional 28–32% finished strength; standard 40% vodka gives ~18–22% — softer but good.",
             "Two 750 ml bottles of high-proof spirit ≈ one 4 L batch.",
         ]),
    # gf-reference is built from the "# Ingredient Notes" chapter — handled specially.
    dict(slug="gf-reference", heading="__ingredient_notes__", category="Reference",
         base=1, yield_word="card", noscale=True, gf=False,
         meta="Kitchen & grill reference"),
]

# ---------------------------------------------------------------- amount parsing
# Shared with the app's URL importer — single implementation in the api package.

from app.services.ingredient_parse import (  # noqa: E402
    METRIC_FACTOR,  # noqa: F401  (kept for import compatibility)
    NUM,
    RANGE_SEP,
    UNIT_MAP,  # noqa: F401
    _convert,  # noqa: F401
    _norm_unit,  # noqa: F401
    _num,
    parse_ingredient,
)


# ---------------------------------------------------------------- master parsing

def _blocks(text: str) -> dict[str, list[str]]:
    """Map recipe heading → its lines. Block ends at the next known heading or category header."""
    lines = text.splitlines()
    known = {m["heading"] for m in MANIFEST if not m["heading"].startswith("__")}
    starts: list[tuple[int, str]] = []
    for i, line in enumerate(lines):
        h = re.match(r"^#{2,3}\s+(.*)$", line)
        if h and h.group(1).strip() in known:
            starts.append((i, h.group(1).strip()))
    blocks: dict[str, list[str]] = {}
    for idx, (start, heading) in enumerate(starts):
        end = len(lines)
        for j in range(start + 1, len(lines)):
            if re.match(r"^#\s+", lines[j]):  # next chapter
                end = j
                break
            if idx + 1 < len(starts) and j == starts[idx + 1][0]:
                end = j
                break
        blocks[heading] = lines[start + 1 : end]
    # the Ingredient Notes chapter for gf-reference
    for i, line in enumerate(lines):
        if line.strip() == "# Ingredient Notes":
            blocks["__ingredient_notes__"] = lines[i + 1 :]
            break
    return blocks


def _sections(block: list[str]) -> list[tuple[str, list[str]]]:
    """Split a recipe block into (section-heading, lines) pairs; leading preamble under ''."""
    out: list[tuple[str, list[str]]] = [("", [])]
    for line in block:
        h = re.match(r"^###\s+(.*)$", line)
        if h:
            out.append((h.group(1).strip(), []))
        else:
            out[-1][1].append(line)
    return out


def _parse_ing_lines(lines: list[str]) -> list[dict]:
    rows: list[dict] = []
    section: str | None = None
    for line in lines:
        sub = re.match(r"^####\s+(.*)$", line)
        if sub:
            section = sub.group(1).strip()
            continue
        if line.strip().startswith("- "):
            rows.append(parse_ingredient(line, section))
    return rows


def _parse_steps(lines: list[str]) -> list[dict]:
    steps = []
    for line in lines:
        m = re.match(r"^\s*\d+\.\s+(.*)$", line)
        if m:
            steps.append({"text": m.group(1).strip()})
    return steps


def _parse_notes(lines: list[str]) -> list[str]:
    return [line.strip()[2:].strip() for line in lines if line.strip().startswith("- ")]


def _paragraph(lines: list[str]) -> str:
    return " ".join(x.strip() for x in lines if x.strip())


def _build_gf_reference(block: list[str]) -> tuple[list, list, list]:
    """The Ingredient Notes chapter → reference-card steps."""
    steps: list[dict] = []
    notes: list[str] = []
    current = ""
    for line in block:
        h = re.match(r"^##\s+(.*)$", line)
        if h:
            current = h.group(1).strip()
            continue
        s = line.strip()
        if not s.startswith("- "):
            continue
        item = s[2:].strip()
        if current.startswith("Hidden Gluten"):
            steps.append({"text": item})
        # the Wasabi Oil checklist bullets are single words — covered by the synthesized step below
    steps.append({"text": "**Wasabi oil:** check for wheat, barley, malt, regular soy sauce, or a 'may contain wheat' line; use GF tamari wherever soy sauce appears."})
    steps.append({"text": "**Goulash checkpoints:** paprika (wheat anti-caking in cheap blends), beef broth/bouillon, tomato paste."})
    notes.append("Lea & Perrins Canada Worcestershire is GF; the US version is not always.")
    return [], steps, notes


def parse_master(text: str) -> list[dict]:
    """Pure parse → list of recipe dicts ready for DB insert (tested without a DB)."""
    blocks = _blocks(text)
    recipes: list[dict] = []
    for spec in MANIFEST:
        block = blocks.get(spec["heading"])
        if block is None:
            print(f"  !! heading not found in master: {spec['heading']}", file=sys.stderr)
            continue
        roles = {**DEFAULT_ROLES, **spec.get("roles", {})}
        ingredients: list[dict] = []
        steps: list[dict] = []
        notes: list[str] = []

        if spec["slug"] == "gf-reference":
            ingredients, steps, notes = _build_gf_reference(block)
        else:
            for heading, lines in _sections(block):
                role = roles.get(heading)
                if role == "ing":
                    ingredients.extend(_parse_ing_lines(lines))
                elif role == "steps":
                    steps.extend(_parse_steps(lines))
                elif role == "notes":
                    notes.extend(_parse_notes(lines))
                elif role == "step_para":
                    steps.append({"text": f"**{heading}:** {_paragraph(lines)}"})
                elif role and role.startswith("note_join:"):
                    label = role.split(":", 1)[1]
                    items = _parse_notes(lines) or [_paragraph(lines)]
                    notes.append(f"{label}: " + "; ".join(i.rstrip(".") for i in items if i) + ".")

        if "notes_override" in spec:
            notes = list(spec["notes_override"])

        recipes.append(
            dict(
                slug=spec["slug"],
                title=spec["heading"] if spec["slug"] != "gf-reference" else "Hidden Gluten — Celiac Watch-Outs",
                category=spec["category"],
                meta=spec.get("meta"),
                base_yield=spec["base"],
                yield_word=spec["yield_word"],
                gf=spec.get("gf", False),
                noscale=spec.get("noscale", False),
                source=spec.get("source"),
                status=spec.get("status", "active"),
                label=spec.get("label"),
                ingredients=ingredients,
                steps=steps,
                notes=notes,
            )
        )
    return recipes


# ---------------------------------------------------------------- DB load

async def load(recipes: list[dict], force: bool) -> None:
    from sqlalchemy import select

    from app.db import SessionLocal
    from app.models import Recipe, RecipeVersion

    async with SessionLocal() as session:
        for r in recipes:
            existing = (
                await session.execute(select(Recipe).where(Recipe.slug == r["slug"]))
            ).scalar_one_or_none()
            if existing is not None:
                if not force:
                    print(f"  skip {r['slug']} (exists)")
                    continue
                await session.delete(existing)
                await session.flush()
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
            print(f"  + {r['slug']} ({len(r['ingredients'])} ing, {len(r['steps'])} steps, status={r['status']})")
        await session.commit()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("master", nargs="?", default=str(DEFAULT_MASTER))
    ap.add_argument("--force", action="store_true", help="replace recipes that already exist")
    ap.add_argument("--dry-run", action="store_true", help="parse and print, no DB writes")
    args = ap.parse_args()

    text = Path(args.master).read_text(encoding="utf-8")
    recipes = parse_master(text)
    print(f"Parsed {len(recipes)} recipes from {args.master}")
    if args.dry_run:
        for r in recipes:
            print(f"  {r['slug']}: {len(r['ingredients'])} ing / {len(r['steps'])} steps / {len(r['notes'])} notes")
        return
    asyncio.run(load(recipes, args.force))


if __name__ == "__main__":
    main()
