"""Record which terms and privacy policy a user actually accepted

The registration screen showed "Terms of Service" and "Privacy Policy" as
tappable text whose handler raised a toast saying "coming soon". There was no
checkbox, nothing to accept, and nowhere to record an acceptance if there had
been — so the app collected a woman's location, her microphone, her camera and
her emergency contacts without ever asking, and could not have shown when or
to what she agreed if anyone asked.

Three columns rather than one boolean, because consent is only meaningful
against a *version*. "She agreed" is not an answer to "to what, and when" —
and when the policy changes, a stored `true` cannot tell you whether she saw
the clause that changed. Versions make re-consent possible; a boolean makes it
unanswerable.

All three are nullable, and NULL is load-bearing: it means this account was
created before consent was recorded. That is a different fact from refusing,
and the two must not look alike — the same absent-versus-zero rule the threat
signals follow. Existing accounts are not retroactively marked as having
agreed to something they were never shown.
"""

from alembic import op
import sqlalchemy as sa

revision = "0014_terms_acceptance"
down_revision = "0013_dispatch_state"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("users") as batch:
        # The version string the user accepted, e.g. "2026-10-06". Compared
        # against `Settings.current_terms_version` to decide whether re-consent
        # is needed after the document changes.
        batch.add_column(sa.Column("terms_version", sa.String(), nullable=True))
        batch.add_column(sa.Column("privacy_version", sa.String(), nullable=True))
        # When they accepted. Stored separately from `created_at` because an
        # account can outlive the consent on it: a later re-acceptance moves
        # this forward while the account's age stays what it was.
        batch.add_column(
            sa.Column("terms_accepted_at", sa.DateTime(), nullable=True)
        )


def downgrade() -> None:
    with op.batch_alter_table("users") as batch:
        batch.drop_column("terms_accepted_at")
        batch.drop_column("privacy_version")
        batch.drop_column("terms_version")
