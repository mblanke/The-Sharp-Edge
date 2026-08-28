from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.auth import require_token
from app.db import get_session
from app.models import Recipe
from app.services.coverage import book_coverage, describe
from app.services.gf_audit import audit

router = APIRouter(prefix="/admin", tags=["admin"], dependencies=[Depends(require_token)])

#: What to run on Atlas to make a book searchable. Ingestion is Atlas's job (CLAUDE.md
#: §9) so this app reports the gap and hands over the command rather than acting.
#: Full context in docs/atlas-runbook.md.
RUNBOOK: dict[str, str] = {
    "under-pressure": "extract the 6 split .zip parts, then re-sweep",
    "flavor-bible": "extract the 4 split .zip parts, then re-sweep",
    "modernist-cuisine": "delete the 1 KB blurb .txt and force-ingest the PDFs",
    "modernist-bread": "force-ingest the PDF (never attempted — absent from /failed)",
    "fat-duck": "force-ingest the PDF (never attempted)",
    "japanese-cooking": "force-ingest the PDF (never attempted)",
    "hamelman-bread": "force-ingest the PDF; the indexed files are download stubs",
    "kitchen-confidential": "corrupt EPUB, 426 failed retries — replace the file",
}


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


@router.get("/library/coverage")
async def library_coverage(refresh: bool = False):
    """Which books are genuinely searchable, and which only look like they are.

    Ingestion belongs to Atlas, so this reports rather than repairs — but a gap nobody
    can see is a gap nobody fixes, and these had been silent for months. `fix` carries
    the operator command for each problem; see docs/atlas-runbook.md.
    """
    coverage = await book_coverage(force=refresh)
    if not coverage:
        return {"available": False, "reason": "coverage index unreachable", "books": []}

    books = sorted(coverage.values(), key=lambda c: (c.status != "missing", -c.chunks))
    return {
        "available": True,
        "searchable": sum(1 for c in books if c.searchable),
        "total": len(books),
        "books": [
            {
                "id": c.book_id,
                "title": c.title,
                "chunks": c.chunks,
                "status": c.status,
                "note": describe(c.book_id, c.chunks),
                "fix": RUNBOOK.get(c.book_id) if c.status != "indexed" else None,
            }
            for c in books
        ],
    }
