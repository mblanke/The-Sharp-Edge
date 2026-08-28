"""What is on the shelf, and who wrote it — one table, three consumers.

Book identity used to live in three places that disagreed. The retrieval eval matched
`source_path` substrings, and its guesses were wrong in ways nobody could see: `mcgee`
matched **zero** indexed files, because *On Food and Cooking* is filed under its title;
`food-lab` matched zero, because the real path is `The Food Lab_ Better Home Cooking…`;
and `gf` matched **25** files, because a video release group is called `DawgFather`. Four
of fifteen golden questions could never credit the right book, and one scored a hit off
any Keller lecture. A "53% hit rate" measured spelling, not retrieval.

So identity is written down once, here, and everything reads it:

* `resolve_path` — an indexed `source_path` → a canonical book id. The eval asserts on
  ids, so a filename is no longer an API.
* `authorities_in` — free text → the books an authority is named in. `services/citations`
  uses it to stop the model attributing a passage to an author who isn't on the shelf.
* `BOOKS` — the display titles the coverage report and the shelf selector show.

Adding a book means adding one row. Nothing else in the codebase should learn a filename.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from app.services.lexical import _fold

__all__ = [
    "Book",
    "BOOKS",
    "AMBIGUOUS",
    "resolve_path",
    "book_by_id",
    "authorities_in",
    "known_authority_ids",
]


@dataclass(frozen=True)
class Book:
    """One work, however many files it happens to be stored as."""

    id: str
    title: str
    # Case-folded substrings of an indexed source_path. Any match claims the file.
    globs: tuple[str, ...]
    # Surnames/titles a cook would name this book by ("how does McGee explain…").
    authorities: tuple[str, ...] = field(default_factory=tuple)


# Every row's globs were checked against the 64 source files actually indexed under
# `Cooking` (Qdrant facet on source_path). Do not guess a glob — read the facet.
BOOKS: tuple[Book, ...] = (
    Book(
        "professional-chef",
        "The Professional Chef — Culinary Institute of America",
        ("culinary institute of america",),
        ("cia", "professional chef"),
    ),
    Book(
        "food-lab",
        "The Food Lab — J. Kenji López-Alt",
        ("the food lab_",),
        ("kenji", "lopez-alt", "lopez alt", "food lab"),
    ),
    Book("the-wok", "The Wok — J. Kenji López-Alt", ("the wok-",), ("kenji", "lopez-alt")),
    Book(
        "on-food-and-cooking",
        "On Food and Cooking — Harold McGee",
        ("on food and cooking",),
        ("mcgee",),
    ),
    Book(
        "fci-cuisine",
        "Fundamental Techniques of Classic Cuisine — FCI",
        ("fundamental techniques of classic cuisine",),
        ("fci", "french culinary institute"),
    ),
    Book(
        "fci-pastry",
        "Fundamental Techniques of Classic Pastry Arts — FCI",
        ("fundamental techniques of classic pastry",),
        ("fci", "french culinary institute"),
    ),
    Book(
        "french-laundry",
        "The French Laundry / Per Se — Thomas Keller",
        ("the french laundry",),
        ("keller", "french laundry", "per se"),
    ),
    Book(
        "keller-masterclass",
        "Thomas Keller Teaches Cooking Techniques",
        ("thomas keller teaches", "masterclass - thomas keller"),
        ("keller",),
    ),
    Book(
        "bocuse",
        "Institut Paul Bocuse Gastronomique",
        ("institut paul bocuse",),
        ("bocuse",),
    ),
    Book(
        "food-of-sichuan",
        "The Food of Sichuan — Fuchsia Dunlop",
        ("fuchsia dunlop",),
        ("dunlop", "sichuan"),
    ),
    Book(
        "franklin-barbecue",
        "Franklin Barbecue — Aaron Franklin",
        ("franklin barbecue",),
        ("franklin",),
    ),
    Book(
        "noma-fermentation",
        "The Noma Guide to Fermentation",
        ("noma guide to fermentation",),
        ("redzepi", "noma"),
    ),
    Book(
        "household-management",
        "The Book of Household Management — Mrs Beeton",
        ("book of household management",),
        ("beeton",),
    ),
    Book(
        "art-of-cookery",
        "The Art of Cookery Made Plain and Easy — Hannah Glasse",
        ("art of cookery made plain",),
        ("glasse",),
    ),
    Book(
        "physiology-of-taste",
        "The Physiology of Taste — Brillat-Savarin",
        ("physiology of taste",),
        ("brillat-savarin", "brillat savarin"),
    ),
    Book(
        "virginia-housewife",
        "The Virginia Housewife — Mary Randolph",
        ("virginia housewife",),
        ("randolph",),
    ),
    Book(
        "great-courses-food",
        "Food: A Cultural Culinary History — The Great Courses",
        ("great.courses",),
        ("great courses",),
    ),
    Book(
        "medium-raw",
        "Medium Raw — Anthony Bourdain",
        ("medium raw",),
        ("bourdain",),
    ),
    Book(
        "kitchen-confidential",
        "Kitchen Confidential — Anthony Bourdain",
        ("kitchen confidential",),
        ("bourdain",),
    ),
    Book(
        "essential-cooks-kitchen",
        "The Essential Cook's Kitchen",
        ("essential cook",),
        (),
    ),
    Book(
        "culinary-scrapbook",
        "The Culinary Scrapbook",
        ("culinary scrapbook",),
        (),
    ),
    # --- On the shelf but effectively unindexed. Kept so coverage can name them and the
    # eval can report ABSENT rather than counting them as retrieval failures. ---
    Book(
        "modernist-cuisine",
        "Modernist Cuisine — Nathan Myhrvold",
        ("modernist cuisine",),
        ("myhrvold", "modernist cuisine"),
    ),
    Book(
        "modernist-bread",
        "Modernist Bread — Nathan Myhrvold",
        ("modernist bread",),
        ("myhrvold",),
    ),
    Book(
        "under-pressure",
        "Under Pressure: Cooking Sous Vide — Thomas Keller",
        ("under.pressure", "under pressure"),
        ("keller",),
    ),
    Book(
        "flavor-bible",
        "The Flavor Bible — Page & Dornenburg",
        ("flavor.bible", "flavor bible"),
        ("page", "dornenburg", "flavor bible"),
    ),
    Book(
        "fat-duck",
        "The Fat Duck Cookbook — Heston Blumenthal",
        ("fat duck",),
        ("blumenthal", "heston"),
    ),
    Book(
        "japanese-cooking",
        "Japanese Cooking: A Simple Art — Shizuo Tsuji",
        ("japanese cooking",),
        ("tsuji",),
    ),
    Book(
        "hamelman-bread",
        "Bread — Jeffrey Hamelman",
        ("hamelman",),
        ("hamelman",),
    ),
)

# Authorities a cook might name that are NOT on this shelf at all. Listed explicitly so
# `/ask` can say "there is no Escoffier here" instead of quietly answering in his name
# from somebody else's book — the failure this module exists to stop.
ABSENT_AUTHORITIES: dict[str, str] = {
    "escoffier": "Escoffier",
    "larousse": "Larousse Gastronomique",
    "careme": "Carême",
    "julia child": "Julia Child",
    "pepin": "Jacques Pépin",
    "ruhlman": "Michael Ruhlman",
    "peterson": "James Peterson",
    "hazan": "Marcella Hazan",
    "elizabeth david": "Elizabeth David",
    "james beard": "James Beard",
    "adria": "Ferran Adrià",
    "bouchon": "Bouchon",
}

# Names that are also techniques or preparations. Matching these as authorities produces
# nonsense ("maillard reaction temperature" is not a question about a person), so they are
# never treated as an authority reference. Regression-tested.
AMBIGUOUS: frozenset[str] = frozenset(
    {
        "maillard",
        "chantilly",
        "bechamel",
        "mornay",
        "bourguignon",
        "florentine",
        "hollandaise",
        "dijon",
        "bordelaise",
        "lyonnaise",
        "parmentier",
        "wellington",
        "napoleon",
        "melba",
        "pavlova",
        "carpaccio",
        "stroganoff",
        "diane",
        "romanoff",
        "wok",
        "page",
    }
)

_BY_ID: dict[str, Book] = {b.id: b for b in BOOKS}


def book_by_id(book_id: str) -> Book | None:
    return _BY_ID.get(book_id)


def resolve_path(source_path: str) -> str | None:
    """An indexed ``source_path`` → canonical book id, or None if nothing claims it.

    None is a real answer, not a failure: the shelf carries release-group spam
    ("free audiobook version.txt", "How you can help Team-FTU.txt") that is indexed and
    belongs to no book.
    """
    folded = _fold(source_path or "")
    if not folded:
        return None
    for book in BOOKS:
        if any(g in folded for g in book.globs):
            return book.id
    return None


def known_authority_ids() -> dict[str, tuple[str, ...]]:
    """Authority phrase → the book ids it names. Longest phrases first when matching."""
    out: dict[str, list[str]] = {}
    for book in BOOKS:
        for name in book.authorities:
            out.setdefault(_fold(name), []).append(book.id)
    return {k: tuple(v) for k, v in out.items()}


_AUTHORITIES = known_authority_ids()
# Longest first so "french culinary institute" wins over a bare surname inside it.
_ORDERED = sorted(
    [*_AUTHORITIES, *ABSENT_AUTHORITIES], key=len, reverse=True
)


def authorities_in(text: str) -> list[tuple[str, tuple[str, ...]]]:
    """Authorities named in ``text``, as (display name, book ids).

    An empty id tuple means "named, but no such book on this shelf" — the Escoffier case.
    Matching is whole-word on folded text, so "pages" never matches the author "Page" and
    a substring can't manufacture a reference.
    """
    folded = _fold(text or "")
    found: list[tuple[str, tuple[str, ...]]] = []
    seen: set[str] = set()
    for phrase in _ORDERED:
        if phrase in AMBIGUOUS or phrase in seen:
            continue
        if not re.search(rf"(?<!\w){re.escape(phrase)}(?!\w)", folded):
            continue
        seen.add(phrase)
        if phrase in _AUTHORITIES:
            ids = _AUTHORITIES[phrase]
            display = _BY_ID[ids[0]].title.split(" — ")[0]
            found.append((display, ids))
        else:
            found.append((ABSENT_AUTHORITIES[phrase], ()))
    return found
