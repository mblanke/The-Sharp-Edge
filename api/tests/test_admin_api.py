"""Admin routes: the celiac sweep and the shelf-coverage report."""



# --- shelf coverage report ------------------------------------------------------------


async def test_coverage_report_names_the_fix(client, auth, monkeypatch):
    """A gap nobody can see is a gap nobody fixes. Ingestion is Atlas's job, so the
    report hands over the command rather than acting."""
    import app.routers.admin as admin_module
    from app.services.coverage import BookCoverage

    async def fake(*, force: bool = False):
        return {
            "professional-chef": BookCoverage("professional-chef", "The Professional Chef", 5423, "indexed"),
            "under-pressure": BookCoverage("under-pressure", "Under Pressure", 0, "missing"),
            "modernist-cuisine": BookCoverage("modernist-cuisine", "Modernist Cuisine", 2, "thin"),
        }

    monkeypatch.setattr(admin_module, "book_coverage", fake)

    assert (await client.get("/api/v1/admin/library/coverage")).status_code == 401

    body = (await client.get("/api/v1/admin/library/coverage", headers=auth)).json()
    assert body["available"] is True
    assert body["searchable"] == 1 and body["total"] == 3

    by_id = {b["id"]: b for b in body["books"]}
    assert by_id["professional-chef"]["fix"] is None  # nothing to do
    assert "split .zip" in by_id["under-pressure"]["fix"]
    # 875 MB of PDFs represented by a 1 KB blurb file — the case a size-blind rule misses
    assert by_id["modernist-cuisine"]["status"] == "thin"
    assert "blurb" in by_id["modernist-cuisine"]["fix"]


async def test_coverage_reports_unavailable_rather_than_empty(client, auth, monkeypatch):
    import app.routers.admin as admin_module

    async def fake(*, force: bool = False):
        return {}

    monkeypatch.setattr(admin_module, "book_coverage", fake)
    body = (await client.get("/api/v1/admin/library/coverage", headers=auth)).json()
    assert body["available"] is False and body["books"] == []
