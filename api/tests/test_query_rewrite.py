"""History-aware retrieval query rewriting (D4)."""

from app.services.query_rewrite import REWRITE_SYSTEM, standalone_query

HISTORY = [
    {"role": "user", "content": "how long for short ribs sous vide?"},
    {"role": "assistant", "content": "Keller does 48 hours at 62C [1]."},
]


class FakeProvider:
    def __init__(self, tokens=("sous vide lamb ", "time and temperature")):
        self.tokens = tokens
        self.calls: list[dict] = []

    async def stream_chat(self, messages, *, has_corpus_chunks=False):
        self.calls.append({"messages": messages, "has_corpus_chunks": has_corpus_chunks})
        for t in self.tokens:
            yield t


class ExplodingProvider:
    async def stream_chat(self, messages, *, has_corpus_chunks=False):
        raise RuntimeError("router down")
        yield ""


async def test_no_history_skips_the_model():
    provider = FakeProvider()
    out = await standalone_query("what about lamb?", [], provider)
    assert out == "what about lamb?"
    assert provider.calls == []


async def test_rewrites_follow_up_with_history_on_private_tier():
    provider = FakeProvider()
    out = await standalone_query("what about with lamb?", HISTORY, provider)
    assert out == "sous vide lamb time and temperature"
    call = provider.calls[0]
    # tier rule: history may carry corpus text — always flagged private
    assert call["has_corpus_chunks"] is True
    assert call["messages"][0] == {"role": "system", "content": REWRITE_SYSTEM}
    assert "short ribs" in str(call["messages"])


async def test_provider_failure_falls_back_to_raw_question():
    out = await standalone_query("what about lamb?", HISTORY, ExplodingProvider())
    assert out == "what about lamb?"


async def test_garbage_rewrites_fall_back():
    for tokens in [("",), ("x" * 400,), ("ok",)]:
        out = await standalone_query("what about lamb?", HISTORY, FakeProvider(tokens))
        assert out == "what about lamb?", tokens


async def test_history_budget_keeps_most_recent_turns():
    provider = FakeProvider()
    long_history = [{"role": "user", "content": f"turn {i} " + "x" * 1400} for i in range(6)]
    await standalone_query("and then?", long_history, provider)
    sent = str(provider.calls[0]["messages"])
    assert "turn 5" in sent  # most recent kept
    assert "turn 0" not in sent  # oldest dropped
