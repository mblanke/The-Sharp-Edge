"""The promotion rule behind scripts/promote_golden.py, without a database."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from promote_golden import Rated, promote  # noqa: E402

CIA = {"source_path": "Cooking/Culinary Institute of America - The Professional Chef.pdf", "page": 358}
FOOD_LAB = {"source_path": "Cooking/The Food Lab_ Better Home Cooking Through Science.epub", "page": 12}
RECIPE = {"n": 0, "source_path": "/r/goulash", "title": "Goulash"}


def test_a_thumbs_up_with_citations_becomes_a_golden_question():
    result = promote([Rated("How does  the CIA make onion soup? ", [CIA], "up")], existing=set())
    assert result.candidates == [{"q": "How does the CIA make onion soup?", "expect_any": ["professional-chef"]}]
    assert result.poor == []


def test_cited_books_keep_first_cited_order_and_drop_the_working_recipe():
    result = promote([Rated("what thickens a stew", [RECIPE, FOOD_LAB, CIA, FOOD_LAB], "up")], existing=set())
    assert result.candidates[0]["expect_any"] == ["food-lab", "professional-chef"]


def test_known_questions_uncited_answers_and_duplicates_are_skipped():
    rated = [
        Rated("How does the CIA make onion soup?", [CIA], "up"),   # already golden
        Rated("what is a roux", [], "up"),                          # good answer, no shelf citation
        Rated("Why rest meat?", [CIA], "up"),
        Rated("why rest meat?", [FOOD_LAB], "up"),                  # same question, different day
        Rated("unrated", [CIA], None),
    ]
    result = promote(rated, existing={"how does the cia make onion soup?"})
    assert [c["q"] for c in result.candidates] == ["Why rest meat?"]
    assert result.skipped_known == 2
    assert result.skipped_uncited == 1


def test_a_thumbs_down_is_a_lead_not_an_entry():
    result = promote([Rated("how does Escoffier build an espagnole", [CIA], "down")], existing=set())
    assert result.candidates == []
    assert result.poor == [("how does Escoffier build an espagnole", ["professional-chef"])]
