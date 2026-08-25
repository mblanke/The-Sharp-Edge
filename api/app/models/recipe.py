import uuid
from datetime import datetime, timezone

from sqlalchemy import JSON, Boolean, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint, Uuid
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base

# JSONB on Postgres, plain JSON elsewhere (sqlite in tests)
JsonCol = JSON().with_variant(JSONB(), "postgresql")


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Recipe(Base):
    __tablename__ = "recipe"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    slug: Mapped[str] = mapped_column(String, unique=True, nullable=False, index=True)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    category: Mapped[str] = mapped_column(String, nullable=False)
    meta: Mapped[str | None] = mapped_column(Text)
    base_yield: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    yield_word: Mapped[str] = mapped_column(String, nullable=False, default="servings")
    gf: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    noscale: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    source: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String, nullable=False, default="active")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)

    versions: Mapped[list["RecipeVersion"]] = relationship(
        back_populates="recipe", order_by="RecipeVersion.version", cascade="all, delete-orphan"
    )
    # selectin: loaded with the recipe, async-safe on every existing query path
    tag_rows: Mapped[list["Tag"]] = relationship(
        secondary="recipe_tag", order_by="Tag.name", lazy="selectin"
    )
    pages: Mapped[list["NotebookPage"]] = relationship(
        order_by="NotebookPage.page_number", cascade="all, delete-orphan", lazy="selectin"
    )

    @property
    def tags(self) -> list[str]:
        return [t.name for t in self.tag_rows]


class RecipeVersion(Base):
    __tablename__ = "recipe_version"
    __table_args__ = (UniqueConstraint("recipe_id", "version"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    recipe_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("recipe.id", ondelete="CASCADE"), nullable=False)
    version: Mapped[int] = mapped_column(Integer, nullable=False)
    label: Mapped[str | None] = mapped_column(String)
    ingredients: Mapped[list] = mapped_column(JsonCol, nullable=False, default=list)
    steps: Mapped[list] = mapped_column(JsonCol, nullable=False, default=list)
    notes: Mapped[list] = mapped_column(JsonCol, nullable=False, default=list)
    is_current: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    recipe: Mapped[Recipe] = relationship(back_populates="versions")


class Tag(Base):
    __tablename__ = "tag"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String, unique=True, nullable=False)


class RecipeTag(Base):
    __tablename__ = "recipe_tag"

    recipe_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("recipe.id", ondelete="CASCADE"), primary_key=True)
    tag_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("tag.id", ondelete="CASCADE"), primary_key=True)


class NotebookPage(Base):
    __tablename__ = "notebook_page"

    recipe_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("recipe.id", ondelete="CASCADE"), primary_key=True)
    page_number: Mapped[int] = mapped_column(Integer, primary_key=True)
    section: Mapped[str | None] = mapped_column(String)


class Redirect(Base):
    """Slug renames: old_slug keeps working forever (QR contract)."""

    __tablename__ = "redirect"

    old_slug: Mapped[str] = mapped_column(String, primary_key=True)
    slug: Mapped[str] = mapped_column(String, nullable=False)
