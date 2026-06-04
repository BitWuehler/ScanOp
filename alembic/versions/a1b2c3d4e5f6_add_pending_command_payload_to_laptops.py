"""add_pending_command_payload_to_laptops

Revision ID: a1b2c3d4e5f6
Revises: f5630f027558
Create Date: 2026-06-04 15:45:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, None] = 'f5630f027558'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('laptops', sa.Column('pending_command_payload', sa.Text(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('laptops', 'pending_command_payload')
