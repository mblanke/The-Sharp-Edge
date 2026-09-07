"""Many recipes in, as drafts.

Every import path (photo, URL, passage) produced one draft for one review, which is
right for one recipe and hopeless for the twenty in a folder. A batch runs the same
importers and lands each result as a **draft** — out of the index, out of the exports,
waiting on `/drafts` — so a Sunday afternoon can approve them one at a time. Nothing is
ever auto-approved: a draft becomes a recipe when a person saves it without the flag.
"""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Recipe, RecipeVersion
from app.services.ingredients import CATEGORY_ORDER, match_category, slugify

FALLBACK_CATEGORY = "Entrées" if "Entrées" in CATEGORY_ORDER else CATEGORY_ORDER[0]


async def unique_slug(session: AsyncSession, title: str) -> str:
    """`slugify(title)`, or `-2`, `-3`… when taken. Slugs are the QR contract
    (CLAUDE.md §5): a second "Onion Soup" is a different recipe, never an overwrite."""
    base = slugify(title) or "recipe"
    taken = set(
        (await session.execute(select(Recipe.slug).where(Recipe.slug.like(f"{base}%")))).scalars().all()
    )
    if base not in taken:
        return base
    n = 2
    while f"{base}-{n}" in taken:
        n += 1
    return f"{base}-{n}"


async def create_draft(
    session: AsyncSession,
    draft: dict,
    *,
    source: str | None,
    label: str,
    private: bool = False,
) -> Recipe:
    """One importer result → one draft recipe (status='draft', version 1)."""
    title = (draft.get("title") or "Untitled").strip() or "Untitled"
    recipe = Recipe(
        slug=await unique_slug(session, title),
        title=title,
        category=match_category(title) or FALLBACK_CATEGORY,
        meta=draft.get("meta") or None,
        base_yield=max(1, int(draft.get("base_yield") or 1)),
        yield_word=draft.get("yield_word") or "servings",
        gf=False,
        noscale=False,
        source=source,
        private=private,
        status="draft",
    )
    recipe.versions.append(
        RecipeVersion(
            version=1,
            label=label,
            ingredients=[_clean(i) for i in draft.get("ingredients") or []],
            steps=[_clean(s) for s in draft.get("steps") or []],
            notes=[n for n in draft.get("notes") or [] if n],
            is_current=True,
        )
    )
    session.add(recipe)
    await session.flush()
    return recipe


def _clean(row: dict) -> dict:
    return {k: v for k, v in row.items() if v is not None}
