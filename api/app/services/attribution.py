"""Don't let the model answer in the voice of a book we don't own.

The failure this exists to stop, from the live conversation log: "How does Escoffier
build an espagnole?" was asked six times, and every answer opened *"To build an espagnole
according to Escoffier's method…"* while citing The Professional Chef and the French
Culinary Institute. There is no Escoffier on this shelf. The model invented the
provenance. "How does the CIA make french onion soup" came back citing The French Laundry.

The existing `ungrounded` flag cannot catch this. It fires when an answer carries *no*
`[n]` markers at all; these answers had citations — they simply pointed at the wrong
authority. Wrong attribution is the more dangerous failure, because it looks like rigour.

The fix is **attribution, not refusal**. The CIA's passages genuinely are a good answer to
"how do I build an espagnole"; only the label was wrong. So the question is answered, and
the answer says whose book it actually came from.

Detection is deterministic — a table lookup and a word-boundary match, no LLM call on the
streaming path. That keeps it testable and free.
"""

from __future__ import annotations

from dataclasses import dataclass

from app.services.shelf import authorities_in, book_by_id, resolve_path

__all__ = ["Attribution", "check", "shelf_note"]


@dataclass(frozen=True)
class Attribution:
    """What the question asked for, versus what the shelf can actually offer."""

    #: Authorities named in the question that the shelf does not hold at all.
    absent: tuple[str, ...] = ()
    #: Named, owned, but nothing from them was retrieved for this question.
    unretrieved: tuple[str, ...] = ()
    #: Display titles of the books the answer will actually be drawn from.
    sources: tuple[str, ...] = ()

    @property
    def needs_note(self) -> bool:
        return bool(self.absent or self.unretrieved)

    def as_dict(self) -> dict | None:
        if not self.needs_note:
            return None
        return {
            "absent": list(self.absent),
            "unretrieved": list(self.unretrieved),
            "sources": list(self.sources),
            "note": shelf_note(self),
        }


def check(question: str, chunks: list[dict]) -> Attribution:
    """Compare the authorities a question names against what was actually retrieved."""
    named = authorities_in(question)
    if not named:
        return Attribution()

    retrieved_ids = {
        book_id
        for c in chunks
        if (book_id := resolve_path(str(c.get("source_path") or "")))
    }
    source_titles = tuple(
        dict.fromkeys(
            book.title
            for book_id in retrieved_ids
            if (book := book_by_id(book_id)) is not None
        )
    )

    absent: list[str] = []
    unretrieved: list[str] = []
    for display, book_ids in named:
        if not book_ids:
            absent.append(display)
        elif not (set(book_ids) & retrieved_ids):
            unretrieved.append(display)
        # named, owned and retrieved → nothing to say

    return Attribution(tuple(absent), tuple(unretrieved), source_titles)


#: Sources are listed for a cook to read, so keep it short — four book titles in one
#: sentence is a wall, and the citations underneath carry the full detail anyway.
_MAX_LISTED_SOURCES = 3


def _join(names: tuple[str, ...], conjunction: str = "and") -> str:
    if len(names) == 1:
        return names[0]
    return ", ".join(names[:-1]) + f" {conjunction} {names[-1]}"


def _list_sources(sources: tuple[str, ...]) -> str:
    if len(sources) <= _MAX_LISTED_SOURCES:
        return _join(sources)
    rest = len(sources) - _MAX_LISTED_SOURCES
    shown = ", ".join(sources[:_MAX_LISTED_SOURCES])
    return f"{shown} and {rest} other book{'s' if rest != 1 else ''}"


def shelf_note(attribution: Attribution) -> str:
    """One or two sentences, written to be read by both the model and the cook."""
    parts: list[str] = []
    if attribution.absent:
        parts.append(f"There is no {_join(attribution.absent, 'or')} on this shelf.")
    if attribution.unretrieved:
        parts.append(
            f"The shelf has {_join(attribution.unretrieved, 'and')}, "
            "but nothing from it matched this question."
        )
    if attribution.sources:
        parts.append(f"The excerpts below are from {_list_sources(attribution.sources)}.")
    else:
        parts.append("Nothing on the shelf matched this question.")
    return " ".join(parts)


def prompt_preamble(attribution: Attribution) -> str:
    """The instruction that actually stops the fabrication.

    Placed before the excerpts, because a correction after them reads as commentary on
    the sources rather than a constraint on the answer.
    """
    if not attribution.needs_note:
        return ""
    named = _join(attribution.absent, "or") if attribution.absent else ""
    instruction = (
        f" Do not attribute anything below to {named}, and do not describe the method as "
        f"{named}'s. Say plainly that the shelf does not have that book, then answer from "
        "the excerpts and name the book each claim comes from."
        if attribution.absent
        else " Name the book each claim comes from."
    )
    return f"Shelf note: {shelf_note(attribution)}{instruction}"
