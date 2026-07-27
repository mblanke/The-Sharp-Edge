import io

import qrcode
from fastapi import APIRouter, Depends, HTTPException, Response
from qrcode.constants import ERROR_CORRECT_H
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.auth import require_token
from app.config import settings
from app.db import get_session
from app.models import Recipe, RecipeVersion, Redirect
from app.schemas.recipe import (
    RecipeCard,
    RecipeCreate,
    RecipeFull,
    RecipeUpdate,
    ScaleRequest,
    ScaleResponse,
    VersionOut,
    VersionSummary,
)
from app.services.scaling import scale_ingredients

router = APIRouter(prefix="/recipes", tags=["recipes"])

MAX_SCALE_FACTOR = 4


async def _resolve(session: AsyncSession, slug: str, *, with_versions: bool = False) -> Recipe:
    """Fetch by slug, honouring the redirect table (renamed slugs keep working)."""
    q = select(Recipe).where(Recipe.slug == slug)
    if with_versions:
        q = q.options(selectinload(Recipe.versions))
    recipe = (await session.execute(q)).scalar_one_or_none()
    if recipe is None:
        target = (
            await session.execute(select(Redirect.slug).where(Redirect.old_slug == slug))
        ).scalar_one_or_none()
        if target:
            return await _resolve(session, target, with_versions=with_versions)
        raise HTTPException(404, f"No recipe with slug '{slug}'")
    return recipe


def _current_version(recipe: Recipe) -> RecipeVersion:
    current = [v for v in recipe.versions if v.is_current]
    if not current:
        raise HTTPException(500, f"Recipe '{recipe.slug}' has no current version")
    return current[-1]


def _full(recipe: Recipe) -> RecipeFull:
    return RecipeFull(
        **RecipeCard.model_validate(recipe).model_dump(),
        source=recipe.source,
        current_version=VersionOut.model_validate(_current_version(recipe)),
    )


@router.get("", response_model=list[RecipeCard])
async def list_recipes(
    category: str | None = None,
    q: str | None = None,
    gf: bool | None = None,
    status: str = "active",
    session: AsyncSession = Depends(get_session),
):
    query = select(Recipe).order_by(Recipe.category, Recipe.title)
    if status != "all":
        query = query.where(Recipe.status == status)
    if category:
        query = query.where(Recipe.category == category)
    if q:
        query = query.where(Recipe.title.ilike(f"%{q}%"))
    if gf is not None:
        query = query.where(Recipe.gf == gf)
    recipes = (await session.execute(query)).scalars().all()
    return [RecipeCard.model_validate(r) for r in recipes]


@router.get("/{slug}", response_model=RecipeFull)
async def get_recipe(slug: str, session: AsyncSession = Depends(get_session)):
    recipe = await _resolve(session, slug, with_versions=True)
    return _full(recipe)


@router.get("/{slug}/versions", response_model=list[VersionSummary])
async def list_versions(slug: str, session: AsyncSession = Depends(get_session)):
    recipe = await _resolve(session, slug, with_versions=True)
    return [VersionSummary.model_validate(v) for v in recipe.versions]


@router.get("/{slug}/versions/{version}", response_model=VersionOut)
async def get_version(slug: str, version: int, session: AsyncSession = Depends(get_session)):
    """The full body of one past version.

    /versions returns metadata only, so until now an old version existed in the
    database but could not be read back — the append-only history was write-only,
    and the version switcher had nothing to switch to.
    """
    recipe = await _resolve(session, slug, with_versions=True)
    match = next((v for v in recipe.versions if v.version == version), None)
    if match is None:
        raise HTTPException(404, f"Recipe '{slug}' has no version {version}")
    return VersionOut.model_validate(match)


@router.post("/{slug}/versions/{version}/restore", response_model=RecipeFull,
             dependencies=[Depends(require_token)])
async def restore_version(slug: str, version: int, session: AsyncSession = Depends(get_session)):
    """Bring a past version back as a new current version.

    Append-only, like every other write: restoring v1 over v6 creates v7 with v1's
    contents. Nothing is destroyed, so a restore is itself undoable — which is the
    whole point of keeping the history.
    """
    recipe = await _resolve(session, slug, with_versions=True)
    source = next((v for v in recipe.versions if v.version == version), None)
    if source is None:
        raise HTTPException(404, f"Recipe '{slug}' has no version {version}")
    if source.is_current:
        return _full(recipe)

    next_number = max(v.version for v in recipe.versions) + 1
    # Snapshot the body before flipping flags — `source` stays attached to the
    # session and the collection is about to be mutated underneath it.
    ingredients, steps, notes = source.ingredients, source.steps, source.notes
    label = source.label or f"restored v{source.version}"
    for v in recipe.versions:
        v.is_current = False
    # Append through the relationship, as update_recipe does. Adding a standalone row
    # leaves recipe.versions stale, and _full() then finds no current version.
    recipe.versions.append(
        RecipeVersion(version=next_number, label=label, ingredients=ingredients,
                      steps=steps, notes=notes, is_current=True)
    )
    await session.commit()
    await session.refresh(recipe, ["versions"])
    return _full(recipe)


@router.post("", response_model=RecipeFull, status_code=201, dependencies=[Depends(require_token)])
async def create_recipe(payload: RecipeCreate, session: AsyncSession = Depends(get_session)):
    exists = (
        await session.execute(select(func.count()).select_from(Recipe).where(Recipe.slug == payload.slug))
    ).scalar_one()
    if exists:
        raise HTTPException(409, f"Slug '{payload.slug}' already exists")
    recipe = Recipe(
        slug=payload.slug,
        title=payload.title,
        category=payload.category,
        meta=payload.meta,
        base_yield=payload.base_yield,
        yield_word=payload.yield_word,
        gf=payload.gf,
        noscale=payload.noscale,
        source=payload.source,
        status=payload.status,
    )
    recipe.versions.append(
        RecipeVersion(
            version=1,
            label=payload.label,
            ingredients=[i.model_dump(exclude_none=True) for i in payload.ingredients],
            steps=[s.model_dump(exclude_none=True) for s in payload.steps],
            notes=payload.notes,
            is_current=True,
        )
    )
    session.add(recipe)
    await session.commit()
    await session.refresh(recipe, ["versions"])
    return _full(recipe)


@router.put("/{slug}", response_model=RecipeFull, dependencies=[Depends(require_token)])
async def update_recipe(slug: str, payload: RecipeUpdate, session: AsyncSession = Depends(get_session)):
    """Append-only: every PUT creates a new version and marks it current."""
    recipe = await _resolve(session, slug, with_versions=True)
    for field in ("title", "category", "meta", "base_yield", "yield_word", "gf", "noscale", "source", "status"):
        value = getattr(payload, field)
        if value is not None:
            setattr(recipe, field, value)
    for v in recipe.versions:
        v.is_current = False
    next_version = max((v.version for v in recipe.versions), default=0) + 1
    recipe.versions.append(
        RecipeVersion(
            version=next_version,
            label=payload.label,
            ingredients=[i.model_dump(exclude_none=True) for i in payload.ingredients],
            steps=[s.model_dump(exclude_none=True) for s in payload.steps],
            notes=payload.notes,
            is_current=True,
        )
    )
    await session.commit()
    await session.refresh(recipe, ["versions"])
    return _full(recipe)


@router.post("/{slug}/scale", response_model=ScaleResponse)
async def scale_recipe(slug: str, payload: ScaleRequest, session: AsyncSession = Depends(get_session)):
    recipe = await _resolve(session, slug, with_versions=True)
    if recipe.noscale:
        raise HTTPException(400, f"'{recipe.slug}' is a reference card and does not scale")
    if payload.target_yield > recipe.base_yield * MAX_SCALE_FACTOR:
        raise HTTPException(400, f"Max scale is {MAX_SCALE_FACTOR}× base ({recipe.base_yield * MAX_SCALE_FACTOR})")
    version = _current_version(recipe)
    scaled = scale_ingredients(version.ingredients, recipe.base_yield, payload.target_yield)
    return ScaleResponse(
        slug=recipe.slug,
        base_yield=recipe.base_yield,
        target_yield=payload.target_yield,
        yield_word=recipe.yield_word,
        ingredients=scaled,
    )


@router.get("/{slug}/qr")
async def recipe_qr(slug: str, session: AsyncSession = Depends(get_session)):
    recipe = await _resolve(session, slug)
    qr = qrcode.QRCode(error_correction=ERROR_CORRECT_H, box_size=8, border=2)
    qr.add_data(f"{settings.base_url.rstrip('/')}/r/{recipe.slug}")
    qr.make(fit=True)
    img = qr.make_image(fill_color="#14161C", back_color="white")
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return Response(content=buf.getvalue(), media_type="image/png")
