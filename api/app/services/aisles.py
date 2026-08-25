"""Which part of the shop each ingredient comes from.

A shopping list ordered by when you added it makes you criss-cross the shop. Ordered
by aisle you walk it once. This classifies on the ingredient name, server-side, so
the app and the web client always agree — the same reason the gluten flags live
next door in services/shopping.py.

Deliberately a keyword table rather than anything cleverer: a wrong guess sends you
to the wrong aisle, and a table is auditable and correctable in one line. Anything
unrecognised lands in "Other" rather than being guessed at, so an unfamiliar
ingredient is visibly unsorted instead of quietly filed wrong.
"""

from __future__ import annotations

import re
import unicodedata

__all__ = ["AISLE_ORDER", "classify_aisle"]

#: Walking order through a supermarket: fresh edges first, then the middle, then
#: frozen last so it spends least time out of the cold.
AISLE_ORDER = (
    "Produce",
    "Meat & fish",
    "Dairy & eggs",
    "Bakery",
    "Pantry",
    "Herbs & spices",
    "Frozen",
    "Other",
)

# Longest phrases first within each aisle; the first hit wins, and the aisles are
# tested in the order below. Order matters where a word appears twice — "coconut
# milk" is pantry, plain "milk" is dairy, so the pantry entry has to be checked
# first, which is why the table is a list of (aisle, terms) pairs rather than a dict.
# Checked before everything else. These are the cases where two aisles both match
# and the shorter word would win by accident: "garlic cloves" is not the spice clove,
# "nutmeg" is not a nut, "coconut" is neither.
_OVERRIDES: list[tuple[str, tuple[str, ...]]] = [
    ("Herbs & spices", ("garlic powder", "onion powder", "ground clove", "whole clove",
                        "ground ginger", "nutmeg", "peppercorn")),
    ("Produce", ("garlic", "spring onion", "green onion", "scallion", "ginger root",
                 "fresh ginger")),
    ("Pantry", ("coconut", "peanut", "chestnut", "pine nut", "nutella")),
    ("Produce", ("butternut", "chestnut mushroom")),
]

_RULES: list[tuple[str, tuple[str, ...]]] = [
    # Checked before Dairy/Produce so the specific beats the general.
    ("Pantry", (
        "coconut milk", "coconut cream", "condensed milk", "evaporated milk",
        "almond milk", "oat milk", "soy milk", "buttermilk powder", "peanut butter",
        "tomato paste", "tomato puree", "passata", "canned tomato", "can diced tomato",
        "tomato juice", "spaghetti sauce", "stock", "broth", "bouillon",
        "olive oil", "vegetable oil", "canola", "sesame oil", "oil",
        "vinegar", "soy sauce", "tamari", "worcestershire", "hoisin", "oyster sauce",
        "fish sauce", "mustard", "mayonnaise", "ketchup", "honey", "maple syrup",
        "sugar", "brown sugar", "flour", "cornstarch", "corn starch", "baking soda",
        "baking powder", "yeast", "rice", "pasta", "spaghetti", "noodle", "lentil",
        "chickpea", "bean", "quinoa", "couscous", "oats", "breadcrumb", "panko",
        "chocolate", "cocoa", "vanilla extract", "wine", "bourbon", "tequila",
        "port", "sherry", "stock cube", "gelatin", "cornmeal", "molasses", "capers",
        "olives", "pickle", "jam", "almond", "walnut", "pecan", "cashew",
        "raisin", "dried", "can ", "canned", "tinned", "tin ", "nuts", "mixed nuts",
    )),
    ("Herbs & spices", (
        "paprika", "cumin", "coriander seed", "caraway", "cinnamon", "nutmeg",
        "cardamom", "turmeric", "curry powder", "chili powder", "chilli powder",
        "cayenne", "peppercorn", "black pepper", "white pepper", "salt", "fleur de sel",
        "bay leaf", "bay leaves", "oregano", "thyme", "rosemary", "sage", "marjoram",
        "tarragon", "dill", "basil", "parsley", "cilantro", "mint", "chive",
        "saffron", "star anise", "fennel seed", "mustard seed", "seasoning", "spice",
        "herbs", "vanilla bean", "ginger, ground", "garlic powder", "onion powder",
    )),
    ("Meat & fish", (
        "beef", "chuck", "steak", "flank", "brisket", "mince", "ground pork",
        "ground veal", "ground beef", "pork", "bacon", "pancetta", "prosciutto",
        "ham", "sausage", "chicken", "turkey", "duck", "lamb", "veal", "salmon",
        "cod", "haddock", "tuna", "trout", "shrimp", "prawn", "scallop", "oyster",
        "mussel", "clam", "crab", "lobster", "anchovy", "fish", "chorizo",
    )),
    ("Dairy & eggs", (
        "butter", "milk", "cream", "creme fraiche", "crème fraîche", "sour cream",
        "yogurt", "yoghurt", "cheese", "parmesan", "cheddar", "feta", "mozzarella",
        "gruyere", "gruyère", "comte", "comté", "ricotta", "mascarpone", "egg",
        "buttermilk", "ghee",
    )),
    ("Bakery", (
        "bread", "baguette", "brioche", "roll", "bun", "tortilla", "pita",
        "croissant", "crouton", "sourdough", "naan", "cake",
    )),
    ("Frozen", ("frozen", "ice cream", "puff pastry", "filo", "phyllo")),
    ("Produce", (
        "onion", "shallot", "garlic", "leek", "celery", "carrot", "potato",
        "tomato", "pepper", "cucumber", "lettuce", "spinach", "kale", "chard",
        "cabbage", "broccoli", "cauliflower", "courgette", "zucchini", "aubergine",
        "eggplant", "mushroom", "squash", "pumpkin", "beet", "radish", "turnip",
        "celeriac", "parsnip", "fennel", "asparagus", "green bean", "pea",
        "corn", "avocado", "lemon", "lime", "orange", "apple", "pear", "banana",
        "mango", "pineapple", "watermelon", "melon", "berry", "strawberr",
        "raspberr", "blueberr", "cherry", "cherries", "grape", "peach", "plum",
        "ginger", "chilli", "chili", "jalapeño", "jalapeno", "scallion",
        "green onion", "spring onion", "sprout", "herb",
    )),
]


def _fold(name: str) -> str:
    text = "".join(
        c for c in unicodedata.normalize("NFKD", name or "") if not unicodedata.combining(c)
    )
    return re.sub(r"\s+", " ", text).strip().lower()


def classify_aisle(name: str) -> str:
    """Best-guess aisle for an ingredient name, or "Other" when nothing matches.

    Classified on the part before the first comma, the same head the merge key uses.
    Recipe names carry preparation after it — "jalapeño, seeded and minced" — and
    preparation is not where a thing lives in the shop. Matching the whole string put
    that jalapeño in Meat & fish, because "minced" contains "mince".
    """
    head = _fold(name.split(",")[0])
    probe = head or _fold(name)
    if not probe:
        return "Other"
    for aisle, terms in _OVERRIDES:
        for term in sorted(terms, key=len, reverse=True):
            if term in probe:
                return aisle
    for aisle, terms in _RULES:
        for term in sorted(terms, key=len, reverse=True):
            if term in probe:
                return aisle
    # Nothing in the head — fall back to the whole string before giving up, so
    # "1 can of San Marzano tomatoes, drained" still finds its aisle.
    if probe != _fold(name):
        return classify_aisle(name.replace(",", " "))
    return "Other"


def aisle_rank(aisle: str) -> int:
    try:
        return AISLE_ORDER.index(aisle)
    except ValueError:
        return len(AISLE_ORDER)
