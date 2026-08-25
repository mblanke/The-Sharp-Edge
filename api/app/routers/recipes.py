import io

import qrcode
from fastapi import APIRouter, Depends, HTTPException, Response, UploadFile
from pydantic import BaseModel, Field
from qrcode.constants import ERROR_CORRECT_H
from sqlalchemy import Text, cast, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.auth import require_token
from app.config import settings
from app.db import get_session
from app.models import CookSession, NotebookPage, Recipe, RecipeTag, RecipeVersion, Redirect, Tag
from app.schemas.recipe import (
    CookSessionCreate,
    CookSessionOut,
    PageRef,
    RecipeCard,
    RecipeCreate,
    RecipeFull,
    RecipeUpdate,
    ScaleRequest,
    ScaleResponse,
    VersionOut,
)
from app.services.scaling import scale_ingredients

router = APIRouter(prefix="/recipes", tags=["recipes"])

MAX_SCALE_FACTOR = 4


class ImportUrlRequest(BaseModel):
    url: str = Field(min_length=8, max_length=2000)


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
        pages=[PageRef.model_validate(p) for p in recipe.pages],
        current_version=VersionOut.model_validate(_current_version(recipe)),
    )


async def _resolve_tags(session: AsyncSession, names: list[str]) -> list[Tag]:
    """Get-or-create tags by name (case-insensitive dedupe, order preserved)."""
    cleaned: list[str] = []
    for name in names:
        name = name.strip()
        if name and name.lower() not in {c.lower() for c in cleaned}:
            cleaned.append(name)
    if not cleaned:
        return []
    existing = {
        t.name.lower(): t
        for t in (
            (await session.execute(select(Tag).where(func.lower(Tag.name).in_([c.lower() for c in cleaned]))))
            .scalars()
            .all()
        )
    }
    out: list[Tag] = []
    for name in cleaned:
        tag = existing.get(name.lower())
        if tag is None:
            tag = Tag(name=name)
            session.add(tag)
        out.append(tag)
    return out


@router.get("", response_model=list[RecipeCard])
async def list_recipes(
    category: str | None = None,
    q: str | None = None,
    ingredient: str | None = None,
    gf: bool | None = None,
    tag: str | None = None,
    status: str = "active",
    session: AsyncSession = Depends(get_session),
):
    query = select(Recipe).order_by(Recipe.category, Recipe.title)
    if status != "all":
        query = query.where(Recipe.status == status)
    if category:
        query = query.where(Recipe.category == category)
    if q:
        # "what can I make": titles, tag names, or current-version ingredients
        needle = f"%{q}%"
        current_ing = (
            select(RecipeVersion.recipe_id)
            .where(RecipeVersion.is_current, cast(RecipeVersion.ingredients, Text).ilike(needle))
            .scalar_subquery()
        )
        tagged = (
            select(RecipeTag.recipe_id)
            .join(Tag, Tag.id == RecipeTag.tag_id)
            .where(Tag.name.ilike(needle))
            .scalar_subquery()
        )
        query = query.where(
            Recipe.title.ilike(needle) | Recipe.id.in_(current_ing) | Recipe.id.in_(tagged)
        )
    if ingredient:
        query = query.where(
            Recipe.id.in_(
                select(RecipeVersion.recipe_id)
                .where(
                    RecipeVersion.is_current,
                    cast(RecipeVersion.ingredients, Text).ilike(f"%{ingredient}%"),
                )
                .scalar_subquery()
            )
        )
    if gf is not None:
        query = query.where(Recipe.gf == gf)
    if tag:
        query = (
            query.join(RecipeTag, RecipeTag.recipe_id == Recipe.id)
            .join(Tag, Tag.id == RecipeTag.tag_id)
            .where(func.lower(Tag.name) == tag.lower())
        )
    recipes = (await session.execute(query)).scalars().all()
    return [RecipeCard.model_validate(r) for r in recipes]


@router.get("/{slug}", response_model=RecipeFull)
async def get_recipe(slug: str, session: AsyncSession = Depends(get_session)):
    recipe = await _resolve(session, slug, with_versions=True)
    return _full(recipe)


@router.get("/{slug}/versions", response_model=list[VersionOut])
async def list_versions(slug: str, session: AsyncSession = Depends(get_session)):
    """Full version history, oldest first — the order the iOS app relies on;
    the web switcher re-sorts newest-first client-side."""
    recipe = await _resolve(session, slug, with_versions=True)
    ordered = sorted(recipe.versions, key=lambda v: v.version)
    return [VersionOut.model_validate(v) for v in ordered]


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
    recipe.tag_rows = await _resolve_tags(session, payload.tags)
    recipe.pages = [NotebookPage(page_number=p.page_number, section=p.section) for p in payload.pages]
    session.add(recipe)
    await session.commit()
    await session.refresh(recipe, ["versions", "tag_rows", "pages"])
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
    if payload.tags is not None:
        recipe.tag_rows = await _resolve_tags(session, payload.tags)
    if payload.pages is not None:
        recipe.pages = [
            NotebookPage(page_number=p.page_number, section=p.section) for p in payload.pages
        ]
    await session.commit()
    await session.refresh(recipe, ["versions", "tag_rows", "pages"])
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


@router.post("/parse-photo", dependencies=[Depends(require_token)])
async def parse_photo_endpoint(photo: UploadFile):
    """Owner's notebook photo → structured draft for the editor (E2). Never
    auto-saves; never accepts library content. Cloud call is public-tier only."""
    from app.services.photo_import import parse_photo

    draft = await parse_photo(await photo.read(), photo.content_type or "")
    return draft


@router.post("/import-url", dependencies=[Depends(require_token)])
async def import_url_endpoint(payload: "ImportUrlRequest"):
    """Recipe URL → structured draft for the editor (F4). Review-first —
    never auto-saved; source line = bare domain."""
    from app.services.import_url import import_from_url
    from app.services.llm import get_provider

    return await import_from_url(payload.url, get_provider())


@router.get("/{slug}/sessions", response_model=list[CookSessionOut])
async def list_sessions(
    slug: str, limit: int = 10, session: AsyncSession = Depends(get_session)
):
    """Cook history, newest first — app-only, never exported."""
    recipe = await _resolve(session, slug)
    rows = (
        (
            await session.execute(
                select(CookSession)
                .where(CookSession.recipe_id == recipe.id)
                .order_by(CookSession.finished_at.desc())
                .limit(max(1, min(limit, 50)))
            )
        )
        .scalars()
        .all()
    )
    return [CookSessionOut.model_validate(r) for r in rows]


@router.post(
    "/{slug}/sessions",
    response_model=CookSessionOut,
    status_code=201,
    dependencies=[Depends(require_token)],
)
async def log_session(
    slug: str, payload: CookSessionCreate, session: AsyncSession = Depends(get_session)
):
    recipe = await _resolve(session, slug)
    from app.models.recipe import utcnow

    finished = utcnow()
    row = CookSession(
        recipe_id=recipe.id,
        started_at=payload.started_at or finished,
        finished_at=finished,
        scaled_yield=payload.scaled_yield,
        notes=(payload.notes or "").strip() or None,
    )
    session.add(row)
    await session.commit()
    return CookSessionOut.model_validate(row)


def _annotation_out(a) -> dict:
    return {
        "step_index": a.step_index,
        "phrase": a.phrase,
        "title": a.title,
        "source_path": a.source_path,
        "heading": a.heading,
        "page": a.page,
        "snippet": a.snippet,
    }


@router.get("/{slug}/annotations")
async def list_annotations(slug: str, session: AsyncSession = Depends(get_session)):
    """Cached library margin notes for the current version (F5)."""
    from app.models import RecipeAnnotation

    recipe = await _resolve(session, slug, with_versions=True)
    current = _current_version(recipe)
    rows = (
        (
            await session.execute(
                select(RecipeAnnotation)
                .where(RecipeAnnotation.recipe_version_id == current.id)
                .order_by(RecipeAnnotation.step_index)
            )
        )
        .scalars()
        .all()
    )
    return {"annotated": bool(rows), "annotations": [_annotation_out(a) for a in rows]}


@router.post("/{slug}/annotate", dependencies=[Depends(require_token)])
async def annotate_recipe(
    slug: str, force: bool = False, session: AsyncSession = Depends(get_session)
):
    """Run retrieval over the current version's steps and cache the results.
    Skips work when the version is already annotated (unless force)."""
    from app.models import RecipeAnnotation
    from app.services.annotate import build_annotations

    recipe = await _resolve(session, slug, with_versions=True)
    current = _current_version(recipe)
    existing = (
        (
            await session.execute(
                select(RecipeAnnotation).where(RecipeAnnotation.recipe_version_id == current.id)
            )
        )
        .scalars()
        .all()
    )
    if existing and not force:
        return {"annotated": True, "annotations": [_annotation_out(a) for a in existing]}
    for row in existing:
        await session.delete(row)
    rows = await build_annotations(current.id, current.steps)
    session.add_all(rows)
    await session.commit()
    return {"annotated": bool(rows), "annotations": [_annotation_out(a) for a in rows]}


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
