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

    async def retrieve(self, question, top_k=None):
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
