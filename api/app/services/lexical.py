"""A lexical ranking channel over retrieved chunks, fused with the vector ranking.

CLAUDE.md §3 asks for hybrid search — "exact-term culinary queries ('beurre blanc')
must win" — and until now there was only one channel. The consequence was reproducible:

    query: "french onion soup"
    top result: The French Laundry p.18 — an ingredient list containing Comté,
                truffle, and a Vidalia *onion*, with nothing to do with onion soup.
    rank 17:    Culinary Institute of America, "Onion Soup Gratinée: Portion the
                soup into flameproof…" — the actual recipe.

The retrieved scores across all 24 candidates spanned 0.013 to 0.032. That is noise,
not ranking, so no amount of read-side filtering could rescue it: the right passage was
retrieved, just buried.

§3 specifies Postgres FTS, which assumed chunks live in Postgres. They do not — §9 moved
the corpus to Atlas's Qdrant and this app is a consumer. So the lexical channel scores
the **candidate pool** rather than a local index: BM25 with the over-fetched chunks as
the collection. That is a re-ranker rather than a retriever, which is the honest limit —
it can only reorder what Atlas returned, so `rag_fetch_k` matters. It cannot find a
passage that was never retrieved.
"""

from __future__ import annotations

import math
import re
import unicodedata
from collections import Counter
from typing import Any, Iterable

__all__ = ["tokenize", "bm25_scores", "phrase_bonus", "rank_lexically", "reciprocal_rank_fusion"]

# BM25 constants. k1 controls term-frequency saturation, b the length normalisation;
# these are the standard defaults and there is no tuning data to justify moving them.
_K1 = 1.5
_B = 0.75
#: RRF damping. 60 is the value from the original Cormack et al. paper, and it is chosen
#: so a top-ranked result in one channel cannot single-handedly dominate the fusion.
_RRF_K = 60

_WORD = re.compile(r"[^\W\d_]+|\d+", re.UNICODE)

#: Words that carry no discrimination in a cookbook. Deliberately short — an aggressive
#: list would strip "in", "of" and "with" out of "cream of mushroom" and "chicken in
#: wine", which are exactly the exact-phrase queries this exists to serve.
_STOP = {
    "the", "a", "an", "and", "or", "to", "for", "is", "are", "be", "it", "this", "that",
    "how", "do", "does", "make", "makes", "made", "recipe", "recipes",
}


def _fold(text: str) -> str:
    return "".join(
        c for c in unicodedata.normalize("NFKD", text or "") if not unicodedata.combining(c)
    ).lower()


def tokenize(text: str, keep_stopwords: bool = False) -> list[str]:
    """Fold, split on word boundaries, drop stopwords.

    Diacritics are folded so "sauté" matches "saute" — dictated and OCR'd text disagree
    about accents constantly, and a cook searching for "creme brulee" means the accented
    thing.
    """
    words = _WORD.findall(_fold(text))
    if keep_stopwords:
        return words
    return [w for w in words if w not in _STOP]


def bm25_scores(query: str, documents: list[str]) -> list[float]:
    """BM25 of the query against each document, with the documents as the collection.

    Scoring within the candidate pool rather than the whole corpus means IDF reflects
    "rare among what was retrieved". For re-ranking that is the useful signal: if every
    candidate says "onion", saying "onion" is not evidence, and the term that separates
    them earns the weight.
    """
    if not documents:
        return []
    q_terms = tokenize(query)
    if not q_terms:
        return [0.0] * len(documents)

    doc_tokens = [tokenize(d) for d in documents]
    lengths = [len(t) for t in doc_tokens]
    avg_len = (sum(lengths) / len(lengths)) or 1.0
    counters = [Counter(t) for t in doc_tokens]

    n_docs = len(documents)
    doc_freq = Counter()
    for counter in counters:
        for term in set(q_terms) & counter.keys():
            doc_freq[term] += 1

    scores = []
    for counter, length in zip(counters, lengths):
        total = 0.0
        for term in q_terms:
            tf = counter.get(term, 0)
            if not tf:
                continue
            df = doc_freq[term]
            # Standard BM25 IDF, floored at zero so a term present in every candidate
            # contributes nothing rather than pushing the score negative.
            idf = max(0.0, math.log(1 + (n_docs - df + 0.5) / (df + 0.5)))
            denom = tf + _K1 * (1 - _B + _B * length / avg_len)
            total += idf * (tf * (_K1 + 1)) / denom
        scores.append(total)
    return scores


def phrase_bonus(query: str, text: str) -> float:
    """How much of the query appears as a contiguous phrase.

    This is the part that separates a recipe from a mention. "French onion soup" appears
    as a phrase in the CIA's recipe heading and does not appear at all in a French
    Laundry ingredient list that merely happens to contain the word "onion".

    Returns the fraction of the longest matching query n-gram, so a full phrase match
    scores 1.0 and a two-of-three match scores ~0.67.
    """
    q = tokenize(query)
    if not q:
        return 0.0
    haystack = " ".join(tokenize(text, keep_stopwords=True))
    for size in range(len(q), 1, -1):
        for start in range(0, len(q) - size + 1):
            gram = " ".join(q[start:start + size])
            if gram in haystack:
                return size / len(q)
    return 0.0


def rank_lexically(query: str, chunks: list[dict[str, Any]]) -> list[float]:
    """A combined lexical score per chunk: BM25 over the body, plus phrase and heading
    evidence.

    Headings and titles are weighted because in a cookbook the dish name is the heading,
    and a passage headed "Onion Soup Gratinée" is about onion soup in a way that a
    passage merely mentioning onions is not.
    """
    bodies = [str(c.get("text") or "") for c in chunks]
    base = bm25_scores(query, bodies)
    top = max(base) if base and max(base) > 0 else 1.0

    out = []
    for chunk, score in zip(chunks, base):
        text = str(chunk.get("text") or "")
        heading = " ".join(
            str(chunk.get(field) or "") for field in ("heading", "title")
        )
        combined = (
            0.6 * (score / top)
            + 0.3 * phrase_bonus(query, text)
            + 0.1 * phrase_bonus(query, heading)
        )
        out.append(combined)
    return out


def reciprocal_rank_fusion(
    rankings: Iterable[list[int]], k: int = _RRF_K, weights: list[float] | None = None
) -> dict[int, float]:
    """Fuse several rankings of the same items into one score per item.

    Each ranking is a list of item indices, best first. RRF is used rather than
    normalising and adding the raw scores because the two channels are not on comparable
    scales — the vector scores here span 0.013 to 0.032 while BM25 is unbounded, and any
    normalisation of a range that narrow amplifies noise into apparent signal.
    """
    rankings = list(rankings)
    if weights is None:
        weights = [1.0] * len(rankings)

    fused: dict[int, float] = {}
    for ranking, weight in zip(rankings, weights):
        for position, item in enumerate(ranking):
            fused[item] = fused.get(item, 0.0) + weight / (k + position + 1)
    return fused


def hybrid_order(
    query: str,
    chunks: list[dict[str, Any]],
    lexical_weight: float = 1.0,
    vector_weight: float = 1.0,
) -> list[int]:
    """Indices of `chunks`, best first, fusing the vector ranking with a lexical one."""
    if not chunks:
        return []

    vector_order = sorted(
        range(len(chunks)),
        key=lambda i: -(chunks[i].get("rerank_score") or chunks[i].get("score") or 0.0),
    )
    lexical = rank_lexically(query, chunks)
    lexical_order = sorted(range(len(chunks)), key=lambda i: -lexical[i])

    fused = reciprocal_rank_fusion(
        [lexical_order, vector_order], weights=[lexical_weight, vector_weight]
    )
    # Ties broken by lexical score, then original order, so the result is deterministic.
    return sorted(range(len(chunks)), key=lambda i: (-fused.get(i, 0.0), -lexical[i], i))
