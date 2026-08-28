#!/usr/bin/env python
"""Propose golden eval questions from the questions actually asked.

Real questions beat invented ones, and a question asked six different ways is the most
valuable entry in an eval set — the rephrasing is the label. This reads the conversation
log, clusters near-duplicates, and prints candidate entries.

It **proposes**; a human commits. Deliberately so: filling in `expect_any` from whatever
the system already returned would bake today's wrong answers into the ratchet, which is
the one thing a baseline must never do. Where a cluster's answers cited books, those are
printed as *suggestions* to check, not as expectations.

Read-only. Usage:

    uv run python scripts/harvest_questions.py [--min-cluster 1] [--limit 40]
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from collections import Counter
from pathlib import Path

from sqlalchemy import select

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.db import SessionLocal  # noqa: E402
from app.models.chat import Message  # noqa: E402
from app.services.lexical import tokenize  # noqa: E402
from app.services.shelf import resolve_path  # noqa: E402

JACCARD = 0.6


def _similar(a: set[str], b: set[str]) -> float:
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


async def harvest(min_cluster: int, limit: int) -> list[dict]:
    async with SessionLocal() as session:
        rows = (
            await session.execute(
                select(Message.content, Message.citations)
                .where(Message.role == "user")
                .order_by(Message.created_at)
            )
        ).all()
        cited = (
            await session.execute(
                select(Message.citations).where(Message.role == "assistant")
            )
        ).scalars().all()

    # every book any answer cited, as a hint for the human filling in expect_any
    hint = Counter()
    for citations in cited:
        for c in citations or []:
            book = resolve_path(str(c.get("source_path") or ""))
            if book:
                hint[book] += 1

    clusters: list[dict] = []
    for content, _ in rows:
        question = (content or "").strip()
        if len(question) < 8:
            continue
        toks = set(tokenize(question))
        for cluster in clusters:
            if _similar(toks, cluster["tokens"]) >= JACCARD:
                cluster["variants"].append(question)
                cluster["tokens"] |= toks
                break
        else:
            clusters.append({"variants": [question], "tokens": toks})

    clusters = [c for c in clusters if len(c["variants"]) >= min_cluster]
    clusters.sort(key=lambda c: -len(c["variants"]))
    return [
        {
            "asked": len(c["variants"]),
            "canonical": max(c["variants"], key=len),
            "variants": list(dict.fromkeys(c["variants"])),
        }
        for c in clusters[:limit]
    ], hint


async def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--min-cluster", type=int, default=1)
    ap.add_argument("--limit", type=int, default=40)
    args = ap.parse_args()

    clusters, hint = await harvest(args.min_cluster, args.limit)
    if not clusters:
        print("no questions in the log yet")
        return

    print(f"# {len(clusters)} question clusters, most-asked first")
    print("# Books your answers have cited (a hint, NOT an expectation):")
    for book, n in hint.most_common(10):
        print(f"#   {book}: {n}")
    print("#\n# Paste into tests/golden_questions.json and fill in expect_any YOURSELF.")
    print("# Do not copy the hint blindly — that would freeze today's answers into the floor.\n")

    for c in clusters:
        if c["asked"] > 1:
            print(f"    // asked {c['asked']}× — {len(c['variants'])} phrasings:")
            for v in c["variants"]:
                print(f"    //   {v}")
        print(f'    {{ "q": {json.dumps(c["canonical"])}, "expect_any": [] }},')


if __name__ == "__main__":
    asyncio.run(main())
