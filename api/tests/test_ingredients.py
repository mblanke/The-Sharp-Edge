"""Multilingual ingredient parsing, slugify and category matching.

Every case here is a line someone would actually say standing at a counter. The
contract under test: ingredient *names* survive verbatim in the language spoken,
while amount/unit/category normalise to the app's canonical English set.
"""

import pytest

from app.services.ingredients import (
    is_valid_slug,
    parse_lines,
    split_run_on,
    match_category,
    normalise_spoken,
    parse_ingredient,
    slugify,
    strip_diacritics,
)


def spoken(line: str, lang: str) -> tuple[float, str, str]:
    row = parse_ingredient(line, lang=lang, spoken=True)
    return row["amount"], row["unit"], row["name"]


# ---------------------------------------------------------------- English

@pytest.mark.parametrize(
    "line,expected",
    [
        ("2 tablespoons olive oil", (2.0, "tbsp", "olive oil")),
        ("1 1/2 cups all-purpose flour", (1.5, "cup", "all-purpose flour")),
        ("two and a half pounds flank steak", (2.5, "lb", "flank steak")),
        ("half a cup of cream", (0.5, "cup", "cream")),
        ("three quarters of a cup of sugar", (0.75, "cup", "sugar")),
        ("about 200 grams of butter", (200.0, "g", "butter")),
        ("2 kilos of potatoes", (2000.0, "g", "potatoes")),
        ("1 litre of stock", (1000.0, "ml", "stock")),
        # amount 0 is the "to taste" contract — an em dash that never scales.
        ("a pinch of saffron", (0, "", "saffron")),
        ("black pepper, to taste", (0, "", "black pepper")),
        ("1 can diced tomatoes", (1.0, "", "can diced tomatoes")),
        ("½ cup yoghurt", (0.5, "cup", "yoghurt")),
        ("1½ cups milk", (1.5, "cup", "milk")),
    ],
)
def test_english(line, expected):
    assert spoken(line, "en") == expected


# ---------------------------------------------------------------- French

@pytest.mark.parametrize(
    "line,expected",
    [
        ("200 grammes de farine", (200.0, "g", "farine")),
        ("2 cuillères à soupe d'huile d'olive", (2.0, "tbsp", "huile d'olive")),
        ("3 cuillères à café de sucre", (3.0, "tsp", "sucre")),
        ("1 tasse de la crème", (1.0, "cup", "crème")),
        # Decimal comma: this used to fall through to amount 0 and lose the quantity.
        ("1,5 kg de tomates", (1500.0, "g", "tomates")),
        ("deux et demi tasses de lait", (2.5, "cup", "lait")),
        ("un quart de tasse de vinaigre", (0.25, "cup", "vinaigre")),
        # A French *livre* is 500 g, not a pound.
        ("une livre de beurre", (500.0, "g", "beurre")),
        ("environ 3 gousses d'ail", (3.0, "", "gousses d'ail")),
        ("une pincée de sel", (0, "", "sel")),
        ("sel, à votre goût", (0, "", "sel")),
        ("poivre selon le goût", (0, "", "poivre")),
        ("500 ml de bouillon", (500.0, "ml", "bouillon")),
    ],
)
def test_french(line, expected):
    assert spoken(line, "fr") == expected


# ---------------------------------------------------------------- German

@pytest.mark.parametrize(
    "line,expected",
    [
        ("200 Gramm Mehl", (200.0, "g", "Mehl")),
        # German writes these as one word, so they never survive tokenisation.
        ("zweieinhalb Esslöffel Paprikapulver", (2.5, "tbsp", "Paprikapulver")),
        ("anderthalb Teelöffel Salz", (1.5, "tsp", "Salz")),
        ("dreiviertel Tasse Sahne", (0.75, "cup", "Sahne")),
        ("1,5 kg Kartoffeln", (1500.0, "g", "Kartoffeln")),
        ("ein halber Liter Sahne", (500.0, "ml", "Sahne")),
        # A German *Pfund* is 500 g, not a pound.
        ("ein Pfund Butter", (500.0, "g", "Butter")),
        ("2 EL Tomatenmark", (2.0, "tbsp", "Tomatenmark")),
        ("1 TL Kümmel", (1.0, "tsp", "Kümmel")),
        ("eine Prise Salz", (0, "", "Salz")),
        ("Pfeffer nach Geschmack", (0, "", "Pfeffer")),
        ("etwa 300 Gramm Zwiebeln", (300.0, "g", "Zwiebeln")),
    ],
)
def test_german(line, expected):
    assert spoken(line, "de") == expected


# ---------------------------------------------------------------- Romanian

@pytest.mark.parametrize(
    "line,expected",
    [
        # ă/ș/ț sit outside the old [A-Za-zÀ-ÿ] class — every one of these used to
        # fall through to amount 0 with the whole line as the name.
        ("200 g de făină", (200.0, "g", "făină")),
        ("două linguri de ulei de măsline", (2.0, "tbsp", "ulei de măsline")),
        ("o linguriță de sare, după gust", (0, "tsp", "sare")),
        ("1,5 kg de roșii", (1500.0, "g", "roșii")),
        ("două și jumătate căni de lapte", (2.5, "cup", "lapte")),
        ("trei sferturi de cană de zahăr", (0.75, "cup", "zahăr")),
        ("un praf de scorțișoară", (0, "", "scorțișoară")),
        ("un vârf de cuțit de nucșoară", (0, "", "nucșoară")),
        ("500 ml de smântână", (500.0, "ml", "smântână")),
        ("piper după gust", (0, "", "piper")),
        # Dictation often emits the legacy cedilla forms ş/ţ instead of ș/ț.
        ("o linguriţă de zahăr", (1.0, "tsp", "zahăr")),
    ],
)
def test_romanian(line, expected):
    assert spoken(line, "ro") == expected


# ---------------------------------------------------------------- normalise_spoken

@pytest.mark.parametrize(
    "text,lang,expected",
    [
        ("zweieinhalb Esslöffel Paprikapulver", "de", "2.5 tbsp Paprikapulver"),
        ("200 grammes de farine", "fr", "200 g farine"),
        ("1,5 kg de roșii", "ro", "1.5 kg roșii"),
        ("two and a half pounds flank steak", "en", "2.5 lb flank steak"),
        ("¾ cup sugar", "en", "3/4 cup sugar"),
    ],
)
def test_normalise_spoken(text, lang, expected):
    assert normalise_spoken(text, lang) == expected


def test_printed_path_is_untouched_by_language_support():
    """The seed importer's behaviour is pinned by test_import_master; spot-check it here."""
    assert parse_ingredient("- ~2 kg sour cherries") == {
        "amount": 2000.0,
        "unit": "g",
        "name": "sour cherries",
    }
    # Printed text keeps ", to taste" in the name; only the spoken path strips it.
    assert parse_ingredient("- Freshly ground black pepper, to taste")["name"] == (
        "Freshly ground black pepper, to taste"
    )


# ---------------------------------------------------------------- slug

@pytest.mark.parametrize(
    "title,expected",
    [
        ("Vișinată", "visinata"),          # matches the slug already in the seed manifest
        ("Gurkensalat", "gurkensalat"),
        ("Crème Brûlée!", "creme-brulee"),
        ("Weißwein Soße", "weisswein-sosse"),
        ("Mango  Salsa", "mango-salsa"),
        ("  Flank Steak — Overnight  ", "flank-steak-overnight"),
        ("Sauces & Salsas", "sauces-salsas"),
        ("Ciorbă de burtă", "ciorba-de-burta"),
    ],
)
def test_slugify(title, expected):
    assert slugify(title) == expected
    assert is_valid_slug(slugify(title))


def test_slugify_rejects_unusable_titles():
    assert slugify("!!!") == ""
    assert not is_valid_slug("")
    assert not is_valid_slug("-leading")
    assert not is_valid_slug("Upper")


def test_strip_diacritics():
    assert strip_diacritics("ăâîșț") == "aaist"
    assert strip_diacritics("äöüß") == "aouss"


# ---------------------------------------------------------------- category

@pytest.mark.parametrize(
    "spoken_name,lang,expected",
    [
        ("Salads", "en", "Salads"),
        ("salade", "fr", "Salads"),
        ("Salate", "de", "Salads"),
        ("salate", "ro", "Salads"),
        ("sosuri", "ro", "Sauces & Salsas"),
        ("Saucen", "de", "Sauces & Salsas"),
        ("ciorbe", "ro", "Soups & Stews"),
        ("Suppen", "de", "Soups & Stews"),
        ("garnituri", "ro", "Sides"),
        ("Beilagen", "de", "Sides"),
        ("desserts", "fr", "Baking & Desserts"),
        ("băuturi", "ro", "Drinks"),
        ("Frühstück", "de", "Breakfast"),
        # Dictation drops diacritics often enough that this has to work.
        ("bauturi", "ro", "Drinks"),
        ("Fruhstuck", "de", "Breakfast"),
    ],
)
def test_match_category(spoken_name, lang, expected):
    assert match_category(spoken_name, lang) == expected


def test_entree_is_a_false_friend():
    """French *entrée* is a starter; the English category "Entrées" is the main course."""
    assert match_category("entrée", "fr") == "Appetizers & Preserves"
    assert match_category("plat principal", "fr") == "Entrées"
    assert match_category("Hauptgerichte", "de") == "Entrées"
    assert match_category("feluri principale", "ro") == "Entrées"


def test_match_category_unknown():
    assert match_category("zzz nonsense", "en") is None


# ---------------------------------------------------------------- unpunctuated runs
# Speech recognition only inserts full stops if you say "period", so a dictated
# ingredient list arrives as one long string. Quantities are the boundary.

@pytest.mark.parametrize(
    "line,lang,expected",
    [
        ("two pounds beef chuck three onions four cloves of garlic", "en",
         ["two pounds beef chuck", "three onions", "four cloves of garlic"]),
        ("200 grammes de farine 3 oeufs 500 ml de lait", "fr",
         ["200 grammes de farine", "3 oeufs", "500 ml de lait"]),
        ("zweieinhalb Esslöffel Paprika 200 Gramm Mehl", "de",
         ["zweieinhalb Esslöffel Paprika", "200 Gramm Mehl"]),
        ("200 g de făină două linguri de ulei", "ro",
         ["200 g de făină", "două linguri de ulei"]),
    ],
)
def test_a_run_splits_into_one_ingredient_each(line, lang, expected):
    assert split_run_on(line, lang) == expected


def test_a_mixed_fraction_is_not_cut_in_half():
    assert split_run_on("1 1/2 cups flour 2 eggs", "en") == ["1 1/2 cups flour", "2 eggs"]


def test_a_range_stays_whole():
    assert split_run_on("2 to 3 cloves garlic 1 onion", "en") == ["2 to 3 cloves garlic", "1 onion"]


def test_a_measurement_inside_a_name_is_not_a_boundary():
    assert split_run_on("2 lb beef chuck cut into 1 inch cubes", "en") == [
        "2 lb beef chuck cut into 1 inch cubes"
    ]


def test_a_single_ingredient_is_left_alone():
    assert split_run_on("two pounds of beef chuck", "en") == ["two pounds of beef chuck"]
    assert split_run_on("", "en") == []


def test_the_whole_run_parses_into_separate_ingredients():
    """The bug: a dictated recipe landed as one ingredient named after the sentence."""
    rows = parse_lines(["two pounds beef chuck three onions four cloves of garlic"], lang="en")
    assert len(rows) == 3
    assert (rows[0]["amount"], rows[0]["unit"]) == (2.0, "lb")
    assert "beef chuck" in rows[0]["name"]
    assert (rows[1]["amount"], rows[1]["name"]) == (3.0, "onions")
    assert rows[2]["amount"] == 4.0


def test_printed_input_is_never_split():
    """The seed importer passes real bullet lines; they must stay one ingredient."""
    rows = parse_lines(["1.5–2 lb block feta in brine"], lang="en", spoken=False)
    assert len(rows) == 1
