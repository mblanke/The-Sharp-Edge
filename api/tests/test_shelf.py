"""Book identity — the table the eval and attribution both trust.

Offline by design: these assert the *mapping*, not the corpus, so they run on every PR
without the tailnet. The path fixtures below are real `source_path` values taken from the
Qdrant facet over the `Cooking` folder — if a glob stops matching them, retrieval will
silently start crediting the wrong book, which is the failure this file exists to catch.
"""

import pytest

from app.services.shelf import (
    AMBIGUOUS,
    BOOKS,
    authorities_in,
    book_by_id,
    resolve_path,
)

ROOT = "/mnt/references/Cooking/"

# (real indexed source_path suffix, expected book id)
REAL_PATHS = [
    ("Culinary Institute of America - The Professional Chef (9th edition).txt", "professional-chef"),
    (
        "The Food Lab_ Better Home Cooking Through Science by J. Kenji Lopez-Alt EPUB/"
        "The Food Lab_ Better Home Cooking Through Science.epub",
        "food-lab",
    ),
    ("_acquired/On Food and Cooking.epub", "on-food-and-cooking"),
    ("_acquired/The Book of Household Management.epub", "household-management"),
    ("_acquired/The Physiology of Taste.epub", "physiology-of-taste"),
    ("_acquired/The Noma Guide to Fermentation.epub", "noma-fermentation"),
    ("_acquired/The Art of Cookery Made Plain and Easy.epub", "art-of-cookery"),
    ("_acquired/The Virginia Housewife.epub", "virginia-housewife"),
    ("J Kenji López-Alt - The Wok- Recipes and Techniques (azw3 epub mobi)/x.epub", "the-wok"),
    (
        "The Fundamental Techniques of Classic Cuisine By French Culinary Institute/x.epub",
        "fci-cuisine",
    ),
    (
        "The Fundamental Techniques of Classic Pastry Arts by French Culinary Institute EPUB/x.epub",
        "fci-pastry",
    ),
    ("The French Laundry, Per Se/The French Laundry, Per Se.epub", "french-laundry"),
    (
        "MasterClass - Thomas Keller Teaches Cooking Techniques III/11.Sous Vide Cooking - Turbot.mkv",
        "keller-masterclass",
    ),
    (
        "Thomas Keller Teaches Cooking Techniques I/24 Poached Eggs.1080p.WebRip.10Bit."
        "H265-DawgFather.mkv",
        "keller-masterclass",
    ),
    ("Institut Paul Bocuse Gastronomique- The definitive step-by-step guide.txt", "bocuse"),
    ("Fuchsia Dunlop - The Food of Sichuan (azw3 epub mobi pdf)/x.epub", "food-of-sichuan"),
    ("Franklin Barbecue - Aaron Franklin/Franklin Barbecue - Aaron Franklin.epub", "franklin-barbecue"),
    ("Medium Raw by Anthony Bourdain EPUB/Medium Raw by Anthony Bourdain.epub", "medium-raw"),
    (
        "The.Great.Courses.Plus.-.Food.A.Cultural.Culinary.History.2013.BOOKWARE-LERNSTUF/"
        "Guidebook/000-course_guidebook.pdf",
        "great-courses-food",
    ),
    ("Modernist Cuisine Volume 1-6/Modernist Cuisine.txt", "modernist-cuisine"),
    (
        "[food] Bread_ A Baker's Book of Techniques and Recipes, 3rd Edition by Jeffrey "
        "Hamelman PDF/_ DOWNLOAD.txt",
        "hamelman-bread",
    ),
]


@pytest.mark.parametrize("suffix,expected", REAL_PATHS)
def test_real_indexed_paths_resolve(suffix, expected):
    assert resolve_path(ROOT + suffix) == expected


def test_release_group_spam_belongs_to_no_book():
    """`_sourcing-report.md` is indexed and is not a book. None is the right answer."""
    assert resolve_path(ROOT + "_acquired/_sourcing-report.md") is None
    assert resolve_path("") is None


def test_every_book_id_is_unique_and_resolvable():
    ids = [b.id for b in BOOKS]
    assert len(ids) == len(set(ids))
    for book_id in ids:
        assert book_by_id(book_id) is not None


# --- authority detection -------------------------------------------------------------
# The failure being prevented: six identical asks of "how does Escoffier build an
# espagnole?" were each answered "according to Escoffier's method…" and cited the CIA and
# the FCI. There is no Escoffier on this shelf.


def test_absent_authority_is_named_with_no_books():
    found = authorities_in("How does Escoffier build an espagnole?")
    assert found == [("Escoffier", ())]


def test_present_authority_resolves_to_its_books():
    assert authorities_in("How does the CIA make french onion soup") == [
        ("The Professional Chef", ("professional-chef",))
    ]
    # filed under its title, not its author — the case that scored 0 in the old eval
    assert authorities_in("what does McGee say about gluten") == [
        ("On Food and Cooking", ("on-food-and-cooking",))
    ]


def test_authority_naming_several_books_returns_all():
    _, ids = authorities_in("sous vide short ribs per Keller")[0]
    assert set(ids) >= {"french-laundry", "keller-masterclass"}


@pytest.mark.parametrize(
    "question",
    [
        "maillard reaction temperature",  # a chemist, but this is a technique question
        "chantilly cream method",
        "how to make a bechamel",
        "beef bourguignon timing",
        "how many pages should I read",  # must not match the author "Page"
        "mother sauces of French cuisine",  # names no authority at all
    ],
)
def test_ambiguous_and_bare_technique_questions_name_nobody(question):
    assert authorities_in(question) == []


def test_ambiguous_names_are_never_authorities():
    for name in AMBIGUOUS:
        assert authorities_in(f"a question about {name}") == []
