"""Phase 4: shopping_item table for the running shopping list.

Amount is numeric rather than the text sketched in CLAUDE.md §5 — merging
quantities across recipes ("3 tbsp" + "2 tbsp" = "5 tbsp") needs arithmetic, and
the display string is derived on read so it matches every other quantity in the
app. See DECISIONS.md.

Revision ID: 0003
Revises: 0002
Create Date: 2026-07-26
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "shopping_item",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("amount", sa.Float(), nullable=False, server_default="0"),
        sa.Column("unit", sa.String(), nullable=False, server_default=""),
        sa.Column("to_taste", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("checked", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("recipes", JSONB(), nullable=False, server_default="[]"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )


def downgrade() -> None:
    op.drop_table("shopping_item")
