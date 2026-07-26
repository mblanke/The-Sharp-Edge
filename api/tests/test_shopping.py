"""Shopping-list merging.

The requirement in one line: adding a second recipe must ADD to a line, never
replace it.
"""

import pytest

from app.services.shopping import ShoppingLine, as_text, merge_lines, normalise_name


def line(name, amount=0.0, unit="", recipe="r1"):
    return ShoppingLine(name=name, amount=amount, unit=unit,
                        to_taste=amount == 0, recipes=[recipe])


# ---------------------------------------------------------------- the core rule

def test_same_ingredient_and_unit_adds():
    out = merge_lines([
        line("sweet Hungarian paprika", 3, "tbsp", "goulash"),
        line("sweet Hungarian paprika", 2, "tbsp", "rub"),
    ])
    assert len(out) == 1
    assert out[0].amount == 5
    assert out[0].unit == "tbsp"
    assert out[0].recipes == ["goulash", "rub"]


def test_preparation_after_a_comma_is_ignored_when_matching():
    """You buy beef chuck; how it gets cut is not a separate shopping item."""
    out = merge_lines([
        line("beef chuck, cut into 1-inch cubes", 2, "lb"),
        line("beef chuck, trimmed", 1, "lb"),
    ])
    assert len(out) == 1
    assert out[0].amount == 3


def test_singular_and_plural_merge():
    out = merge_lines([line("yellow onions, diced", 3), line("yellow onion", 2)])
    assert len(out) == 1
    assert out[0].amount == 5


def test_plural_stripping_does_not_mangle_real_words():
    assert normalise_name("asparagus") == "asparagus"
    assert normalise_name("Swiss chard") == "swiss chard"
    assert normalise_name("molasses") == "molasses"


# ---------------------------------------------------------------- unit families

def test_volume_units_convert_and_add():
    """1 cup + 2 tbsp is one line, read in cups because the cup is the larger part."""
    out = merge_lines([line("olive oil", 1, "cup"), line("olive oil", 2, "tbsp")])
    assert len(out) == 1
    assert out[0].unit == "cup"
    assert out[0].amount == pytest.approx(1.125, abs=0.01)


def test_smaller_unit_wins_when_it_is_the_larger_amount():
    out = merge_lines([line("olive oil", 3, "tbsp"), line("olive oil", 1, "tsp")])
    assert out[0].unit == "tbsp"
    assert out[0].amount == pytest.approx(3.333, abs=0.01)


def test_weight_units_convert_and_add():
    out = merge_lines([line("butter", 500, "g"), line("butter", 1, "lb")])
    assert len(out) == 1
    assert out[0].unit == "g"                       # 500 g > 453 g
    assert out[0].amount == pytest.approx(953.6, abs=0.5)


def test_volume_and_weight_never_combine():
    """2 cups of stock and 400 g of beef are not 'the same ingredient, more of it'."""
    out = merge_lines([line("stock", 2, "cup"), line("stock", 400, "g")])
    assert len(out) == 2


def test_countables_add():
    out = merge_lines([line("limes", 2), line("limes", 3)])
    assert len(out) == 1
    assert out[0].amount == 5
    assert out[0].unit == ""


# ---------------------------------------------------------------- to taste

def test_to_taste_items_do_not_gain_a_quantity():
    out = merge_lines([line("salt", 0), line("salt", 0)])
    assert len(out) == 1
    assert out[0].to_taste
    assert out[0].display == "to taste"


def test_a_to_taste_item_is_absorbed_by_a_measured_one():
    """One recipe wants 1 tsp of pepper, another wants it "to taste" — you buy pepper
    once, and the measured amount is the more useful of the two. Never the reverse."""
    out = merge_lines([
        line("black pepper", 1, "tsp", "goulash"),
        line("black pepper", 0, "", "salad"),
    ])
    assert len(out) == 1
    assert not out[0].to_taste
    assert out[0].amount == 1 and out[0].unit == "tsp"
    assert set(out[0].recipes) == {"goulash", "salad"}


def test_a_to_taste_only_ingredient_stays_a_staple():
    out = merge_lines([line("flaky salt", 0), line("flaky salt", 0)])
    assert len(out) == 1 and out[0].to_taste


# ---------------------------------------------------------------- rendering

def test_display_uses_kitchen_fractions():
    out = merge_lines([line("flour", 1, "cup"), line("flour", 2, "tbsp")])
    assert "⅛" in out[0].display          # 1.125 cup, not 1.125
    assert "1.125" not in out[0].display


def test_metric_display_is_whole_numbers():
    out = merge_lines([line("milk", 150, "ml"), line("milk", 100, "ml")])
    assert out[0].display == "250 ml"


def test_order_of_first_appearance_is_kept():
    out = merge_lines([line("onions", 1), line("garlic", 2), line("onions", 1)])
    assert [ln.name for ln in out] == ["onions", "garlic"]


# ---------------------------------------------------------------- gluten

@pytest.mark.parametrize("name", [
    "sweet Hungarian paprika (certified GF)", "beef broth", "tomato paste",
    "GF tamari", "Worcestershire sauce", "chicken bouillon",
])
def test_hidden_gluten_ingredients_are_flagged(name):
    assert ShoppingLine(name=name, amount=1, unit="tbsp").check_gluten


def test_plain_ingredients_are_not_flagged():
    for name in ["yellow onions", "carrots", "heavy cream", "butter"]:
        assert not ShoppingLine(name=name, amount=1).check_gluten


# ---------------------------------------------------------------- share text

def test_text_export_is_one_item_per_line():
    text = as_text(merge_lines([
        line("beef chuck, cubed", 2, "lb"),
        line("beef broth", 3, "cup"),
        line("salt", 0),
    ]))
    body = [ln for ln in text.splitlines() if ln.strip()]
    assert "2 lb beef chuck, cubed" in body
    assert any("beef broth" in ln and "check GF" in ln for ln in body)
    # to-taste items are separated out — you do not buy them
    assert "Check you have:" in body
    assert body.index("Check you have:") < body.index("salt")


def test_text_export_has_no_gf_flag_on_safe_items():
    text = as_text(merge_lines([line("carrots", 3)]))
    assert "check GF" not in text
