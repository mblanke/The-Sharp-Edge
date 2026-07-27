"""Aisle classification for the shopping list.

The test names are the promise: a list sorted this way should let you walk the shop
once. Cases below are taken from the real seeded recipes.
"""

import pytest

from app.services.aisles import AISLE_ORDER, aisle_rank, classify_aisle


@pytest.mark.parametrize(
    "name,aisle",
    [
        ("beef chuck, cut into 1-inch cubes", "Meat & fish"),
        ("ground pork", "Meat & fish"),
        ("salmon fillets, 170–200 g each", "Meat & fish"),
        ("yellow onions, diced", "Produce"),
        ("garlic cloves, minced", "Produce"),
        ("Yukon Gold potatoes, cubed", "Produce"),
        ("red bell peppers, diced", "Produce"),
        ("English cucumber, grated and squeezed dry", "Produce"),
        ("limes, juiced", "Produce"),
        ("heavy cream", "Dairy & eggs"),
        ("block feta in brine, cubed or crumbled", "Dairy & eggs"),
        ("1 large egg", "Dairy & eggs"),
        ("baguette, sliced", "Bakery"),
        ("brioche croutons", "Bakery"),
        ("sweet Hungarian paprika (certified GF)", "Herbs & spices"),
        ("caraway seeds, crushed", "Herbs & spices"),
        ("bay leaves", "Herbs & spices"),
        ("flaky salt and black pepper", "Herbs & spices"),
        ("beef broth (certified GF)", "Pantry"),
        ("tomato paste", "Pantry"),
        ("GF tamari", "Pantry"),
        ("red wine vinegar", "Pantry"),
        ("all-purpose flour", "Pantry"),
        ("brown sugar, packed", "Pantry"),
    ],
)
def test_real_ingredients_land_in_the_right_aisle(name, aisle):
    assert classify_aisle(name) == aisle


def test_the_specific_beats_the_general():
    """"coconut milk" is a tin in the middle of the shop; "milk" is the chiller."""
    assert classify_aisle("coconut milk") == "Pantry"
    assert classify_aisle("whole milk") == "Dairy & eggs"
    assert classify_aisle("canned diced tomatoes") == "Pantry"
    assert classify_aisle("tomatoes, diced") == "Produce"


def test_unknown_ingredients_are_not_guessed_at():
    """Wrong aisle is worse than no aisle — it sends you to the wrong end of the shop."""
    assert classify_aisle("Pre-Hy") == "Other"
    assert classify_aisle("") == "Other"
    assert classify_aisle("Ultra-Tex") == "Other"


def test_accents_and_case_do_not_matter():
    assert classify_aisle("Crème fraîche") == "Dairy & eggs"
    assert classify_aisle("CREME FRAICHE") == "Dairy & eggs"
    assert classify_aisle("Gruyère cheese") == "Dairy & eggs"


def test_walking_order_puts_fresh_first_and_frozen_last():
    assert AISLE_ORDER[0] == "Produce"
    assert AISLE_ORDER[-1] == "Other"
    assert aisle_rank("Frozen") > aisle_rank("Produce")
    assert aisle_rank("Other") == len(AISLE_ORDER) - 1
    assert aisle_rank("nonsense") == len(AISLE_ORDER)


def test_every_aisle_is_reachable():
    """A category nothing can land in is dead weight in the UI."""
    samples = {
        "Produce": "onion", "Meat & fish": "chicken", "Dairy & eggs": "butter",
        "Bakery": "bread", "Pantry": "olive oil", "Herbs & spices": "cinnamon",
        "Frozen": "frozen peas", "Other": "Pre-Hy",
    }
    assert set(samples) == set(AISLE_ORDER)
    for aisle, sample in samples.items():
        assert classify_aisle(sample) == aisle


@pytest.mark.parametrize(
    "name,aisle",
    [
        ("garlic cloves, minced", "Produce"),      # not the spice clove
        ("garlic powder", "Herbs & spices"),       # but this one is
        ("ground cloves", "Herbs & spices"),
        ("freshly grated nutmeg", "Herbs & spices"),   # not a nut
        ("coconut milk", "Pantry"),                    # also not a nut
        ("butternut squash", "Produce"),               # still not a nut
        ("chopped walnuts", "Pantry"),
        ("fresh ginger, grated", "Produce"),
        ("ground ginger", "Herbs & spices"),
        ("green onions, sliced", "Produce"),
    ],
)
def test_near_misses_where_a_shorter_word_would_win(name, aisle):
    assert classify_aisle(name) == aisle


@pytest.mark.parametrize(
    "name,aisle",
    [
        # Preparation after the comma is not where a thing lives in the shop.
        ("jalapeño, seeded and minced", "Produce"),       # "minced" is not mince
        ("beef chuck, cut into 1-inch cubes", "Meat & fish"),
        ("red onion, finely diced", "Produce"),
        ("salmon fillets, about 170 to 200 g each", "Meat & fish"),
        ("lime, zested", "Produce"),
        ("English cucumber, grated and squeezed dry", "Produce"),
    ],
)
def test_preparation_does_not_decide_the_aisle(name, aisle):
    assert classify_aisle(name) == aisle


def test_falls_back_to_the_whole_name_when_the_head_says_nothing():
    """"1 can of San Marzano tomatoes, drained" — the head alone is uninformative."""
    assert classify_aisle("tin of San Marzano tomatoes, drained") != "Other"
