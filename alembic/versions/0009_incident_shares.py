"""time-limited share links for incidents (SRS FR-RPT-06)

Lets an incident reach someone with no SafeHer account -- a police officer,
a lawyer, a parent -- without handing over the owner's credentials.

Only the token hash is stored, matching every other secret in this schema:
a leaked database must not yield working links to recordings of people in
danger.
"""

from alembic import op
import sqlalchemy as sa

revision = "0009_incident_shares"
down_revision = "0008_contact_verification"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "incident_shares",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column(
            "incident_id",
            sa.String(),
            sa.ForeignKey("incidents.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("token_hash", sa.String(), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("revoked_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_incident_shares_incident_id", "incident_shares", ["incident_id"])
    # Unique as well as indexed: the token hash is the lookup key for every
    # unauthenticated read, so a duplicate would be a link that resolves to
    # two different people's incidents.
    op.create_index(
        "ix_incident_shares_token_hash", "incident_shares", ["token_hash"], unique=True
    )


def downgrade() -> None:
    op.drop_index("ix_incident_shares_token_hash", table_name="incident_shares")
    op.drop_index("ix_incident_shares_incident_id", table_name="incident_shares")
    op.drop_table("incident_shares")
