"""Dispatch state on the incident (FR-EMG-01, FR-EMG-04)

`POST /alerts/emergency` used to fan the alert out to every emergency contact
*before* it answered. That read well -- the response could say exactly who had
been reached -- and it was the wrong shape for the one request in this product
that must never wait.

Each contact is tried on up to three channels, each channel up to three times,
and a channel whose port is blocked fails by timing out rather than refusing.
Two contacts against a blocked SMTP port took roughly two minutes of wall
clock, while the phone gave up at fifteen seconds and filed the alert in its
offline queue -- telling a woman who had full signal that her contacts would
be notified "when you have signal". FR-EMG-01 asks for dispatch within three
seconds; the endpoint could not answer within thirty.

So the fan-out moves to a background task and the response returns as soon as
the incident is durable. That means the outcome has to live somewhere the
client can come back for, which is what these columns are: the dispatch's
state machine, on the row it belongs to.

`contacts_reached` is JSON text rather than a relation on purpose -- it is a
snapshot of one dispatch attempt, not a fact about the contacts, and modelling
it as rows would invite it being read as the latter.
"""

from alembic import op
import sqlalchemy as sa

revision = "0013_dispatch_state"
down_revision = "0012_detection_evidence"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("incidents") as batch:
        # NULL means no dispatch was ever attempted for this incident, which
        # is a different fact from "attempted and reached nobody". Every
        # incident created outside POST /alerts/emergency stays NULL.
        batch.add_column(sa.Column("dispatch_status", sa.String(), nullable=True))
        # Known before the fan-out starts, so the client can render the right
        # number of pending contacts immediately rather than an empty list.
        batch.add_column(sa.Column("contacts_total", sa.Integer(), nullable=True))
        batch.add_column(sa.Column("contacts_notified", sa.Integer(), nullable=True))
        batch.add_column(sa.Column("contacts_reached", sa.Text(), nullable=True))
        batch.add_column(sa.Column("contacts_failed", sa.Text(), nullable=True))
        batch.add_column(sa.Column("dispatch_completed_at", sa.DateTime(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("incidents") as batch:
        for column in (
            "dispatch_completed_at",
            "contacts_failed",
            "contacts_reached",
            "contacts_notified",
            "contacts_total",
            "dispatch_status",
        ):
            batch.drop_column(column)
