from typing import Literal

from pydantic import BaseModel, Field

from app.schemas.recipe import Ingredient
from app.services.ingredients import LANGS

Lang = Literal["en", "fr", "de", "ro"]
assert set(LANGS) == {"en", "fr", "de", "ro"}, "Lang literal must track ingredients.LANGS"


class ParseIngredientsRequest(BaseModel):
    """One dictated (or typed) utterance per line."""

    lines: list[str] = Field(max_length=200)
    lang: Lang = "en"


class ParseIngredientsResponse(BaseModel):
    ingredients: list[Ingredient]


class SlugRequest(BaseModel):
    title: str = Field(min_length=1, max_length=200)


class SlugResponse(BaseModel):
    slug: str
    #: False when a recipe already holds this slug — surfaced inline before save so the
    #: create POST never dead-ends on a 409. Slugs are the QR contract and never change.
    available: bool
    valid: bool


class CategoryRequest(BaseModel):
    spoken: str = Field(min_length=1, max_length=100)
    lang: Lang = "en"


class CategoryResponse(BaseModel):
    category: str | None
