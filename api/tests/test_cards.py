"""cards.pdf generator (§10): geometry, order, content, imposition."""

import io

from pypdf import PdfReader

from tests.test_export_master import MASTER, seeded  # noqa: F401 (fixture reuse)


async def test_cards_pdf_smoke(client, auth, seeded):  # noqa: F811
    res = await client.get("/api/v1/export/cards.pdf", headers=auth)
    assert res.status_code == 200
    assert res.headers["content-type"] == "application/pdf"

    reader = PdfReader(io.BytesIO(res.content))
    # 2 reference cards + one per seeded recipe, 2-up
    expected_sheets = -(-(2 + len(seeded)) // 2)
    assert len(reader.pages) == expected_sheets
    page = reader.pages[0]
    assert float(page.mediabox.width) == 11 * 72
    assert float(page.mediabox.height) == 8.5 * 72

    # sheet 1 = allocation table + glue-in index
    first = reader.pages[0].extract_text()
    assert "Page Allocation" in first
    assert "Glue-In Index" in first
    assert "184-page notebook" in first

    all_text = "\n".join(p.extract_text() for p in reader.pages)
    assert "Gluten-Free Hungarian Beef Goulash" in all_text
    assert "beef chuck" in all_text
    # category eyebrow + GF marker travel to print
    assert "SOUPS & STEWS  ·  GF" in all_text
    # never the owner's name
    assert "marc" not in all_text.lower()
    assert "blanke" not in all_text.lower()


async def test_cards_pdf_requires_auth(client, seeded):  # noqa: F811
    assert (await client.get("/api/v1/export/cards.pdf")).status_code == 401


def test_imposition_math():
    from app.services.cards import CARD_H, CARD_W, LETTER_H, LETTER_W

    gap = (LETTER_W - 2 * CARD_W) / 3
    assert gap > 0  # two 4.5" cards + margins fit on 11"
    assert (LETTER_H - CARD_H) / 2 > 0  # 6.75" card fits on 8.5"


def test_card_order_is_glue_in_order():
    from app.services.master_export import category_rank

    assert category_rank("Sauces & Salsas") < category_rank("Marinades")
    assert category_rank("Drinks") < category_rank("Reference")
    assert category_rank("Unknown Category") > category_rank("Reference")
