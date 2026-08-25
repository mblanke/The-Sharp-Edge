"""Phase 4: meal_plan + shopping_item (CLAUDE.md §5).

Revision ID: 0003
Revises: 0002
Create Date: 2026-08-24
"""
from alembic import op
import sqlalchemy as sa

revision = "0003"
down_revision = "0002"
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
    op.create_table(
        "shopping_item",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("plan_week", sa.Date(), nullable=False, index=True),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("amount", sa.Text(), nullable=False),
        sa.Column("checked", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("recipe_id", sa.Uuid(), sa.ForeignKey("recipe.id", ondelete="SET NULL"), nullable=True),
    )


def downgrade() -> None:
    op.drop_table("shopping_item")
    op.drop_table("meal_plan")
