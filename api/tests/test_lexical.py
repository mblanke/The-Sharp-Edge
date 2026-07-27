"""The lexical ranking channel and RRF fusion.

CLAUDE.md §3: "exact-term culinary queries ('beurre blanc') must win." Until this
existed there was only a vector channel, and on the real corpus its scores for
"french onion soup" spanned 0.013 to 0.032 across all 24 candidates — noise rather
than ranking.
"""

import pytest

from app.services.lexical import (
    bm25_scores,
    hybrid_order,
    phrase_bonus,
    rank_lexically,
    reciprocal_rank_fusion,
    tokenize,
)


# ------------------------------------------------------------------ tokenising

def test_diacritics_are_folded_so_dictated_text_matches_printed():
    assert tokenize("Sauté") == tokenize("saute")
    assert tokenize("crème brûlée") == tokenize("creme brulee")


def test_stopwords_go_but_culinary_glue_stays():
    """"cream of mushroom" and "chicken in wine" are exact-phrase queries, so the
    connecting words are kept on purpose — an aggressive stoplist would gut them.
    What goes is question scaffolding, which carries no information about the dish."""
    assert tokenize("cream of mushroom") == ["cream", "of", "mushroom"]
    assert tokenize("chicken in wine") == ["chicken", "in", "wine"]
    assert tokenize("how do I make beurre blanc") == ["i", "beurre", "blanc"]


def test_digits_survive_tokenising():
    assert "350" in tokenize("bake at 350 degrees")


# ------------------------------------------------------------------ BM25

def test_a_document_about_the_query_outscores_one_that_merely_mentions_it():
    docs = [
        "Onion soup gratinee. Portion the soup into flameproof crocks. The onion soup "
        "is topped with cheese and browned. Serve the onion soup hot.",
        "A note on liaisons. We love the warm gelee effect it gives our rendition of "
        "french onion soup. The following are general percentages.",
    ]
    scores = bm25_scores("onion soup", docs)
    assert scores[0] > scores[1]


def test_a_term_present_in_every_candidate_is_nearly_worthless():
    """If everything retrieved says "soup", saying "soup" is barely evidence.

    BM25's smoothed IDF floors near zero rather than at it, so the check is that a term
    unique to one candidate is worth far more than one shared by all.
    """
    docs = ["soup soup soup", "soup and bread", "soup with cheese"]
    ubiquitous = max(bm25_scores("soup", docs))
    distinctive = max(bm25_scores("cheese", docs))
    assert distinctive > ubiquitous * 3


def test_empty_inputs_do_not_explode():
    assert bm25_scores("anything", []) == []
    assert bm25_scores("", ["some text"]) == [0.0]
    assert bm25_scores("the a an", ["some text"]) == [0.0]   # all stopwords


# ------------------------------------------------------------------ phrases

def test_a_full_phrase_match_scores_one():
    assert phrase_bonus("french onion soup", "our take on French Onion Soup is…") == 1.0


def test_a_partial_phrase_scores_proportionally():
    # "onion soup" is two of the three query words, contiguous.
    assert phrase_bonus("french onion soup", "Onion Soup Gratinee") == pytest.approx(2 / 3)


def test_scattered_words_are_not_a_phrase():
    """This is the case that separates a recipe from a coincidence: an ingredient list
    with a Vidalia onion and a stock made of soup bones is not about onion soup."""
    assert phrase_bonus("french onion soup", "40 g Vidalia onion, and soup bones") == 0.0


def test_phrase_matching_ignores_accents_and_case():
    assert phrase_bonus("creme brulee", "CRÈME BRÛLÉE, classic") == 1.0


# ------------------------------------------------------------------ fusion

def test_rrf_rewards_agreement_between_channels():
    """An item both channels rank first beats one only a single channel likes.

    Note what RRF does *not* promise: with k=60 the curve is nearly linear, so a
    first-and-last placing (1/61 + 1/63) edges out a second-and-second (2/62). Ranking
    first in both is the property worth asserting.
    """
    fused = reciprocal_rank_fusion([[0, 1, 2], [0, 2, 1]])
    assert fused[0] > fused[1]
    assert fused[0] > fused[2]


def test_rrf_weights_shift_the_balance():
    lexical = [2, 1, 0]
    vector = [0, 1, 2]
    lexical_heavy = reciprocal_rank_fusion([lexical, vector], weights=[3.0, 1.0])
    assert lexical_heavy[2] > lexical_heavy[0]


def test_fusion_of_nothing_is_nothing():
    assert reciprocal_rank_fusion([]) == {}


# ------------------------------------------------------------------ end to end

def _chunk(text, score, title="Book", heading=""):
    return {"text": text, "score": score, "title": title, "heading": heading}


def test_the_real_failure_case_is_reordered():
    """Reproduces what the corpus actually returned for "french onion soup".

    The vector channel put an unrelated ingredient list first (it contains the word
    "onion") and the actual recipe well down the list. Scores are the real ones.
    """
    chunks = [
        _chunk("Comte or Parmesan cheese. 5 grams sliced shallot. 1 gram lemon juice. "
               "40 grams half-inch-dice Vidalia onion. 4 grams thyme leaves.",
               0.0292, title="The French Laundry, Per Se"),
        _chunk("Ultra-Tex is also cold-soluble. It thickens a vegetable juice meant to "
               "be served with a natural raw flavor, such as carrot or tomato.",
               0.0149, title="The French Laundry, Per Se"),
        _chunk("Onion Soup Gratinee: Portion the soup into flameproof crocks. The onion "
               "soup is finished with a slice of bread and cheese, then browned under "
               "the salamander until the cheese bubbles.",
               0.0248, title="Culinary Institute of America",
               heading="Onion Soup Gratinee"),
    ]
    order = hybrid_order("french onion soup", chunks)
    assert order[0] == 2, "the actual onion soup recipe should rank first"


def test_a_heading_that_names_the_dish_counts_for_something():
    body = "Portion into crocks and brown under the salamander until bubbling."
    with_heading = _chunk(body, 0.02, heading="Onion Soup Gratinee")
    without = _chunk(body, 0.02, heading="Garnishes")
    scores = rank_lexically("onion soup", [with_heading, without])
    assert scores[0] > scores[1]


def test_ordering_is_deterministic_and_total():
    chunks = [_chunk("onion soup", 0.01), _chunk("onion soup", 0.01),
              _chunk("beef stew", 0.01)]
    order = hybrid_order("onion soup", chunks)
    assert sorted(order) == [0, 1, 2], "every chunk appears exactly once"
    assert hybrid_order("onion soup", chunks) == order, "stable across calls"


def test_no_chunks_no_problem():
    assert hybrid_order("anything", []) == []
