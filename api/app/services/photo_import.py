"""Photo-to-recipe capture (E2): a photo of the owner's own notebook page
becomes a structured draft prefilled into the editor — never auto-saved.

Fully local: the photo goes to the LiteLLM router's `vision` alias (a
multimodal model on the GB10s) — nothing ever leaves the house, so there is
no tier question at all. First call after idle can be slow while Ollama
loads the vision model; the timeout allows for a cold start.
"""

import base64
import json
import logging
import re

import httpx
from fastapi import HTTPException
from pydantic import BaseModel, Field, model_validator

from app.config import settings

logger = logging.getLogger("sharp-edge")

ALLOWED_MEDIA = {"image/jpeg", "image/png", "image/webp", "image/gif"}
MAX_BYTES = 15 * 1024 * 1024
TIMEOUT = 300.0  # cold model load on the GB10s can take minutes

PROMPT = (
    "This is a photo of a handwritten or printed recipe page from the user's own "
    "notebook. The page may be in English, French, German, or Romanian — keep the "
    "original language, do not translate. Transcribe it as JSON with keys: title, "
    "meta (short subtitle or null), base_yield (int), yield_word, ingredients "
    "(list of {amount, unit, name, section} — unit is one of g, kg, ml, cl, dl, "
    "l, cup, tbsp, tsp, lb, oz, or empty for countable items; keep the amount "
    "exactly as written on the page, never convert; map spoon/cup words: "
    "c. à s./EL/lingură → tbsp, c. à c./TL/linguriță → tsp, tasse/Tasse/cană → "
    "cup; amount 0 means 'to taste' / 'au goût' / 'nach Geschmack' / 'după gust'; "
    "section null unless the page groups ingredients), steps (list of {text, "
    "timer_seconds} — timer_seconds only for explicit durations, else null), "
    "notes (list of strings). Keep the cook's own wording; leave anything "
    "unreadable out rather than inventing it. Output ONLY the JSON."
)

# Metric multiples come back as written; the app's unit set is g/ml (§5).
_METRIC_FACTOR = {"kg": ("g", 1000), "l": ("ml", 1000), "cl": ("ml", 10), "dl": ("ml", 100)}


def _normalize_units(draft: "RecipeDraft") -> "RecipeDraft":
    for ing in draft.ingredients:
        unit = ing.unit.strip().lower()
        if unit in _METRIC_FACTOR:
            base, factor = _METRIC_FACTOR[unit]
            ing.amount *= factor
            ing.unit = base
    return draft


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

    @model_validator(mode="before")
    @classmethod
    def _tolerate_model_output(cls, data):
        """Vision models emit null/strings where the schema wants values — a
        page with no serving count comes back as base_yield: null. Coerce
        rather than 422 on an otherwise-good read."""
        if not isinstance(data, dict):
            return data
        for key, default in (("base_yield", 1), ("yield_word", "servings"),
                             ("title", ""), ("ingredients", []), ("steps", []),
                             ("notes", [])):
            if data.get(key) is None:
                data[key] = default
        try:
            data["base_yield"] = max(1, int(float(data["base_yield"])))
        except (TypeError, ValueError):
            data["base_yield"] = 1
        # ingredient/step rows: drop unusable entries instead of failing the draft
        rows = []
        for ing in data.get("ingredients", []):
            if not isinstance(ing, dict) or not str(ing.get("name") or "").strip():
                continue
            try:
                ing["amount"] = float(ing.get("amount") or 0)
            except (TypeError, ValueError):
                ing["amount"] = 0
            ing["unit"] = str(ing.get("unit") or "")
            rows.append(ing)
        data["ingredients"] = rows
        steps = []
        for step in data.get("steps", []):
            if isinstance(step, str) and step.strip():
                steps.append({"text": step})
            elif isinstance(step, dict) and str(step.get("text") or "").strip():
                ts = step.get("timer_seconds")
                try:
                    step["timer_seconds"] = int(float(ts)) if ts is not None else None
                except (TypeError, ValueError):
                    step["timer_seconds"] = None
                steps.append(step)
        data["steps"] = steps
        data["notes"] = [str(n) for n in data.get("notes", []) if str(n or "").strip()]
        return data


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
                    # ollama passthrough: keep the vision model resident so the
                    # retry (and the next cook) skips the cold load
                    "keep_alive": "60m",
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
        logger.warning("photo-import: no JSON in model output: %.400s", raw)
        raise HTTPException(422, "Could not read a recipe from that photo")
    try:
        return _normalize_units(RecipeDraft.model_validate(json.loads(m.group())))
    except Exception as exc:
        logger.warning("photo-import: draft rejected (%s): %.600s", exc, m.group())
        raise HTTPException(422, "Could not read a recipe from that photo") from exc
