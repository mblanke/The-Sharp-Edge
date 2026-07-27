"""The Python side of the cross-language parity contract.

These tests are deliberately thin — the fixtures were generated *from* this code, so
green here mostly proves the generator is honest and nobody hand-edited a JSON file.
The fixtures earn their keep in ios/TheSharpEdgeTests, where the same cases are the
specification for a Swift implementation that has no server to fall back on.

The one test with real teeth on this side is the last: a fixture file no suite reads
is worse than no fixture at all, because it looks like coverage.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

from app.services.aisles import aisle_rank, classify_aisle
from app.services.scaling import format_amount
from app.services.shopping import ShoppingLine, as_text, merge_lines, normalise_name
from tests.fixtures import all_fixture_names, cases, load

REPO = Path(__file__).resolve().parents[2]

#: Every fixture file must be listed here AND consumed by a test below.
CONSUMED = {
    "scaling.format_amount",
    "shopping.normalise_name",
    "shopping.check_gluten",
    "shopping.merge_lines",
    "shopping.as_text",
    "aisles.classify_aisle",
    "aisles.aisle_rank",
}


def _lines(specs):
    return [ShoppingLine(name=s["name"], amount=s["amount"], unit=s["unit"],
                         to_taste=s["amount"] == 0, recipes=[s["recipe"]])
            for s in specs]


@pytest.mark.parametrize("case_id,args,expect", cases("scaling.format_amount"))
def test_format_amount_matches_fixture(case_id, args, expect):
    assert format_amount(args["value"], args["unit"]) == expect


@pytest.mark.parametrize("case_id,args,expect", cases("shopping.normalise_name"))
def test_normalise_name_matches_fixture(case_id, args, expect):
    assert normalise_name(args["name"]) == expect


@pytest.mark.parametrize("case_id,args,expect", cases("shopping.check_gluten"))
def test_check_gluten_matches_fixture(case_id, args, expect):
    assert ShoppingLine(name=args["name"], amount=1, unit="tbsp").check_gluten == expect


@pytest.mark.parametrize("case_id,args,expect", cases("aisles.classify_aisle"))
def test_classify_aisle_matches_fixture(case_id, args, expect):
    assert classify_aisle(args["name"]) == expect


@pytest.mark.parametrize("case_id,args,expect", cases("aisles.aisle_rank"))
def test_aisle_rank_matches_fixture(case_id, args, expect):
    assert aisle_rank(args["aisle"]) == expect


@pytest.mark.parametrize("case_id,args,expect", cases("shopping.merge_lines"))
def test_merge_lines_matches_fixture(case_id, args, expect):
    tol = load("shopping.merge_lines").get("tolerance", 0.001)
    got = merge_lines(_lines(args["lines"]))
    assert len(got) == len(expect), f"{case_id}: line count"
    for line, want in zip(got, expect):
        assert line.name == want["name"]
        assert line.unit == want["unit"]
        assert line.amount == pytest.approx(want["amount"], abs=tol)
        assert line.display == want["display"]          # strings compare exactly
        assert line.to_taste == want["to_taste"]
        assert line.recipes == want["recipes"]
        assert line.check_gluten == want["check_gluten"]
        assert classify_aisle(line.name) == want["aisle"]


@pytest.mark.parametrize("case_id,args,expect", cases("shopping.as_text"))
def test_as_text_matches_fixture(case_id, args, expect):
    merged = merge_lines(_lines(args["lines"]))
    if args["group_by_aisle"]:
        merged.sort(key=lambda ln: aisle_rank(classify_aisle(ln.name)))
        assert as_text(merged, group_by=lambda ln: classify_aisle(ln.name)) == expect
    else:
        assert as_text(merged) == expect


# ------------------------------------------------------------------- the net

def test_every_fixture_file_has_a_consumer():
    """A fixture nothing reads looks like coverage and is not."""
    orphans = all_fixture_names() - CONSUMED
    assert not orphans, (
        f"Fixture files with no test reading them: {sorted(orphans)}. "
        "Add a test above (and the matching Swift test) or delete the file."
    )


def test_no_consumer_references_a_missing_fixture():
    missing = CONSUMED - all_fixture_names()
    assert not missing, (
        f"Tests expect fixtures that do not exist: {sorted(missing)}. "
        "Run: python api/scripts/dump_fixtures.py"
    )


def test_committed_fixtures_are_not_stale():
    """The generator is the source of truth; a hand-edited fixture is a lie.

    This is what turns "I changed shopping.py" into a red build rather than a silent
    divergence — regenerate, and the Swift suite fails on the case that moved.
    """
    result = subprocess.run(
        [sys.executable, str(REPO / "api" / "scripts" / "dump_fixtures.py"), "--check"],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, result.stderr or result.stdout
