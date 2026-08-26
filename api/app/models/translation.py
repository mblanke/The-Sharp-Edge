import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, Text, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base
from app.models.recipe import JsonCol, utcnow


class RecipeTranslation(Base):
    """One version of one recipe, in one language.

    Keyed on the version rather than the recipe: an edit produces a new version,
    which must not inherit the previous version's translated words.
    """

    __tablename__ = "recipe_translation"
    __table_args__ = (
        UniqueConstraint("recipe_version_id", "lang", name="uq_translation_version_lang"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    recipe_version_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("recipe_version.id", ondelete="CASCADE"), nullable=False, index=True
    )
    lang: Mapped[str] = mapped_column(String, nullable=False)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    meta: Mapped[str | None] = mapped_column(Text)
    ingredients: Mapped[list] = mapped_column(JsonCol, nullable=False, default=list)
    steps: Mapped[list] = mapped_column(JsonCol, nullable=False, default=list)
    notes: Mapped[list] = mapped_column(JsonCol, nullable=False, default=list)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
