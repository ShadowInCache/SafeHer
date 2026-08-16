"""emergency contact verification (SRS FR-EMG-10)

Adds the storage for a per-contact confirmation code, so a contact is only
marked verified once someone at that address has proved they received it.

Backfill notes:
  * `verified_at` is left NULL for existing rows. Unlike the account-level
    `is_verified` backfill in 0007, marking these verified would be a claim
    nobody ever checked — and the whole point of this column is to tell a
    user which of her contacts might be a typo. An unverified contact is
    still notified; it is flagged, not disabled.
  * Only the hash of a code is stored, matching `email_verification_codes`:
    a leaked database must not yield working codes.
"""

from alembic import op
import sqlalchemy as sa

revision = "0008_contact_verification"
down_revision = "0007_auth_hardening"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("emergency_contacts") as batch:
        batch.add_column(sa.Column("verified_at", sa.DateTime(), nullable=True))
        batch.add_column(sa.Column("verification_code_hash", sa.String(), nullable=True))
        batch.add_column(sa.Column("verification_expires_at", sa.DateTime(), nullable=True))
        batch.add_column(
            sa.Column(
                "verification_attempts",
                sa.Integer(),
                nullable=False,
                server_default="0",
            )
        )


def downgrade() -> None:
    with op.batch_alter_table("emergency_contacts") as batch:
        batch.drop_column("verification_attempts")
        batch.drop_column("verification_expires_at")
        batch.drop_column("verification_code_hash")
        batch.drop_column("verified_at")
