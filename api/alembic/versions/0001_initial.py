"""Phase 1 tables: recipe, recipe_version, tag, recipe_tag, notebook_page, redirect.

pgvector extension enabled now (idempotent) so Phase 3 needs no superuser step;
no Phase 3 tables are created here (CLAUDE.md §13).

Revision ID: 0001
Revises:
Create Date: 2026-07-23
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS vector")

    op.create_table(
        "recipe",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("slug", sa.String(), nullable=False, unique=True, index=True),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("category", sa.String(), nullable=False),
        sa.Column("meta", sa.Text(), nullable=True),
        sa.Column("base_yield", sa.Integer(), nullable=False),
        sa.Column("yield_word", sa.String(), nullable=False),
        sa.Column("gf", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("noscale", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("source", sa.Text(), nullable=True),
        sa.Column("status", sa.String(), nullable=False, server_default="active"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )

    op.create_table(
        "recipe_version",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("recipe_id", sa.Uuid(), sa.ForeignKey("recipe.id", ondelete="CASCADE"), nullable=False),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("label", sa.String(), nullable=True),
        sa.Column("ingredients", JSONB(), nullable=False),
        sa.Column("steps", JSONB(), nullable=False),
        sa.Column("notes", JSONB(), nullable=False),
        sa.Column("is_current", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("recipe_id", "version"),
    )

    op.create_table(
        "tag",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("name", sa.String(), nullable=False, unique=True),
    )

    op.create_table(
        "recipe_tag",
        sa.Column("recipe_id", sa.Uuid(), sa.ForeignKey("recipe.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("tag_id", sa.Uuid(), sa.ForeignKey("tag.id", ondelete="CASCADE"), primary_key=True),
    )

    op.create_table(
        "notebook_page",
        sa.Column("recipe_id", sa.Uuid(), sa.ForeignKey("recipe.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("page_number", sa.Integer(), primary_key=True),
        sa.Column("section", sa.String(), nullable=True),
    )

    op.create_table(
        "redirect",
        sa.Column("old_slug", sa.String(), primary_key=True),
        sa.Column("slug", sa.String(), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("redirect")
    op.drop_table("notebook_page")
    op.drop_table("recipe_tag")
    op.drop_table("tag")
    op.drop_table("recipe_version")
    op.drop_table("recipe")
