import httpx
import pytest
from fastapi import HTTPException

from app.services.atlas_rag import AtlasRag, _in_scope


def make_client(handler) -> httpx.AsyncClient:
    return httpx.AsyncClient(transport=httpx.MockTransport(handler), base_url="http://rag.test")


CHUNKS = [
    {"text": "sous vide short ribs 48h", "source_path": "Cooking/keller-under-pressure.epub", "source_folder": "Cooking", "page": 112, "score": 0.9},
    {"text": "buffer overflow exploitation", "source_path": "Security/sans-660.pdf", "source_folder": "Security", "page": 4, "score": 0.88},
    {"text": "espagnole base", "source_path": "/mnt/references/Cooking/professional-chef.pdf", "source_folder": "", "page": 300, "score": 0.8},
    {"text": "ml pipelines", "source_path": "AI/mlops.pdf", "source_folder": "AI", "page": 9, "score": 0.7},
]


async def test_retrieve_filters_to_cooking():
    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/retrieve"
        return httpx.Response(200, json={"chunks": CHUNKS})

    rag = AtlasRag(base_url="http://rag.test", client=make_client(handler))
    out = await rag.retrieve("short ribs", top_k=8)
    paths = [c["source_path"] for c in out]
    assert paths == [
        "Cooking/keller-under-pressure.epub",
        "/mnt/references/Cooking/professional-chef.pdf",
    ]


async def test_retrieve_caps_top_k():
    many = [
        {"text": f"c{i}", "source_path": f"Cooking/book{i}.pdf", "source_folder": "Cooking"}
        for i in range(20)
    ]

    async def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"chunks": many})

    rag = AtlasRag(base_url="http://rag.test", client=make_client(handler))
    out = await rag.retrieve("x", top_k=5)
    assert len(out) == 5


async def test_retrieve_unreachable_is_502():
    async def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("boom")

    rag = AtlasRag(base_url="http://rag.test", client=make_client(handler))
    with pytest.raises(HTTPException) as exc:
        await rag.retrieve("x")
    assert exc.value.status_code == 502


async def test_health_degrades_gracefully():
    async def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("down")

    rag = AtlasRag(base_url="http://rag.test", client=make_client(handler))
    health = await rag.health()
    assert health["ok"] is False


def test_in_scope_variants():
    assert _in_scope({"source_folder": "Cooking"}, "Cooking")
    assert _in_scope({"source_path": "Cooking/x.pdf"}, "Cooking")
    assert _in_scope({"source_path": "/mnt/references/Cooking/x.pdf"}, "Cooking")
    assert not _in_scope({"source_path": "Security/x.pdf", "source_folder": "Security"}, "Cooking")
    assert _in_scope({"source_path": "anything"}, "")  # empty folder = no filter
