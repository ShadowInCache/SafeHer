"""link locations to the incident they were captured for

Emergency-alert and heartbeat handlers already wrote a Location row
alongside an Incident, but never linked them — GET /incidents/{id} had no
way to look up where an incident happened. Nullable since heartbeat
locations aren't tied to any one incident.

Revision ID: 0004_location_incident_link
Revises: 0003_user_profile_fields
Create Date: 2026-08-13 00:00:00.000000
"""

from alembic import op
import sqlalchemy as sa

revision = "0004_location_incident_link"
down_revision = "0003_user_profile_fields"
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table("locations") as batch_op:
        batch_op.add_column(sa.Column("incident_id", sa.String(), nullable=True))


def downgrade():
    with op.batch_alter_table("locations") as batch_op:
        batch_op.drop_column("incident_id")
