"""Citation handling: chunks are numbered [1]..[n] in the prompt; the model
cites by number; we map the numbers it actually used back to sources."""

import re


def chunks_block(chunks: list[dict]) -> str:
    """Render retrieved chunks for the prompt, numbered for citation."""
    parts = []
    for i, c in enumerate(chunks, 1):
        title = c.get("title") or c.get("source_path") or "unknown"
        heading = c.get("heading") or ""
        page = c.get("page")
        loc = f" p.{page}" if page is not None else ""
        head = f" — {heading}" if heading else ""
        parts.append(f"[{i}] {title}{head}{loc}\n{c.get('text', '').strip()}")
    return "\n\n".join(parts)


def extract_citations(
    answer: str, chunks: list[dict], recipe: dict | None = None
) -> list[dict]:
    """Map [n] references in the answer to structured citations, in first-use
    order. When a working recipe is in scope it may be cited as [R] — mapped to
    n=0 with the recipe's app path as source."""
    seen: list[int] = []
    for m in re.finditer(r"\[(\d+)\]", answer):
        n = int(m.group(1))
        if 1 <= n <= len(chunks) and n not in seen:
            seen.append(n)
    out = [
        {
            "n": n,
            "title": chunks[n - 1].get("title"),
            "source_path": chunks[n - 1].get("source_path"),
            "heading": chunks[n - 1].get("heading"),
            "page": chunks[n - 1].get("page"),
        }
        for n in seen
    ]
    if recipe and re.search(r"\[R\]", answer):
        out.insert(
            0,
            {
                "n": 0,
                "title": recipe.get("title"),
                "source_path": f"/r/{recipe.get('slug')}",
                "heading": "notebook recipe",
                "page": None,
            },
        )
    return out


SYSTEM_PROMPT = (
    "You are the culinary research assistant for The Sharp Edge, a chef's recipe "
    "notebook. Answer from the numbered source excerpts provided. Cite sources "
    "inline with their bracket numbers, e.g. [2]. If the sources don't cover the "
    "question, say so plainly — do not invent culinary facts. Be practical and "
    "concise; this is read in a kitchen."
)
