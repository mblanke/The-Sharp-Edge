import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.auth import token_configured
from app.config import settings
from app.problems import install_problem_handlers
from app.routers import ask, export, library, plan, recipes

logger = logging.getLogger("sharp-edge")


def create_app() -> FastAPI:
    app = FastAPI(title="The Sharp Edge API", version="0.1.0", docs_url="/api/docs")
    if not token_configured():
        logger.warning(
            "API_TOKEN is unset or still the placeholder — write routes will return 503"
        )
    # The web app talks through its same-origin proxy; browsers only need CORS
    # for the app's own origins — never the whole tailnet.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    install_problem_handlers(app)

    app.include_router(recipes.router, prefix="/api/v1")
    app.include_router(library.router, prefix="/api/v1")
    app.include_router(ask.router, prefix="/api/v1")
    app.include_router(export.router, prefix="/api/v1")
    app.include_router(plan.router, prefix="/api/v1")

    @app.get("/api/v1/healthz")
    async def healthz():
        return {"status": "ok"}

    return app


app = create_app()
