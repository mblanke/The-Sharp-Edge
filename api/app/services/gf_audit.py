"""Hidden-gluten audit (F3): scan every recipe's current ingredients against
the celiac watch-out list. GF status is load-bearing — this catches a soy-sauce
slip before it reaches a plate.

Rules live here (curated from the gf-reference card) rather than being parsed
out of its prose — prose parsing would silently weaken when the card is
reworded. Update both together; test_gf_audit.py pins the load-bearing terms.
"""

import re
from dataclasses import dataclass


@dataclass(frozen=True)
class Rule:
    term: str  # regex, case-insensitive
    why: str


# An ingredient matching a rule is risky unless it also matches CLEARED.
RULES: list[Rule] = [
    Rule(r"soy sauce", "usually wheat-brewed — use GF tamari"),
    Rule(r"\bshoyu\b", "wheat-brewed soy sauce"),
    Rule(r"worcestershire", "often contains malt vinegar (US); Lea & Perrins Canada is GF"),
    Rule(r"\bmalt(ed)?\b|malt vinegar|malt extract", "malt is barley"),
    Rule(r"\bbarley\b", "gluten grain"),
    Rule(r"\brye\b", "gluten grain"),
    Rule(r"\bwheat\b", "gluten grain"),
    Rule(r"\bflour\b", "wheat unless explicitly GF"),
    Rule(r"\bpanko\b|breadcrumbs?|bread crumbs?", "wheat bread"),
    Rule(r"\bcouscous\b|\bsemolina\b|\bfarro\b|\bspelt\b|\borzo\b", "wheat product"),
    Rule(r"hoisin", "commonly thickened with wheat"),
    Rule(r"oyster sauce", "often contains wheat"),
    Rule(r"\bmiso\b", "some miso is barley-based"),
    Rule(r"\bbeer\b|\blager\b|\bstout\b|\bale\b", "barley malt"),
    Rule(r"\bseitan\b", "is wheat gluten"),
    Rule(r"bouillon|broth base|stock cube", "cheap bases can hide wheat"),
    Rule(r"\bpaprika blend\b|spice mix|seasoning mix", "anti-caking agents can be wheat"),
    Rule(r"wasabi (oil|paste|powder)", "often contains wheat — check the label"),
]

CLEARED = re.compile(
    r"gluten[- ]free|\bgf\b|certified gf|tamari|rice flour|almond flour|corn flour|"
    r"chickpea flour|buckwheat|potato flour|oat flour",
    re.I,
)


def scan_ingredients(ingredients: list[dict]) -> list[dict]:
    """Risky rows: [{ingredient, term, why}] — cleared phrasings pass."""
    risks: list[dict] = []
    for ing in ingredients:
        name = str(ing.get("name", ""))
        note = str(ing.get("note") or "")
        text = f"{name} {note}"
        if CLEARED.search(text):
            continue
        for rule in RULES:
            if re.search(rule.term, text, re.I):
                risks.append({"ingredient": name, "term": rule.term, "why": rule.why})
                break
    return risks


def audit(recipes) -> list[dict]:
    """One row per recipe: verdict 'warning' (gf=true but risky), 'candidate'
    (not flagged gf and nothing risky), or 'ok'."""
    out: list[dict] = []
    for recipe in recipes:
        current = next((v for v in recipe.versions if v.is_current), None)
        if current is None or recipe.noscale:
            continue
        risks = scan_ingredients(current.ingredients)
        if recipe.gf and risks:
            verdict = "warning"
        elif not recipe.gf and not risks:
            verdict = "candidate"
        else:
            verdict = "ok"
        out.append(
            {
                "slug": recipe.slug,
                "title": recipe.title,
                "gf": recipe.gf,
                "risks": risks,
                "verdict": verdict,
            }
        )
    return out
