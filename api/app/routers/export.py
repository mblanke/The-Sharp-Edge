from fastapi import APIRouter, Depends
from fastapi.responses import PlainTextResponse, Response
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.auth import require_token
from app.db import get_session
from app.models import Recipe
from app.services.cards import build_cards_pdf
from app.services.master_export import render_master

router = APIRouter(prefix="/export", tags=["export"])


async def _active_recipes(session: AsyncSession) -> list[Recipe]:
    return list(
        (
            await session.execute(
                select(Recipe)
                .where(Recipe.status != "archived")
                .options(selectinload(Recipe.versions))
            )
        )
        .scalars()
        .all()
    )


@router.get("/master.md", dependencies=[Depends(require_token)])
async def export_master(session: AsyncSession = Depends(get_session)):
    """Regenerate recipes-master.md from the DB (auth: the file enumerates the
    whole notebook; recipes are all owner-authored/public tier)."""
    recipes = await _active_recipes(session)
    return PlainTextResponse(
        render_master(recipes),
        media_type="text/markdown; charset=utf-8",
        headers={"content-disposition": 'attachment; filename="recipes-master.md"'},
    )


@router.get("/cards.pdf", dependencies=[Depends(require_token)])
async def export_cards(session: AsyncSession = Depends(get_session)):
    """Regenerate the print-card deck (§10): 2-up landscape letter, dashed cut
    lines, allocation table + glue-in index up front, QR per card."""
    recipes = await _active_recipes(session)
    return Response(
        content=build_cards_pdf(recipes),
        media_type="application/pdf",
        headers={"content-disposition": 'attachment; filename="cards.pdf"'},
    )
