"""Deterministic text → structured-recipe helpers for the add-recipe flow.

Unauthenticated, like /ask — these are pure functions over text the caller already
has, and both clients reach them through the web proxy which forwards no bearer
token. Saving a recipe still requires auth (POST /recipes).

No LLM is involved anywhere in this path.
"""

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.models import Recipe, Redirect
from app.schemas.parse import (
    CategoryRequest,
    CategoryResponse,
    ParseIngredientsRequest,
    ParseIngredientsResponse,
    SlugRequest,
    SlugResponse,
)
from app.schemas.recipe import ALLOWED_UNITS, Ingredient
from app.services.ingredients import is_valid_slug, match_category, parse_lines, slugify

router = APIRouter(prefix="/parse", tags=["parse"])


@router.post("/ingredients", response_model=ParseIngredientsResponse)
async def parse_ingredients(payload: ParseIngredientsRequest) -> ParseIngredientsResponse:
    rows = parse_lines(payload.lines, lang=payload.lang, spoken=True)
    out: list[Ingredient] = []
    for row in rows:
        # ALLOWED_UNITS is declared but not enforced by the Ingredient schema, so the
        # gate lives here — same closed set the editor's <select>/Picker offers.
        if row.get("unit") not in ALLOWED_UNITS:
            row["unit"] = ""
        out.append(Ingredient(**row))
    return ParseIngredientsResponse(ingredients=out)


@router.post("/slug", response_model=SlugResponse)
async def make_slug(
    payload: SlugRequest, session: AsyncSession = Depends(get_session)
) -> SlugResponse:
    slug = slugify(payload.title)
    if not slug:
        return SlugResponse(slug="", available=False, valid=False)

    taken = (
        await session.execute(select(func.count()).select_from(Recipe).where(Recipe.slug == slug))
    ).scalar_one()
    # A slug that shadows a redirect would silently kill it, so treat it as taken.
    redirected = (
        await session.execute(
            select(func.count()).select_from(Redirect).where(Redirect.old_slug == slug)
        )
    ).scalar_one()
    return SlugResponse(slug=slug, available=not (taken or redirected), valid=is_valid_slug(slug))


@router.post("/category", response_model=CategoryResponse)
async def resolve_category(payload: CategoryRequest) -> CategoryResponse:
    return CategoryResponse(category=match_category(payload.spoken, payload.lang))
