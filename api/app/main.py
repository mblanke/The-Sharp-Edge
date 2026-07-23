from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.problems import install_problem_handlers
from app.routers import ask, library, recipes


def create_app() -> FastAPI:
    app = FastAPI(title="The Sharp Edge API", version="0.1.0", docs_url="/api/docs")
    # Household app behind Tailscale; the web container and LAN clients are trusted.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )
    install_problem_handlers(app)

    app.include_router(recipes.router, prefix="/api/v1")
    app.include_router(library.router, prefix="/api/v1")
    app.include_router(ask.router, prefix="/api/v1")

    @app.get("/api/v1/healthz")
    async def healthz():
        return {"status": "ok"}

    return app


app = create_app()
