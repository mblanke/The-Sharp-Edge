"""Batch import: a list of links or a folder of photos → drafts to review."""

from __future__ import annotations

from fastapi import APIRouter, Depends, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import require_token
from app.db import get_session
from app.services.batch_import import create_draft
from app.services.import_url import import_from_url
from app.services.llm import get_provider
from app.services.photo_import import parse_photo

router = APIRouter(prefix="/import", tags=["import"], dependencies=[Depends(require_token)])


class BatchUrls(BaseModel):
    urls: list[str] = Field(min_length=1, max_length=50)


class Created(BaseModel):
    slug: str
    title: str
    source: str | None = None


class Failed(BaseModel):
    item: str
    error: str


class BatchResult(BaseModel):
    created: list[Created]
    failed: list[Failed]


@router.post("/batch", response_model=BatchResult)
async def batch_urls(payload: BatchUrls, session: AsyncSession = Depends(get_session)):
    """Each link becomes a draft; a link that fails is reported and the rest carry on."""
    created: list[Created] = []
    failed: list[Failed] = []
    provider = get_provider()
    seen: set[str] = set()
    for raw in payload.urls:
        url = raw.strip()
        if not url or url in seen:
            continue
        seen.add(url)
        try:
            result = await import_from_url(url, provider)
            recipe = await create_draft(
                session, result["draft"], source=result.get("source"), label="imported from url"
            )
            created.append(Created(slug=recipe.slug, title=recipe.title, source=recipe.source))
        except Exception as exc:  # one bad link must not sink the batch
            failed.append(Failed(item=url, error=_message(exc)))
    await session.commit()
    return BatchResult(created=created, failed=failed)


@router.post("/batch/photos", response_model=BatchResult)
async def batch_photos(photos: list[UploadFile], session: AsyncSession = Depends(get_session)):
    """Each photographed page becomes a draft, read by the local vision model."""
    created: list[Created] = []
    failed: list[Failed] = []
    for photo in photos[:50]:
        name = photo.filename or "photo"
        try:
            draft = await parse_photo(await photo.read(), photo.content_type or "")
            recipe = await create_draft(session, _as_dict(draft), source=None, label="from photo")
            created.append(Created(slug=recipe.slug, title=recipe.title))
        except Exception as exc:
            failed.append(Failed(item=name, error=_message(exc)))
    await session.commit()
    return BatchResult(created=created, failed=failed)


def _as_dict(draft) -> dict:
    if isinstance(draft, dict):
        return draft.get("draft", draft)
    return draft.model_dump()


def _message(exc: Exception) -> str:
    detail = getattr(exc, "detail", None)
    return str(detail or exc) or exc.__class__.__name__
