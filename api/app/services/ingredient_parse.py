"""Prose → structured ingredient parsing (units per CLAUDE.md §5).

Moved from seed/import_master.py so the URL importer (F4) and the seed
importer share one implementation; the seed importer re-exports these.
"""

import re
from fractions import Fraction

UNIT_MAP = {
    "tablespoon": "tbsp", "tablespoons": "tbsp", "tbsp": "tbsp",
    "teaspoon": "tsp", "teaspoons": "tsp", "tsp": "tsp",
    "cup": "cup", "cups": "cup",
    "pound": "lb", "pounds": "lb", "lb": "lb", "lbs": "lb",
    "ounce": "oz", "ounces": "oz", "oz": "oz",
    "g": "g", "gram": "g", "grams": "g",
    "kg": "kg", "kilogram": "kg", "kilograms": "kg",
    "ml": "ml",
    "l": "l", "liter": "l", "liters": "l", "litre": "l", "litres": "l",
}
# spec units are g/ml — convert metric multiples
METRIC_FACTOR = {"kg": ("g", 1000), "l": ("ml", 1000)}

NUM = r"(?:\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?)"
RANGE_SEP = r"(?:–|—|-|\s+to\s+)"


def _num(token: str) -> float:
    token = token.strip()
    m = re.fullmatch(r"(\d+)\s+(\d+)/(\d+)", token)
    if m:
        return int(m.group(1)) + int(m.group(2)) / int(m.group(3))
    if "/" in token:
        return float(Fraction(token))
    return float(token)


def _norm_unit(word: str) -> str | None:
    return UNIT_MAP.get(word.lower().rstrip("."))


def _convert(amount: float, unit: str | None) -> tuple[float, str]:
    if unit in METRIC_FACTOR:
        base, factor = METRIC_FACTOR[unit]
        return amount * factor, base
    return amount, unit or ""


def parse_ingredient(line: str, section: str | None = None) -> dict:
    """One prose line → {amount, unit, name[, section]}. amount 0 = to taste/unscaled."""
    text = line.strip().lstrip("-").strip()
    row: dict = {"amount": 0, "unit": "", "name": text}

    juice = re.match(rf"(?:Juice|Zest) of (~?{NUM})(?:{RANGE_SEP}(~?{NUM}))?\s+(.+)", text, re.I)
    if juice:
        lo = _num(juice.group(1).lstrip("~"))
        hi = _num(juice.group(2).lstrip("~")) if juice.group(2) else lo
        verb = "juiced" if text.lower().startswith("juice") else "zested"
        row.update(amount=(lo + hi) / 2, unit="", name=f"{juice.group(3).rstrip(',')}, {verb}")
    else:
        m = re.match(
            rf"~?({NUM})\s*([A-Za-zÀ-ÿ]+)?\.?\s*(?:{RANGE_SEP}\s*~?({NUM})\s*([A-Za-zÀ-ÿ]+)?\.?)?\s+(.*)",
            text,
        )
        # ranges like "1.5–2 lb" parse as: 1.5, unit=None, 2, "lb", rest — normalise both sides
        if not m:
            m = re.match(rf"~?({NUM})\s*{RANGE_SEP}\s*~?({NUM})\s*([A-Za-zÀ-ÿ]+)?\.?\s+(.*)", text)
            if m:
                lo, hi = _num(m.group(1)), _num(m.group(2))
                unit = _norm_unit(m.group(3) or "")
                lo, _ = _convert(lo, unit)
                hi, unit_out = _convert(hi, unit)
                name = m.group(4).strip()
                if unit is None and m.group(3):
                    name = f"{m.group(3)} {name}"
                row.update(amount=(lo + hi) / 2, unit=unit_out if unit else "", name=name)
        else:
            lo_raw, u1_raw, hi_raw, u2_raw, rest = m.groups()
            u1 = _norm_unit(u1_raw) if u1_raw else None
            u2 = _norm_unit(u2_raw) if u2_raw else None
            if hi_raw is not None:
                # true range; each side may carry its own unit ("700 g–1 kg")
                lo, _ = _convert(_num(lo_raw), u1 or u2)
                hi, unit_out = _convert(_num(hi_raw), u2 or u1)
                name = rest.strip()
                if u2 is None and u2_raw:
                    name = f"{u2_raw} {name}"
                row.update(amount=(lo + hi) / 2, unit=unit_out if (u1 or u2) else "", name=name)
            else:
                amount, unit_out = _convert(_num(lo_raw), u1)
                name = rest.strip()
                if u1 is None and u1_raw:
                    # not a unit word — it's part of the name ("1 can diced tomatoes")
                    name = f"{u1_raw} {name}"
                row.update(amount=amount, unit=unit_out if u1 else "", name=name)

    if section:
        row["section"] = section
    return row
