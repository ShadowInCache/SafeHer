"""What the models saw, recorded on the incident (SRS §6.1, FR-EMG-02)

An automatic SOS is raised by three models -- XGBoost over the glove's motion,
CNN+LSTM over the glasses' audio, YOLOv8 over its video. Until now the
incident recorded only that the system had raised it (`auto_dispatched`), not
what any model actually observed.

That gap matters twice over. A woman reading her own report deserves to know
*why* SafeHer decided she was in danger -- "a raised voice and a knife in
frame" is an account she can act on, "threat score 0.83" is not. And an
incident report offered as forensic evidence has to say what produced the
conclusion; a number with no provenance is not evidence of anything.

`detections` is free text rather than a relation because its shape belongs to
the models, which are not trained yet. Committing to columns for "weapon
class" and "trigger words" before a model emits either would be guessing at a
schema, and a wrong guess here is a migration in the middle of a live
deployment.
"""

from alembic import op
import sqlalchemy as sa

revision = "0012_detection_evidence"
down_revision = "0011_auto_sos_threshold"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("incidents") as batch:
        # Per-modality, nullable: a sensor that did not report is not the same
        # as one that reported calm, and the report must be able to say which.
        batch.add_column(sa.Column("motion_score", sa.Float(), nullable=True))
        batch.add_column(sa.Column("audio_score", sa.Float(), nullable=True))
        batch.add_column(sa.Column("vision_score", sa.Float(), nullable=True))
        batch.add_column(sa.Column("weapon_confidence", sa.Float(), nullable=True))
        # The value actually compared against the threshold, after fusion,
        # smoothing and context boosters -- not the raw arithmetic mean.
        batch.add_column(sa.Column("fused_score", sa.Float(), nullable=True))
        batch.add_column(sa.Column("threshold_used", sa.Float(), nullable=True))
        batch.add_column(sa.Column("detections", sa.Text(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("incidents") as batch:
        for column in (
            "detections",
            "threshold_used",
            "fused_score",
            "weapon_confidence",
            "vision_score",
            "audio_score",
            "motion_score",
        ):
            batch.drop_column(column)
