from pathlib import Path
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.config import settings
from app.auth import require_token
from app.db import get_session
from app.models import Conversation
from app.schemas.chat import BookOut, ChunkOut, ConversationFull, ConversationSummary, LibraryStatus
from app.services.atlas_rag import atlas_rag
from app.services.coverage import book_coverage, describe
from app.services.shelf import resolve_path
from app.services.source_page import SourceError, extract_page, resolve_source

router = APIRouter(tags=["library"])


@router.get("/search", response_model=list[ChunkOut])
async def search(
    q: str = Query(min_length=2),
    top_k: int = Query(default=8, ge=1, le=20),
    book: str | None = None,
):
    """Fast retrieval from the Cooking corpus — vector + rerank, no LLM.
    `book` restricts to one source file (client-side filter; `kind=` awaits
    chunk metadata from Atlas)."""
    chunks = await atlas_rag.retrieve(q, top_k=top_k, books=[book] if book else None)
    return [ChunkOut.model_validate(c) for c in chunks]


@router.get("/library/books", response_model=LibraryStatus)
async def library_books():
    """The shelf, reconciled against what is actually searchable.

    The file list and the index were never compared, so a book that failed to ingest
    looked exactly like one that worked. Several had been broken for months in silence —
    Under Pressure and The Flavor Bible still sealed in split archives, Modernist Cuisine
    represented by two chunks off a blurb file. Each entry now carries its coverage, and
    a null status means the lookup was unavailable, not that the book is missing.
    """
    health = await atlas_rag.health()
    coverage = await book_coverage()
    books: list[BookOut] = []
    mounted = False
    lib = settings.library_dir
    if lib:
        root = Path(lib)
        if root.is_dir():
            mounted = True
            for entry in sorted(root.iterdir(), key=lambda p: p.name.lower()):
                if entry.name.startswith("."):
                    continue
                try:
                    size = entry.stat().st_size if entry.is_file() else None
                except OSError:
                    size = None
                status = chunks = note = None
                if coverage:
                    book_id = resolve_path(str(entry))
                    found = coverage.get(book_id) if book_id else None
                    if found:
                        status, chunks = found.status, found.chunks
                        note = describe(found.book_id, found.chunks)
                    else:
                        # On the shelf, claimed by no book in the table — a stray file, or
                        # a book nobody has added yet. Either way it is not searchable.
                        status, chunks = "missing", 0
                        note = f"{entry.name} — not indexed"
                books.append(
                    BookOut(
                        name=entry.name,
                        kind="file" if entry.is_file() else "folder",
                        size_bytes=size,
                        status=status,
                        chunks=chunks,
                        note=note,
                    )
                )
    return LibraryStatus(mounted=mounted, library_dir=lib or None, books=books, rag_health=health)


@router.get("/conversations", response_model=list[ConversationSummary])
async def list_conversations(session: AsyncSession = Depends(get_session)):
    rows = (
        (await session.execute(select(Conversation).order_by(Conversation.created_at.desc()).limit(50)))
        .scalars()
        .all()
    )
    return [ConversationSummary.model_validate(c) for c in rows]


@router.get("/conversations/{conversation_id}", response_model=ConversationFull)
async def get_conversation(conversation_id: UUID, session: AsyncSession = Depends(get_session)):
    conversation = (
        await session.execute(
            select(Conversation)
            .where(Conversation.id == conversation_id)
            .options(selectinload(Conversation.messages))
        )
    ).scalar_one_or_none()
    if conversation is None:
        raise HTTPException(404, "No such conversation")
    return ConversationFull.model_validate(conversation)


@router.get("/library/source", dependencies=[Depends(require_token)])
async def library_source(path: str, page: int):
    """One page of a source book, as a one-page PDF.

    The point of the feature: extraction only has to be good enough to *find* the page,
    and then you read the real thing — layout, photographs and all — rather than a
    reconstruction that might have missed a line of the method.

    Requires a token. Everything else in the library is metadata or short quoted
    passages; this returns actual book content, and CLAUDE.md §1 keeps the corpus inside
    the local deployment. One page at a time, PDFs only — there is deliberately no route
    that hands over a whole book.
    """
    try:
        pdf = resolve_source(path, settings.library_dir)
        data = extract_page(pdf, page)
    except SourceError as exc:
        raise HTTPException(404, str(exc)) from exc

    return Response(
        content=data,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'inline; filename="page-{page}.pdf"',
            "Cache-Control": "private, max-age=3600",
        },
    )
