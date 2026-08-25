"""Technique auto-linking (F5): each step's text runs through retrieval once;
strong matches become cached margin notes — Escoffier annotating the goulash.

GPU rule honoured: these are interactive one-off /retrieve calls (one per
step, only when the cook taps Illuminate and only once per version) — never
batch embedding from this app.
"""

from app.config import settings
from app.models import RecipeAnnotation
from app.services.atlas_rag import atlas_rag


def _score(chunk: dict) -> float:
    return float(chunk.get("rerank_score") or chunk.get("score") or 0.0)


def _phrase(chunk: dict) -> str:
    return str(chunk.get("heading") or chunk.get("title") or "related technique")


async def build_annotations(version_id, steps: list[dict]) -> list[RecipeAnnotation]:
    """Top match per step above the score floor, deduped by (source, page)
    across the recipe (keep the highest-scoring occurrence)."""
    best_by_ref: dict[tuple, RecipeAnnotation] = {}
    for index, step in enumerate(steps):
        text = str(step.get("text", "")).replace("**", "").strip()
        if len(text) < 15:  # "Serve." teaches nothing
            continue
        chunks = await atlas_rag.retrieve(text, top_k=3)
        chunks = [c for c in chunks if _score(c) >= settings.annotation_min_score]
        if not chunks:
            continue
        top = max(chunks, key=_score)
        ref = (top.get("source_path"), top.get("page"))
        candidate = RecipeAnnotation(
            recipe_version_id=version_id,
            step_index=index,
            phrase=_phrase(top),
            title=top.get("title"),
            source_path=top.get("source_path"),
            heading=top.get("heading"),
            page=top.get("page"),
            snippet=str(top.get("text", ""))[:600],
            score=_score(top),
        )
        existing = best_by_ref.get(ref)
        if existing is None or (candidate.score or 0) > (existing.score or 0):
            best_by_ref[ref] = candidate
    return sorted(best_by_ref.values(), key=lambda a: a.step_index)
