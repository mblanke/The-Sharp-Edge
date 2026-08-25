"""Recipe import from URL (F4): fetch → schema.org JSON-LD → structured draft,
with a local-LLM fallback for pages without markup. Review-first like photo
import — the draft prefills the editor and is never auto-saved.

Tier note: web pages are public content; the fallback still runs on the LOCAL
provider (no cloud dependency, no key needed). Source line = bare domain per
the no-editorializing rule.
"""

import ipaddress
import json
import re
import socket
from html.parser import HTMLParser
from urllib.parse import urlparse

import httpx
from fastapi import HTTPException

from app.services.gf_audit import scan_ingredients
from app.services.ingredients import parse_ingredient
from app.services.llm import LLMProvider
from app.services.photo_import import RecipeDraft

MAX_BYTES = 3 * 1024 * 1024
UA = "Mozilla/5.0 (compatible; SharpEdge/1.0 recipe importer)"


def _check_url(url: str) -> str:
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise HTTPException(400, "Provide an http(s) recipe URL")
    host = parsed.hostname
    try:
        addr = ipaddress.ip_address(socket.gethostbyname(host))
        if addr.is_private or addr.is_loopback or addr.is_link_local:
            raise HTTPException(400, "Refusing to fetch private addresses")
    except (socket.gaierror, ValueError) as exc:
        raise HTTPException(400, f"Cannot resolve '{host}'") from exc
    return host


async def _fetch(url: str) -> str:
    try:
        async with httpx.AsyncClient(
            follow_redirects=True, timeout=20.0, headers={"User-Agent": UA}
        ) as client:
            res = await client.get(url)
            res.raise_for_status()
            return res.text[:MAX_BYTES]
    except httpx.HTTPError as exc:
        raise HTTPException(502, f"Could not fetch the page: {exc}") from exc


class _LdJsonCollector(HTMLParser):
    def __init__(self):
        super().__init__()
        self.blocks: list[str] = []
        self._in_ld = False
        self._buf: list[str] = []

    def handle_starttag(self, tag, attrs):
        if tag == "script" and dict(attrs).get("type", "").startswith("application/ld+json"):
            self._in_ld = True
            self._buf = []

    def handle_endtag(self, tag):
        if tag == "script" and self._in_ld:
            self._in_ld = False
            self.blocks.append("".join(self._buf))

    def handle_data(self, data):
        if self._in_ld:
            self._buf.append(data)


def _find_recipe_node(html: str) -> dict | None:
    collector = _LdJsonCollector()
    collector.feed(html)
    candidates: list = []
    for block in collector.blocks:
        try:
            candidates.append(json.loads(block))
        except json.JSONDecodeError:
            continue
    queue = list(candidates)
    while queue:
        node = queue.pop(0)
        if isinstance(node, list):
            queue.extend(node)
            continue
        if not isinstance(node, dict):
            continue
        node_type = node.get("@type", "")
        types = node_type if isinstance(node_type, list) else [node_type]
        if any(str(t).lower() == "recipe" for t in types):
            return node
        queue.extend(node.get("@graph", []))
    return None


def _strip(text) -> str:
    return re.sub(r"<[^>]+>", "", str(text or "")).replace("&amp;", "&").strip()


def _yield_of(node: dict) -> tuple[int, str]:
    raw = node.get("recipeYield")
    if isinstance(raw, list):
        raw = raw[0] if raw else None
    m = re.search(r"\d+", str(raw or ""))
    return (int(m.group()) if m else 1), "servings"


def _steps_of(node: dict) -> list[dict]:
    out: list[dict] = []
    instructions = node.get("recipeInstructions") or []
    if isinstance(instructions, str):
        instructions = [s for s in re.split(r"\.\s+", _strip(instructions)) if s]
    queue = list(instructions)
    while queue:
        item = queue.pop(0)
        if isinstance(item, dict):
            if str(item.get("@type", "")).lower() == "howtosection":
                queue = list(item.get("itemListElement", [])) + queue
                continue
            text = _strip(item.get("text") or item.get("name"))
        else:
            text = _strip(item)
        if text:
            out.append({"text": text.rstrip(".") + "."})
    return out


def draft_from_jsonld(node: dict) -> RecipeDraft:
    base_yield, yield_word = _yield_of(node)
    ingredients = [
        parse_ingredient(_strip(line)) for line in node.get("recipeIngredient") or [] if _strip(line)
    ]
    return RecipeDraft(
        title=_strip(node.get("name")) or "Imported recipe",
        meta=_strip(node.get("description"))[:120] or None,
        base_yield=base_yield,
        yield_word=yield_word,
        ingredients=ingredients,
        steps=_steps_of(node),
        notes=[],
    )


FALLBACK_PROMPT = (
    "Extract the recipe from this web page text as JSON with keys: title, "
    "base_yield (int), yield_word, ingredients (list of {amount, unit, name} — "
    "units only g, ml, cup, tbsp, tsp, lb, oz, or empty; amount 0 = to taste), "
    "steps (list of {text}), notes (list of strings). Output ONLY the JSON."
)


async def _draft_from_llm(html: str, provider: LLMProvider) -> RecipeDraft:
    text = re.sub(r"<(script|style)[^>]*>.*?</\1>", " ", html, flags=re.S | re.I)
    text = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", text))[:8000]
    parts: list[str] = []
    try:
        async for token in provider.stream_chat(
            [
                {"role": "system", "content": FALLBACK_PROMPT},
                {"role": "user", "content": text},
            ],
            has_corpus_chunks=False,
        ):
            parts.append(token)
    except Exception as exc:
        raise HTTPException(422, "No structured recipe found on that page") from exc
    raw = "".join(parts)
    m = re.search(r"\{.*\}", raw, re.S)
    if not m:
        raise HTTPException(422, "No structured recipe found on that page")
    try:
        return RecipeDraft.model_validate(json.loads(m.group()))
    except Exception as exc:
        raise HTTPException(422, "No structured recipe found on that page") from exc


async def import_from_url(url: str, provider: LLMProvider) -> dict:
    """→ {draft, source, gf_risks}; raises problem responses on failure."""
    host = _check_url(url)
    html = await _fetch(url)
    node = _find_recipe_node(html)
    draft = draft_from_jsonld(node) if node else await _draft_from_llm(html, provider)
    risks = scan_ingredients([i.model_dump() for i in draft.ingredients])
    return {
        "draft": draft.model_dump(),
        "source": host.removeprefix("www."),
        "gf_risks": risks,
    }
