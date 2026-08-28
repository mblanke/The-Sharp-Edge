"""Retrieval quality harness — runs against the LIVE Atlas rag-api.

Skipped unless RAG_EVAL=1 (needs the tailnet and a populated references_v2).

This used to report a single hit rate over `source_path` substring guesses, and the
number was meaningless: four questions named books by an author the files aren't named
after (`mcgee` matched zero indexed files), one scored a hit off any Keller lecture
because `gf` appears in the release group `DawgFather`, and questions about books that
were never ingested at all — Escoffier, Under Pressure — counted as retrieval failures.
"53%" was measuring spelling and corpus gaps, not retrieval.

So every question now resolves to one of three outcomes:

* **HIT**   — an expected book appeared in the top 8.
* **MISS**  — the expected book *is* indexed and retrieval didn't surface it. The only
              outcome that counts against the floor, and the only one worth fixing here.
* **ABSENT** — no expected book has meaningful coverage. Reported as a shelf gap, and
              excluded from the rate. Fix those by ingesting the book, not by tuning RRF.

The ratchet is per-question, not a percentage: a question that was a HIT may never become
a MISS. A rate alone lets one regression hide behind one unrelated improvement.
"""

import json
import os
from pathlib import Path

import pytest

HERE = Path(__file__).parent
GOLDEN = json.loads((HERE / "golden_questions.json").read_text())["questions"]
BASELINE_PATH = HERE / "retrieval_baseline.json"

# Floor over *reachable* questions only (HIT + MISS). ABSENT never counts.
MIN_HIT_RATE = 0.5

pytestmark = [
    pytest.mark.slow,
    pytest.mark.skipif(os.environ.get("RAG_EVAL") != "1", reason="live-Atlas eval; set RAG_EVAL=1"),
]


async def _evaluate() -> list[dict]:
    from app.services.atlas_rag import AtlasRag
    from app.services.coverage import indexed_book_ids
    from app.services.shelf import resolve_path

    indexed = await indexed_book_ids()
    if not indexed:
        pytest.skip("Qdrant coverage unavailable — cannot separate MISS from ABSENT")

    rag = AtlasRag()
    try:
        rows = []
        for item in GOLDEN:
            want = set(item["expect_any"])
            chunks = await rag.retrieve(item["q"], top_k=8)
            got = [resolve_path(str(c.get("source_path") or "")) for c in chunks]
            got_ids = [g for g in got if g]

            if want & set(got_ids):
                outcome = "HIT"
            elif not (want & indexed):
                outcome = "ABSENT"
            else:
                outcome = "MISS"

            rows.append(
                {
                    "q": item["q"],
                    "outcome": outcome,
                    "want": sorted(want),
                    "got": list(dict.fromkeys(got_ids))[:4],
                }
            )
        return rows
    finally:
        await rag.aclose()


def _report(rows: list[dict]) -> str:
    mark = {"HIT": "✓", "MISS": "✗", "ABSENT": "·"}
    lines = []
    for r in rows:
        line = f"  {mark[r['outcome']]} {r['q']}"
        if r["outcome"] == "MISS":
            line += f"\n      wanted {r['want']} · got {r['got']}"
        elif r["outcome"] == "ABSENT":
            line += f"\n      not on the shelf: {r['want']}"
        lines.append(line)
    return "\n".join(lines)


async def test_retrieval_quality():
    rows = await _evaluate()

    hits = [r for r in rows if r["outcome"] == "HIT"]
    misses = [r for r in rows if r["outcome"] == "MISS"]
    absent = [r for r in rows if r["outcome"] == "ABSENT"]
    reachable = len(hits) + len(misses)
    rate = len(hits) / reachable if reachable else 1.0

    print(
        f"\nretrieval eval — {len(hits)}/{reachable} reachable ({rate:.0%})"
        f" · {len(absent)} absent from the shelf\n{_report(rows)}"
    )
    if absent:
        print("\n  shelf gaps (ingest these, don't tune retrieval for them):")
        for r in absent:
            print(f"    {r['q']} → {r['want']}")

    # Per-question ratchet: nothing that worked may quietly stop working.
    if BASELINE_PATH.exists():
        baseline = json.loads(BASELINE_PATH.read_text())["outcomes"]
        regressed = [
            r["q"] for r in rows if baseline.get(r["q"]) == "HIT" and r["outcome"] == "MISS"
        ]
        assert not regressed, "questions that used to work and no longer do:\n  " + "\n  ".join(
            regressed
        )

    assert rate >= MIN_HIT_RATE, (
        f"hit rate over reachable questions {rate:.0%} is below the {MIN_HIT_RATE:.0%} floor\n"
        f"{_report(rows)}"
    )


@pytest.mark.skipif(
    os.environ.get("RAG_EVAL_WRITE_BASELINE") != "1",
    reason="set RAG_EVAL_WRITE_BASELINE=1 to re-record the baseline",
)
async def test_write_baseline():
    """Deliberately opt-in. Re-recording is a commit someone makes on purpose, so a
    regression can never be laundered into the baseline by a normal test run."""
    rows = await _evaluate()
    BASELINE_PATH.write_text(
        json.dumps(
            {
                "comment": (
                    "Per-question outcomes from the last deliberate recording. CI asserts no "
                    "HIT becomes a MISS. Re-record with RAG_EVAL=1 "
                    "RAG_EVAL_WRITE_BASELINE=1 pytest tests/test_retrieval_eval.py and commit "
                    "the diff on purpose."
                ),
                "outcomes": {r["q"]: r["outcome"] for r in rows},
            },
            indent=2,
        )
        + "\n"
    )
    print(f"\nwrote baseline → {BASELINE_PATH}")
