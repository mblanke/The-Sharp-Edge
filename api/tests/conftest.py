import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.config import settings
from app.db import Base, get_session, get_sessionmaker
from app.main import app

TEST_TOKEN = "test-token-not-the-placeholder"


@pytest.fixture(autouse=True)
def configured_token(monkeypatch):
    """Auth fails closed on the placeholder token, so tests run with a real one."""
    monkeypatch.setattr(settings, "api_token", TEST_TOKEN)


@pytest.fixture
async def session_factory():
    engine = create_async_engine("sqlite+aiosqlite://")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    factory = async_sessionmaker(engine, expire_on_commit=False)
    yield factory
    await engine.dispose()


@pytest.fixture
async def client(session_factory):
    async def override_session():
        async with session_factory() as session:
            yield session

    app.dependency_overrides[get_session] = override_session
    app.dependency_overrides[get_sessionmaker] = lambda: session_factory
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c
    app.dependency_overrides.clear()


@pytest.fixture
def auth():
    return {"Authorization": f"Bearer {TEST_TOKEN}"}
