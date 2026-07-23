from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+asyncpg://sharpedge:sharpedge@localhost:5432/sharpedge"
    base_url: str = "http://localhost:3000"
    api_token: str = "change-me-long-random"
    ollama_url: str = "http://host.docker.internal:11434"
    embed_model: str = "nomic-embed-text"
    chat_model: str = "llama3.1:8b"
    anthropic_api_key: str = ""


settings = Settings()
