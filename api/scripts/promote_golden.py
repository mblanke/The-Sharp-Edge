#!/usr/bin/env python
"""Turn rated answers into golden eval questions.

`harvest_questions.py` proposes questions but refuses to fill in `expect_any` from what
the system returned — that would bake today's wrong answers into the ratchet. A thumbs
up changes that: a cook looked at the answer and its citations and said *this was right*.
That verdict is the missing label, so a thumbs-up answer's cited books become the
expectation for its question. A thumbs-down is printed separately as a lead: the eval
may be missing a question, or the shelf may be missing a book.

Proposes by default; `--write` appends new questions to tests/golden_questions.json.
Re-record the baseline afterwards on purpose (RAG_EVAL=1 RAG_EVAL_WRITE_BASELINE=1).

    uv run python scripts/promote_golden.py [--write]
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

from sqlalchemy import select

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.db import SessionLocal  # noqa: E402
from app.models.chat import Message  # noqa: E402
from app.services.shelf import resolve_path  # noqa: E402

GOLDEN = Path(__file__).resolve().parent.parent / "tests" / "golden_questions.json"


@dataclass
class Rated:
    question: str
    citations: list[dict]
    feedback: str


@dataclass
class Promotion:
    candidates: list[dict] = field(default_factory=list)
    poor: list[tuple[str, list[str]]] = field(default_factory=list)
    skipped_known: int = 0
    skipped_uncited: int = 0


def books_cited(citations: list[dict]) -> list[str]:
    """Shelf ids from an answer's citations, in first-cited order. `[R]` (the working
    recipe) resolves to nothing and drops out."""
    out: list[str] = []
    for c in citations or []:
        book = resolve_path(str(c.get("source_path") or ""))
        if book and book not in out:
            out.append(book)
    return out


def promote(rated: list[Rated], existing: set[str]) -> Promotion:
    """Pure: which rated pairs become golden questions."""
    result = Promotion()
    seen: set[str] = set()
    for r in rated:
        q = " ".join(r.question.split()).strip()
        if len(q) < 8:
            continue
        books = books_cited(r.citations)
        if r.feedback == "down":
            result.poor.append((q, books))
            continue
        if r.feedback != "up":
            continue
        key = q.lower()
        if key in existing or key in seen:
            result.skipped_known += 1
            continue
        if not books:
            result.skipped_uncited += 1  # a good answer with no shelf citation is not a retrieval case
            continue
        seen.add(key)
        result.candidates.append({"q": q, "expect_any": books})
    return result


async def load_rated() -> list[Rated]:
    """Each rated assistant turn paired with the user turn just before it."""
    async with SessionLocal() as session:
        rows = (
            await session.execute(
                select(Message.conversation_id, Message.role, Message.content, Message.citations, Message.feedback)
                .order_by(Message.conversation_id, Message.created_at)
            )
        ).all()
    rated: list[Rated] = []
    last_user: dict = {}
    for conversation_id, role, content, citations, feedback in rows:
        if role == "user":
            last_user[conversation_id] = content
        elif role == "assistant" and feedback and conversation_id in last_user:
            rated.append(Rated(last_user[conversation_id], citations or [], feedback))
    return rated


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true", help="append new questions to golden_questions.json")
    args = ap.parse_args()

    golden = json.loads(GOLDEN.read_text())
    existing = {q["q"].lower() for q in golden["questions"]}
    result = promote(asyncio.run(load_rated()), existing)

    if result.poor:
        print(f"# {len(result.poor)} answers rated poor — leads, not entries:")
        for q, books in result.poor:
            print(f"#   {q}  (cited: {', '.join(books) or 'nothing'})")
        print()
    print(
        f"# {len(result.candidates)} new golden questions from thumbs-up answers "
        f"({result.skipped_known} already in the set, {result.skipped_uncited} uncited)"
    )
    for c in result.candidates:
        print(f"    {json.dumps(c)},")

    if args.write and result.candidates:
        golden["questions"].extend(result.candidates)
        GOLDEN.write_text(json.dumps(golden, indent=2, ensure_ascii=False) + "\n")
        print(f"\nwrote {len(result.candidates)} questions → {GOLDEN}")
        print("now: RAG_EVAL=1 RAG_EVAL_WRITE_BASELINE=1 uv run --extra dev pytest tests/test_retrieval_eval.py")


if __name__ == "__main__":
    main()
