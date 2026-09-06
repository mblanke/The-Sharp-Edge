"""Build the iOS font bundle from the web app's self-hosted woff2 files.

The web ships Fraunces, Work Sans and Spline Sans Mono as variable woff2 subsets
(latin + latin-ext). iOS cannot load woff2 and SwiftUI cannot pick a weight from a
variable font by name, so this instances one static TTF per design weight, merges
the two subsets (Romanian ă/ș/ț and German ß stay in-family), and sets the
PostScript names `Typography.swift` looks up. All three families are OFL-licensed.

Run from the repo root:

    cd api && uv run --with fonttools --with brotli python ../ios/scripts/make_fonts.py
"""

from __future__ import annotations

import io
import os
import tempfile
from pathlib import Path

from fontTools.merge import Merger
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "web" / "static" / "fonts"
OUT = ROOT / "ios" / "TheSharpEdge" / "Resources" / "Fonts"

# (web basename, axis coordinates, family, style, PostScript name)
JOBS = [
    ("fraunces", {"opsz": 72, "wght": 650}, "Fraunces", "SemiBold", "Fraunces-SemiBold"),
    ("work-sans", {"wght": 400}, "Work Sans", "Regular", "WorkSans-Regular"),
    ("work-sans", {"wght": 600}, "Work Sans", "SemiBold", "WorkSans-SemiBold"),
    ("spline-sans-mono", {"wght": 500}, "Spline Sans Mono", "Medium", "SplineSansMono-Medium"),
    ("spline-sans-mono", {"wght": 600}, "Spline Sans Mono", "SemiBold", "SplineSansMono-SemiBold"),
]


def instance(path: Path, coords: dict[str, float]) -> bytes:
    font = TTFont(path)
    font.flavor = None  # woff2 → plain sfnt
    static = instancer.instantiateVariableFont(font, coords, inplace=False)
    buf = io.BytesIO()
    static.save(buf)
    return buf.getvalue()


def set_names(font: TTFont, family: str, style: str, ps: str) -> None:
    name = font["name"]
    for nid in (1, 2, 3, 4, 6, 16, 17):
        name.removeNames(nameID=nid)
    for pid, eid, lid in ((3, 1, 0x409), (1, 0, 0)):
        name.setName(family, 1, pid, eid, lid)
        name.setName(style, 2, pid, eid, lid)
        name.setName(f"{family}:{ps}", 3, pid, eid, lid)
        name.setName(f"{family} {style}", 4, pid, eid, lid)
        name.setName(ps, 6, pid, eid, lid)
    bold = "Bold" in style
    font["head"].macStyle = 1 if bold else 0
    font["OS/2"].fsSelection = (font["OS/2"].fsSelection & ~0x61) | (0x20 if bold else 0x40)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for base, coords, family, style, ps in JOBS:
        with tempfile.TemporaryDirectory() as tmp:
            parts = []
            for subset in ("latin", "latin-ext"):
                p = Path(tmp) / f"{ps}-{subset}.ttf"
                p.write_bytes(instance(SRC / f"{base}-{subset}.woff2", coords))
                parts.append(str(p))
            merged = Merger().merge(parts)
        set_names(merged, family, style, ps)
        out = OUT / f"{ps}.ttf"
        merged.save(out)
        chars = set(map(chr, TTFont(out).getBestCmap()))
        assert {"ă", "ș", "ț", "ß", "é"} <= chars, f"{ps}: latin-ext glyphs missing"
        print(f"{ps:26} {os.path.getsize(out) // 1024:4} KB")


if __name__ == "__main__":
    main()
