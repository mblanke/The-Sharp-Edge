"""A library passage → a notebook draft (the read loop finally closes).

The library could answer questions but never *give* anything: finding the CIA's onion
soup meant retyping it. This turns the passage a citation shows into the same reviewed
draft that photo import and dictation produce — nothing auto-saves, the cook reads the
form before anything lands.

Two paths, cheapest first:

* **Deterministic.** Cookbook passages are far cleaner than web pages: ingredient lines
  start with a quantity ("5 lb/2.27 kg thinly sliced onions"), steps are numbered prose.
  Lines are classified with the same `parse_ingredient` the dictation and photo paths
  use, so structure comes from tested code and nothing paraphrases the book.
* **Local-model fallback**, only when the passage is prose-shaped (fewer than two
  ingredient lines found). The model is asked to *transcribe into the layout*, exactly
  like photo import — never to summarise — and `parse_transcript` does the structuring.
  The text is corpus content, so this must never leave the house: the call goes to the
  local router directly, same as photo import (`photo_import._complete`).

Tier note (CLAUDE.md §1): a recipe drafted from a copyrighted book is private to this
deployment. The router marks these drafts `private=True`, and the public exports
(master.md, cards.pdf) exclude them.
"""

from __future__ import annotations

import re

from app.config import settings
from app.services.ingredients import parse_ingredient
from app.services.photo_import import (
    PROMPT as TRANSCRIBE_PROMPT,
)
from app.services.photo_import import (
    DraftIngredient,
    DraftStep,
    RecipeDraft,
    _complete,
    _timer_seconds,
    parse_transcript,
)

__all__ = ["parse_passage", "passage_to_draft"]

MAX_CHARS = 20_000

#: "5 lb/2.27 kg" — the CIA prints imperial/metric twins. Keep the first reading; the
#: letter guard before the slash keeps fractions ("1/2 cup") intact.
_METRIC_TWIN = re.compile(
    r"(?<=[A-Za-z])\s*/\s*\d[\d.,]*\s*(?:kg|g|mg|ml|l|litres?|liters?|fl\s?oz|oz|lb)s?\b\.?",
    re.I,
)
#: "Makes 1 gal/3.84 L", "Serves 6", "Yield: 8 portions"
_YIELD_LINE = re.compile(r"^(?:makes|serves|yield[s]?[:\s])\s*(.+)$", re.I)
_YIELD_COUNT = re.compile(r"(\d+)\s*([A-Za-zÀ-ÿ]+)?")
#: "1. Caramelize the onions…" — a numbered method step.
_STEP_NUMBER = re.compile(r"^\s*(?:\d+[.)]|step\s+\d+[:.]?)\s*", re.I)
_NOTE_LINE = re.compile(r"^\s*notes?\s*[:.]", re.I)
#: "FOR THE BROTH:" / "GARNISH:" — a section header inside the ingredient list.
_SECTION_LINE = re.compile(r"^(?:for\s+the\s+)?[A-ZÀ-Þ][A-ZÀ-Þ\s'’-]{2,30}:?$")
_SENTENCE = re.compile(r"[.!?](?:\s|$)")
#: "Salt, as needed" / "black pepper, to taste" — an ingredient whose amount is 0
#: (rendered as an em dash, never scaled — CLAUDE.md §5).
_TO_TASTE = re.compile(r",?\s*(?:as needed|to taste)\s*$", re.I)


def _clean(line: str) -> str:
    return _METRIC_TWIN.sub("", " ".join(line.split())).strip()


def _is_ingredient(line: str) -> bool:
    """A short line the shared parser can read a quantity or unit out of."""
    if len(line) > 110 or _SENTENCE.search(line):
        return False
    if _TO_TASTE.search(line):
        return True
    row = parse_ingredient(line, lang="en")
    return bool(row.get("amount")) or bool(str(row.get("unit") or ""))


def parse_passage(text: str, *, fallback_title: str = "") -> RecipeDraft:
    """Deterministic pass: classify lines, structure with the shared parser."""
    lines = [_clean(ln) for ln in text.splitlines()]
    lines = [ln for ln in lines if ln]

    title = ""
    meta = ""
    base_yield, yield_word = 1, "servings"
    ingredients: list[DraftIngredient] = []
    steps: list[str] = []
    notes: list[str] = []
    section: str | None = None
    seen_ingredients = False

    for line in lines:
        if (m := _YIELD_LINE.match(line)) is not None and not meta:
            meta = line
            if (c := _YIELD_COUNT.search(m.group(1))) is not None:
                base_yield = max(1, int(c.group(1)))
                yield_word = (c.group(2) or "servings").strip() or "servings"
            continue
        if _NOTE_LINE.match(line):
            notes.append(_NOTE_LINE.sub("", line).strip())
            continue
        if _is_ingredient(line):
            if _TO_TASTE.search(line):
                # "Salt, as needed" → the name alone, amount 0 (em dash, unscaled)
                row = {"amount": 0, "unit": "", "name": _TO_TASTE.sub("", line).strip()}
            else:
                row = parse_ingredient(line, lang="en")
            if str(row.get("name") or "").strip():
                ingredients.append(DraftIngredient(**{**row, "section": section}))
                seen_ingredients = True
            continue
        if not seen_ingredients and not title and len(line) <= 60 and not _SENTENCE.search(line):
            # a heading before the ingredient list is the recipe's name
            title = _STEP_NUMBER.sub("", line)
            continue
        if seen_ingredients and _SECTION_LINE.match(line) and len(line) <= 34:
            section = line.rstrip(":").strip().title()
            continue
        if _STEP_NUMBER.match(line) or (seen_ingredients and _SENTENCE.search(line)):
            steps.append(_STEP_NUMBER.sub("", line))
            continue
        # prose before the ingredients (an introduction) is dropped: the notebook keeps
        # method and function, not editorial (CLAUDE.md §1)

    return RecipeDraft(
        title=title or fallback_title or "Untitled recipe",
        meta=meta or None,
        base_yield=base_yield,
        yield_word=yield_word,
        ingredients=ingredients,
        steps=[DraftStep(text=s, timer_seconds=_timer_seconds(s)) for s in steps],
        notes=notes,
    )


_REFORMAT_PROMPT = TRANSCRIBE_PROMPT.replace(
    "Transcribe this recipe page exactly as written.",
    "Reformat this cookbook passage exactly as written.",
)


async def passage_to_draft(text: str, *, fallback_title: str = "") -> RecipeDraft:
    """Deterministic first; the local model only when the passage is prose-shaped."""
    text = text[:MAX_CHARS]
    draft = parse_passage(text, fallback_title=fallback_title)
    if len(draft.ingredients) >= 2 and draft.steps:
        return draft

    # Prose-shaped (a technique discussion, or a recipe written out in sentences).
    # Local router only — this text is corpus content and never leaves the house.
    reply = await _complete(
        [
            {"role": "system", "content": _REFORMAT_PROMPT},
            {"role": "user", "content": text},
        ],
        settings.chat_model_alias,
    )
    fallback = parse_transcript(reply)
    if fallback.title == "Untitled recipe" and fallback_title:
        fallback.title = fallback_title
    # keep whichever reading actually found a recipe
    if len(fallback.ingredients) > len(draft.ingredients):
        return fallback
    return draft
