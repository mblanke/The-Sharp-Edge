from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+asyncpg://sharpedge:sharpedge@localhost:5432/sharpedge"
    base_url: str = "http://localhost:3000"
    api_token: str = "change-me-long-random"
    anthropic_api_key: str = ""
    # Router alias of a local multimodal model (photo-to-recipe import).
    # Empty disables the feature; "vision" = llava:13b on Wile today.
    vision_model_alias: str = "vision"
    # Router alias of a local instruct model used to translate a recipe's words.
    translate_model_alias: str = "translate"

    # Browser origins allowed by CORS; the web app itself goes through its
    # same-origin proxy, so this only needs the app's own base URL (plus any
    # extra Tailscale/LAN hostnames, comma-separated in CORS_ORIGINS).
    cors_origins: str = ""

    @property
    def cors_origin_list(self) -> list[str]:
        extra = [o.strip() for o in self.cors_origins.split(",") if o.strip()]
        return list(dict.fromkeys([self.base_url, *extra]))

    # Atlas RAG stack (see CLAUDE.md §9 — retrieval and embedding are delegated)
    rag_api_url: str = "http://100.110.190.10:8099"
    rag_source_folder: str = "Cooking"
    rag_top_k: int = 8
    rag_fetch_k: int = 24  # over-fetch before the client-side folder filter
    # A question that names a book runs a second, deeper search that is then filtered
    # down to that book. It has to be deep because a named book can sit well below the
    # normal cut: measured, the Professional Chef's onion soup was at rank 25 for
    # "How does the CIA make french onion soup". Only paid when a book is named.
    rag_named_book_fetch_k: int = 150
    annotation_min_score: float = 0.4  # floor for technique margin notes (F5)

    # Qdrant, read-only and payload-only: the coverage report facets `source_path` to
    # count what is actually indexed. No vector is ever read from this app (CLAUDE.md §9).
    qdrant_url: str = "http://qdrant:6333"
    qdrant_collection: str = "references_v2"

    # LiteLLM router on Atlas — OpenAI-compatible; 'cluster' balances Wile + RoadRunner
    llm_router_url: str = "http://100.110.190.10:4000/v1"
    llm_router_key: str = ""
    chat_model_alias: str = "cluster"

    # Optional read-only mount of the NAS Cooking folder for the /library book list
    library_dir: str = ""
    # The same folder as the *index* records it (rag-api's mount). The shelf can be
    # mounted anywhere locally — /library on Atlas — so matching a shelf entry to its
    # indexed chunks means translating the entry name onto this root, not comparing
    # local paths.
    rag_corpus_root: str = "/mnt/references/Cooking"


settings = Settings()
