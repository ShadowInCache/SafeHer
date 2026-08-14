"""device telemetry columns

Heartbeats (POST /devices/{id}/heartbeat) validated battery_level,
signal_strength, and firmware_version but had nowhere to persist them —
the handler only ever touched last_seen. This adds the columns so a real
device's last-reported telemetry is actually queryable via GET /devices/me
instead of being silently discarded.

Revision ID: 0002_device_telemetry
Revises: 0001_initial_unified_schema
Create Date: 2026-08-13 00:00:00.000000
"""

from alembic import op
import sqlalchemy as sa

revision = "0002_device_telemetry"
down_revision = "0001_initial_unified_schema"
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table("devices") as batch_op:
        batch_op.add_column(sa.Column("battery_level", sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column("signal_strength", sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column("firmware_version", sa.String(), nullable=True))


def downgrade():
    with op.batch_alter_table("devices") as batch_op:
        batch_op.drop_column("firmware_version")
        batch_op.drop_column("signal_strength")
        batch_op.drop_column("battery_level")
