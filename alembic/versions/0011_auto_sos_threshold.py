"""Auto-SOS threshold and dispatch marker (SRS FR-EMG-02, §6.2)

Two columns, both in service of an auto-SOS that never existed.

`users.threat_threshold` gives the setting a home on the server. The mobile
app has shipped a "threat threshold" slider on the Profile screen for some
time, writing to Hive and read by nothing -- a control that implied SafeHer
would raise the alarm on the user's behalf when it could not. The decision
is taken server-side, so the preference has to live there too.

`incidents.auto_dispatched` marks an incident the system raised by itself.
It is what the SRS §6.2 deduplication window is measured against: without a
durable marker the window lives only in process memory, and a restart mid
emergency would let a second alert go to every contact of a woman already
in one.
"""

from alembic import op
import sqlalchemy as sa

revision = "0011_auto_sos_threshold"
down_revision = "0010_incident_ai_summary"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("users") as batch:
        # server_default so existing rows get the SRS default rather than
        # NULL, which would read as "no threshold" and disable auto-SOS for
        # every account created before this migration.
        batch.add_column(
            sa.Column("threat_threshold", sa.Float(), nullable=False, server_default="0.75")
        )
    with op.batch_alter_table("incidents") as batch:
        batch.add_column(
            sa.Column(
                "auto_dispatched", sa.Boolean(), nullable=False, server_default=sa.false()
            )
        )


def downgrade() -> None:
    with op.batch_alter_table("incidents") as batch:
        batch.drop_column("auto_dispatched")
    with op.batch_alter_table("users") as batch:
        batch.drop_column("threat_threshold")
