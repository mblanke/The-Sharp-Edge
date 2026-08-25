"""Register the brand fonts with reportlab for the print deck.

The vendored files are variable TTFs (full charset — the notebook has Romanian
names the PDF base-14 fonts can't render). Static instances are cut with
fonttools at first use and cached in memory; registration is idempotent.
Falls back to base-14 silently if anything goes wrong, so cards.pdf always
generates."""

import io
from functools import lru_cache
from pathlib import Path

FONT_DIR = Path(__file__).resolve().parent.parent / "assets" / "fonts"

# (reportlab name, file, axes)
INSTANCES = [
    ("Fraunces-Display", "Fraunces-var.ttf", {"wght": 650, "opsz": 40, "SOFT": 0, "WONK": 1}),
    ("WorkSans", "WorkSans-var.ttf", {"wght": 400}),
    ("WorkSans-SemiBold", "WorkSans-var.ttf", {"wght": 600}),
    ("SplineSansMono", "SplineSansMono-var.ttf", {"wght": 400}),
    ("SplineSansMono-Medium", "SplineSansMono-var.ttf", {"wght": 500}),
]

# card font roles → (registered-or-fallback names resolved at registration)
_FALLBACK = {
    "Fraunces-Display": "Times-Bold",
    "WorkSans": "Helvetica",
    "WorkSans-SemiBold": "Helvetica-Bold",
    "SplineSansMono": "Courier",
    "SplineSansMono-Medium": "Courier-Bold",
}


def _instance_ttf(path: Path, axes: dict) -> bytes:
    from fontTools import ttLib
    from fontTools.varLib import instancer

    font = ttLib.TTFont(str(path))
    limited = {k: v for k, v in axes.items() if k in {a.axisTag for a in font["fvar"].axes}}
    instancer.instantiateVariableFont(font, limited, inplace=True)
    buf = io.BytesIO()
    font.save(buf)
    return buf.getvalue()


@lru_cache(maxsize=1)
def register_card_fonts() -> dict[str, str]:
    """Returns role → usable reportlab font name (brand font or base-14 fallback)."""
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont

    resolved: dict[str, str] = {}
    for name, filename, axes in INSTANCES:
        try:
            data = _instance_ttf(FONT_DIR / filename, axes)
            pdfmetrics.registerFont(TTFont(name, io.BytesIO(data)))
            resolved[name] = name
        except Exception:
            resolved[name] = _FALLBACK[name]
    return resolved
