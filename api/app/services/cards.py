"""Print-card PDF (CLAUDE.md §10): 4.5" × 6.75" cards imposed 2-up on landscape
letter with dashed cut lines. First two cards are the Page Allocation table and
the glue-in index; then one card per recipe in category (= glue-in) order.
Content voice: ingredients, method, functional notes only."""

import io

import qrcode
from pypdf import PdfReader, PdfWriter, Transformation
from qrcode.constants import ERROR_CORRECT_H
from reportlab.lib.colors import HexColor
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas as rl_canvas

from app.config import settings
from app.services.fonts import register_card_fonts
from app.services.master_export import category_rank
from app.services.scaling import format_amount

# geometry (points)
CARD_W, CARD_H = 4.5 * 72, 6.75 * 72
LETTER_W, LETTER_H = 11 * 72, 8.5 * 72
MARGIN = 24
QR_SIZE = 0.6 * 72

INK = HexColor("#20241E")
GREEN = HexColor("#3E6B4A")
GREEN_DEEP = HexColor("#2C4F36")
COPPER = HexColor("#C87A2E")
FAINT = HexColor("#6B6F63")
LINE = HexColor("#D9D7CC")

# role → reportlab font name; filled by _ensure_fonts() (brand TTFs or base-14)
F: dict[str, str] = {}


def _ensure_fonts() -> None:
    F.update(register_card_fonts())


# §10 page allocation for the 184-page notebook
PAGE_ALLOCATION = [
    ("Sauces", 20), ("Marinades", 18), ("Salads", 16), ("Soups", 10),
    ("Sandwiches", 8), ("Pasta", 8), ("Entrées", 20), ("Sides", 10),
    ("Breakfast", 8), ("Baking/Desserts", 8), ("Drinks", 6),
    ("Apps/Preserves", 6), ("Overflow (back)", 46),
]


def _qr_image(slug: str) -> ImageReader:
    qr = qrcode.QRCode(error_correction=ERROR_CORRECT_H, box_size=8, border=2)
    qr.add_data(f"{settings.base_url.rstrip('/')}/r/{slug}")
    qr.make(fit=True)
    img = qr.make_image(fill_color="#20241E", back_color="white")
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    buf.seek(0)
    return ImageReader(buf)


class _Card:
    """One 4.5×6.75 card page with a simple text cursor."""

    BOTTOM = MARGIN + QR_SIZE + 8  # keep clear of the QR/footer strip

    def __init__(self, c: rl_canvas.Canvas):
        self.c = c
        self.y = CARD_H - MARGIN
        self.overflowed = False

    def _room(self) -> bool:
        if self.y < self.BOTTOM:
            if not self.overflowed:
                self.overflowed = True
                self.c.setFont(F["WorkSans"], 6.5)
                self.c.setFillColor(FAINT)
                self.c.drawString(MARGIN, self.BOTTOM - 6, "… continues in the app")
            return False
        return True

    def eyebrow(self, text: str):
        self.c.setFont(F["SplineSansMono-Medium"], 7.5)
        self.c.setFillColor(COPPER)
        self.c.drawString(MARGIN, self.y, text.upper())
        self.y -= 14

    def title(self, text: str, size: float = 13.5):
        self.c.setFont(F["Fraunces-Display"], size)
        self.c.setFillColor(INK)
        for line in self._wrap(text, F["Fraunces-Display"], size, CARD_W - 2 * MARGIN):
            self.c.drawString(MARGIN, self.y, line)
            self.y -= size + 2
        self.y -= 2

    def meta(self, text: str):
        self.c.setFont(F["WorkSans"], 7.5)
        self.c.setFillColor(FAINT)
        self.c.drawString(MARGIN, self.y, text)
        self.y -= 12

    def rule(self):
        self.c.setStrokeColor(LINE)
        self.c.setLineWidth(0.6)
        self.c.line(MARGIN, self.y, CARD_W - MARGIN, self.y)
        self.y -= 9

    def section(self, text: str):
        self.y -= 2
        self.c.setFont(F["SplineSansMono-Medium"], 7)
        self.c.setFillColor(GREEN)
        self.c.drawString(MARGIN, self.y, text.upper())
        self.y -= 10

    def line(self, text: str, font: str | None = None, size: float = 7.6,
             color=INK, indent: float = 0, qty: str | None = None):
        """One content line; qty renders mono in a fixed left column."""
        if not self._room():
            return self.y
        font = font or F["WorkSans"]
        max_w = CARD_W - 2 * MARGIN - indent
        qty_w = 44 if qty is not None else 0
        if qty is not None:
            self.c.setFont(F["SplineSansMono"], size)
            self.c.setFillColor(GREEN_DEEP)
            self.c.drawRightString(MARGIN + indent + qty_w - 4, self.y, qty)
        for wrapped in self._wrap(text, font, size, max_w - qty_w):
            if not self._room():
                break
            self.c.setFont(font, size)
            self.c.setFillColor(color)
            self.c.drawString(MARGIN + indent + qty_w, self.y, wrapped)
            self.y -= size + 2.2
        return self.y

    def qr(self, slug: str):
        self.c.drawImage(
            _qr_image(slug),
            CARD_W - MARGIN - QR_SIZE,
            MARGIN * 0.75,
            QR_SIZE,
            QR_SIZE,
        )
        self.c.setFont(F["SplineSansMono"], 6)
        self.c.setFillColor(FAINT)
        self.c.drawRightString(CARD_W - MARGIN, MARGIN * 0.75 - 7, f"/r/{slug}")

    def footer_left(self, text: str):
        self.c.setFont(F["SplineSansMono"], 6.5)
        self.c.setFillColor(FAINT)
        self.c.drawString(MARGIN, MARGIN * 0.75, text)

    def _wrap(self, text: str, font: str, size: float, max_w: float) -> list[str]:
        words = text.split()
        lines: list[str] = []
        cur = ""
        for w in words:
            probe = f"{cur} {w}".strip()
            if self.c.stringWidth(probe, font, size) <= max_w or not cur:
                cur = probe
            else:
                lines.append(cur)
                cur = w
        if cur:
            lines.append(cur)
        return lines or [""]


def _allocation_card(card: _Card):
    card.eyebrow("The Sharp Edge · Notebook Reference")
    card.title("Page Allocation")
    card.meta("184-page notebook · section budgets")
    card.rule()
    total = 0
    for name, pages in PAGE_ALLOCATION:
        card.line(name, qty=str(pages))
        total += pages
    card.rule()
    card.line("Total", font=F["WorkSans-SemiBold"], qty=str(total))


def _index_card(card: _Card, recipes: list):
    card.eyebrow("The Sharp Edge · Notebook Reference")
    card.title("Glue-In Index")
    card.meta("Recipe → notebook page (card order = glue-in order)")
    card.rule()
    for recipe in recipes:
        pages = ", ".join(str(p.page_number) for p in recipe.pages) or "—"
        card.line(recipe.title, size=7.2, qty=pages)


def _recipe_card(card: _Card, recipe, version):
    card.eyebrow(recipe.category + ("  ·  GF" if recipe.gf else ""))
    card.title(recipe.title)
    bits = [f"base {recipe.base_yield} {recipe.yield_word}"]
    if recipe.meta:
        bits.insert(0, recipe.meta)
    card.meta(" · ".join(bits))
    card.rule()

    if version.ingredients:
        section = None
        for ing in version.ingredients:
            if ing.get("section") and ing["section"] != section:
                section = ing["section"]
                card.section(section)
            qty = format_amount(ing.get("amount", 0) or 0, ing.get("unit", "") or "")
            card.line(ing.get("name", ""), qty=qty)

    if version.steps:
        card.section("Method")
        for i, step in enumerate(version.steps, 1):
            text = step["text"].replace("**", "")
            card.line(f"{i}. {text}", size=7.2)

    if version.notes:
        card.section("Notes")
        for note in version.notes:
            card.line(f"– {note.replace('**', '')}", size=6.8, color=FAINT)

    pages = ", ".join(str(p.page_number) for p in recipe.pages)
    if pages:
        card.footer_left(f"notebook p. {pages}")
    card.qr(recipe.slug)


def build_card_pages(recipes) -> bytes:
    """Single-card pages (324×486), §10 order: allocation, index, recipes."""
    _ensure_fonts()
    ordered = sorted(recipes, key=lambda r: (category_rank(r.category), r.title.lower()))
    buf = io.BytesIO()
    c = rl_canvas.Canvas(buf, pagesize=(CARD_W, CARD_H))

    _allocation_card(_Card(c))
    c.showPage()
    _index_card(_Card(c), ordered)
    c.showPage()

    for recipe in ordered:
        current = next((v for v in recipe.versions if v.is_current), None)
        if current is None:
            continue
        _recipe_card(_Card(c), recipe, current)
        c.showPage()

    c.save()
    return buf.getvalue()


def impose_2up(card_pdf: bytes) -> bytes:
    """Two cards per landscape-letter sheet with dashed cut lines."""
    reader = PdfReader(io.BytesIO(card_pdf))
    writer = PdfWriter()

    # dashed cut-line overlay drawn once per sheet
    gap = (LETTER_W - 2 * CARD_W) / 3
    y0 = (LETTER_H - CARD_H) / 2
    slots = [gap, gap * 2 + CARD_W]

    overlay_buf = io.BytesIO()
    oc = rl_canvas.Canvas(overlay_buf, pagesize=(LETTER_W, LETTER_H))
    oc.setStrokeColor(LINE)
    oc.setLineWidth(0.5)
    oc.setDash(4, 3)
    for x in slots:
        oc.rect(x, y0, CARD_W, CARD_H)
    oc.showPage()
    oc.save()
    overlay = PdfReader(io.BytesIO(overlay_buf.getvalue())).pages[0]

    for i in range(0, len(reader.pages), 2):
        sheet = writer.add_blank_page(width=LETTER_W, height=LETTER_H)
        sheet.merge_page(overlay)
        for slot, page_idx in zip(slots, (i, i + 1)):
            if page_idx >= len(reader.pages):
                break
            sheet.merge_transformed_page(
                reader.pages[page_idx], Transformation().translate(tx=slot, ty=y0)
            )

    out = io.BytesIO()
    writer.write(out)
    return out.getvalue()


def build_cards_pdf(recipes) -> bytes:
    return impose_2up(build_card_pages(recipes))
