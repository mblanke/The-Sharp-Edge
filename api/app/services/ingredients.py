"""Free-text and dictated ingredient lines → structured ``{amount, unit, name}``.

Promoted here from ``seed/import_master.py`` so the seed importer, the ``/parse``
endpoints and both clients share one implementation (docs/voice-recipe-capture.md).

Two entry points:

* ``parse_ingredient(line)`` — printed-text behaviour, byte-identical to what the
  seed importer has always done. Do not change its output; ``recipes-master.md``
  is imported through it and ``api/tests/test_import_master.py`` pins it.
* ``parse_ingredient(line, lang="fr", spoken=True)`` — the dictation path. Runs
  ``normalise_spoken()`` first, which rewrites everything language-specific into
  the English-canonical form the core parser already understands, then applies the
  "to taste" rule.

The data model stays English-canonical: ``unit`` is always one of ALLOWED_UNITS and
categories are always CATEGORY_ORDER entries. Ingredient *names* are left exactly as
spoken — "200 g de farine" yields ``name="farine"``, not "flour". Nothing is
translated and no model is involved.
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field
from fractions import Fraction

__all__ = [
    "LANGS",
    "match_category",
    "normalise_spoken",
    "parse_ingredient",
    "slugify",
]

# ---------------------------------------------------------------- core (English) tables

UNIT_MAP = {
    "tablespoon": "tbsp", "tablespoons": "tbsp", "tbsp": "tbsp",
    "teaspoon": "tsp", "teaspoons": "tsp", "tsp": "tsp",
    "cup": "cup", "cups": "cup",
    "pound": "lb", "pounds": "lb", "lb": "lb", "lbs": "lb",
    "ounce": "oz", "ounces": "oz", "oz": "oz",
    "g": "g", "gram": "g", "grams": "g",
    "kg": "kg", "kilogram": "kg", "kilograms": "kg",
    "ml": "ml", "millilitre": "ml", "millilitres": "ml", "milliliter": "ml", "milliliters": "ml",
    "cl": "cl", "centilitre": "cl", "centilitres": "cl", "centiliter": "cl", "centiliters": "cl",
    "dl": "dl", "decilitre": "dl", "decilitres": "dl", "deciliter": "dl", "deciliters": "dl",
    "l": "l", "liter": "l", "liters": "l", "litre": "l", "litres": "l",
    # Synthetic token. French *livre* and German *Pfund* are half-kilos, not pounds;
    # normalise_spoken() rewrites them to this so the conversion below catches them.
    "halfkilo": "halfkilo",
}
# spec units are g/ml — convert metric multiples
METRIC_FACTOR = {
    "kg": ("g", 1000), "l": ("ml", 1000), "halfkilo": ("g", 500),
    # European pages and dictation say centilitres/decilitres routinely
    "cl": ("ml", 10), "dl": ("ml", 100),
}

NUM = r"(?:\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?)"
RANGE_SEP = r"(?:–|—|-|\s+to\s+)"
# Any Unicode letter. The old [A-Za-zÀ-ÿ] excluded ă (U+0103), ș (U+0219) and
# ț (U+021B), so every Romanian line fell through to amount 0.
WORD = r"[^\W\d_]+"

LANGS = ("en", "fr", "de", "ro")


# ---------------------------------------------------------------- text helpers

# Romanian dictation emits the legacy cedilla forms about as often as the correct
# comma-below ones; fold them together before anything else looks at the string.
_CEDILLA_FIX = {"ş": "ș", "Ş": "Ș", "ţ": "ț", "Ţ": "Ț"}

_VULGAR = {
    "¼": "1/4", "½": "1/2", "¾": "3/4",
    "⅐": "1/7", "⅑": "1/9", "⅒": "1/10",
    "⅓": "1/3", "⅔": "2/3",
    "⅕": "1/5", "⅖": "2/5", "⅗": "3/5", "⅘": "4/5",
    "⅙": "1/6", "⅚": "5/6",
    "⅛": "1/8", "⅜": "3/8", "⅝": "5/8", "⅞": "7/8",
}


def strip_diacritics(text: str) -> str:
    """'Vișinată' → 'Visinata'. ß → ss (NFKD leaves it alone)."""
    text = "".join(_CEDILLA_FIX.get(ch, ch) for ch in text)
    text = text.replace("ß", "ss").replace("ẞ", "SS")
    return "".join(c for c in unicodedata.normalize("NFKD", text) if not unicodedata.combining(c))


def _variants(phrase: str) -> list[str]:
    """A phrase and its de-accented twin, so dictation that drops diacritics still matches."""
    bare = strip_diacritics(phrase)
    return [phrase] if bare == phrase else [phrase, bare]


def _alternation(phrases) -> str:
    """Regex alternation over phrases, longest first so 'cuillère à soupe' beats 'cuillère'."""
    out: list[str] = []
    for p in phrases:
        out.extend(_variants(p))
    out.sort(key=len, reverse=True)
    # Allow any run of whitespace where the phrase has a space.
    return "|".join(r"\s+".join(re.escape(w) for w in p.split()) for p in out)


# ---------------------------------------------------------------- per-language lexicons

@dataclass(frozen=True)
class Lexicon:
    """Everything language-specific. Values are rewritten into English-canonical form."""

    #: spoken unit phrase → a key of UNIT_MAP
    units: dict[str, str]
    #: spoken number/fraction phrase → numeric value, matched only at the start of a line
    numbers: dict[str, float]
    #: "N and a half" style suffixes applied to a preceding digit → the value they add.
    #: A dict rather than a tuple because "and a quarter" is not 0.5; when this was a
    #: bare tuple every suffix added 0.5, so "2 and a quarter cups" parsed as 2.5.
    half_suffixes: dict[str, float] = field(default_factory=dict)
    #: "pinch"-type phrases: force amount 0, dropped from the name
    pinch: tuple[str, ...] = ()
    #: "to taste"-type phrases: force amount 0, dropped from the name
    to_taste: tuple[str, ...] = ()
    #: partitive glue between unit and name — "200 g **de** farine"
    connectors: tuple[str, ...] = ()
    #: approximation markers, rewritten to "~"
    approx: tuple[str, ...] = ()
    #: True where "1,5" means one and a half
    decimal_comma: bool = False
    #: spoken category name → a CATEGORY_ORDER entry
    categories: dict[str, str] = field(default_factory=dict)


def _ones(pairs: dict[str, float], fraction_suffixes: dict[str, float]) -> dict[str, float]:
    """Expand '<n> <fraction phrase>' into the number table.

    Recipes are full of these — "two and a quarter cups flour", "deux et demi
    tasses". Without the expansion the fraction is left stranded in the ingredient
    *name* ("and a quarter cup all purpose flour") and the amount is silently wrong.
    """
    out = dict(pairs)
    for word, value in pairs.items():
        if value != int(value) or value < 1:
            continue
        for phrase, extra in fraction_suffixes.items():
            out[f"{word} {phrase}"] = value + extra
    return out


_EN_ONES = {
    "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
    "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15,
    "twenty": 20,
}
_FR_ONES = {
    "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6,
    "sept": 7, "huit": 8, "neuf": 9, "dix": 10, "douze": 12, "quinze": 15, "vingt": 20,
}
_DE_ONES = {
    "ein": 1, "eine": 1, "einen": 1, "zwei": 2, "drei": 3, "vier": 4, "fünf": 5,
    "sechs": 6, "sieben": 7, "acht": 8, "neun": 9, "zehn": 10, "zwölf": 12,
    "fünfzehn": 15, "zwanzig": 20,
}
_RO_ONES = {
    "un": 1, "o": 1, "doi": 2, "două": 2, "trei": 3, "patru": 4, "cinci": 5,
    "șase": 6, "șapte": 7, "opt": 8, "nouă": 9, "zece": 10, "doisprezece": 12,
    "cincisprezece": 15, "douăzeci": 20,
}

_THIRD = 1 / 3
_TWO_THIRDS = 2 / 3

LEXICONS: dict[str, Lexicon] = {
    "en": Lexicon(
        units={
            "tablespoons": "tbsp", "tablespoon": "tbsp",
            "teaspoons": "tsp", "teaspoon": "tsp",
            "cups": "cup", "cup": "cup",
            "pounds": "lb", "pound": "lb",
            "ounces": "oz", "ounce": "oz",
            "grams": "g", "gram": "g",
            "kilograms": "kg", "kilogram": "kg", "kilos": "kg", "kilo": "kg",
            "millilitres": "ml", "milliliters": "ml", "millilitre": "ml", "milliliter": "ml",
            "centilitres": "cl", "centiliters": "cl", "centilitre": "cl", "centiliter": "cl",
            "decilitres": "dl", "deciliters": "dl", "decilitre": "dl", "deciliter": "dl",
            "litres": "l", "liters": "l", "litre": "l", "liter": "l",
        },
        numbers={
            **_ones(_EN_ONES, {"and a half": 0.5, "and a quarter": 0.25, "and three quarters": 0.75, "and a third": _THIRD, "and two thirds": _TWO_THIRDS}),
            "half a": 0.5, "a half": 0.5, "half": 0.5,
            "a quarter of a": 0.25, "a quarter": 0.25, "quarter": 0.25,
            "three quarters of a": 0.75, "three quarters": 0.75,
            "a third of a": _THIRD, "a third": _THIRD, "two thirds": _TWO_THIRDS,
            "a": 1, "an": 1,
        },
        half_suffixes={"and a half": 0.5, "and a quarter": 0.25,
                       "and three quarters": 0.75, "and a third": _THIRD},
        pinch=("a pinch of", "a pinch", "pinch of", "a dash of", "a dash"),
        to_taste=("to taste", "season to taste"),
        connectors=("of",),
        approx=("about", "roughly", "around", "approximately"),
        categories={},
    ),
    "fr": Lexicon(
        units={
            "cuillères à soupe": "tbsp", "cuillère à soupe": "tbsp",
            "cuillères à table": "tbsp", "cuillère à table": "tbsp",
            "c. à s.": "tbsp", "c à s": "tbsp", "cas": "tbsp",
            "cuillères à café": "tsp", "cuillère à café": "tsp",
            "cuillères à thé": "tsp", "cuillère à thé": "tsp",
            "c. à c.": "tsp", "c à c": "tsp", "cac": "tsp",
            "tasses": "cup", "tasse": "cup",
            "grammes": "g", "gramme": "g",
            "kilogrammes": "kg", "kilogramme": "kg", "kilos": "kg", "kilo": "kg",
            "millilitres": "ml", "millilitre": "ml",
            "centilitres": "cl", "centilitre": "cl",
            "decilitres": "dl", "decilitre": "dl",
            "litres": "l", "litre": "l",
            # A French *livre* is 500 g, not a pound.
            "livres": "halfkilo", "livre": "halfkilo",
        },
        numbers={
            **_ones(_FR_ONES, {"et demi": 0.5, "et demie": 0.5, "et quart": 0.25, "et un quart": 0.25}),
            "un demi": 0.5, "une demie": 0.5, "demi": 0.5, "demie": 0.5,
            "un quart de": 0.25, "un quart": 0.25, "quart": 0.25,
            "trois quarts de": 0.75, "trois quarts": 0.75,
            "un tiers de": _THIRD, "un tiers": _THIRD, "deux tiers": _TWO_THIRDS,
        },
        half_suffixes={"et demi": 0.5, "et demie": 0.5,
                       "et quart": 0.25, "et un quart": 0.25},
        pinch=("une pincée de", "une pincée", "pincée de", "pincée"),
        to_taste=("à votre goût", "selon le goût", "selon votre goût", "au goût"),
        connectors=("de la", "de l'", "des", "du", "d'", "de"),
        approx=("environ", "à peu près"),
        decimal_comma=True,
        categories={
            "sauces": "Sauces & Salsas", "sauce": "Sauces & Salsas",
            "marinades": "Marinades", "marinade": "Marinades",
            "salades": "Salads", "salade": "Salads",
            "soupes": "Soups & Stews", "soupe": "Soups & Stews", "potages": "Soups & Stews",
            "sandwichs": "Sandwiches", "sandwich": "Sandwiches",
            "pâtes": "Pasta",
            # Careful: French *entrée* is a starter. The English category "Entrées"
            # is the main course, so these two must not be matched to each other.
            "plats principaux": "Entrées", "plat principal": "Entrées", "plats": "Entrées",
            "accompagnements": "Sides", "accompagnement": "Sides", "garnitures": "Sides",
            "petit-déjeuner": "Breakfast", "petit déjeuner": "Breakfast",
            "desserts": "Baking & Desserts", "dessert": "Baking & Desserts",
            "pâtisserie": "Baking & Desserts", "boulangerie": "Baking & Desserts",
            "boissons": "Drinks", "boisson": "Drinks",
            "entrées": "Appetizers & Preserves", "entrée": "Appetizers & Preserves",
            "apéritifs": "Appetizers & Preserves", "conserves": "Appetizers & Preserves",
            "référence": "Reference",
        },
    ),
    "de": Lexicon(
        units={
            "esslöffel": "tbsp", "suppenlöffel": "tbsp", "el": "tbsp", "essl.": "tbsp",
            "teelöffel": "tsp", "kaffeelöffel": "tsp", "tl": "tsp", "teel.": "tsp",
            "tassen": "cup", "tasse": "cup", "becher": "cup",
            "gramm": "g",
            "kilogramm": "kg", "kilo": "kg",
            "milliliter": "ml",
            "zentiliter": "cl", "deziliter": "dl",
            "liter": "l",
            # A German *Pfund* is 500 g, not a pound.
            "pfund": "halfkilo",
        },
        numbers={
            **_DE_ONES,
            # German writes these as one word, so they never survive tokenisation.
            "anderthalb": 1.5, "eineinhalb": 1.5, "zweieinhalb": 2.5,
            "dreieinhalb": 3.5, "viereinhalb": 4.5, "fünfeinhalb": 5.5,
            "ein halber": 0.5, "eine halbe": 0.5, "ein halbes": 0.5, "halb": 0.5,
            "ein viertel": 0.25, "viertel": 0.25,
            "dreiviertel": 0.75, "drei viertel": 0.75,
            "ein drittel": _THIRD, "zwei drittel": _TWO_THIRDS,
        },
        pinch=("eine prise", "prise", "eine messerspitze", "messerspitze"),
        to_taste=("nach geschmack", "nach belieben"),
        approx=("etwa", "ca.", "circa", "ungefähr"),
        decimal_comma=True,
        categories={
            "saucen": "Sauces & Salsas", "soßen": "Sauces & Salsas", "sauce": "Sauces & Salsas",
            "marinaden": "Marinades", "marinade": "Marinades",
            "salate": "Salads", "salat": "Salads",
            "suppen": "Soups & Stews", "suppe": "Soups & Stews", "eintöpfe": "Soups & Stews",
            "sandwiches": "Sandwiches", "brote": "Sandwiches",
            "nudeln": "Pasta", "pasta": "Pasta",
            "hauptgerichte": "Entrées", "hauptgericht": "Entrées", "hauptspeisen": "Entrées",
            "beilagen": "Sides", "beilage": "Sides",
            "frühstück": "Breakfast",
            "backen": "Baking & Desserts", "desserts": "Baking & Desserts",
            "nachspeisen": "Baking & Desserts", "kuchen": "Baking & Desserts",
            "getränke": "Drinks",
            "vorspeisen": "Appetizers & Preserves", "vorspeise": "Appetizers & Preserves",
            "eingemachtes": "Appetizers & Preserves",
            "referenz": "Reference",
        },
    ),
    "ro": Lexicon(
        units={
            "linguri": "tbsp", "lingură": "tbsp",
            "lingurițe": "tsp", "linguriță": "tsp",
            "căni": "cup", "cană": "cup",
            "grame": "g", "gram": "g",
            "kilograme": "kg", "kilogram": "kg", "kile": "kg", "kil": "kg",
            "mililitri": "ml", "mililitru": "ml",
            "litri": "l", "litru": "l",
        },
        numbers={
            **_ones(_RO_ONES, {"și jumătate": 0.5, "si jumatate": 0.5, "și un sfert": 0.25}),
            "o jumătate de": 0.5, "o jumătate": 0.5, "jumătate de": 0.5, "jumătate": 0.5,
            "un sfert de": 0.25, "un sfert": 0.25, "sfert": 0.25,
            "trei sferturi de": 0.75, "trei sferturi": 0.75,
            "o treime de": _THIRD, "o treime": _THIRD, "două treimi": _TWO_THIRDS,
        },
        half_suffixes={"și jumătate": 0.5, "si jumatate": 0.5, "și un sfert": 0.25},
        pinch=("un praf de", "un praf", "praf de", "un vârf de cuțit de", "un vârf de cuțit",
               "vârf de cuțit"),
        to_taste=("după gust", "dupa gust"),
        connectors=("de",),
        approx=("aproximativ", "cam", "circa"),
        decimal_comma=True,
        categories={
            "sosuri": "Sauces & Salsas", "sos": "Sauces & Salsas",
            "marinate": "Marinades", "marinadă": "Marinades",
            "salate": "Salads", "salată": "Salads",
            "supe": "Soups & Stews", "supă": "Soups & Stews",
            "ciorbe": "Soups & Stews", "ciorbă": "Soups & Stews", "tocănițe": "Soups & Stews",
            "sandvișuri": "Sandwiches", "sandviș": "Sandwiches",
            "paste": "Pasta",
            "feluri principale": "Entrées", "fel principal": "Entrées", "principale": "Entrées",
            "garnituri": "Sides", "garnitură": "Sides",
            "mic dejun": "Breakfast",
            "deserturi": "Baking & Desserts", "desert": "Baking & Desserts",
            "prăjituri": "Baking & Desserts", "cozonaci": "Baking & Desserts",
            "băuturi": "Drinks", "băutură": "Drinks",
            "aperitive": "Appetizers & Preserves", "aperitiv": "Appetizers & Preserves",
            "conserve": "Appetizers & Preserves", "murături": "Appetizers & Preserves",
            "referință": "Reference",
        },
    ),
}

CATEGORY_ORDER = (
    "Sauces & Salsas", "Marinades", "Salads", "Soups & Stews", "Sandwiches",
    "Pasta", "Entrées", "Sides", "Breakfast", "Baking & Desserts",
    "Drinks", "Appetizers & Preserves", "Reference",
)


def _lex(lang: str) -> Lexicon:
    return LEXICONS.get(lang, LEXICONS["en"])


# Compiled once per language: (pattern, replacement-callable) applied in order.
def _compile(lang: str):
    lex = _lex(lang)
    units = re.compile(rf"(?<![^\W\d_])({_alternation(lex.units)})(?![^\W\d_])", re.I)
    unit_lookup = {}
    for phrase, canonical in lex.units.items():
        for variant in _variants(phrase):
            unit_lookup[re.sub(r"\s+", " ", variant.lower())] = canonical

    numbers = re.compile(rf"^\s*({_alternation(lex.numbers)})(?![^\W\d_])", re.I)
    number_lookup = {}
    for phrase, value in lex.numbers.items():
        for variant in _variants(phrase):
            number_lookup[re.sub(r"\s+", " ", variant.lower())] = value

    # "2 and a half cups", but also "a cup and a half" — English, French and Romanian all
    # let the fraction follow the unit, and that word order used to strand it in the
    # ingredient name with the amount silently short by up to 0.75.
    # Units are already canonical by the time this runs, so the optional middle group is
    # matched against UNIT_MAP's values rather than the spoken phrases.
    canonical_units = "|".join(
        re.escape(u) for u in sorted(set(UNIT_MAP.values()), key=len, reverse=True)
    )
    halves = (
        re.compile(
            rf"^\s*({NUM})\s+(?:({canonical_units})\s+)?({_alternation(lex.half_suffixes)})"
            rf"(?![^\W\d_])",
            re.I,
        )
        if lex.half_suffixes
        else None
    )
    half_lookup = {}
    for phrase, value in lex.half_suffixes.items():
        for variant in _variants(phrase):
            half_lookup[re.sub(r"\s+", " ", variant.lower())] = value
    pinch = (re.compile(rf"(?<![^\W\d_])(?:{_alternation(lex.pinch)})(?![^\W\d_])\s*", re.I)
             if lex.pinch else None)
    to_taste = (re.compile(rf"[,;]?\s*(?<![^\W\d_])(?:{_alternation(lex.to_taste)})(?![^\W\d_])\s*", re.I)
                if lex.to_taste else None)
    # Strip the partitive glue between a unit and the name: "200 g de farine" → "200 g farine".
    # The trailing boundary must tolerate elision — French "d'huile" has no space after "d'".
    connectors = (
        re.compile(
            rf"(?<=\s)({'|'.join(re.escape(u) for u in sorted(set(UNIT_MAP.values()), key=len, reverse=True))})"
            rf"\s+(?:{_alternation(lex.connectors)})(?:(?<=')|(?![^\W\d_]))\s*",
            re.I,
        )
        if lex.connectors
        else None
    )
    approx = (re.compile(rf"(?<![^\W\d_])(?:{_alternation(lex.approx)})(?![^\W\d_])\s*", re.I)
              if lex.approx else None)
    return dict(lex=lex, units=units, unit_lookup=unit_lookup, numbers=numbers,
                number_lookup=number_lookup, halves=halves, half_lookup=half_lookup,
                pinch=pinch, to_taste=to_taste, connectors=connectors, approx=approx)


_COMPILED = {lang: _compile(lang) for lang in LANGS}


# ---------------------------------------------------------------- spoken pre-pass

def normalise_spoken(text: str, lang: str = "en") -> str:
    """Rewrite a dictated line into the English-canonical form the core parser reads.

    "zweieinhalb Esslöffel Paprikapulver" → "2.5 tbsp Paprikapulver"
    "200 grammes de farine"               → "200 g farine"
    "1,5 kg de roșii"                     → "1.5 kg roșii"

    Ingredient names are never touched beyond the glue words in front of them.
    """
    c = _COMPILED.get(lang, _COMPILED["en"])
    lex = c["lex"]

    text = unicodedata.normalize("NFC", text).strip()
    text = "".join(_CEDILLA_FIX.get(ch, ch) for ch in text)

    # ¾ → 3/4, and 1½ → 1 1/2
    for glyph, ascii_form in _VULGAR.items():
        text = re.sub(rf"(?<=\d)\s*{glyph}", f" {ascii_form}", text)
        text = text.replace(glyph, ascii_form)

    if lex.decimal_comma:
        text = re.sub(r"(?<=\d),(?=\d)", ".", text)

    if c["approx"] is not None:
        text = c["approx"].sub("~", text, count=1)

    # Unit phrases → canonical abbreviations, before number words so that
    # "un quart de tasse" still finds its unit.
    def _unit_sub(m: re.Match) -> str:
        key = re.sub(r"\s+", " ", m.group(1).lower())
        return c["unit_lookup"].get(key, m.group(1))

    text = c["units"].sub(_unit_sub, text)

    # Leading number phrase → digits. Only at the start: an ingredient line is
    # "<quantity> <unit> <name>", and substituting mid-string would mangle names.
    m = c["numbers"].match(text)
    if m:
        key = re.sub(r"\s+", " ", m.group(1).lower())
        value = c["number_lookup"].get(key)
        if value is not None:
            text = f"{_fmt(value)} {text[m.end():].lstrip()}".strip()

    # "2 et demi" / "2 și jumătate", and the unit-in-the-middle word order:
    # "1 cup and a half" / "o cană și jumătate" / "une tasse et demie".
    if c["halves"] is not None:
        m = c["halves"].match(text)
        if m:
            key = re.sub(r"\s+", " ", m.group(3).lower())
            extra = c["half_lookup"].get(key, 0.5)
            unit = f"{m.group(2)} " if m.group(2) else ""
            text = f"{_fmt(float(Fraction(m.group(1))) + extra)} {unit}{text[m.end():].lstrip()}".strip()

    # Partitive glue between the unit and the name: "200 g de farine" → "200 g farine".
    if c["connectors"] is not None:
        text = c["connectors"].sub(r"\1 ", text, count=1)

    return re.sub(r"\s{2,}", " ", text).strip()


def _fmt(value: float) -> str:
    return str(int(value)) if value == int(value) else f"{value:g}"


# ---------------------------------------------------------------- core parser

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


def parse_ingredient(
    line: str,
    section: str | None = None,
    lang: str = "en",
    spoken: bool = False,
) -> dict:
    """One ingredient line → ``{amount, unit, name[, section]}``. amount 0 = to taste.

    ``spoken=True`` runs the dictation pre-pass and applies the pinch/to-taste rule.
    The default is the printed-text behaviour the seed importer depends on.
    """
    text = line.strip().lstrip("-").strip()
    forced_zero = False

    if spoken:
        c = _COMPILED.get(lang, _COMPILED["en"])
        # Detect the markers on the raw text, before unit rewriting can eat "pincée".
        if c["pinch"] is not None and c["pinch"].search(text):
            text = c["pinch"].sub("", text, count=1)
            forced_zero = True
        if c["to_taste"] is not None and c["to_taste"].search(text):
            text = c["to_taste"].sub(" ", text).strip(" ,;")
            forced_zero = True
        text = normalise_spoken(text, lang)

    row: dict = {"amount": 0, "unit": "", "name": text}

    juice = re.match(rf"(?:Juice|Zest) of (~?{NUM})(?:{RANGE_SEP}(~?{NUM}))?\s+(.+)", text, re.I)
    if juice:
        lo = _num(juice.group(1).lstrip("~"))
        hi = _num(juice.group(2).lstrip("~")) if juice.group(2) else lo
        verb = "juiced" if text.lower().startswith("juice") else "zested"
        row.update(amount=(lo + hi) / 2, unit="", name=f"{juice.group(3).rstrip(',')}, {verb}")
    else:
        m = re.match(
            rf"~?({NUM})\s*({WORD})?\.?\s*(?:{RANGE_SEP}\s*~?({NUM})\s*({WORD})?\.?)?\s+(.*)",
            text,
        )
        # ranges like "1.5–2 lb" parse as: 1.5, unit=None, 2, "lb", rest — normalise both sides
        if not m:
            m = re.match(rf"~?({NUM})\s*{RANGE_SEP}\s*~?({NUM})\s*({WORD})?\.?\s+(.*)", text)
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

    if forced_zero:
        # "to taste" and "a pinch of" are amount 0 by contract — an em dash that
        # never scales. Never guess a quantity for them (CLAUDE.md §5).
        row["amount"] = 0
    row["name"] = row["name"].strip(" ,;")
    if section:
        row["section"] = section
    return row


def split_run_on(line: str, lang: str = "en") -> list[str]:
    """Break a punctuation-free dictated run into one ingredient per entry.

    Speech recognition only inserts full stops if the speaker says "period", so a
    dictated ingredient list usually arrives as one long string:

        "two pounds beef chuck three onions four cloves of garlic"

    Splitting on punctuation yields one ingredient. Quantities are the reliable
    boundary instead — an ingredient nearly always starts with a number — so this
    cuts before each quantity after the first, in whichever language.

    Guards against cutting inside a quantity: mixed fractions ("1 1/2 cups"),
    ranges ("2 to 3 cloves"), and a number that is part of the name ("1-inch
    cubes", "2 cm dice") all stay whole.
    """
    text = re.sub(r"\s+", " ", (line or "").strip())
    if not text:
        return []

    lex = _lex(lang)
    number_words = {w.split()[0] for w in lex.numbers}          # first token of each phrase
    connectors = {c.rstrip(" '") for c in lex.connectors} | {"to", "or", "and"}
    units = set(UNIT_MAP) | {u for u in lex.units}

    tokens = text.split(" ")
    starts = [0]
    for i in range(1, len(tokens)):
        tok = tokens[i].lower().strip(",;")
        prev = tokens[i - 1].lower().strip(",;")

        is_number = bool(re.fullmatch(r"~?\d+(?:[.,]\d+)?(?:/\d+)?", tok)) or tok in number_words
        if not is_number:
            continue
        # Second half of a mixed fraction, a range, or a hyphenated measurement.
        if re.fullmatch(r"~?\d+(?:[.,]\d+)?", prev) or prev in connectors or prev in number_words:
            continue
        # A number gluing onto the previous word ("1-inch", "2 cm") is part of a name.
        if i + 1 < len(tokens) and re.match(r"^(inch|cm|mm|inches|centimet)", tokens[i + 1].lower()):
            continue
        # Do not cut so soon that the previous piece has no name in it.
        if i - starts[-1] < 2:
            continue
        starts.append(i)

    if len(starts) < 2:
        return [text]

    pieces = []
    for a, b in zip(starts, starts[1:] + [len(tokens)]):
        piece = " ".join(tokens[a:b]).strip(" ,;")
        if piece:
            pieces.append(piece)
    return pieces


def parse_lines(lines: list[str], lang: str = "en", spoken: bool = True) -> list[dict]:
    """Parse a dictated block, skipping blank lines.

    When spoken, a line carrying several quantities is a run of ingredients the
    speech recogniser never punctuated — split it rather than storing the lot as
    one ingredient named after the whole sentence.
    """
    out: list[dict] = []
    for line in lines:
        if not line.strip():
            continue
        parts = split_run_on(line, lang) if spoken else [line]
        out.extend(parse_ingredient(p, lang=lang, spoken=spoken) for p in parts)
    return out


# ---------------------------------------------------------------- slug

_SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")


def slugify(title: str) -> str:
    """'Vișinată' → 'visinata'. Matches the API's own ``^[a-z0-9][a-z0-9-]*$``.

    Slugs are the QR contract (CLAUDE.md §5) — generated once, never renamed.
    """
    slug = strip_diacritics(title).lower()
    slug = re.sub(r"[^a-z0-9]+", "-", slug).strip("-")
    slug = re.sub(r"-{2,}", "-", slug)
    return slug


def is_valid_slug(slug: str) -> bool:
    return bool(_SLUG_RE.match(slug))


# ---------------------------------------------------------------- category

def match_category(spoken: str, lang: str = "en") -> str | None:
    """A dictated category name → a CATEGORY_ORDER entry, or None if nothing matches."""
    probe = strip_diacritics(spoken).lower().strip(" .,")
    if not probe:
        return None

    for canonical in CATEGORY_ORDER:
        if strip_diacritics(canonical).lower() == probe:
            return canonical

    for table in (_lex(lang).categories, *(l.categories for l in LEXICONS.values())):
        for phrase, canonical in table.items():
            if strip_diacritics(phrase).lower() == probe:
                return canonical

    # Loose fall-back: the probe is contained in an English category name
    # ("salsa" → "Sauces & Salsas", "dessert" → "Baking & Desserts").
    for canonical in CATEGORY_ORDER:
        if probe in strip_diacritics(canonical).lower():
            return canonical
    return None
