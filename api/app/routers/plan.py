from datetime import date, timedelta
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.auth import require_token
from app.db import get_session
from app.models import MealPlan, Recipe, ShoppingItem
from app.schemas.plan import (
    PlanEntryCreate,
    PlanEntryOut,
    ShoppingCheckUpdate,
    ShoppingItemOut,
    WeekPlanOut,
)
from app.services.scaling import scale_ingredients
from app.services.shopping import merge_shopping

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
    shopping = (
        (
            await session.execute(
                select(ShoppingItem)
                .where(ShoppingItem.plan_week == week)
                .order_by(ShoppingItem.name)
            )
        )
        .scalars()
        .all()
    )
    return WeekPlanOut(
        week=week,
        entries=[_entry_out(e) for e in entries],
        shopping=[ShoppingItemOut.model_validate(s) for s in shopping],
    )


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


@router.post("/shopping-list", response_model=WeekPlanOut, dependencies=[Depends(require_token)])
async def generate_shopping_list(
    week: date = Query(default_factory=date.today),
    session: AsyncSession = Depends(get_session),
):
    """Regenerate the week's list from its planned recipes — canonical server
    scaling (§8), duplicates merged. Existing checkmarks are discarded."""
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
    rows: list[dict] = []
    for entry in entries:
        recipe = entry.recipe
        current = next((v for v in recipe.versions if v.is_current), None)
        if current is None:
            continue
        target = entry.scaled_yield if not recipe.noscale else recipe.base_yield
        for ing in scale_ingredients(current.ingredients, recipe.base_yield, target):
            rows.append({**ing, "recipe_id": recipe.id})

    await session.execute(delete(ShoppingItem).where(ShoppingItem.plan_week == week))
    for item in merge_shopping(rows):
        session.add(
            ShoppingItem(
                plan_week=week,
                name=item["name"],
                amount=item["amount"],
                recipe_id=item["recipe_id"],
            )
        )
    await session.commit()
    return await _week_payload(session, week)


@router.patch(
    "/shopping-list/{item_id}",
    response_model=ShoppingItemOut,
    dependencies=[Depends(require_token)],
)
async def check_item(
    item_id: UUID, payload: ShoppingCheckUpdate, session: AsyncSession = Depends(get_session)
):
    item = (
        await session.execute(select(ShoppingItem).where(ShoppingItem.id == item_id))
    ).scalar_one_or_none()
    if item is None:
        raise HTTPException(404, "No such shopping item")
    item.checked = payload.checked
    await session.commit()
    return ShoppingItemOut.model_validate(item)
