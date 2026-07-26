import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, Float, String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base
from app.models.recipe import JsonCol, utcnow


class ShoppingItem(Base):
    """One line of the running shopping list.

    CLAUDE.md §5 sketched this as `amount text`, but merging quantities across
    recipes needs numbers — "3 tbsp paprika" plus "2 tbsp paprika" can only become
    "5 tbsp" if the amount is a float and the unit is separate. The rendered string
    is derived on read via services/scaling.format_amount, so the display stays
    identical to every other quantity in the app. Recorded in DECISIONS.md.
    """

    __tablename__ = "shopping_item"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    amount: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    unit: Mapped[str] = mapped_column(String, nullable=False, default="")
    #: amount 0 = "to taste" (CLAUDE.md §5) — never carries a quantity, never scales.
    to_taste: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    checked: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    #: Which recipes contributed, so a line can explain itself.
    recipes: Mapped[list] = mapped_column(JsonCol, nullable=False, default=list)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
