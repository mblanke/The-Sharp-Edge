"""Private-tier flag on recipes.

The library→notebook bridge drafts recipes out of copyrighted books. CLAUDE.md §1:
that content is private to the local deployment and never appears on a public route
or export — so a recipe drafted from the corpus carries `private=true`, and
/export/master.md and /export/cards.pdf (the public-tier surfaces) exclude it.

Revision ID: 0008
Revises: 0007
Create Date: 2026-08-28
"""
from alembic import op
import sqlalchemy as sa

revision = "0008"
down_revision = "0007"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "recipe",
        sa.Column("private", sa.Boolean(), nullable=False, server_default=sa.false()),
    )


def downgrade() -> None:
    op.drop_column("recipe", "private")
