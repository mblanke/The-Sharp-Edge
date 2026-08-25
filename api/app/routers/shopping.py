"""The running shopping list.

Adding a recipe **adds** to existing lines rather than replacing them — see
services/shopping.py for the merge rules. Quantities come from the recipe's
*scaled* amounts, so a goulash set to 14 contributes 14 servings' worth.

Writes need the bearer token, like every other write route. Reading does not, so
the list can be pulled up on a phone in the shop without pasting a token.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import require_token
from app.db import get_session
from app.models import Recipe, ShoppingItem
from app.routers.recipes import _resolve
from app.schemas.shopping import (
    ShoppingAdd,
    ShoppingDelete,
    ShoppingItemOut,
    ShoppingListOut,
    ShoppingToggle,
)
from app.services.aisles import aisle_rank, classify_aisle
from app.services.scaling import scale_ingredients
from app.services.shopping import ShoppingLine, as_text, merge_lines

router = APIRouter(prefix="/shopping", tags=["shopping"])

MAX_ITEMS = 400


def _to_line(item: ShoppingItem) -> ShoppingLine:
    return ShoppingLine(name=item.name, amount=item.amount, unit=item.unit,
                        to_taste=item.to_taste, recipes=list(item.recipes or []),
                        checked=item.checked)


def _out(item: ShoppingItem) -> ShoppingItemOut:
    line = _to_line(item)
    return ShoppingItemOut(
        id=item.id, name=item.name, amount=item.amount, unit=item.unit,
        display=line.display, to_taste=item.to_taste, checked=item.checked,
        recipes=list(item.recipes or []), check_gluten=line.check_gluten,
        aisle=classify_aisle(item.name),
    )


async def _all(session: AsyncSession) -> list[ShoppingItem]:
    res = await session.execute(select(ShoppingItem).order_by(ShoppingItem.created_at))
    return list(res.scalars())


@router.get("", response_model=ShoppingListOut)
async def get_list(session: AsyncSession = Depends(get_session)) -> ShoppingListOut:
    """The list, already in walking order: fresh edges first, frozen last.

    Sorted here rather than in each client so the aisle table has exactly one home.
    It exists in Python and Swift (pinned to each other by shared/fixtures); a third
    copy in TypeScript purely to sort a list would be the drift this project keeps
    having to undo. Within an aisle, the order things were added is kept.
    """
    items = await _all(session)
    items.sort(key=lambda i: (aisle_rank(classify_aisle(i.name)), i.created_at))
    return ShoppingListOut(items=[_out(i) for i in items])


@router.get("/text", response_class=Response)
async def get_text(session: AsyncSession = Depends(get_session)) -> Response:
    """Plain text for the iOS share sheet — AnyList, Notes, Reminders all accept it."""
    items = [i for i in await _all(session) if not i.checked]
    # Grouped and ordered the way you walk a shop, so the exported text is useful
    # in AnyList or Notes rather than just a dump.
    items.sort(key=lambda i: (aisle_rank(classify_aisle(i.name)), i.created_at))
    body = as_text([_to_line(i) for i in items], group_by=lambda i: classify_aisle(i.name))
    return Response(content=body, media_type="text/plain; charset=utf-8")


@router.post("/add", response_model=ShoppingListOut, dependencies=[Depends(require_token)])
async def add_recipe(
    payload: ShoppingAdd, session: AsyncSession = Depends(get_session)
) -> ShoppingListOut:
    """Add a recipe's ingredients at `target_yield`, merging into what's already there."""
    recipe = await _resolve(session, payload.slug, with_versions=True)
    version = next((v for v in recipe.versions if v.is_current), None)
    if version is None:
        raise HTTPException(404, "Recipe has no current version")

    target = payload.target_yield or recipe.base_yield
    scaled = scale_ingredients(version.ingredients, recipe.base_yield, target)

    # amount 0 means "to taste" — salt, pepper, a drizzle of oil. They are not
    # shopping, they are things you already have, so they never join the list.
    incoming = [
        ShoppingLine(
            name=row["name"], amount=row["scaled_amount"], unit=row.get("unit", ""),
            to_taste=False, recipes=[recipe.slug],
        )
        for row in scaled
        if (row.get("name") or "").strip() and row["scaled_amount"] > 0
    ]

    existing = await _all(session)
    combined = merge_lines([_to_line(i) for i in existing] + incoming)
    if len(combined) > MAX_ITEMS:
        raise HTTPException(400, f"Shopping list would exceed {MAX_ITEMS} items")

    # The merge is authoritative, so the table is rewritten from it. Checked state
    # survives because merge_lines carries it on the line it came from.
    await session.execute(delete(ShoppingItem))
    for line in combined:
        session.add(ShoppingItem(
            name=line.name, amount=line.amount, unit=line.unit,
            to_taste=line.to_taste, checked=line.checked, recipes=line.recipes,
        ))
    await session.commit()
    return ShoppingListOut(items=[_out(i) for i in await _all(session)])


@router.patch("/{item_id}", response_model=ShoppingItemOut, dependencies=[Depends(require_token)])
async def toggle(
    item_id: uuid.UUID, payload: ShoppingToggle, session: AsyncSession = Depends(get_session)
) -> ShoppingItemOut:
    item = await session.get(ShoppingItem, item_id)
    if item is None:
        raise HTTPException(404, "No such shopping item")
    item.checked = payload.checked
    await session.commit()
    await session.refresh(item)
    return _out(item)


@router.post("/delete", status_code=204, dependencies=[Depends(require_token)])
async def remove_many(
    payload: ShoppingDelete, session: AsyncSession = Depends(get_session)
) -> Response:
    """Delete a selection in one request rather than one round trip per item."""
    await session.execute(delete(ShoppingItem).where(ShoppingItem.id.in_(payload.ids)))
    await session.commit()
    return Response(status_code=204)


@router.delete("/{item_id}", status_code=204, dependencies=[Depends(require_token)])
async def remove(item_id: uuid.UUID, session: AsyncSession = Depends(get_session)) -> Response:
    item = await session.get(ShoppingItem, item_id)
    if item is None:
        raise HTTPException(404, "No such shopping item")
    await session.delete(item)
    await session.commit()
    return Response(status_code=204)


@router.delete("", status_code=204, dependencies=[Depends(require_token)])
async def clear(
    checked_only: bool = False, session: AsyncSession = Depends(get_session)
) -> Response:
    stmt = delete(ShoppingItem)
    if checked_only:
        stmt = stmt.where(ShoppingItem.checked.is_(True))
    await session.execute(stmt)
    await session.commit()
    return Response(status_code=204)
