from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from app.config import settings


class Base(DeclarativeBase):
    pass


engine = create_async_engine(settings.database_url, echo=False)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False)


async def get_session() -> AsyncIterator[AsyncSession]:
    async with SessionLocal() as session:
        yield session


def get_sessionmaker() -> async_sessionmaker[AsyncSession]:
    """For code that outlives the request scope (e.g. SSE generators), which must
    open its own session — the Depends(get_session) one is torn down with the
    dependency stack and can close before a stream finishes."""
    return SessionLocal
