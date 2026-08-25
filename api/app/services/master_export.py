"""Regenerate recipes-master.md from the DB (CLAUDE.md §6, Phase 2).

The output mirrors the seed master-file structure (category chapters, ###
sections, ingredient bullets) so content re-parses identically through
seed/import_master.py's parsers. Metadata lines are prose the parser ignores.
Timers are app-only and not exported. Current versions only — history lives
in the app; paper is the permanent record.
"""

from fractions import Fraction

# Glue-in / card order — CLAUDE.md §10 (mirrors CATEGORY_ORDER in web/src/lib/types.ts)
CATEGORY_ORDER = [
    "Sauces & Salsas",
    "Marinades",
    "Salads",
    "Soups & Stews",
    "Sandwiches",
    "Pasta",
    "Entrées",
    "Sides",
    "Breakfast",
    "Baking & Desserts",
    "Drinks",
    "Appetizers & Preserves",
    "Reference",
]


def category_rank(category: str) -> int:
    try:
        return CATEGORY_ORDER.index(category)
    except ValueError:
        return len(CATEGORY_ORDER)


def format_master_amount(amount: float) -> str:
    """Inverse of the importer's _num: whole numbers plain, kitchen fractions as
    a/b or 'n a/b', anything else as a decimal (all three re-parse exactly)."""
    if amount == int(amount):
        return str(int(amount))
    frac = Fraction(amount).limit_denominator(16)
    if float(frac) == amount:
        whole, rem = divmod(frac.numerator, frac.denominator)
        if whole:
            return f"{whole} {rem}/{frac.denominator}"
        return f"{frac.numerator}/{frac.denominator}"
    return f"{amount:g}"


def _ingredient_line(ing: dict) -> str:
    amount = ing.get("amount", 0) or 0
    unit = ing.get("unit", "") or ""
    name = ing.get("name", "")
    if not amount:
        return f"- {name}"
    if unit:
        return f"- {format_master_amount(amount)} {unit} {name}"
    return f"- {format_master_amount(amount)} {name}"


def _recipe_block(recipe, version) -> list[str]:
    lines: list[str] = [f"## {recipe.title}", ""]

    meta_bits = [f"Base: {recipe.base_yield} {recipe.yield_word}"]
    if recipe.gf:
        meta_bits.append("GF")
    if recipe.status != "active":
        meta_bits.append(recipe.status)
    if version.label:
        meta_bits.append(f"version: {version.label}")
    if recipe.meta:
        lines.append(f"_{recipe.meta}_")
    lines.append("_" + " · ".join(meta_bits) + "_")
    if recipe.source:
        lines.append(f"_Source: {recipe.source}_")
    lines.append("")

    if version.ingredients:
        lines.append("### Ingredients")
        lines.append("")
        section = None
        for ing in version.ingredients:
            ing_section = ing.get("section")
            if ing_section and ing_section != section:
                lines.append(f"#### {ing_section}")
            section = ing_section
            lines.append(_ingredient_line(ing))
        lines.append("")

    if version.steps:
        lines.append("### Instructions")
        lines.append("")
        for i, step in enumerate(version.steps, 1):
            lines.append(f"{i}. {step['text']}")
        lines.append("")

    if version.notes:
        lines.append("### Notes")
        lines.append("")
        for note in version.notes:
            lines.append(f"- {note}")
        lines.append("")

    return lines


def render_master(recipes) -> str:
    """recipes: iterable of Recipe ORM objects with versions loaded."""
    ordered = sorted(recipes, key=lambda r: (category_rank(r.category), r.title.lower()))
    lines: list[str] = [
        "# The Sharp Edge — Master Recipe File",
        "",
        "_Regenerated from the app database. Paper is the permanent record;_",
        "_this file is the current state of every recipe card._",
        "",
    ]
    category = None
    for recipe in ordered:
        current = next((v for v in recipe.versions if v.is_current), None)
        if current is None:
            continue
        if recipe.category != category:
            category = recipe.category
            lines.append(f"# {category}")
            lines.append("")
        lines.extend(_recipe_block(recipe, current))
    return "\n".join(lines).rstrip() + "\n"
