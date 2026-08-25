from datetime import date, timedelta
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.auth import require_token
from app.db import get_session
from app.models import MealPlan, Recipe, ShoppingItem
from app.routers.shopping import MAX_ITEMS, _all, _out, _to_line
from app.schemas.plan import PlanEntryCreate, PlanEntryOut, WeekPlanOut
from app.schemas.shopping import ShoppingListOut
from app.services.scaling import scale_ingredients
from app.services.shopping import ShoppingLine, merge_lines

router = APIRouter(prefix="/plan", tags=["plan"])


def monday_of(d: date) -> date:
    return d - timedelta(days=d.weekday())


def _entry_out(e: MealPlan) -> PlanEntryOut:
    return PlanEntryOut(
        id=e.id,
        date=e.date,
        meal=e.meal,
        scaled_yield=e.scaled_yield,
        recipe_slug=e.recipe.slug,
        recipe_title=e.recipe.title,
        gf=e.recipe.gf,
    )


async def _week_payload(session: AsyncSession, week: date) -> WeekPlanOut:
    entries = (
        (
            await session.execute(
                select(MealPlan)
                .where(MealPlan.date >= week, MealPlan.date < week + timedelta(days=7))
                .order_by(MealPlan.date, MealPlan.meal)
            )
        )
        .scalars()
        .all()
    )
    return WeekPlanOut(week=week, entries=[_entry_out(e) for e in entries])


@router.get("", response_model=WeekPlanOut)
async def get_week(
    week: date = Query(default_factory=date.today),
    session: AsyncSession = Depends(get_session),
):
    return await _week_payload(session, monday_of(week))


@router.post("", response_model=WeekPlanOut, dependencies=[Depends(require_token)])
async def upsert_entry(payload: PlanEntryCreate, session: AsyncSession = Depends(get_session)):
    """Put a recipe in a (date, meal) slot — replaces whatever was there."""
    recipe = (
        await session.execute(select(Recipe).where(Recipe.slug == payload.recipe_slug))
    ).scalar_one_or_none()
    if recipe is None:
        raise HTTPException(404, f"No recipe with slug '{payload.recipe_slug}'")
    existing = (
        await session.execute(
            select(MealPlan).where(MealPlan.date == payload.date, MealPlan.meal == payload.meal)
        )
    ).scalar_one_or_none()
    if existing is not None:
        await session.delete(existing)
        await session.flush()
    session.add(
        MealPlan(
            date=payload.date,
            meal=payload.meal,
            recipe_id=recipe.id,
            scaled_yield=payload.scaled_yield or recipe.base_yield,
        )
    )
    await session.commit()
    return await _week_payload(session, monday_of(payload.date))


@router.delete("/{entry_id}", response_model=WeekPlanOut, dependencies=[Depends(require_token)])
async def remove_entry(entry_id: UUID, session: AsyncSession = Depends(get_session)):
    entry = (
        await session.execute(select(MealPlan).where(MealPlan.id == entry_id))
    ).scalar_one_or_none()
    if entry is None:
        raise HTTPException(404, "No such plan entry")
    week = monday_of(entry.date)
    await session.delete(entry)
    await session.commit()
    return await _week_payload(session, week)


@router.post(
    "/shopping-list", response_model=ShoppingListOut, dependencies=[Depends(require_token)]
)
async def push_week_to_shopping(
    week: date = Query(default_factory=date.today),
    session: AsyncSession = Depends(get_session),
):
    """Push the week's planned recipes into the running shopping list — the one
    list the iOS app and /shopping share. Adding merges into existing lines
    (never replaces them) and checked state survives, per the merge rules in
    services/shopping.py. To-taste rows never join the list."""
    week = monday_of(week)
    entries = (
        (
            await session.execute(
                select(MealPlan)
                .where(MealPlan.date >= week, MealPlan.date < week + timedelta(days=7))
                .options(selectinload(MealPlan.recipe).selectinload(Recipe.versions))
            )
        )
        .scalars()
        .all()
    )
    incoming: list[ShoppingLine] = []
    for entry in entries:
        recipe = entry.recipe
        current = next((v for v in recipe.versions if v.is_current), None)
        if current is None or recipe.noscale:
            continue
        target = entry.scaled_yield or recipe.base_yield
        for row in scale_ingredients(current.ingredients, recipe.base_yield, target):
            if (row.get("name") or "").strip() and row["scaled_amount"] > 0:
                incoming.append(
                    ShoppingLine(
                        name=row["name"],
                        amount=row["scaled_amount"],
                        unit=row.get("unit", ""),
                        to_taste=False,
                        recipes=[recipe.slug],
                    )
                )

    existing = await _all(session)
    combined = merge_lines([_to_line(i) for i in existing] + incoming)
    if len(combined) > MAX_ITEMS:
        raise HTTPException(400, f"Shopping list would exceed {MAX_ITEMS} items")
    await session.execute(delete(ShoppingItem))
    for line in combined:
        session.add(
            ShoppingItem(
                name=line.name,
                amount=line.amount,
                unit=line.unit,
                to_taste=line.to_taste,
                checked=line.checked,
                recipes=line.recipes,
            )
        )
    await session.commit()
    return ShoppingListOut(items=[_out(i) for i in await _all(session)])
