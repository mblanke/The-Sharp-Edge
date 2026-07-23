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
