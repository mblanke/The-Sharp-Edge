from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+asyncpg://sharpedge:sharpedge@localhost:5432/sharpedge"
    base_url: str = "http://localhost:3000"
    api_token: str = "change-me-long-random"
    anthropic_api_key: str = ""

    # Atlas RAG stack (see CLAUDE.md §9 — retrieval and embedding are delegated)
    rag_api_url: str = "http://100.110.190.10:8099"
    rag_source_folder: str = "Cooking"
    rag_top_k: int = 8
    rag_fetch_k: int = 24  # over-fetch before the client-side folder filter

    # LiteLLM router on Atlas — OpenAI-compatible; 'cluster' balances Wile + RoadRunner
    llm_router_url: str = "http://100.110.190.10:4000/v1"
    llm_router_key: str = ""
    chat_model_alias: str = "cluster"

    # Optional read-only mount of the NAS Cooking folder for the /library book list
    library_dir: str = ""


settings = Settings()
