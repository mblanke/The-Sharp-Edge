from datetime import date
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

MEALS = {"breakfast", "lunch", "dinner"}


class PlanEntryCreate(BaseModel):
    date: date
    meal: str = Field(pattern=r"^(breakfast|lunch|dinner)$")
    recipe_slug: str
    scaled_yield: int | None = Field(default=None, ge=1)  # None = recipe base


class PlanEntryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    date: date
    meal: str
    scaled_yield: int
    recipe_slug: str
    recipe_title: str
    gf: bool


class ShoppingItemOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    amount: str
    checked: bool
    recipe_id: UUID | None = None


class WeekPlanOut(BaseModel):
    week: date  # Monday
    entries: list[PlanEntryOut]
    shopping: list[ShoppingItemOut]


class ShoppingCheckUpdate(BaseModel):
    checked: bool
