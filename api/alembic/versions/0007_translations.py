"""Cached recipe translations, one per version per language.

A photographed page keeps the cook's own language; this is how it gets read in
another one. Cached per *version* so a translation is never shown against edited
content, and generated once rather than on every view.

Revision ID: 0007
Revises: 0006
Create Date: 2026-08-26
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None

JsonCol = sa.JSON().with_variant(JSONB(), "postgresql")


def upgrade() -> None:
    op.create_table(
        "recipe_translation",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("recipe_version_id", sa.Uuid(),
                  sa.ForeignKey("recipe_version.id", ondelete="CASCADE"),
                  nullable=False, index=True),
        sa.Column("lang", sa.String(), nullable=False),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("meta", sa.Text(), nullable=True),
        sa.Column("ingredients", JsonCol, nullable=False),
        sa.Column("steps", JsonCol, nullable=False),
        sa.Column("notes", JsonCol, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
        sa.UniqueConstraint("recipe_version_id", "lang", name="uq_translation_version_lang"),
    )


def downgrade() -> None:
    op.drop_table("recipe_translation")
