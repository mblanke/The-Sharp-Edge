"""Never answer in the voice of a book we don't own.

Offline and fast, so this runs on every PR rather than only under RAG_EVAL. The cases are
taken from the real conversation log — including the six identical Escoffier asks, each of
which was answered "according to Escoffier's method" while citing the CIA and the FCI.
"""

import pytest

from app.services.attribution import check, prompt_preamble, shelf_note

ROOT = "/mnt/references/Cooking/"
CIA = {"source_path": ROOT + "Culinary Institute of America - The Professional Chef.txt"}
FCI = {"source_path": ROOT + "The Fundamental Techniques of Classic Cuisine By FCI/x.epub"}
LAUNDRY = {"source_path": ROOT + "The French Laundry, Per Se/The French Laundry, Per Se.epub"}
MCGEE = {"source_path": ROOT + "_acquired/On Food and Cooking.epub"}


def test_absent_authority_is_reported_and_named():
    """The exact failure: asked six times, answered six times in Escoffier's name."""
    a = check("How does Escoffier build an espagnole?", [CIA, FCI])
    assert a.absent == ("Escoffier",)
    assert a.needs_note

    note = shelf_note(a)
    assert "no Escoffier on this shelf" in note
    assert "The Professional Chef" in note and "Fundamental Techniques" in note


def test_the_preamble_forbids_the_attribution_rather_than_the_answer():
    """Attribute, don't refuse — the CIA passages are a good espagnole."""
    preamble = prompt_preamble(check("How does Escoffier build an espagnole?", [CIA]))
    assert "Do not attribute anything below to Escoffier" in preamble
    assert "answer from the excerpts" in preamble


def test_named_book_that_was_retrieved_says_nothing():
    a = check("How does The Professional Chef describe the standard breading procedure?", [CIA])
    assert not a.needs_note
    assert a.as_dict() is None
    assert prompt_preamble(a) == ""


def test_named_book_that_is_owned_but_missed_is_flagged():
    """From the log: "How does the CIA make french onion soup" came back citing The
    French Laundry. The book is on the shelf — retrieval simply didn't reach it."""
    a = check("How does the CIA make french onion soup", [LAUNDRY, MCGEE])
    assert a.absent == ()
    assert a.unretrieved == ("The Professional Chef",)
    note = shelf_note(a)
    assert "shelf has The Professional Chef" in note
    assert "nothing from it matched" in note


def test_an_authority_named_and_retrieved_alongside_an_absent_one():
    a = check("Does Escoffier or McGee explain gluten?", [MCGEE])
    assert a.absent == ("Escoffier",)
    assert a.unretrieved == ()


@pytest.mark.parametrize(
    "question",
    [
        "maillard reaction temperature",  # a chemist, but this is a technique question
        "how to make a bechamel",
        "chantilly cream",
        "beef bourguignon timing",
        "mother sauces of French cuisine",
        "how many pages should I read",
    ],
)
def test_questions_that_name_nobody_are_silent(question):
    """False positives are the real risk: a spurious note on every technique question
    would train the cook to ignore all of them."""
    assert not check(question, [CIA]).needs_note


def test_no_chunks_at_all_is_said_plainly():
    a = check("How does Escoffier build an espagnole?", [])
    assert "Nothing on the shelf matched" in shelf_note(a)


def test_as_dict_carries_what_the_ui_renders():
    a = check("How does Escoffier build an espagnole?", [CIA])
    payload = a.as_dict()
    assert payload["absent"] == ["Escoffier"]
    assert payload["sources"] == ["The Professional Chef — Culinary Institute of America"]
    assert "no Escoffier" in payload["note"]


def test_source_list_stays_readable_when_many_books_matched():
    """Four book titles in one sentence is a wall; the citations below carry the detail."""
    from app.services.attribution import Attribution

    a = Attribution(
        absent=("Escoffier",),
        sources=("Alpha", "Bravo", "Charlie", "Delta", "Foxtrot"),
    )
    note = shelf_note(a)
    assert "Alpha, Bravo, Charlie and 2 other books" in note
    assert "Delta" not in note and "Foxtrot" not in note

    one_more = Attribution(sources=("Alpha", "Bravo", "Charlie", "Delta"))
    assert "Charlie and 1 other book." in shelf_note(one_more)


def test_absent_authorities_read_as_or_and_sources_as_and():
    from app.services.attribution import Attribution

    note = shelf_note(Attribution(absent=("Escoffier", "Larousse"), sources=("A", "B")))
    assert "no Escoffier or Larousse" in note
    assert "from A and B" in note
