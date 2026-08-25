"""Standalone-query rewriting for follow-up questions (D4).

"what about with lamb?" retrieves nothing useful on its own; rewritten against
the conversation it becomes "sous vide cooking time and temperature for lamb".
Tier rule: history can contain corpus text, so the rewrite ALWAYS runs on the
local provider with has_corpus_chunks=True — never a cloud model. Any failure
falls through to the raw question; retrieval never breaks on this feature."""

from app.services.llm import LLMProvider

REWRITE_SYSTEM = (
    "Rewrite the user's follow-up question as one standalone search query for a "
    "cookbook library, folding in whatever context from the conversation the "
    "query needs. Output ONLY the query text — no quotes, no explanation, one line."
)

MAX_HISTORY_CHARS = 4000


def _trimmed_history(history: list[dict]) -> list[dict]:
    """Most recent turns first to fit the budget, returned in original order."""
    kept: list[dict] = []
    used = 0
    for message in reversed(history):
        content = str(message.get("content", ""))[:1500]
        if used + len(content) > MAX_HISTORY_CHARS:
            break
        kept.append({"role": message["role"], "content": content})
        used += len(content)
    return list(reversed(kept))


async def standalone_query(question: str, history: list[dict], provider: LLMProvider) -> str:
    """Best-effort rewrite; the raw question on empty history or any failure."""
    if not history:
        return question
    messages = (
        [{"role": "system", "content": REWRITE_SYSTEM}]
        + _trimmed_history(history)
        + [{"role": "user", "content": f"Follow-up question: {question}"}]
    )
    try:
        parts: list[str] = []
        async for token in provider.stream_chat(messages, has_corpus_chunks=True):
            parts.append(token)
            if sum(len(p) for p in parts) > 400:
                break
        rewritten = " ".join("".join(parts).split()).strip().strip('"')
        # sanity: a usable query is short, non-empty prose
        if 3 <= len(rewritten) <= 300 and "\n" not in rewritten:
            return rewritten
    except Exception:
        pass
    return question
