"""user profile fields (phone, avatar)

The Profile screen needs a real phone number and avatar URL on the user
record — neither existed before. Nullable so existing rows don't need a
backfill.

Revision ID: 0003_user_profile_fields
Revises: 0002_device_telemetry
Create Date: 2026-08-13 00:00:00.000000
"""

from alembic import op
import sqlalchemy as sa

revision = "0003_user_profile_fields"
down_revision = "0002_device_telemetry"
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table("users") as batch_op:
        batch_op.add_column(sa.Column("phone", sa.String(), nullable=True))
        batch_op.add_column(sa.Column("avatar_url", sa.String(), nullable=True))


def downgrade():
    with op.batch_alter_table("users") as batch_op:
        batch_op.drop_column("avatar_url")
        batch_op.drop_column("phone")
