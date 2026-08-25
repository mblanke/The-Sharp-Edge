"""Photo-to-recipe capture (E2): a photo of the owner's own notebook page
becomes a structured draft prefilled into the editor — never auto-saved.

Tier safety by construction: this path carries ONLY the owner-authored photo
and a fixed instruction — zero corpus content. `ensure_public_tier` is the
same hard firewall the AnthropicProvider enforces; it is called with the
literal capability of this request and unit-tested to refuse corpus content.
"""

import base64

from fastapi import HTTPException
from pydantic import BaseModel, Field

from app.config import settings
from app.services.llm import ensure_public_tier

ALLOWED_MEDIA = {"image/jpeg", "image/png", "image/webp", "image/gif"}
MAX_BYTES = 15 * 1024 * 1024

PROMPT = (
    "This is a photo of a handwritten or printed recipe page from the user's own "
    "notebook. Transcribe it into the structured draft. Rules: units must be one "
    "of g, ml, cup, tbsp, tsp, lb, oz, or empty for countable items (the counting "
    "noun goes in the name); amount 0 means 'to taste'; guess timer_seconds only "
    "for steps with an explicit duration; keep the cook's own wording; leave "
    "anything unreadable out rather than inventing it."
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
    return bool(settings.anthropic_api_key)


async def parse_photo(image: bytes, media_type: str) -> RecipeDraft:
    """One vision call → validated draft. Raises 4xx/5xx problem responses."""
    ensure_public_tier(has_corpus_chunks=False)
    if not enabled():
        raise HTTPException(501, "Photo import needs ANTHROPIC_API_KEY configured")
    if media_type not in ALLOWED_MEDIA:
        raise HTTPException(415, f"Unsupported image type '{media_type}'")
    if len(image) > MAX_BYTES:
        raise HTTPException(413, "Image too large (15 MB max)")

    from anthropic import APIError, AsyncAnthropic

    client = AsyncAnthropic(api_key=settings.anthropic_api_key)
    try:
        response = await client.messages.parse(
            model=settings.anthropic_model,
            max_tokens=16000,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": media_type,
                                "data": base64.standard_b64encode(image).decode("ascii"),
                            },
                        },
                        {"type": "text", "text": PROMPT},
                    ],
                }
            ],
            output_format=RecipeDraft,
        )
    except APIError as exc:
        raise HTTPException(502, f"Photo parsing failed: {exc}") from exc
    finally:
        await client.close()

    if response.stop_reason == "refusal" or response.parsed_output is None:
        raise HTTPException(422, "Could not read a recipe from that photo")
    return response.parsed_output
