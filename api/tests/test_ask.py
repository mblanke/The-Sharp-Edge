import json

import app.routers.ask as ask_module
from app.services import atlas_rag as rag_module

COOKING_CHUNKS = [
    {
        "text": "Short ribs, 48 hours at 62C.",
        "source_path": "Cooking/keller-under-pressure.epub",
        "source_folder": "Cooking",
        "title": "Under Pressure",
        "heading": "Short Ribs",
        "page": 112,
    }
]


class FakeProvider:
    def __init__(self, tokens=("Braise ", "48h ", "per [1].")):
        self.tokens = tokens
        self.calls: list[dict] = []

    async def stream_chat(self, messages, *, has_corpus_chunks=False):
        self.calls.append({"messages": messages, "has_corpus_chunks": has_corpus_chunks})
        for t in self.tokens:
            yield t


class FakeRag:
    async def retrieve(self, question, top_k=None):
        return COOKING_CHUNKS


def parse_sse(body: str) -> list[tuple[str, dict]]:
    events = []
    for block in body.strip().split("\n\n"):
        lines = block.splitlines()
        event = next(x[7:] for x in lines if x.startswith("event: "))
        data = json.loads(next(x[6:] for x in lines if x.startswith("data: ")))
        events.append((event, data))
    return events


async def ask_and_parse(client, monkeypatch, payload, provider=None):
    provider = provider or FakeProvider()
    monkeypatch.setattr(ask_module, "atlas_rag", FakeRag())
    monkeypatch.setattr(ask_module, "get_provider", lambda: provider)
    res = await client.post("/api/v1/ask", json=payload)
    assert res.status_code == 200
    assert res.headers["content-type"].startswith("text/event-stream")
    return parse_sse(res.text), provider


async def test_ask_streams_and_cites(client, monkeypatch):
    events, provider = await ask_and_parse(client, monkeypatch, {"question": "how long for short ribs sous vide?"})
    kinds = [e for e, _ in events]
    assert kinds[0] == "meta"
    assert kinds[-1] == "done"
    tokens = "".join(d["t"] for e, d in events if e == "token")
    assert tokens == "Braise 48h per [1]."
    done = events[-1][1]
    assert done["citations"] == [
        {"n": 1, "title": "Under Pressure", "source_path": "Cooking/keller-under-pressure.epub", "heading": "Short Ribs", "page": 112}
    ]
    # corpus chunks were flagged private-tier to the provider
    assert provider.calls[0]["has_corpus_chunks"] is True
    # chunks were injected into the user message
    assert "Under Pressure" in provider.calls[0]["messages"][-1]["content"]


async def test_ask_persists_conversation(client, monkeypatch):
    events, _ = await ask_and_parse(client, monkeypatch, {"question": "first question"})
    conversation_id = events[0][1]["conversation_id"]

    res = await client.get(f"/api/v1/conversations/{conversation_id}")
    assert res.status_code == 200
    roles = [m["role"] for m in res.json()["messages"]]
    assert roles == ["user", "assistant"]

    # follow-up in the same conversation carries history
    provider = FakeProvider(tokens=("ok",))
    await ask_and_parse(
        client, monkeypatch, {"question": "and the sauce?", "conversation_id": conversation_id}, provider
    )
    history_roles = [m["role"] for m in provider.calls[0]["messages"]]
    assert history_roles[0] == "system"
    assert "first question" in json.dumps(provider.calls[0]["messages"])

    res = await client.get("/api/v1/conversations")
    assert len(res.json()) == 1


async def test_ask_recipe_scope_injects_context(client, auth, monkeypatch):
    from tests.test_recipes_api import GOULASH

    await client.post("/api/v1/recipes", json=GOULASH, headers=auth)
    events, provider = await ask_and_parse(
        client, monkeypatch, {"question": "double it?", "scope": {"recipe_slug": "goulash"}}
    )
    system = provider.calls[0]["messages"][0]["content"]
    assert "GF Hungarian Beef Goulash" in system
    assert "beef chuck" in system
