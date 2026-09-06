"""Thumbs up/down on an answer.

The retrieval eval is a 27-question ratchet that only grows when somebody writes
JSON by hand. A one-tap verdict on a real answer is the raw material for the golden
set (see api/scripts/promote_golden.py) — and the only signal the app has that an
answer was actually useful in a kitchen.

Revision ID: 0009
Revises: 0008
Create Date: 2026-09-06
"""
from alembic import op
import sqlalchemy as sa

revision = "0009"
down_revision = "0008"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("message", sa.Column("feedback", sa.String(), nullable=True))


def downgrade() -> None:
    op.drop_column("message", "feedback")
