"""Exhaustive fraction-table tests for CLAUDE.md §8. Mirrored in web/src/lib/scaling.test.ts."""

import pytest

from app.services.scaling import format_amount, scale_ingredients

# (value, unit, expected)
FRACTION_TABLE = [
    # amount 0 → em dash, always
    (0, "tsp", "—"),
    (0, "", "—"),
    # metric: integer below 200, nearest 5 at/above 200
    (120, "ml", "120 ml"),
    (187.5, "g", "188 g"),
    (199.4, "g", "199 g"),
    (250, "g", "250 g"),
    (252, "g", "250 g"),
    (253, "g", "255 g"),
    (375, "g", "375 g"),
    (562.5, "ml", "565 ml"),  # exact half rounds up (matches the JS mirror)
    (900 * 14 / 6, "g", "2100 g"),
    # kitchen fractions, unicode glyphs, never raw decimals
    (0.125, "tsp", "⅛ tsp"),
    (0.25, "cup", "¼ cup"),
    (1 / 3, "cup", "⅓ cup"),
    (0.375, "tsp", "⅜ tsp"),
    (0.5, "tsp", "½ tsp"),
    (0.625, "cup", "⅝ cup"),
    (2 / 3, "cup", "⅔ cup"),
    (0.75, "cup", "¾ cup"),
    (0.875, "tsp", "⅞ tsp"),
    # whole + fraction
    (1.5, "cup", "1 ½ cup"),
    (2.25, "tbsp", "2 ¼ tbsp"),
    (7.0, "tbsp", "7 tbsp"),
    # snapping: 0.7 → ⅔, 0.8 → ¾ (nearest wins), 0.95 → rolls to next whole
    (0.7, "cup", "⅔ cup"),
    (0.8, "cup", "¾ cup"),
    (2.95, "cup", "3 cup"),
    (1.02, "tsp", "1 tsp"),
    # counts (empty unit)
    (3, "", "3"),
    (1.5, "", "1 ½"),
    (0.5, "", "½"),
    # tiny but nonzero → pinch, not 0
    (0.02, "tsp", "pinch"),
]


@pytest.mark.parametrize("value,unit,expected", FRACTION_TABLE)
def test_format_amount(value, unit, expected):
    assert format_amount(value, unit) == expected


def test_never_raw_decimals():
    for value in [0.75, 1.5, 2.25, 0.333, 4.666]:
        for unit in ["cup", "tbsp", "tsp", "lb", "oz", ""]:
            out = format_amount(value, unit)
            assert "." not in out, f"raw decimal leaked: {value} {unit} -> {out}"


class TestGoulash6To14:
    """Acceptance case: goulash scaled 6 → 14 (factor 2⅓)."""

    FACTOR = 14 / 6

    def test_beef(self):
        # 2 lb chuck → 4.67 lb → 4 ⅔ lb
        assert format_amount(2 * self.FACTOR, "lb") == "4 ⅔ lb"

    def test_paprika(self):
        # 3 tbsp → 7 tbsp
        assert format_amount(3 * self.FACTOR, "tbsp") == "7 tbsp"

    def test_broth(self):
        # 3 cup → 7 cup
        assert format_amount(3 * self.FACTOR, "cup") == "7 cup"

    def test_to_taste_unscaled(self):
        rows = scale_ingredients(
            [{"amount": 0, "unit": "", "name": "salt, to taste"}], 6, 14
        )
        assert rows[0]["display"] == "—"
        assert rows[0]["scaled_amount"] == 0


class TestCeleriacMetric:
    """900 g celeriac, 500 ml milk, 120 ml cream at various factors."""

    def test_double(self):
        assert format_amount(900 * 2, "g") == "1800 g"
        assert format_amount(500 * 2, "ml") == "1000 ml"
        assert format_amount(120 * 2, "ml") == "240 ml"

    def test_x1_5(self):
        assert format_amount(900 * 1.5, "g") == "1350 g"
        assert format_amount(120 * 1.5, "ml") == "180 ml"

    def test_x1_25_rounds_to_5(self):
        # 500 × 1.25 = 625 → already a 5-multiple; 120 × 1.25 = 150 < 200 → integer
        assert format_amount(500 * 1.25, "ml") == "625 ml"
        assert format_amount(120 * 1.25, "ml") == "150 ml"


def test_scale_ingredients_passthrough_fields():
    rows = scale_ingredients(
        [{"amount": 1.5, "unit": "cup", "name": "flour", "section": "Dry"}], 4, 8
    )
    assert rows[0]["name"] == "flour"
    assert rows[0]["section"] == "Dry"
    assert rows[0]["display"] == "3 cup"
    assert rows[0]["scaled_amount"] == 3.0
