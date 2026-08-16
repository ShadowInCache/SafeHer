"""AI-generated incident summary (SRS FR-RPT-01)

Stored rather than generated on demand: a summary that changes wording every
time a report is opened is not something anyone can cite, and re-running the
model on every read would spend the free tier on nothing.

`ai_summary_generated_at` exists so a stale summary can be told from one
written against the incident's final state -- evidence and contact counts
arrive seconds after the incident row does.
"""

from alembic import op
import sqlalchemy as sa

revision = "0010_incident_ai_summary"
down_revision = "0009_incident_shares"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("incidents") as batch:
        batch.add_column(sa.Column("ai_summary", sa.Text(), nullable=True))
        batch.add_column(sa.Column("ai_summary_generated_at", sa.DateTime(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("incidents") as batch:
        batch.drop_column("ai_summary_generated_at")
        batch.drop_column("ai_summary")
