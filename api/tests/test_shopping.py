"""Merge-table tests for the shopping list (services/shopping.py)."""

from app.services.shopping import merge_shopping


def row(name, unit, scaled_amount, recipe_id=None):
    return {"name": name, "unit": unit, "scaled_amount": scaled_amount, "recipe_id": recipe_id}


def test_same_name_and_unit_sum_with_kitchen_fractions():
    out = merge_shopping([
        row("garlic cloves, minced", "", 4, "r1"),
        row("Garlic cloves", "", 2.5, "r2"),
    ])
    assert out == [{"name": "garlic cloves", "amount": "6 ½", "recipe_id": None}]


def test_metric_sums_follow_rounding_rules():
    out = merge_shopping([
        row("beef broth", "ml", 150, "r1"),
        row("beef broth", "ml", 62.5, "r2"),  # 212.5 ≥ 200 → nearest 5, half up
    ])
    assert out[0]["amount"] == "215 ml"


def test_different_units_stay_separate():
    out = merge_shopping([
        row("olive oil", "tbsp", 2, "r1"),
        row("olive oil", "cup", 0.25, "r2"),
    ])
    assert [(o["name"], o["amount"]) for o in out] == [
        ("olive oil", "2 tbsp"),
        ("olive oil", "¼ cup"),
    ]


def test_prep_clause_merges_but_different_heads_do_not():
    out = merge_shopping([
        row("yellow onions, diced", "", 2, "r1"),
        row("yellow onions, thinly sliced", "", 1, "r2"),
        row("red onions, diced", "", 1, "r3"),
    ])
    assert [(o["name"], o["amount"]) for o in out] == [
        ("yellow onions", "3"),
        ("red onions", "1"),
    ]


def test_to_taste_folds_into_measured_line():
    out = merge_shopping([
        row("salt", "tsp", 1.5, "r1"),
        row("salt, to taste", "", 0, "r2"),
    ])
    assert out == [{"name": "salt", "amount": "1 ½ tsp", "recipe_id": "r1"}]


def test_to_taste_standalone_dedupes():
    out = merge_shopping([
        row("black pepper, to taste", "", 0, "r1"),
        row("black pepper", "", 0, "r2"),
    ])
    assert out == [{"name": "black pepper", "amount": "— to taste", "recipe_id": None}]


def test_single_recipe_provenance_kept():
    out = merge_shopping([row("caraway seeds, crushed", "tsp", 1, "r1")])
    assert out == [{"name": "caraway seeds", "amount": "1 tsp", "recipe_id": "r1"}]


def test_fraction_glyphs_never_decimals():
    out = merge_shopping([
        row("flour", "cup", 0.75, "r1"),
        row("butter", "tbsp", 1.5, "r1"),
    ])
    for o in out:
        assert "." not in o["amount"]
    assert out[0]["amount"] == "¾ cup"
    assert out[1]["amount"] == "1 ½ tbsp"


def test_blank_names_dropped_and_order_stable():
    out = merge_shopping([
        row("  ", "", 1, "r1"),
        row("beef chuck, cubed", "lb", 2, "r1"),
        row("paprika", "tbsp", 3, "r1"),
    ])
    assert [o["name"] for o in out] == ["beef chuck", "paprika"]
