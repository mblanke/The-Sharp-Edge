"""sqlite-backed API for Playwright e2e runs — no Postgres or Docker needed.

Seeds the 18 notebook recipes from seed/recipes-master.md into a throwaway
sqlite file, then serves the real FastAPI app. Launched by web/playwright.config.ts.
"""

import asyncio
import os
import sys
from pathlib import Path

API_DIR = Path(__file__).resolve().parent.parent
REPO = API_DIR.parent
DB_FILE = API_DIR / ".e2e" / "e2e.db"

# Config must be set before app.config is imported.
DB_FILE.parent.mkdir(exist_ok=True)
if DB_FILE.exists():
    DB_FILE.unlink()  # fresh seed every run
os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{DB_FILE}"
os.environ.setdefault("API_TOKEN", "e2e-token")
os.environ.setdefault("BASE_URL", "http://127.0.0.1:4173")

sys.path.insert(0, str(REPO / "seed"))

import uvicorn  # noqa: E402

from app.db import Base, engine  # noqa: E402
from app.main import app  # noqa: E402
from import_master import load, parse_master  # noqa: E402


def install_rag_stubs() -> None:
    """Canned retrieval + provider so /ask is e2e-testable without the tailnet.

    The passage below is deliberately recipe-shaped and >120 chars: the citation
    panel's "draft into notebook" button appears and the deterministic passage
    parser must structure it — so the e2e covers ask → citation → draft end to end.
    The source_path is a real indexed path shape, so `shelf.resolve_path` and the
    attribution check run their genuine code paths.
    """
    import app.routers.ask as ask_module
    import app.routers.library as library_module

    passage = (
        "Onion Soup\n"
        "Makes 1 gal/3.84 L\n"
        "5 lb/2.27 kg thinly sliced onions\n"
        "2 oz/57 g clarified or whole butter\n"
        "1 gal/3.84 L Chicken or White Beef Stock, warm\n"
        "Salt, as needed\n"
        "1. Caramelize the onions in the butter until browned, 25 to 30 minutes.\n"
        "2. Add the stock and simmer for 30 minutes. Season and serve."
    )
    chunks = [
        {
            "text": passage,
            "source_path": "/mnt/references/Cooking/Culinary Institute of America - "
            "The Professional Chef (9th edition).pdf",
            "title": "The Professional Chef",
            "heading": "Soups",
            "page": 358,
            "page_end": 358,
            "file_type": "pdf",
            "score": 4.2,
            "rerank_score": 4.2,
        }
    ]

    class StubRag:
        async def retrieve(self, question, top_k=None, books=None, as_passages=True):
            return chunks

        async def health(self):
            return {"ok": True, "qdrant_points": 50_511}

    class StubProvider:
        async def stream_chat(self, messages, *, has_corpus_chunks=False):
            for token in ("Caramelize the onions slowly, ", "then simmer in stock [1]."):
                yield token

    ask_module.atlas_rag = StubRag()
    library_module.atlas_rag = StubRag()

    # batch import without the network: every link is a small canned recipe named
    # after its path, and one path fails on purpose
    import app.routers.imports as imports_module
    from fastapi import HTTPException

    async def stub_import(url, provider):
        name = url.rstrip("/").rsplit("/", 1)[-1].replace("-", " ").title() or "Imported"
        if "broken" in url:
            raise HTTPException(422, "No recipe on that page")
        return {
            "draft": {
                "title": name, "meta": "imported for review", "base_yield": 4, "yield_word": "servings",
                "ingredients": [{"amount": 1, "unit": "cup", "name": "stock"}],
                "steps": [{"text": "Simmer."}], "notes": [],
            },
            "source": "example.com",
            "gf_risks": [],
        }

    imports_module.import_from_url = stub_import  # type: ignore[assignment]
    imports_module.get_provider = lambda: StubProvider()  # type: ignore[assignment]
    ask_module.get_provider = lambda: StubProvider()  # type: ignore[assignment]


async def prepare() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    master = (REPO / "seed" / "recipes-master.md").read_text(encoding="utf-8")
    await load(parse_master(master), force=False)


if __name__ == "__main__":
    asyncio.run(prepare())
    install_rag_stubs()
    uvicorn.run(app, host="127.0.0.1", port=int(os.environ.get("PORT", "8001")))
