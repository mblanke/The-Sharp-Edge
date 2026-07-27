#!/usr/bin/env python3
"""Generate the cross-language parity fixtures in shared/fixtures/.

The Sharp Edge runs the same kitchen arithmetic in three languages: Python on the
server, Swift on the iPad, TypeScript on the web. Until now the rule was a comment
("the server is canonical", CLAUDE.md §8) and it did not hold — the iOS gluten-watch
list drifted to 14 terms against the server's 23, and AISLE_ORDER exists in four
hand-copied places.

Local notebook mode makes that dangerous rather than untidy: with no server in the
loop, the Swift copy *is* the answer a cook acts on, and GF is load-bearing (§1).

So: **inputs are hand-curated here, expectations are generated from the live Python.**
That asymmetry is the point. Hand-typed expectations only pin what someone remembered
to type; generated ones mean changing shopping.py and regenerating turns the Swift
suite red on the exact case that changed.

    python api/scripts/dump_fixtures.py           # rewrite shared/fixtures/
    python api/scripts/dump_fixtures.py --check   # fail if stale (used by CI)
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.services.aisles import aisle_rank, classify_aisle  # noqa: E402
from app.services.scaling import format_amount  # noqa: E402
from app.services.shopping import ShoppingLine, as_text, merge_lines, normalise_name  # noqa: E402

FIXTURES = Path(__file__).resolve().parents[2] / "shared" / "fixtures"


# --------------------------------------------------------------- curated inputs

# Every boundary in CLAUDE.md §8: the metric integer rule, the ≥200 round-to-5 rule,
# the nine kitchen fractions, and the em dash for "to taste".
FORMAT_AMOUNT_INPUTS = [
    ("zero-is-an-em-dash", 0, ""),
    ("zero-with-a-unit-is-still-an-em-dash", 0, "g"),
    ("grams-are-integers", 12.4, "g"),
    ("grams-round-half-up", 12.5, "g"),
    ("ml-are-integers", 7.6, "ml"),
    ("metric-just-below-the-rounding-boundary", 199, "g"),
    ("metric-at-the-rounding-boundary", 200, "g"),
    ("metric-above-the-boundary-rounds-to-5", 203, "g"),
    ("metric-above-the-boundary-rounds-down", 202, "g"),
    ("metric-large", 953.592, "g"),
    ("ml-above-the-boundary", 237, "ml"),
    ("eighth", 0.125, "cup"),
    ("quarter", 0.25, "cup"),
    ("third", 1 / 3, "cup"),
    ("three-eighths", 0.375, "cup"),
    ("half", 0.5, "tbsp"),
    ("five-eighths", 0.625, "cup"),
    ("two-thirds", 2 / 3, "cup"),
    ("three-quarters", 0.75, "cup"),
    ("seven-eighths", 0.875, "cup"),
    ("whole-number-keeps-no-fraction", 2, "cup"),
    ("mixed-number", 1.125, "cup"),
    ("mixed-number-two-and-a-half", 2.5, "tsp"),
    ("countable-has-no-unit", 3, ""),
    ("countable-fraction", 1.5, ""),
    ("nearest-fraction-rounds", 0.24, "cup"),
    ("nearest-fraction-rounds-up", 0.76, "cup"),
    ("tiny-amount-does-not-vanish", 0.05, "tsp"),
    ("lb-uses-fractions-not-decimals", 2.25, "lb"),
    ("oz-uses-fractions", 1.75, "oz"),
]

# The merge key. "You buy beef chuck; how it gets cut is not a separate item."
NORMALISE_NAME_INPUTS = [
    ("preparation-after-a-comma-is-dropped", "beef chuck, cut into 1-inch cubes"),
    ("case-is-folded", "Sweet Hungarian Paprika"),
    ("parentheticals-are-dropped", "sweet Hungarian paprika (certified GF)"),
    ("accents-are-folded", "jalapeño"),
    ("accents-in-french", "crème fraîche"),
    ("plural-is-stripped", "yellow onions"),
    ("singular-is-left-alone", "yellow onion"),
    ("asparagus-is-not-a-plural", "asparagus"),
    ("molasses-is-not-a-plural", "molasses"),
    ("swiss-chard-is-not-a-plural", "Swiss chard"),
    ("couscous-is-not-a-plural", "couscous"),
    ("hummus-is-not-a-plural", "hummus"),
    ("capers-stay-capers", "capers"),
    ("oats-stay-oats", "oats"),
    ("short-words-keep-their-s", "figs"),
    ("double-s-is-kept", "watercress"),
    ("is-ending-is-kept", "orzo is"),
    ("punctuation-is-stripped", "all-purpose flour"),
    ("digits-survive", "00 flour"),
    ("whitespace-is-collapsed", "  olive    oil  "),
    ("empty-string", ""),
    ("comma-first", ", diced"),
    ("romanian-diacritics", "vișinată"),
    ("german-sharp-s", "Weißwein"),
]

CHECK_GLUTEN_INPUTS = [
    ("paprika-hides-gluten", "sweet Hungarian paprika (certified GF)"),
    ("broth-hides-gluten", "beef broth"),
    ("stock-hides-gluten", "chicken stock"),
    ("bouillon-hides-gluten", "chicken bouillon"),
    ("tomato-paste-hides-gluten", "tomato paste"),
    ("soy-sauce-hides-gluten", "soy sauce"),
    ("tamari-hides-gluten", "GF tamari"),
    ("worcestershire-hides-gluten", "Worcestershire sauce"),
    ("hoisin-hides-gluten", "hoisin sauce"),
    ("oyster-sauce-hides-gluten", "oyster sauce"),
    ("miso-hides-gluten", "white miso"),
    ("malt-hides-gluten", "malt vinegar"),
    ("vinegar-hides-gluten", "red wine vinegar"),
    ("mustard-hides-gluten", "Dijon mustard"),
    ("curry-powder-hides-gluten", "curry powder"),
    ("spice-blend-hides-gluten", "cajun spice blend"),
    ("seasoning-hides-gluten", "italian seasoning"),
    ("gravy-hides-gluten", "gravy granules"),
    ("sausage-hides-gluten", "italian sausage"),
    ("bacon-hides-gluten", "smoked bacon"),
    ("imitation-crab-hides-gluten", "imitation crab"),
    ("surimi-hides-gluten", "surimi sticks"),
    ("oats-hide-gluten", "rolled oats"),
    ("onions-are-safe", "yellow onions"),
    ("carrots-are-safe", "carrots"),
    ("heavy-cream-is-safe", "heavy cream"),
    ("butter-is-safe", "unsalted butter"),
    ("garlic-is-safe", "garlic cloves"),
]

CLASSIFY_AISLE_INPUTS = [
    ("beef-chuck", "beef chuck, cut into 1-inch cubes"),
    ("ground-pork", "ground pork"),
    ("salmon-fillets", "salmon fillets, 170–200 g each"),
    ("yellow-onions", "yellow onions, diced"),
    ("garlic-cloves-are-produce-not-the-spice", "garlic cloves, minced"),
    ("garlic-powder-is-a-spice", "garlic powder"),
    ("ground-cloves-are-a-spice", "ground cloves"),
    ("nutmeg-is-not-a-nut", "freshly grated nutmeg"),
    ("coconut-milk-is-not-a-nut", "coconut milk"),
    ("butternut-is-not-a-nut", "butternut squash"),
    ("walnuts-are-pantry", "chopped walnuts"),
    ("fresh-ginger-is-produce", "fresh ginger, grated"),
    ("ground-ginger-is-a-spice", "ground ginger"),
    ("green-onions-are-produce", "green onions, sliced"),
    ("jalapeno-minced-is-not-mince", "jalapeño, seeded and minced"),
    ("potatoes", "Yukon Gold potatoes, cubed"),
    ("bell-peppers", "red bell peppers, diced"),
    ("cucumber", "English cucumber, grated and squeezed dry"),
    ("limes", "limes, juiced"),
    ("lime-zested", "lime, zested"),
    ("heavy-cream", "heavy cream"),
    ("feta", "block feta in brine, cubed or crumbled"),
    ("egg", "1 large egg"),
    ("whole-milk-is-dairy", "whole milk"),
    ("baguette", "baguette, sliced"),
    ("croutons", "brioche croutons"),
    ("paprika", "sweet Hungarian paprika (certified GF)"),
    ("caraway", "caraway seeds, crushed"),
    ("bay-leaves", "bay leaves"),
    ("salt-and-pepper", "flaky salt and black pepper"),
    ("beef-broth", "beef broth (certified GF)"),
    ("tomato-paste", "tomato paste"),
    ("canned-tomatoes-are-pantry", "canned diced tomatoes"),
    ("fresh-tomatoes-are-produce", "tomatoes, diced"),
    ("tamari", "GF tamari"),
    ("vinegar", "red wine vinegar"),
    ("flour", "all-purpose flour"),
    ("brown-sugar", "brown sugar, packed"),
    ("frozen-peas", "frozen peas"),
    ("accents-do-not-matter", "Crème fraîche"),
    ("shouting-does-not-matter", "CREME FRAICHE"),
    ("gruyere", "Gruyère cheese"),
    ("unknown-is-not-guessed-at", "Pre-Hy"),
    ("another-unknown", "Ultra-Tex"),
    ("empty-is-other", ""),
    ("head-says-nothing-falls-back", "tin of San Marzano tomatoes, drained"),
]

# (id, [(name, amount, unit, recipe)]) — the whole point of the list is that a second
# recipe ADDS to a line rather than replacing it.
MERGE_INPUTS: list[tuple[str, list[tuple[str, float, str, str]]]] = [
    ("same-ingredient-and-unit-adds", [
        ("sweet Hungarian paprika", 3, "tbsp", "goulash"),
        ("sweet Hungarian paprika", 2, "tbsp", "rub"),
    ]),
    ("preparation-is-ignored-when-matching", [
        ("beef chuck, cut into 1-inch cubes", 2, "lb", "goulash"),
        ("beef chuck, trimmed", 1, "lb", "stew"),
    ]),
    ("singular-and-plural-merge", [
        ("yellow onions, diced", 3, "", "goulash"),
        ("yellow onion", 2, "", "soup"),
    ]),
    ("volume-units-convert-and-add", [
        ("olive oil", 1, "cup", "a"), ("olive oil", 2, "tbsp", "b"),
    ]),
    ("smaller-unit-wins-when-it-is-the-larger-amount", [
        ("olive oil", 3, "tbsp", "a"), ("olive oil", 1, "tsp", "b"),
    ]),
    ("weight-units-convert-and-add", [
        ("butter", 500, "g", "a"), ("butter", 1, "lb", "b"),
    ]),
    ("same-unit-addition-is-exact", [
        ("beef chuck", 2, "lb", "a"), ("beef chuck", 1, "lb", "b"),
    ]),
    ("volume-and-weight-never-combine", [
        ("stock", 2, "cup", "a"), ("stock", 400, "g", "b"),
    ]),
    ("countables-add", [("limes", 2, "", "a"), ("limes", 3, "", "b")]),
    ("to-taste-items-do-not-gain-a-quantity", [
        ("salt", 0, "", "a"), ("salt", 0, "", "b"),
    ]),
    ("a-measured-item-absorbs-a-to-taste-one", [
        ("black pepper", 1, "tsp", "goulash"), ("black pepper", 0, "", "salad"),
    ]),
    ("absorption-works-in-either-order", [
        ("black pepper", 0, "", "salad"), ("black pepper", 1, "tsp", "goulash"),
    ]),
    ("order-of-first-appearance-is-kept", [
        ("onions", 1, "", "a"), ("garlic", 2, "", "b"), ("onions", 1, "", "c"),
    ]),
    ("three-recipes-accumulate", [
        ("olive oil", 2, "tbsp", "a"), ("olive oil", 2, "tbsp", "b"),
        ("olive oil", 2, "tbsp", "c"),
    ]),
    ("a-duplicate-recipe-is-not-listed-twice", [
        ("olive oil", 1, "tbsp", "a"), ("olive oil", 1, "tbsp", "a"),
    ]),
    ("gluten-flag-survives-merging", [
        ("beef broth", 2, "cup", "a"), ("beef broth", 1, "cup", "b"),
    ]),
    ("a-realistic-two-recipe-shop", [
        ("yellow onions, diced", 3, "", "goulash"),
        ("garlic cloves, minced", 4, "", "goulash"),
        ("beef chuck, cut into 1-inch cubes", 2, "lb", "goulash"),
        ("sweet Hungarian paprika", 3, "tbsp", "goulash"),
        ("beef broth", 3, "cup", "goulash"),
        ("salt", 0, "", "goulash"),
        ("red onion, finely diced", 0.25, "", "salsa"),
        ("jalapeño, seeded and minced", 1, "", "salsa"),
        ("limes", 2, "", "salsa"),
        ("salt", 0, "", "salsa"),
    ]),
]


# ---------------------------------------------------------------- generation

def _lines(spec):
    return [ShoppingLine(name=n, amount=a, unit=u, to_taste=a == 0, recipes=[r])
            for n, a, u, r in spec]


def _line_out(ln: ShoppingLine) -> dict:
    return {
        "name": ln.name, "amount": ln.amount, "unit": ln.unit,
        "display": ln.display, "to_taste": ln.to_taste,
        "recipes": ln.recipes, "check_gluten": ln.check_gluten,
        "aisle": classify_aisle(ln.name),
    }


def build() -> dict[str, dict]:
    out: dict[str, dict] = {}

    out["scaling.format_amount"] = {
        "version": 1, "function": "format_amount",
        "note": "CLAUDE.md §8. Kitchen fractions as unicode glyphs; 0.75 is a bug, ¾ is correct.",
        "cases": [
            {"id": i, "args": {"value": v, "unit": u}, "expect": format_amount(v, u)}
            for i, v, u in FORMAT_AMOUNT_INPUTS
        ],
    }

    out["shopping.normalise_name"] = {
        "version": 1, "function": "normalise_name",
        "note": "The merge key: everything before the first comma, folded and de-pluralised.",
        "cases": [
            {"id": i, "args": {"name": n}, "expect": normalise_name(n)}
            for i, n in NORMALISE_NAME_INPUTS
        ],
    }

    out["shopping.check_gluten"] = {
        "version": 1, "function": "check_gluten",
        "note": "GF is load-bearing (CLAUDE.md §1). A missing term here is a bad week.",
        "cases": [
            {"id": i, "args": {"name": n},
             "expect": ShoppingLine(name=n, amount=1, unit="tbsp").check_gluten}
            for i, n in CHECK_GLUTEN_INPUTS
        ],
    }

    out["aisles.classify_aisle"] = {
        "version": 1, "function": "classify_aisle",
        "note": "Wrong aisle is worse than no aisle, so anything unknown must stay 'Other'.",
        "cases": [
            {"id": i, "args": {"name": n}, "expect": classify_aisle(n)}
            for i, n in CLASSIFY_AISLE_INPUTS
        ],
    }

    out["aisles.aisle_rank"] = {
        "version": 1, "function": "aisle_rank",
        "note": "Walking order: fresh edges first, frozen last, unknown after everything.",
        "cases": [
            {"id": a.lower().replace(" ", "-").replace("&", "and"),
             "args": {"aisle": a}, "expect": aisle_rank(a)}
            for a in ["Produce", "Meat & fish", "Dairy & eggs", "Bakery", "Pantry",
                      "Herbs & spices", "Frozen", "Other", "nonsense"]
        ],
    }

    out["shopping.merge_lines"] = {
        "version": 1, "function": "merge_lines",
        "note": "Adding a second recipe must ADD to a line, never replace it.",
        "tolerance": 0.001,
        "cases": [
            {"id": i,
             "args": {"lines": [{"name": n, "amount": a, "unit": u, "recipe": r}
                                for n, a, u, r in spec]},
             "expect": [_line_out(ln) for ln in merge_lines(_lines(spec))]}
            for i, spec in MERGE_INPUTS
        ],
    }

    text_cases = []
    for ident, spec in MERGE_INPUTS[-2:]:
        merged = merge_lines(_lines(spec))
        text_cases.append({
            "id": f"{ident}-plain",
            "args": {"lines": [{"name": n, "amount": a, "unit": u, "recipe": r}
                               for n, a, u, r in spec], "group_by_aisle": False},
            "expect": as_text(merged),
        })
        grouped = sorted(merged, key=lambda ln: aisle_rank(classify_aisle(ln.name)))
        text_cases.append({
            "id": f"{ident}-by-aisle",
            "args": {"lines": [{"name": n, "amount": a, "unit": u, "recipe": r}
                               for n, a, u, r in spec], "group_by_aisle": True},
            "expect": as_text(grouped, group_by=lambda ln: classify_aisle(ln.name)),
        })
    out["shopping.as_text"] = {
        "version": 1, "function": "as_text",
        "note": "List apps split pasted text on newlines, so one item per line is the contract.",
        "cases": text_cases,
    }

    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="exit non-zero if the committed fixtures are stale")
    args = ap.parse_args()

    FIXTURES.mkdir(parents=True, exist_ok=True)
    stale = []
    for name, payload in build().items():
        path = FIXTURES / f"{name}.json"
        text = json.dumps(payload, indent=2, ensure_ascii=False) + "\n"
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                stale.append(path.name)
        else:
            path.write_text(text, encoding="utf-8")

    if args.check:
        if stale:
            print("Stale fixtures — run python api/scripts/dump_fixtures.py:", file=sys.stderr)
            for name in stale:
                print(f"  {name}", file=sys.stderr)
            return 1
        print("fixtures up to date")
        return 0

    total = sum(len(p["cases"]) for p in build().values())
    print(f"wrote {len(build())} fixture files, {total} cases → {FIXTURES}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
