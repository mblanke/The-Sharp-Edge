import uuid

from pydantic import BaseModel, Field


class ShoppingAdd(BaseModel):
    slug: str
    #: Servings to buy for. Defaults to the recipe's base yield.
    target_yield: int | None = Field(default=None, ge=1)


class ShoppingToggle(BaseModel):
    checked: bool


class ShoppingItemOut(BaseModel):
    id: uuid.UUID
    name: str
    amount: float
    unit: str
    #: Rendered by services/scaling.format_amount, so quantities read the same here
    #: as everywhere else — kitchen fractions, em dash for to-taste.
    display: str
    to_taste: bool
    checked: bool
    #: Slugs that contributed to this line.
    recipes: list[str] = []
    #: True for ingredients that routinely hide gluten — worth verifying in the shop.
    check_gluten: bool = False


class ShoppingListOut(BaseModel):
    items: list[ShoppingItemOut] = []
