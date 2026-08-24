import secrets

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import settings

_bearer = HTTPBearer(auto_error=False)

# The placeholder shipped in .env.example — a publicly known value, never a valid credential.
DEFAULT_TOKEN = "change-me-long-random"


def token_configured() -> bool:
    return bool(settings.api_token) and settings.api_token != DEFAULT_TOKEN


async def require_token(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> None:
    """Single-user bearer auth for write/admin routes (CLAUDE.md §3). Fails closed:
    with no real API_TOKEN configured, write routes are unavailable rather than
    guarded by the publicly known placeholder."""
    if not token_configured():
        raise HTTPException(
            status_code=503,
            detail="API_TOKEN is not configured; write routes are disabled",
        )
    if credentials is None or not secrets.compare_digest(
        credentials.credentials, settings.api_token
    ):
        raise HTTPException(status_code=401, detail="Missing or invalid bearer token")
