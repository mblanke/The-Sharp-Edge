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


async def prepare() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    master = (REPO / "seed" / "recipes-master.md").read_text(encoding="utf-8")
    await load(parse_master(master), force=False)


if __name__ == "__main__":
    asyncio.run(prepare())
    uvicorn.run(app, host="127.0.0.1", port=int(os.environ.get("PORT", "8001")))
