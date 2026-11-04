"""Retraction of a false automatic alert (FR-EMG-02)

Auto-SOS dispatches the instant fused confidence crosses the threshold, with
no cancellable countdown in front of it. That is deliberate and recorded as a
decision: the situations auto-SOS exists for -- grabbed, pinned, unconscious,
phone in a bag -- are exactly the ones where she cannot reach the screen to
confirm anything, so a confirmation step would withhold the alert precisely
when it is needed and buy nothing in return.

The cost of that decision is that a false automatic alarm is unrecoverable.
It reaches her contacts before she has a chance to stop it, and until now
there was nothing she could do about it from inside the app: her sister had
been told she was in danger and no later action could tell her otherwise.

These columns are the way back. The correction travels the same route the
alarm did -- afterwards, to the same people, on the same channels -- which
keeps the alert itself as fast as it was while making a false one something
she can undo.

`retracted_at` is also what an in-flight fan-out checks between contacts, so
retracting during the first seconds stops the remaining alarm messages rather
than racing them. That is why it lives on the row and not in memory: the
fan-out runs in a background task holding its own session.

The retraction fan-out gets its own status rather than reusing
`dispatch_status`, because the interesting failure is the two disagreeing --
an alarm that reached three contacts and a correction that reached two.
"""

from alembic import op
import sqlalchemy as sa

revision = "0015_incident_retraction"
down_revision = "0014_terms_acceptance"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("incidents") as batch:
        # NULL is the normal state. Every incident that was a real emergency
        # keeps it, so this must never be read as "not yet retracted".
        batch.add_column(sa.Column("retracted_at", sa.DateTime(), nullable=True))
        batch.add_column(sa.Column("retraction_status", sa.String(), nullable=True))
        batch.add_column(
            sa.Column("retraction_contacts_notified", sa.Integer(), nullable=True)
        )


def downgrade() -> None:
    with op.batch_alter_table("incidents") as batch:
        for column in (
            "retraction_contacts_notified",
            "retraction_status",
            "retracted_at",
        ):
            batch.drop_column(column)
