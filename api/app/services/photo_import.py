"""Photo-to-recipe capture (E2): a photo of the owner's own notebook page
becomes a structured draft prefilled into the editor — never auto-saved.

Fully local: the photo goes to the LiteLLM router's `vision` alias (a
multimodal model on the GB10s), so nothing ever leaves the house.

The model does OCR only. Asking a small vision model for structured JSON was
fast but sloppy ("250 g de farine" came back with unit "de farine" and no
amount); asking a big one for JSON was accurate but took 48 s — too long for a
phone on a kitchen counter. So the model transcribes the page as plain text,
which it is good at, and services/ingredients.py — the same multilingual parser
dictation uses — turns those lines into quantities. Structure comes from code
that is tested, not from a model that is guessing.
"""

import base64
import logging
import re

import httpx
from fastapi import HTTPException
from pydantic import BaseModel, Field

from app.config import settings
from app.services.ingredients import LANGS, parse_ingredient, strip_leading_connector

logger = logging.getLogger("sharp-edge")

ALLOWED_MEDIA = {"image/jpeg", "image/png", "image/webp", "image/gif"}
MAX_BYTES = 15 * 1024 * 1024
TIMEOUT = 300.0  # cold model load on the GB10s can take minutes

# One model, one call. A second "tidy it up" pass by a text model corrupted the
# page — it rewrote 50 cl as 50 ml and invented an ingredient — so nothing gets
# to paraphrase the cook's own words. The vision model transcribes into this
# layout (11 s, byte-identical across runs), and our parser does the rest.
PROMPT = (
    "Transcribe this recipe page exactly as written. Keep the original language "
    "(English, French, German or Romanian) — do not translate, do not convert "
    "units, do not add anything that is not on the page. Use exactly this "
    "layout:\n"
    "LANG: <en|fr|de|ro>\n"
    "TITLE: <the recipe name>\n"
    "YIELD: <the servings line if the page states one, else blank>\n"
    "INGREDIENTS:\n"
    "- <one ingredient per line, exactly as written>\n"
    "STEPS:\n"
    "- <one step per line, exactly as written>\n"
    "NOTES:\n"
    "- <any remaining notes, one per line>\n"
    "Leave a section empty if the page has none. Output only this text."
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


# ---------------------------------------------------------------- transcript

_SECTIONS = ("ingredients", "steps", "notes")
_BULLET = re.compile(r"^\s*(?:[-*•]|\d+[.)])\s*")
# Models sometimes run a section together on one line; treat these as line breaks.
_INLINE_SEPARATORS = re.compile(r"\s*[|·;]\s*")
# "Pour 4 personnes", "Serves 6", "4 Portionen", "Pentru 4 persoane"
_YIELD = re.compile(r"(\d+)\s*([A-Za-zÀ-ÿ]+)?")
_DURATION = re.compile(
    r"(\d+)\s*(hours?|hrs?|heures?|stunden?|ore\b|h\b|"
    r"minutes?|minuten?|mins?|min\b|minute\b|"
    r"seconds?|secondes?|sekunden?|secs?|sec\b)",
    re.I,
)


def _timer_seconds(text: str) -> int | None:
    """First explicit duration in a step, in seconds — the same idea as the
    editor's timer field, read off the page rather than typed."""
    m = _DURATION.search(text)
    if not m:
        return None
    value, unit = int(m.group(1)), m.group(2).lower()
    if unit.startswith(("hour", "hr", "heure", "stunde", "ore", "h")):
        return value * 3600
    if unit.startswith(("min", "minut")):
        return value * 60
    return value


def parse_transcript(text: str) -> RecipeDraft:
    """The model's plain-text page → a draft, structured by our own parser."""
    lang = "en"
    title = ""
    yield_line = ""
    buckets: dict[str, list[str]] = {name: [] for name in _SECTIONS}
    current: str | None = None

    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        low = line.lower()
        if low.startswith("lang:"):
            value = line.split(":", 1)[1].strip().lower()[:2]
            lang = value if value in LANGS else "en"
            continue
        if low.startswith("title:"):
            title = line.split(":", 1)[1].strip()
            continue
        if low.startswith("yield:"):
            yield_line = line.split(":", 1)[1].strip()
            continue
        matched = next((s for s in _SECTIONS if low.startswith(s + ":")), None)
        if matched:
            current = matched
            continue
        if current:
            for part in _INLINE_SEPARATORS.split(line):
                cleaned = _BULLET.sub("", part).strip()
                if cleaned:
                    buckets[current].append(cleaned)

    base_yield, yield_word = 1, "servings"
    if (m := _YIELD.search(yield_line)) is not None:
        base_yield = max(1, int(m.group(1)))
        yield_word = (m.group(2) or "servings").strip() or "servings"

    ingredients: list[DraftIngredient] = []
    for line in buckets["ingredients"]:
        # spoken=True: a photographed page is prose like dictation is — it says
        # "une pincée de sel", not "0". The printed path stays pinned to the seed
        # corpus, so this is opt-in per caller.
        row = parse_ingredient(line, lang=lang, spoken=True)
        if (
            not row.get("amount")
            and not str(row.get("unit") or "")
            and str(row.get("name") or "").strip() == line.strip()
        ):
            # Nothing at all was recognised — re-read as plain printed text. Guarded
            # on the untouched name so a deliberate zero ("1 pincée de sel") is not
            # undone by a second parse that only sees the digit.
            plain = parse_ingredient(line, lang=lang)
            if plain.get("amount"):
                row = plain
        name = strip_leading_connector(str(row.get("name") or ""), lang)
        if name.strip():
            row["name"] = name
            ingredients.append(DraftIngredient(**row))

    steps = [DraftStep(text=s, timer_seconds=_timer_seconds(s)) for s in buckets["steps"]]

    return RecipeDraft(
        title=title or "Untitled recipe",
        meta=yield_line or None,
        base_yield=base_yield,
        yield_word=yield_word,
        ingredients=ingredients,
        steps=steps,
        notes=buckets["notes"],
    )


# ---------------------------------------------------------------- transport


async def _complete(messages: list[dict], model: str) -> str:
    """One non-streamed completion on the local router."""
    try:
        async with httpx.AsyncClient(
            base_url=settings.llm_router_url.rstrip("/"),
            timeout=httpx.Timeout(TIMEOUT, connect=10.0),
            headers={"Authorization": f"Bearer {settings.llm_router_key}"},
        ) as client:
            res = await client.post(
                "/chat/completions",
                json={
                    "model": model,
                    "messages": messages,
                    "max_tokens": 2000,
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
    transcript = await _complete(
        [
            {
                "role": "user",
                "content": [
                    {"type": "image_url", "image_url": {"url": data_uri}},
                    {"type": "text", "text": PROMPT},
                ],
            }
        ],
        settings.vision_model_alias,
    )
    draft = parse_transcript(transcript)
    if not draft.ingredients and not draft.steps:
        logger.warning("photo-import: nothing usable in transcript: %.500s", transcript)
        raise HTTPException(422, "Could not read a recipe from that photo")
    return draft
