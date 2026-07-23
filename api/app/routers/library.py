from pathlib import Path
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.config import settings
from app.db import get_session
from app.models import Conversation
from app.schemas.chat import BookOut, ChunkOut, ConversationFull, ConversationSummary, LibraryStatus
from app.services.atlas_rag import atlas_rag

router = APIRouter(tags=["library"])


@router.get("/search", response_model=list[ChunkOut])
async def search(q: str = Query(min_length=2), top_k: int = Query(default=8, ge=1, le=20)):
    """Fast retrieval from the Cooking corpus — vector + rerank, no LLM."""
    return [ChunkOut.model_validate(c) for c in await atlas_rag.retrieve(q, top_k=top_k)]


@router.get("/library/books", response_model=LibraryStatus)
async def library_books():
    """Book list from the mounted NAS folder (when mounted) + rag-api health."""
    health = await atlas_rag.health()
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
                books.append(
                    BookOut(name=entry.name, kind="file" if entry.is_file() else "folder", size_bytes=size)
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
