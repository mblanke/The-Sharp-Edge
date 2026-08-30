"""Tests for /search, /library/books, and /conversations."""

import uuid

import app.routers.library as library_module
from app.config import settings

CHUNK = {
    "text": "Espagnole begins with a brown roux.",
    "source_path": "Cooking/escoffier-guide.pdf",
    "title": "Le Guide Culinaire",
    "heading": "Espagnole",
    "page": 42,
    "score": 0.91,
}


class FakeRag:
    def __init__(self, chunks=None, healthy=True):
        self.chunks = chunks if chunks is not None else [CHUNK]
        self.healthy = healthy
        self.calls: list[dict] = []

    async def retrieve(self, question, top_k=None, books=None):
        self.calls.append({"question": question, "top_k": top_k})
        return self.chunks

    async def health(self):
        return {"ok": self.healthy}


async def test_search_returns_ranked_chunks(client, monkeypatch):
    rag = FakeRag()
    monkeypatch.setattr(library_module, "atlas_rag", rag)
    res = await client.get("/api/v1/search", params={"q": "espagnole", "top_k": 5})
    assert res.status_code == 200
    body = res.json()
    assert body[0]["source_path"] == "Cooking/escoffier-guide.pdf"
    assert body[0]["page"] == 42
    assert rag.calls == [{"question": "espagnole", "top_k": 5}]


async def test_search_validates_query_length(client, monkeypatch):
    monkeypatch.setattr(library_module, "atlas_rag", FakeRag())
    res = await client.get("/api/v1/search", params={"q": "x"})
    assert res.status_code == 422


async def test_library_books_unmounted(client, monkeypatch):
    monkeypatch.setattr(library_module, "atlas_rag", FakeRag(healthy=False))
    monkeypatch.setattr(settings, "library_dir", "")
    res = await client.get("/api/v1/library/books")
    assert res.status_code == 200
    body = res.json()
    assert body["mounted"] is False
    assert body["books"] == []
    assert body["rag_health"] == {"ok": False}


async def test_library_books_mounted(client, monkeypatch, tmp_path):
    (tmp_path / "escoffier-guide.pdf").write_bytes(b"pdf")
    (tmp_path / ".DS_Store").write_bytes(b"junk")
    (tmp_path / "keller").mkdir()
    monkeypatch.setattr(library_module, "atlas_rag", FakeRag())
    monkeypatch.setattr(settings, "library_dir", str(tmp_path))
    res = await client.get("/api/v1/library/books")
    body = res.json()
    assert body["mounted"] is True
    names = [(b["name"], b["kind"]) for b in body["books"]]
    # dotfiles skipped, folders and files both listed
    assert names == [("escoffier-guide.pdf", "file"), ("keller", "folder")]
    assert body["books"][0]["size_bytes"] == 3


async def test_conversations_empty(client):
    res = await client.get("/api/v1/conversations")
    assert res.status_code == 200
    assert res.json() == []


async def test_conversation_404(client):
    res = await client.get(f"/api/v1/conversations/{uuid.uuid4()}")
    assert res.status_code == 404
    assert res.headers["content-type"] == "application/problem+json"


# --- shelf coverage on the book list --------------------------------------------------
# The file list and the index were never compared, so a book that failed to ingest looked
# exactly like one that worked.


def _counts(monkeypatch, mapping):
    async def fake(*, force: bool = False):
        return mapping

    monkeypatch.setattr(library_module, "indexed_chunk_counts", fake)


async def test_book_list_reports_coverage(client, monkeypatch, tmp_path):
    (tmp_path / "Culinary Institute of America - The Professional Chef.pdf").write_bytes(b"x")
    (tmp_path / "Thomas.Keller.Under.Pressure").mkdir()
    monkeypatch.setattr(library_module, "atlas_rag", FakeRag())
    monkeypatch.setattr(settings, "library_dir", str(tmp_path))
    _counts(
        monkeypatch,
        # the index records its own root — never the local mount (which is /library
        # on Atlas and tmp_path here)
        {"/mnt/references/Cooking/Culinary Institute of America - The Professional Chef.pdf": 5423},
    )

    body = (await client.get("/api/v1/library/books")).json()
    by_name = {b["name"]: b for b in body["books"]}
    chef = by_name["Culinary Institute of America - The Professional Chef.pdf"]
    assert chef["status"] == "indexed" and chef["chunks"] == 5423
    assert "5,423 passages" in chef["note"]

    sealed = by_name["Thomas.Keller.Under.Pressure"]
    assert sealed["status"] == "missing" and sealed["chunks"] == 0
    assert "not indexed" in sealed["note"]


async def test_a_folder_of_many_books_sums_its_contents(client, monkeypatch, tmp_path):
    """`_acquired` holds six indexed books. Reporting the folder as "not indexed"
    because no single book claims the folder path would be the report lying."""
    acquired = tmp_path / "_acquired"
    acquired.mkdir()
    monkeypatch.setattr(library_module, "atlas_rag", FakeRag())
    monkeypatch.setattr(settings, "library_dir", str(tmp_path))
    _counts(
        monkeypatch,
        {
            "/mnt/references/Cooking/_acquired/On Food and Cooking.epub": 3126,
            "/mnt/references/Cooking/_acquired/The Noma Guide to Fermentation.epub": 835,
        },
    )

    body = (await client.get("/api/v1/library/books")).json()
    folder = body["books"][0]
    assert folder["name"] == "_acquired"
    assert folder["status"] == "indexed" and folder["chunks"] == 3961


async def test_unknown_coverage_is_null_not_missing(client, monkeypatch, tmp_path):
    """The failure mode that matters: an unreachable index must not mark every book
    missing. Null means "we don't know"."""
    (tmp_path / "Culinary Institute of America - The Professional Chef.txt").write_bytes(b"x")
    monkeypatch.setattr(library_module, "atlas_rag", FakeRag())
    monkeypatch.setattr(settings, "library_dir", str(tmp_path))
    _counts(monkeypatch, {})

    book = (await client.get("/api/v1/library/books")).json()["books"][0]
    assert book["status"] is None and book["chunks"] is None and book["note"] is None


async def test_a_book_indexed_via_its_sidecar_is_not_reported_missing(client, monkeypatch, tmp_path):
    """Institut Paul Bocuse is a scan docling cannot read, so it is transcribed to a
    `<stem>.txt` beside the PDF and the chunks live there. Matching the exact filename
    reported the PDF as "not indexed" while the book was fully searchable."""
    (tmp_path / "Institut Paul Bocuse.pdf").write_bytes(b"x" * 10)
    monkeypatch.setattr(library_module, "atlas_rag", FakeRag())
    monkeypatch.setattr(settings, "library_dir", str(tmp_path))
    _counts(monkeypatch, {"/mnt/references/Cooking/Institut Paul Bocuse.txt": 1177})

    book = (await client.get("/api/v1/library/books")).json()["books"][0]
    assert book["status"] == "indexed"
    assert book["chunks"] == 1177
