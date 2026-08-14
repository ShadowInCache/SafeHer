"""safe journeys, safety PIN, and phone-side trigger preferences

Backs the Safe Journey, Emergency Cancel PIN, and opt-in shake/voice trigger
features. Journey breadcrumbs deliberately reuse the existing `locations`
table (new nullable `journey_id`) rather than introducing a second location
store — the app has one source of truth for where the user has been.

Revision ID: 0006_safety_features
Revises: 0005_notification_preferences
Create Date: 2026-08-14 00:00:00.000000
"""

from alembic import op
import sqlalchemy as sa

revision = "0006_safety_features"
down_revision = "0005_notification_preferences"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "safe_journeys",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("destination_label", sa.String(), nullable=False),
        sa.Column("destination_lat", sa.Float(), nullable=True),
        sa.Column("destination_lng", sa.Float(), nullable=True),
        sa.Column("expected_duration_minutes", sa.Integer(), nullable=False),
        sa.Column("check_in_interval_minutes", sa.Integer(), nullable=True),
        sa.Column("status", sa.String(), nullable=False, server_default="active"),
        sa.Column("started_at", sa.DateTime(), nullable=False),
        sa.Column("expected_arrival_at", sa.DateTime(), nullable=False),
        sa.Column("last_check_in_at", sa.DateTime(), nullable=True),
        sa.Column("ended_at", sa.DateTime(), nullable=True),
        sa.Column("escalated_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_safe_journeys_user_id", "safe_journeys", ["user_id"])
    op.create_index("ix_safe_journeys_status", "safe_journeys", ["status"])

    op.create_table(
        "journey_participants",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("journey_id", sa.String(), sa.ForeignKey("safe_journeys.id", ondelete="CASCADE"), nullable=False),
        sa.Column(
            "contact_id",
            sa.String(),
            sa.ForeignKey("emergency_contacts.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_journey_participants_journey_id", "journey_participants", ["journey_id"])

    op.create_table(
        "safety_pins",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("pin_hash", sa.String(), nullable=False),
        sa.Column("failed_attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("locked_until", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_safety_pins_user_id", "safety_pins", ["user_id"], unique=True)

    op.create_table(
        "user_safety_preferences",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("shake_trigger_enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("shake_sensitivity", sa.Integer(), nullable=False, server_default="2"),
        sa.Column("voice_commands_enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("require_pin_to_cancel", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("journey_auto_share_location", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_user_safety_preferences_user_id", "user_safety_preferences", ["user_id"], unique=True)

    with op.batch_alter_table("locations") as batch_op:
        batch_op.add_column(sa.Column("journey_id", sa.String(), nullable=True))
        batch_op.create_foreign_key(
            "fk_locations_journey_id", "safe_journeys", ["journey_id"], ["id"], ondelete="CASCADE"
        )
    op.create_index("ix_locations_journey_id", "locations", ["journey_id"])


def downgrade():
    op.drop_index("ix_locations_journey_id", table_name="locations")
    with op.batch_alter_table("locations") as batch_op:
        batch_op.drop_constraint("fk_locations_journey_id", type_="foreignkey")
        batch_op.drop_column("journey_id")

    op.drop_index("ix_user_safety_preferences_user_id", table_name="user_safety_preferences")
    op.drop_table("user_safety_preferences")
    op.drop_index("ix_safety_pins_user_id", table_name="safety_pins")
    op.drop_table("safety_pins")
    op.drop_index("ix_journey_participants_journey_id", table_name="journey_participants")
    op.drop_table("journey_participants")
    op.drop_index("ix_safe_journeys_status", table_name="safe_journeys")
    op.drop_index("ix_safe_journeys_user_id", table_name="safe_journeys")
    op.drop_table("safe_journeys")
