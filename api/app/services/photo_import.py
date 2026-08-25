"""Photo-to-recipe capture (E2): a photo of the owner's own notebook page
becomes a structured draft prefilled into the editor — never auto-saved.

Fully local: the photo goes to the LiteLLM router's `vision` alias (a
multimodal model on the GB10s) — nothing ever leaves the house, so there is
no tier question at all. First call after idle can be slow while Ollama
loads the vision model; the timeout allows for a cold start.
"""

import base64
import json
import re

import httpx
from fastapi import HTTPException
from pydantic import BaseModel, Field

from app.config import settings

ALLOWED_MEDIA = {"image/jpeg", "image/png", "image/webp", "image/gif"}
MAX_BYTES = 15 * 1024 * 1024
TIMEOUT = 300.0  # cold model load on the GB10s can take minutes

PROMPT = (
    "This is a photo of a handwritten or printed recipe page from the user's own "
    "notebook. Transcribe it as JSON with keys: title, meta (short subtitle or "
    "null), base_yield (int), yield_word, ingredients (list of {amount, unit, "
    "name, section} — units only g, ml, cup, tbsp, tsp, lb, oz, or empty for "
    "countable items; amount 0 means 'to taste'; section null unless the page "
    "groups ingredients), steps (list of {text, timer_seconds} — timer_seconds "
    "only for explicit durations, else null), notes (list of strings). Keep the "
    "cook's own wording; leave anything unreadable out rather than inventing it. "
    "Output ONLY the JSON."
)


class DraftIngredient(BaseModel):
    amount: float = 0
    unit: str = ""
    name: str
    section: str | None = None


class DraftStep(BaseModel):
    text: str
    timer_seconds: int | None = None


class RecipeDraft(BaseModel):
    title: str
    meta: str | None = None
    base_yield: int = Field(default=1, ge=1)
    yield_word: str = "servings"
    ingredients: list[DraftIngredient] = []
    steps: list[DraftStep] = []
    notes: list[str] = []


def enabled() -> bool:
    return bool(settings.vision_model_alias)


async def _complete(messages: list[dict]) -> str:
    """One non-streamed completion on the router's vision alias."""
    try:
        async with httpx.AsyncClient(
            base_url=settings.llm_router_url.rstrip("/"),
            timeout=httpx.Timeout(TIMEOUT, connect=10.0),
            headers={"Authorization": f"Bearer {settings.llm_router_key}"},
        ) as client:
            res = await client.post(
                "/chat/completions",
                json={
                    "model": settings.vision_model_alias,
                    "messages": messages,
                    "max_tokens": 4000,
                },
            )
            res.raise_for_status()
            return str(res.json()["choices"][0]["message"]["content"])
    except httpx.HTTPError as exc:
        raise HTTPException(502, f"Vision model unreachable: {exc}") from exc
    except (KeyError, IndexError, ValueError) as exc:
        raise HTTPException(502, "Vision model returned an unexpected response") from exc


async def parse_photo(image: bytes, media_type: str) -> RecipeDraft:
    """One local vision call → validated draft. Raises problem responses."""
    if not enabled():
        raise HTTPException(501, "Photo import needs VISION_MODEL_ALIAS configured")
    if media_type not in ALLOWED_MEDIA:
        raise HTTPException(415, f"Unsupported image type '{media_type}'")
    if len(image) > MAX_BYTES:
        raise HTTPException(413, "Image too large (15 MB max)")

    data_uri = f"data:{media_type};base64,{base64.standard_b64encode(image).decode('ascii')}"
    raw = await _complete(
        [
            {
                "role": "user",
                "content": [
                    {"type": "image_url", "image_url": {"url": data_uri}},
                    {"type": "text", "text": PROMPT},
                ],
            }
        ]
    )
    m = re.search(r"\{.*\}", raw, re.S)
    if not m:
        raise HTTPException(422, "Could not read a recipe from that photo")
    try:
        return RecipeDraft.model_validate(json.loads(m.group()))
    except Exception as exc:
        raise HTTPException(422, "Could not read a recipe from that photo") from exc
