"""Phase 4: meal_plan (CLAUDE.md §5).

The shopping_item table already exists from 0003 (the running shopping list the
iOS app uses); the plan feeds that list rather than keeping its own.

Revision ID: 0004
Revises: 0003
Create Date: 2026-08-24
"""
from alembic import op
import sqlalchemy as sa

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "meal_plan",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("date", sa.Date(), nullable=False),
        sa.Column("recipe_id", sa.Uuid(), sa.ForeignKey("recipe.id", ondelete="CASCADE"), nullable=False),
        sa.Column("meal", sa.String(), nullable=False),
        sa.Column("scaled_yield", sa.Integer(), nullable=False),
        sa.UniqueConstraint("date", "meal", name="uq_meal_plan_slot"),
    )


def downgrade() -> None:
    op.drop_table("meal_plan")
