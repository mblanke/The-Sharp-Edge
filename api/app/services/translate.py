"""Translate a recipe's words, never its numbers (CLAUDE.md §5, §9).

A photographed page keeps the cook's own language by design, which is right for
the notebook and unhelpful when the cook doesn't read Romanian. This turns a
recipe into another language on demand.

Only the *strings* are sent to the model — titles, ingredient names, step text.
Amounts, units and timers stay in our own structures and are reattached
afterwards, so a translation can never quietly turn 500 ml into 50 ml. The model
is the local instruct model on the GB10s; nothing leaves the house.
"""

import logging
import re

import httpx
from fastapi import HTTPException

from app.config import settings

logger = logging.getLogger("sharp-edge")

TIMEOUT = 180.0
LANGUAGE_NAMES = {"en": "English", "fr": "French", "de": "German", "ro": "Romanian"}

PROMPT = (
    "Translate each numbered line into {language}. These are lines from a recipe: "
    "ingredient names, step instructions, a title. Translate cooking terms the way "
    "a cook would say them. Keep every number, quantity and unit exactly as it "
    "appears. Reply with the same numbered lines and nothing else — same count, "
    "same order, one line each."
)

_NUMBERED = re.compile(r"^\s*(\d+)\s*[.):]\s*(.*)$")


def build_lines(payload: dict) -> list[str]:
    """The translatable strings of a recipe, in a fixed order."""
    lines = [payload.get("title") or ""]
    lines.append(payload.get("meta") or "")
    lines += [str(i.get("name") or "") for i in payload.get("ingredients", [])]
    lines += [str(s.get("text") or "") for s in payload.get("steps", [])]
    lines += [str(n or "") for n in payload.get("notes", [])]
    return lines


def apply_lines(payload: dict, lines: list[str]) -> dict:
    """Reattach translated strings to the original structure — numbers untouched."""
    out = dict(payload)
    cursor = 0

    def take() -> str:
        nonlocal cursor
        value = lines[cursor] if cursor < len(lines) else ""
        cursor += 1
        return value

    title = take()
    out["title"] = title or payload.get("title")
    meta = take()
    out["meta"] = meta or payload.get("meta")

    out["ingredients"] = [
        {**ing, "name": take() or ing.get("name")} for ing in payload.get("ingredients", [])
    ]
    out["steps"] = [
        {**step, "text": take() or step.get("text")} for step in payload.get("steps", [])
    ]
    out["notes"] = [take() or note for note in payload.get("notes", [])]
    return out


def parse_numbered(text: str, expected: int) -> list[str]:
    """Read the model's numbered reply back into a positional list.

    Placed by number rather than by arrival order: a model that skips or repeats
    a number must not shift every later line onto the wrong ingredient.
    """
    slots: list[str] = [""] * expected
    for raw in text.splitlines():
        m = _NUMBERED.match(raw.strip())
        if not m:
            continue
        index = int(m.group(1)) - 1
        if 0 <= index < expected and not slots[index]:
            slots[index] = m.group(2).strip()
    return slots


async def translate_recipe(payload: dict, target: str) -> dict:
    """Recipe dict → the same dict with its words in `target`."""
    language = LANGUAGE_NAMES.get(target)
    if language is None:
        raise HTTPException(400, f"Cannot translate to '{target}'")

    lines = build_lines(payload)
    numbered = "\n".join(f"{n}. {line}" for n, line in enumerate(lines, 1) if line.strip())
    if not numbered.strip():
        return payload

    try:
        async with httpx.AsyncClient(
            base_url=settings.llm_router_url.rstrip("/"),
            timeout=httpx.Timeout(TIMEOUT, connect=10.0),
            headers={"Authorization": f"Bearer {settings.llm_router_key}"},
        ) as client:
            res = await client.post(
                "/chat/completions",
                json={
                    "model": settings.translate_model_alias,
                    "messages": [
                        {"role": "system", "content": PROMPT.format(language=language)},
                        {"role": "user", "content": numbered},
                    ],
                    "max_tokens": 2000,
                },
            )
            res.raise_for_status()
            reply = str(res.json()["choices"][0]["message"]["content"])
    except httpx.HTTPError as exc:
        raise HTTPException(502, f"Translation model unreachable: {exc}") from exc
    except (KeyError, IndexError, ValueError) as exc:
        raise HTTPException(502, "Translation model returned an unexpected response") from exc

    translated = parse_numbered(reply, len(lines))
    if not any(translated):
        logger.warning("translate: nothing usable in reply: %.400s", reply)
        raise HTTPException(422, "Could not translate this recipe")
    # blanks fall back to the original line, so a partial reply degrades gracefully
    merged = [new or old for new, old in zip(translated, lines)]
    return apply_lines(payload, merged)
