"""Shopping-list merge (CLAUDE.md §6): duplicate ingredients across a week's
planned recipes combine into single lines using the canonical scaling math."""

import re

from app.services.scaling import EM_DASH, format_amount


def _norm_name(name: str) -> str:
    """Merge key half: casefold, collapse whitespace, drop the trailing prep clause
    ("yellow onions, diced" and "yellow onions" merge; different heads don't)."""
    head = name.split(",")[0]
    return re.sub(r"\s+", " ", head).strip().casefold()


def merge_shopping(rows: list[dict]) -> list[dict]:
    """rows: scaled ingredient dicts ({name, unit, scaled_amount, recipe_id}).
    Returns display rows: {name, amount, recipe_id} — recipe_id None when merged
    across recipes. Same (name, unit) sums via the canonical renderer; a
    to-taste row folds into a measured line of the same ingredient, or stands
    alone as '— to taste'."""
    merged: dict[tuple[str, str], dict] = {}
    order: list[tuple[str, str]] = []
    to_taste: list[dict] = []

    for row in rows:
        name = (row.get("name") or "").strip()
        if not name:
            continue
        amount = float(row.get("scaled_amount", 0) or 0)
        if not amount:
            to_taste.append(row)
            continue
        unit = row.get("unit", "") or ""
        key = (_norm_name(name), unit)
        if key not in merged:
            merged[key] = {
                "display_name": name.split(",")[0].strip(),
                "unit": unit,
                "total": 0.0,
                "recipe_ids": set(),
            }
            order.append(key)
        merged[key]["total"] += amount
        if row.get("recipe_id"):
            merged[key]["recipe_ids"].add(row["recipe_id"])

    # to-taste rows: covered if any measured line shares the name; else standalone
    measured_names = {name for name, _ in order}
    standalone: dict[str, dict] = {}
    for row in to_taste:
        name = _norm_name(row["name"])
        if name in measured_names or name in standalone:
            if name in standalone and row.get("recipe_id"):
                standalone[name]["recipe_ids"].add(row["recipe_id"])
            continue
        standalone[name] = {
            "display_name": row["name"].split(",")[0].strip(),
            "recipe_ids": {row["recipe_id"]} if row.get("recipe_id") else set(),
        }

    def _row(display_name: str, amount_str: str, recipe_ids: set) -> dict:
        ids = list(recipe_ids)
        return {
            "name": display_name,
            "amount": amount_str,
            "recipe_id": ids[0] if len(ids) == 1 else None,
        }

    out = [
        _row(merged[key]["display_name"], format_amount(merged[key]["total"], merged[key]["unit"]), merged[key]["recipe_ids"])
        for key in order
    ]
    out.extend(
        _row(e["display_name"], f"{EM_DASH} to taste", e["recipe_ids"])
        for e in standalone.values()
    )
    return out
