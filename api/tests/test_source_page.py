"""Serving one page of a source book.

The premise: text extraction only has to be good enough to *find* the page. Reading it
should happen in the book, which is on the NAS — proper layout, photographs, and no
chance that a line of the method was lost in extraction.

The tests that matter here are the ones about what must NOT be possible: escaping the
library folder, and pulling down a whole copyrighted book (CLAUDE.md §1).
"""

import io

import pytest
from pypdf import PdfReader, PdfWriter

from app.services.source_page import SourceError, extract_page, resolve_source


@pytest.fixture
def library(tmp_path):
    """A library folder with a 5-page PDF, its extracted .txt twin, and an EPUB."""
    root = tmp_path / "Cooking"
    root.mkdir()

    writer = PdfWriter()
    for _ in range(5):
        writer.add_blank_page(width=612, height=783)
    (root / "Big Book.pdf").write_bytes(_bytes(writer))
    (root / "Big Book.txt").write_text("extracted text layer")
    (root / "Novel.epub").write_bytes(b"PK\x03\x04 not really an epub")
    (tmp_path / "secrets.pdf").write_bytes(_bytes(writer))
    return root


def _bytes(writer) -> bytes:
    buf = io.BytesIO()
    writer.write(buf)
    return buf.getvalue()


# ------------------------------------------------------------------ resolving

def test_a_pdf_resolves_to_itself(library):
    assert resolve_source("Big Book.pdf", str(library)).name == "Big Book.pdf"


def test_an_extracted_txt_resolves_to_the_pdf_beside_it(library):
    """Books whose text layer we extracted are indexed as .txt; the readable original
    is the .pdf next to it, and that is what should open."""
    assert resolve_source("Big Book.txt", str(library)).name == "Big Book.pdf"


def test_an_absolute_container_path_is_accepted(library):
    """Chunks carry container-absolute paths like /mnt/references/Cooking/Big Book.txt."""
    got = resolve_source(f"/mnt/references/{library.name}/Big Book.txt", str(library))
    assert got.name == "Big Book.pdf"


# ------------------------------------------------------------------ what must fail

@pytest.mark.parametrize("attack", [
    "../secrets.pdf",
    "../../etc/passwd",
    "subdir/../../secrets.pdf",
])
def test_traversal_cannot_escape_the_library(library, attack):
    """The path comes from a client. Nothing outside the library folder is reachable."""
    with pytest.raises(SourceError):
        resolve_source(attack, str(library))


def test_an_epub_is_refused_rather_than_served_whole(library):
    """An EPUB has no fixed pages, so there is nothing to slice — and handing over the
    file would be exactly the whole-book download this design avoids."""
    with pytest.raises(SourceError, match="EPUB"):
        resolve_source("Novel.epub", str(library))


def test_a_missing_book_says_so(library):
    with pytest.raises(SourceError):
        resolve_source("Not Here.pdf", str(library))


def test_nothing_is_served_when_the_library_is_not_mounted():
    with pytest.raises(SourceError, match="mounted"):
        resolve_source("Big Book.pdf", "")


# ------------------------------------------------------------------ slicing

def test_one_page_comes_back_and_only_one(library):
    """Never a whole book. This is the line that keeps CLAUDE.md §1 true."""
    data = extract_page(library / "Big Book.pdf", 3)
    assert PdfReader(io.BytesIO(data)).pages.__len__() == 1


def test_the_page_number_is_one_based_like_the_citation(library):
    """Citations show "p. 3"; asking for 3 must not return the fourth page."""
    assert extract_page(library / "Big Book.pdf", 1)
    with pytest.raises(SourceError):
        extract_page(library / "Big Book.pdf", 0)


def test_a_page_past_the_end_says_how_many_there_are(library):
    with pytest.raises(SourceError, match="5 pages"):
        extract_page(library / "Big Book.pdf", 99)


def test_an_unreadable_file_fails_with_a_readable_message(tmp_path):
    broken = tmp_path / "broken.pdf"
    broken.write_bytes(b"not a pdf at all")
    with pytest.raises(SourceError):
        extract_page(broken, 1)
