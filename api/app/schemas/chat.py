from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class AskScope(BaseModel):
    recipe_slug: str | None = None
    # restrict retrieval to these source files (book names from /library/books)
    books: list[str] = []


class AskRequest(BaseModel):
    question: str = Field(min_length=1, max_length=4000)
    conversation_id: UUID | None = None
    scope: AskScope = AskScope()
    top_k: int = Field(default=8, ge=1, le=20)


class ChunkOut(BaseModel):
    model_config = ConfigDict(extra="ignore")

    text: str
    source_path: str | None = None
    title: str | None = None
    heading: str | None = None
    page: int | None = None
    #: Last page of the passage when adjacent chunks were merged; equals `page` otherwise.
    page_end: int | None = None
    #: How many retrieved chunks this passage is made of (1 = unmerged).
    chunk_count: int | None = None
    score: float | None = None
    rerank_score: float | None = None


class Citation(BaseModel):
    n: int
    title: str | None = None
    source_path: str | None = None
    heading: str | None = None
    page: int | None = None


class MessageOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    role: str
    content: str
    citations: list[Citation]
    created_at: datetime


class ConversationSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    title: str | None = None
    created_at: datetime


class ConversationFull(ConversationSummary):
    messages: list[MessageOut]


class BookOut(BaseModel):
    name: str
    kind: str  # file | folder
    size_bytes: int | None = None


class LibraryStatus(BaseModel):
    mounted: bool
    library_dir: str | None = None
    books: list[BookOut]
    rag_health: dict
