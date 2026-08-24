import json
import uuid

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker
from sqlalchemy.orm import selectinload

from app.db import get_session, get_sessionmaker
from app.models import Conversation, Message, Recipe
from app.schemas.chat import AskRequest
from app.services.atlas_rag import atlas_rag
from app.services.citations import SYSTEM_PROMPT, chunks_block, extract_citations
from app.services.llm import get_provider

router = APIRouter(tags=["ask"])


def _sse(event: str, data: dict) -> str:
    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


async def _recipe_context(session: AsyncSession, slug: str | None) -> str:
    if not slug:
        return ""
    recipe = (
        await session.execute(
            select(Recipe).where(Recipe.slug == slug).options(selectinload(Recipe.versions))
        )
    ).scalar_one_or_none()
    if recipe is None:
        return ""
    current = next((v for v in recipe.versions if v.is_current), None)
    payload = {
        "title": recipe.title,
        "category": recipe.category,
        "base_yield": recipe.base_yield,
        "yield_word": recipe.yield_word,
        "gf": recipe.gf,
        "ingredients": current.ingredients if current else [],
        "steps": current.steps if current else [],
        "notes": current.notes if current else [],
    }
    return (
        "\n\nThe user is currently looking at this recipe from their notebook; "
        "treat it as the working context:\n" + json.dumps(payload, ensure_ascii=False)
    )


@router.post("/ask")
async def ask(
    payload: AskRequest,
    session: AsyncSession = Depends(get_session),
    session_factory: async_sessionmaker[AsyncSession] = Depends(get_sessionmaker),
):
    # conversation setup + user message persisted before streaming starts
    if payload.conversation_id:
        conversation = (
            await session.execute(
                select(Conversation)
                .where(Conversation.id == payload.conversation_id)
                .options(selectinload(Conversation.messages))
            )
        ).scalar_one_or_none()
    else:
        conversation = None
    if conversation is None:
        conversation = Conversation(id=uuid.uuid4(), title=payload.question[:80])
        session.add(conversation)
    history = [
        {"role": m.role, "content": m.content}
        for m in (conversation.messages if conversation.messages else [])
    ]
    session.add(Message(conversation_id=conversation.id, role="user", content=payload.question))
    await session.commit()
    conversation_id = str(conversation.id)

    chunks = await atlas_rag.retrieve(payload.question, top_k=payload.top_k)
    recipe_ctx = await _recipe_context(session, payload.scope.recipe_slug)

    user_content = payload.question
    if chunks:
        user_content += (
            "\n\nSource excerpts (cite these — put the bracket number, e.g. [2], "
            "immediately after every claim you take from one):\n" + chunks_block(chunks)
        )
    messages = (
        [{"role": "system", "content": SYSTEM_PROMPT + recipe_ctx}]
        + history
        + [{"role": "user", "content": user_content}]
    )

    provider = get_provider()

    async def stream():
        yield _sse("meta", {"conversation_id": conversation_id, "chunks": len(chunks)})
        answer_parts: list[str] = []
        try:
            async for token in provider.stream_chat(messages, has_corpus_chunks=bool(chunks)):
                answer_parts.append(token)
                yield _sse("token", {"t": token})
        except Exception as exc:  # surfaced to the client instead of a dead stream
            yield _sse("error", {"detail": str(exc)})
            return
        answer = "".join(answer_parts)
        citations = extract_citations(answer, chunks)
        if not citations and chunks:
            # local models don't always emit [n] markers — fall back to the top sources used
            citations = [
                {
                    "n": i + 1,
                    "title": c.get("title"),
                    "source_path": c.get("source_path"),
                    "heading": c.get("heading"),
                    "page": c.get("page"),
                }
                for i, c in enumerate(chunks[:3])
            ]
        # The request-scoped session can be torn down before the stream drains;
        # persist on a session owned by the generator itself.
        async with session_factory() as write_session:
            write_session.add(
                Message(
                    conversation_id=uuid.UUID(conversation_id),
                    role="assistant",
                    content=answer,
                    citations=citations,
                )
            )
            await write_session.commit()
        sources = [
            {
                "n": i + 1,
                "title": c.get("title"),
                "source_path": c.get("source_path"),
                "heading": c.get("heading"),
                "page": c.get("page"),
                "text": c.get("text", "")[:600],
            }
            for i, c in enumerate(chunks)
        ]
        yield _sse("done", {"citations": citations, "sources": sources})

    return StreamingResponse(
        stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
