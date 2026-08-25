"""Serve one page of a source book.

The better answer to "the extracted text is scruffy". Text extraction only has to be
good enough to *find* the right page; once found, the book itself is on the NAS and
shows the recipe properly — photographs, two-column layout intact, nothing reconstructed
and nothing missed. A citation you can open beats a citation you have to trust.

Two rules shape this, both from CLAUDE.md §1 (the corpus is private to the local
deployment):

* **One page, never a book.** The endpoint slices a single page out. There is no route
  that returns a whole copyrighted file.
* **PDFs only.** An EPUB has no fixed pages — its "page" numbers are synthetic — so
  there is nothing meaningful to slice, and serving the file whole would be exactly the
  thing this avoids.
"""

from __future__ import annotations

import io
from pathlib import Path

__all__ = ["resolve_source", "extract_page", "SourceError"]


class SourceError(Exception):
    """Raised with a message safe to show a user."""


def resolve_source(raw_path: str, library_dir: str) -> Path:
    """Map a chunk's ``source_path`` to a readable PDF inside the library.

    Handles two things beyond the obvious:

    * **Traversal.** The path arrives from a client, so it is resolved and then checked
      to be inside the library root. ``..`` cannot escape.
    * **The .txt indirection.** Books whose text layer we extracted ourselves are indexed
      as ``<name>.txt``; the readable original is the ``<name>.pdf`` beside it.
    """
    if not library_dir:
        raise SourceError("The library folder isn't mounted on this server.")
    root = Path(library_dir).resolve()

    candidate = Path(raw_path)
    # Chunks carry absolute container paths; keep only the part below the library.
    if candidate.is_absolute():
        parts = candidate.parts
        if root.name in parts:
            candidate = Path(*parts[parts.index(root.name) + 1:])
        else:
            candidate = Path(candidate.name)

    target = (root / candidate).resolve()
    if not target.is_relative_to(root):
        raise SourceError("That file isn't in the library.")

    if target.suffix.lower() == ".txt":
        pdf = target.with_suffix(".pdf")
        if pdf.is_file():
            target = pdf

    if not target.is_file():
        raise SourceError("That book isn't on the server.")
    if target.suffix.lower() != ".pdf":
        raise SourceError(
            "Only PDFs can be opened at a page. This book is an EPUB, which has no "
            "fixed pages."
        )
    return target


def extract_page(pdf_path: Path, page: int) -> bytes:
    """A one-page PDF, as bytes. `page` is 1-based, as citations show it."""
    from pypdf import PdfReader, PdfWriter

    try:
        reader = PdfReader(str(pdf_path))
    except Exception as exc:  # noqa: BLE001 — surface a readable message, not a stack
        raise SourceError(f"Couldn't read that book: {exc}") from exc

    total = len(reader.pages)
    if page < 1 or page > total:
        raise SourceError(f"That book has {total} pages; page {page} isn't one of them.")

    writer = PdfWriter()
    writer.add_page(reader.pages[page - 1])
    buffer = io.BytesIO()
    writer.write(buffer)
    return buffer.getvalue()


def page_count(pdf_path: Path) -> int:
    from pypdf import PdfReader

    return len(PdfReader(str(pdf_path)).pages)
