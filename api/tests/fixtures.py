"""Loader for the cross-language parity fixtures in shared/fixtures/.

See api/scripts/dump_fixtures.py for why these exist. Inputs are curated by hand,
expectations are generated from this Python — so on this side the fixtures are a
regression net, and on the Swift/TS side they are the specification.
"""

from __future__ import annotations

import json
from pathlib import Path

FIXTURE_DIR = Path(__file__).resolve().parents[2] / "shared" / "fixtures"


def load(name: str) -> dict:
    path = FIXTURE_DIR / f"{name}.json"
    if not path.exists():
        raise FileNotFoundError(
            f"Missing fixture {path}. Run: python api/scripts/dump_fixtures.py"
        )
    return json.loads(path.read_text(encoding="utf-8"))


def cases(name: str) -> list[tuple[str, dict, object]]:
    """(id, args, expect) triples, ready for pytest.mark.parametrize."""
    data = load(name)
    return [(c["id"], c["args"], c["expect"]) for c in data["cases"]]


def all_fixture_names() -> set[str]:
    return {p.stem for p in FIXTURE_DIR.glob("*.json")}
