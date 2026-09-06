"""Kitchen-sane quantity scaling — CLAUDE.md §8. Server is canonical; web/src/lib/scaling.ts mirrors this.

Rules:
- factor = target_yield / base_yield; scaled = amount × factor
- g/ml → integer; values ≥ 200 round to nearest 5
- all other units and counts → nearest kitchen fraction {⅛ ¼ ⅓ ⅜ ½ ⅝ ⅔ ¾ ⅞} as unicode glyphs, never raw decimals
- amount 0 → em dash, unscaled
"""

import math

EM_DASH = "—"

# (value, glyph) — 0 and 1 anchor the snap; 1 rolls into the whole part
_FRACTIONS: list[tuple[float, str]] = [
    (0.0, ""),
    (0.125, "⅛"),  # ⅛
    (0.25, "¼"),   # ¼
    (1 / 3, "⅓"),  # ⅓
    (0.375, "⅜"),  # ⅜
    (0.5, "½"),    # ½
    (0.625, "⅝"),  # ⅝
    (2 / 3, "⅔"),  # ⅔
    (0.75, "¾"),   # ¾
    (0.875, "⅞"),  # ⅞
    (1.0, ""),
]

METRIC_UNITS = {"g", "ml"}


def format_amount(value: float, unit: str) -> str:
    """Render a scaled amount the way a cook would write it."""
    if value == 0:
        return EM_DASH
    if unit in METRIC_UNITS:
        # half-up rounding, explicitly — Python's round() is banker's and would
        # diverge from the JS mirror on exact halves (562.5 → 560 vs 565)
        if value >= 200:
            rounded = math.floor(value / 5 + 0.5) * 5
        else:
            rounded = math.floor(value + 0.5)
        return f"{rounded} {unit}"

    whole = math.floor(value)
    frac = value - whole
    best_value, best_glyph = 0.0, ""
    best_err = 9.0
    for fval, glyph in _FRACTIONS:
        err = abs(frac - fval)
        if err < best_err:
            best_err = err
            best_value, best_glyph = fval, glyph
    if best_value == 1.0:
        whole += 1
        best_glyph = ""

    if whole > 0 and best_glyph:
        amount_str = f"{whole} {best_glyph}"
    elif whole > 0:
        amount_str = str(whole)
    elif best_glyph:
        amount_str = best_glyph
    else:
        return "pinch" if frac > 0 else "0"

    return f"{amount_str} {unit}" if unit else amount_str


def scale_ingredients(ingredients: list[dict], base_yield: int, target_yield: int) -> list[dict]:
    """Scale a version's ingredient list. amount 0 rows pass through unscaled."""
    factor = target_yield / base_yield
    out: list[dict] = []
    for ing in ingredients:
        amount = ing.get("amount", 0) or 0
        unit = ing.get("unit", "") or ""
        scaled = amount * factor
        out.append(
            {
                **ing,
                "scaled_amount": scaled if amount else 0,
                "display": format_amount(scaled if amount else 0, unit),
            }
        )
    return out


# --- unit systems -------------------------------------------------------------
# A recipe keeps the units it was written in; the toggle is a reading lens over the
# scaled amount. Household conversions, not laboratory ones: a cook measuring 240 ml
# for a cup is right, and 236.588 ml is a number nobody has ever measured.

UNIT_SYSTEMS = ("recipe", "metric", "imperial")
_TO_ML = {"cup": 240.0, "tbsp": 15.0, "tsp": 5.0}
_TO_G = {"lb": 450.0, "oz": 28.0}


def convert_amount(amount: float, unit: str, system: str) -> tuple[float, str]:
    """Express an amount in `system` ("recipe" | "metric" | "imperial").

    Countable units (""), to-taste rows (amount 0) and units already in the target
    system pass through unchanged. Imperial picks the unit a cook would reach for:
    ml → tsp under 15, tbsp under 60 (¼ cup), cups from there; g → oz under 450, lb above.
    """
    if system not in UNIT_SYSTEMS:
        raise ValueError(f"unknown unit system {system!r}")
    if amount == 0 or system == "recipe":
        return amount, unit
    if system == "metric":
        if unit in _TO_ML:
            return amount * _TO_ML[unit], "ml"
        if unit in _TO_G:
            return amount * _TO_G[unit], "g"
        return amount, unit
    # imperial
    if unit == "ml":
        if amount >= 60:
            return amount / 240.0, "cup"
        if amount >= 15:
            return amount / 15.0, "tbsp"
        return amount / 5.0, "tsp"
    if unit == "g":
        if amount >= 450:
            return amount / 450.0, "lb"
        return amount / 28.0, "oz"
    return amount, unit


def convert_display(amount: float, unit: str, system: str) -> str:
    """`convert_amount` rendered through `format_amount` — what the screen shows."""
    value, out_unit = convert_amount(amount, unit, system)
    return format_amount(value, out_unit)
