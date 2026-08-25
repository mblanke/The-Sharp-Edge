from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

ALLOWED_UNITS = {"g", "ml", "cup", "tbsp", "tsp", "lb", "oz", ""}


class Ingredient(BaseModel):
    model_config = ConfigDict(extra="allow")  # section, note ride along

    amount: float = 0  # 0 = to taste → em dash, never scales
    unit: str = ""
    name: str
    note: str | None = None
    section: str | None = None


class Step(BaseModel):
    model_config = ConfigDict(extra="allow")

    text: str
    timer_seconds: int | None = None


class PageRef(BaseModel):
    """Notebook page mapping — feeds the cards.pdf glue-in index (§10)."""

    model_config = ConfigDict(from_attributes=True)

    page_number: int = Field(ge=1)
    section: str | None = None


class RecipeCard(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    slug: str
    title: str
    category: str
    meta: str | None = None
    base_yield: int
    yield_word: str
    gf: bool
    noscale: bool
    status: str
    tags: list[str] = []


class VersionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    version: int
    label: str | None = None
    ingredients: list[Ingredient]
    steps: list[Step]
    notes: list[str]
    is_current: bool
    created_at: datetime


class RecipeFull(RecipeCard):
    source: str | None = None
    pages: list[PageRef] = []
    current_version: VersionOut


class VersionSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    version: int
    label: str | None = None
    is_current: bool
    created_at: datetime


class RecipeCreate(BaseModel):
    slug: str = Field(pattern=r"^[a-z0-9][a-z0-9-]*$")
    title: str
    category: str
    meta: str | None = None
    base_yield: int = Field(ge=1)
    yield_word: str = "servings"
    gf: bool = False
    noscale: bool = False
    source: str | None = None
    status: str = "active"
    label: str | None = None
    ingredients: list[Ingredient] = []
    steps: list[Step] = []
    notes: list[str] = []
    tags: list[str] = []
    pages: list[PageRef] = []


class RecipeUpdate(BaseModel):
    """PUT — appends a new version; recipe fields update in place. Slug never changes."""

    title: str | None = None
    category: str | None = None
    meta: str | None = None
    base_yield: int | None = Field(default=None, ge=1)
    yield_word: str | None = None
    gf: bool | None = None
    noscale: bool | None = None
    source: str | None = None
    status: str | None = None
    label: str | None = None
    ingredients: list[Ingredient]
    steps: list[Step]
    notes: list[str] = []
    tags: list[str] | None = None  # None = leave unchanged
    pages: list[PageRef] | None = None  # None = leave unchanged


class CookSessionCreate(BaseModel):
    started_at: datetime | None = None  # None = finished_at (untimed log)
    scaled_yield: int = Field(ge=1)
    notes: str | None = Field(default=None, max_length=500)


class CookSessionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    started_at: datetime
    finished_at: datetime
    scaled_yield: int
    notes: str | None = None


class ScaleRequest(BaseModel):
    target_yield: int = Field(ge=1)


class ScaledIngredient(Ingredient):
    scaled_amount: float
    display: str


class ScaleResponse(BaseModel):
    slug: str
    base_yield: int
    target_yield: int
    yield_word: str
    ingredients: list[ScaledIngredient]
