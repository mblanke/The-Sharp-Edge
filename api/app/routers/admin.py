from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.auth import require_token
from app.db import get_session
from app.models import Recipe
from app.services.gf_audit import audit

router = APIRouter(prefix="/admin", tags=["admin"], dependencies=[Depends(require_token)])


@router.get("/gf-audit")
async def gf_audit(session: AsyncSession = Depends(get_session)):
    """Celiac safety sweep: every active recipe's current ingredients checked
    against the hidden-gluten rules."""
    recipes = (
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
    rows = audit(recipes)
    return {
        "warnings": [r for r in rows if r["verdict"] == "warning"],
        "candidates": [r for r in rows if r["verdict"] == "candidate"],
        "ok": sum(1 for r in rows if r["verdict"] == "ok"),
    }
