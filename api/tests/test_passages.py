"""Index-page filtering and adjacent-chunk merging.

The samples below are trimmed from real chunks the Cooking corpus returned for the
query "French onion soup recipe" — the case that exposed the bug: the top three hits
were all page 53 of The French Laundry, i.e. its index.
"""

from app.services.passages import looks_like_index, to_passages

# The French Laundry index, p.53 — the chunk that used to outrank the actual recipe.
BOOK_INDEX = (
    "ab\n\nFlour, as liaison\n\nFoie Gras\n\nFoie Gras “Mignonette” Sauce\n\n"
    "French Laundry:\n\nGarden\n\nKitchen\n\nTimeline\n\nFrench Leeks\n\n"
    "French Onion Soup\n\nFrost-Kissed Garden Cauliflower\n\nG\n\nGalette: Eggplant"
)

# A soups table-of-contents, p.22.
TABLE_OF_CONTENTS = (
    "white stock, cream, butter\n\nEsaü\n\nShaped-vegetable soups (potage taillés)\n\n"
    "Leeks and potatoes cut in paysanne\n\nParisien\n\nLeeks, potatoes, turnips\n\n"
    "Fermière\n\nCultivateur\n\nPaysanne\n\nBonne Femme"
)

# An ingredient list. Short lines like an index, but full of quantities — must survive.
INGREDIENT_LIST = (
    "Makes 6 servings\n\n150 grams whole milk\n\n150 grams heavy cream\n\n"
    "70 grams grated Parmesan cheese\n\n2 grams minced shallot, rinsed\n\n"
    "2 grams lemon juice\n\n6 grams fleur de sel\n\n1 large egg"
)

PROSE = (
    "Season with salt and pepper to taste and simmer for 30 minutes. Strain well "
    "before using. An impromptu vegetable stock can be made for this recipe by "
    "sweating all of the vegetable trimmings you have on hand with a bay leaf."
)


def test_book_index_is_rejected():
    assert looks_like_index(BOOK_INDEX)


def test_table_of_contents_is_rejected():
    assert looks_like_index(TABLE_OF_CONTENTS)


def test_ingredient_list_survives():
    """Quantities are the signal that separates a recipe from an index."""
    assert not looks_like_index(INGREDIENT_LIST)


def test_prose_survives():
    assert not looks_like_index(PROSE)


def test_colon_headings_do_not_disguise_an_index():
    """"Soups:" / "Mousse:" made indexes look like prose when ':' ended a sentence."""
    assert looks_like_index("Soups:\n\nBlack Truffle Coulis\n\nEgg Flower Soup\n\n"
                            "Mousse:\n\nCorn Mousse\n\nMalt Mousse\n\nOnion Rings")


def test_empty_is_rejected():
    assert looks_like_index("")
    assert looks_like_index("   \n\n  ")


def _chunk(doc, idx, page, text, score):
    return {"doc_id": doc, "chunk_index": idx, "page": page, "text": text,
            "score": score, "rerank_score": score, "title": "Book " + doc}


def test_adjacent_chunks_merge_into_one_passage():
    chunks = [
        _chunk("a", 10, 5, PROSE, 3.0),
        _chunk("a", 11, 6, PROSE, 2.0),
        _chunk("a", 12, 6, PROSE, 1.0),
    ]
    passages = to_passages(chunks)
    assert len(passages) == 1
    p = passages[0]
    assert p["chunk_count"] == 3
    assert p["page"] == 5 and p["page_end"] == 6
    assert p["score"] == 3.0            # best score in the run wins
    assert p["text"].count(PROSE) == 3


def test_a_gap_splits_the_run():
    chunks = [
        _chunk("a", 10, 5, PROSE, 3.0),
        _chunk("a", 40, 20, PROSE, 2.0),   # far away — a different part of the book
    ]
    assert len(to_passages(chunks)) == 2


def test_documents_are_never_merged_together():
    chunks = [_chunk("a", 10, 5, PROSE, 3.0), _chunk("b", 11, 6, PROSE, 2.9)]
    passages = to_passages(chunks)
    assert len(passages) == 2
    assert {p["title"] for p in passages} == {"Book a", "Book b"}


def test_indexes_are_dropped_before_merging():
    chunks = [
        _chunk("a", 1, 53, BOOK_INDEX, 9.0),   # would otherwise rank first
        _chunk("a", 20, 12, PROSE, 2.0),
    ]
    passages = to_passages(chunks)
    assert len(passages) == 1
    assert PROSE in passages[0]["text"]
    assert "Foie Gras" not in passages[0]["text"]


def test_all_index_falls_back_rather_than_returning_nothing():
    """An empty result is worse than a bad one — the user gets to judge."""
    passages = to_passages([_chunk("a", 1, 53, BOOK_INDEX, 9.0)])
    assert len(passages) == 1


def test_keep_limits_the_result():
    chunks = [_chunk(str(i), i, i, PROSE, float(i)) for i in range(12)]
    assert len(to_passages(chunks, keep=4)) == 4


def test_ranking_is_by_best_score_descending():
    chunks = [_chunk("a", 1, 1, PROSE, 1.0), _chunk("b", 2, 2, PROSE, 5.0)]
    assert [p["title"] for p in to_passages(chunks)] == ["Book b", "Book a"]


def test_chunks_without_an_index_still_appear():
    passages = to_passages([{"doc_id": "a", "page": 3, "text": PROSE, "score": 1.0}])
    assert len(passages) == 1
    assert passages[0]["chunk_count"] == 1


# ---------------------------------------------------------------- page markers

def test_page_markers_override_a_placeholder_page():
    """A .txt we extracted ourselves has no page structure, so every chunk claims
    page 1. Our own [page N] markers are the real page number."""
    chunks = [{"doc_id": "cia", "chunk_index": 5, "page": 1, "score": 3.0,
               "text": "[page 447]\n" + PROSE}]
    p = to_passages(chunks)[0]
    assert p["page"] == 447
    assert p["page_end"] == 447


def test_page_markers_are_stripped_from_the_displayed_text():
    chunks = [{"doc_id": "cia", "chunk_index": 5, "page": 1, "score": 3.0,
               "text": "[page 447]\n" + PROSE}]
    assert "[page" not in to_passages(chunks)[0]["text"]
    assert PROSE in to_passages(chunks)[0]["text"]


def test_a_merged_run_spans_the_marked_pages():
    chunks = [
        {"doc_id": "cia", "chunk_index": 5, "page": 1, "score": 3.0, "text": "[page 447]\n" + PROSE},
        {"doc_id": "cia", "chunk_index": 6, "page": 1, "score": 2.0, "text": "[page 448]\n" + PROSE},
    ]
    p = to_passages(chunks)[0]
    assert (p["page"], p["page_end"]) == (447, 448)


def test_real_page_metadata_is_left_alone_when_there_are_no_markers():
    chunks = [{"doc_id": "epub", "chunk_index": 5, "page": 53, "score": 3.0, "text": PROSE}]
    assert to_passages(chunks)[0]["page"] == 53


def test_an_unmarked_placeholder_page_one_reports_no_page():
    """Better no citation than "p.1" for something on page 266."""
    chunks = [{"doc_id": "cia", "chunk_index": 9, "page": 1, "score": 3.0, "text": PROSE}]
    p = to_passages(chunks)[0]
    assert p["page"] is None and p["page_end"] is None


def test_a_marked_page_one_is_still_page_one():
    chunks = [{"doc_id": "cia", "chunk_index": 1, "page": 1, "score": 3.0,
               "text": "[page 1]\n" + PROSE}]
    assert to_passages(chunks)[0]["page"] == 1


def test_a_genuine_page_two_is_untouched():
    chunks = [{"doc_id": "epub", "chunk_index": 9, "page": 2, "score": 3.0, "text": PROSE}]
    assert to_passages(chunks)[0]["page"] == 2
