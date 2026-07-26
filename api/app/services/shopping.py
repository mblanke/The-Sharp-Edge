"""Merging scaled ingredients into one shopping list.

The rule that matters: adding a second recipe must **add** to a line, never replace
it. Three tbsp of paprika from the goulash plus two from a rub is five tbsp on the
list — not two, and not two separate lines.

That needs three things, in order:

1. **Name normalisation.** Recipe names carry preparation after a comma —
   "beef chuck, cut into 1-inch cubes". You buy beef chuck. Everything before the
   first comma, lowercased and de-accented, is the merge key.
2. **Unit families.** tsp/tbsp/cup/ml are all volume; g/oz/lb are all weight; ""
   is a count. Amounts convert within a family and never across one — you cannot
   add 2 cups of stock to 400 g of beef.
3. **A display unit.** The unit of the *largest single contribution* wins, so the
   list keeps your own idiom: 1 cup + 2 tbsp reads in cups, 3 tbsp + 1 tsp in tbsp.

Amount 0 means "to taste" (CLAUDE.md §5) — those never carry a quantity and are
kept apart, because you do not buy "salt, to taste".
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field

from app.services.scaling import format_amount

__all__ = ["ShoppingLine", "merge_lines", "normalise_name", "GLUTEN_WATCH"]

# Everything in a family converts to the family's base unit.
_VOLUME = {"ml": 1.0, "tsp": 4.92892, "tbsp": 14.7868, "cup": 236.588}
_WEIGHT = {"g": 1.0, "oz": 28.3495, "lb": 453.592}
_FAMILIES = {"volume": _VOLUME, "weight": _WEIGHT}

# Ingredients that routinely hide gluten. A shopping list that says "check this one"
# is the difference between a safe shop and a bad week — CLAUDE.md §1 makes GF
# load-bearing, and these are the traps the notebook's reference card already names.
GLUTEN_WATCH = (
    "paprika", "broth", "stock", "bouillon", "tomato paste", "soy sauce", "tamari",
    "worcestershire", "hoisin", "oyster sauce", "miso", "malt", "vinegar", "mustard",
    "curry powder", "spice blend", "seasoning", "gravy", "sausage", "bacon",
    "imitation crab", "surimi", "oats",
)


def _family_of(unit: str) -> str | None:
    for name, table in _FAMILIES.items():
        if unit in table:
            return name
    return None


# Food words that end in 's' but are already singular. A suffix rule cannot tell
# "molasses" from "limes", so the exceptions are listed rather than guessed at.
_NOT_PLURAL = {
    "asparagus", "molasses", "couscous", "hummus", "watercress", "cress", "bass",
    "chard", "swiss chard", "brussels", "greens", "grits", "oats", "capers",
}


def normalise_name(name: str) -> str:
    """'Beef chuck, cut into 1-inch cubes' → 'beef chuck'. The merge key."""
    head = name.split(",")[0]
    head = "".join(
        c for c in unicodedata.normalize("NFKD", head) if not unicodedata.combining(c)
    )
    head = re.sub(r"\([^)]*\)", " ", head)          # drop parentheticals
    head = re.sub(r"[^a-zA-Z0-9 ]+", " ", head)
    head = re.sub(r"\s+", " ", head).strip().lower()
    # "onions" and "onion" belong on one line. Never turn "asparagus" into "asparagu".
    if (
        len(head) > 3
        and head.endswith("s")
        and head not in _NOT_PLURAL
        and not head.endswith(("ss", "us", "is"))
    ):
        head = head[:-1]
    return head


@dataclass
class ShoppingLine:
    """One line of the list. `amount` is 0 for to-taste items, which never merge."""

    name: str
    amount: float = 0.0
    unit: str = ""
    to_taste: bool = False
    recipes: list[str] = field(default_factory=list)
    checked: bool = False

    @property
    def key(self) -> str:
        family = _family_of(self.unit) or ("count" if not self.unit else self.unit)
        return f"{normalise_name(self.name)}|{'taste' if self.to_taste else family}"

    @property
    def ingredient(self) -> str:
        return normalise_name(self.name)

    @property
    def display(self) -> str:
        if self.to_taste or self.amount == 0:
            return "to taste"
        return format_amount(self.amount, self.unit)

    @property
    def check_gluten(self) -> bool:
        probe = self.name.lower()
        return any(term in probe for term in GLUTEN_WATCH)


def _merge_pair(base: ShoppingLine, extra: ShoppingLine) -> ShoppingLine:
    """Add `extra` into `base`, converting within the unit family."""
    for recipe in extra.recipes:
        if recipe not in base.recipes:
            base.recipes.append(recipe)

    if base.unit == extra.unit:
        # The common case. Add directly rather than round-tripping through the
        # family base unit, which would turn 2 lb + 1 lb into 2.9999999999999996.
        base.amount += extra.amount
        return base

    family = _family_of(base.unit)
    if family is None or _family_of(extra.unit) != family:
        return base  # countables, or units that genuinely do not combine

    table = _FAMILIES[family]
    total = base.amount * table[base.unit] + extra.amount * table[extra.unit]
    # The larger single contribution decides how the total reads.
    winner = base if base.amount * table[base.unit] >= extra.amount * table[extra.unit] else extra
    base.unit = winner.unit
    base.amount = total / table[winner.unit]
    return base


def merge_lines(lines: list[ShoppingLine]) -> list[ShoppingLine]:
    """Collapse a flat list into one line per ingredient, adding quantities.

    Order is preserved by first appearance, so a list read top to bottom still
    follows the order things were added.
    """
    merged: dict[str, ShoppingLine] = {}
    order: list[str] = []
    for line in lines:
        key = line.key
        if key in merged:
            _merge_pair(merged[key], line)
        else:
            merged[key] = ShoppingLine(
                name=line.name, amount=line.amount, unit=line.unit,
                to_taste=line.to_taste or line.amount == 0,
                recipes=list(line.recipes), checked=line.checked,
            )
            order.append(key)

    # A to-taste line for something already being bought by measure is absorbed:
    # one recipe wanting 1 tsp of pepper and another wanting "pepper to taste" means
    # buy pepper, and the measured amount is the more useful of the two. Never the
    # reverse — a measured line is never flattened back to "to taste".
    measured = {merged[k].ingredient for k in order if not merged[k].to_taste}
    kept = [k for k in order if not (merged[k].to_taste and merged[k].ingredient in measured)]
    for k in kept:
        if merged[k].to_taste:
            continue
        for dropped in order:
            if dropped not in kept and merged[dropped].ingredient == merged[k].ingredient:
                for recipe in merged[dropped].recipes:
                    if recipe not in merged[k].recipes:
                        merged[k].recipes.append(recipe)
    return [merged[k] for k in kept]


def as_text(lines: list[ShoppingLine], title: str = "Shopping list") -> str:
    """Plain text for the share sheet — AnyList, Notes, Reminders and Messages all
    take this. One item per line so list apps split it into separate entries."""
    buy = [ln for ln in lines if not ln.to_taste]
    staples = [ln for ln in lines if ln.to_taste]
    out = [title, ""]
    for ln in buy:
        flag = "  (check GF)" if ln.check_gluten else ""
        out.append(f"{ln.display} {ln.name}{flag}")
    if staples:
        out += ["", "Check you have:"]
        out += [f"{ln.name}" for ln in staples]
    return "\n".join(out)
