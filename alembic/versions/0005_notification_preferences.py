"""notification preferences on users

The Settings screen's push/SMS/email/location-sharing toggles were only
ever persisted to Firestore, disconnected from the real backend every
other screen now uses. Adding them here instead of a new endpoint —
`/users/me` already exists for exactly this kind of per-user preference.

Revision ID: 0005_notification_preferences
Revises: 0004_location_incident_link
Create Date: 2026-08-13 00:00:00.000000
"""

from alembic import op
import sqlalchemy as sa

revision = "0005_notification_preferences"
down_revision = "0004_location_incident_link"
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table("users") as batch_op:
        batch_op.add_column(
            sa.Column("push_notifications", sa.Boolean(), nullable=False, server_default=sa.true())
        )
        batch_op.add_column(
            sa.Column("sms_notifications", sa.Boolean(), nullable=False, server_default=sa.false())
        )
        batch_op.add_column(
            sa.Column("email_notifications", sa.Boolean(), nullable=False, server_default=sa.true())
        )
        batch_op.add_column(
            sa.Column("location_sharing", sa.Boolean(), nullable=False, server_default=sa.true())
        )


def downgrade():
    with op.batch_alter_table("users") as batch_op:
        batch_op.drop_column("location_sharing")
        batch_op.drop_column("email_notifications")
        batch_op.drop_column("sms_notifications")
        batch_op.drop_column("push_notifications")
