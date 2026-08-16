"""auth hardening: email verification, login lockout, token revocation, deletion grace

Implements the storage side of SRS FR-AUTH-01 (emailed OTP verification),
FR-AUTH-06 (session invalidation on password change), FR-AUTH-07 (failed-login
lockout) and FR-AUTH-08 (deletion with a 30-day grace period).

Backfill notes:
  * `is_verified` defaults to TRUE for rows that already exist. Accounts created
    before verification existed were usable, and retroactively locking real
    users out of their own safety app would be a regression, not a fix. New
    rows default to FALSE via the model.
  * `tokens_valid_from` is backfilled to the row's `created_at` so existing
    sessions stay valid; only a future password change revokes them.
"""

from alembic import op
import sqlalchemy as sa

revision = "0007_auth_hardening"
down_revision = "0006_safety_features"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("users") as batch_op:
        batch_op.add_column(
            sa.Column("is_verified", sa.Boolean(), nullable=False, server_default=sa.false())
        )
        batch_op.add_column(
            sa.Column(
                "failed_login_attempts",
                sa.Integer(),
                nullable=False,
                server_default="0",
            )
        )
        batch_op.add_column(sa.Column("locked_until", sa.DateTime(), nullable=True))
        batch_op.add_column(sa.Column("tokens_valid_from", sa.DateTime(), nullable=True))
        batch_op.add_column(sa.Column("deletion_requested_at", sa.DateTime(), nullable=True))

    # Existing accounts predate verification -- treat them as already verified.
    #
    # `is_verified = 1` is a SQLite-ism: SQLite stores booleans as integers
    # and compares them happily, Postgres does not and raises "operator does
    # not exist: boolean = integer". This migration therefore ran fine in
    # development and would have aborted the first production deploy midway
    # through, leaving the schema half-migrated. Written with real boolean
    # literals, which both databases accept.
    op.execute(sa.text("UPDATE users SET is_verified = true WHERE is_verified = false"))
    op.execute("UPDATE users SET tokens_valid_from = created_at WHERE tokens_valid_from IS NULL")

    with op.batch_alter_table("users") as batch_op:
        batch_op.alter_column("tokens_valid_from", existing_type=sa.DateTime(), nullable=False)

    op.create_table(
        "email_verification_codes",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("user_id", sa.String(), nullable=False),
        sa.Column("code_hash", sa.String(), nullable=False),
        sa.Column(
            "purpose", sa.String(), nullable=False, server_default="email_verification"
        ),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("consumed_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_email_verification_codes_user_id",
        "email_verification_codes",
        ["user_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_email_verification_codes_user_id", table_name="email_verification_codes")
    op.drop_table("email_verification_codes")
    with op.batch_alter_table("users") as batch_op:
        batch_op.drop_column("deletion_requested_at")
        batch_op.drop_column("tokens_valid_from")
        batch_op.drop_column("locked_until")
        batch_op.drop_column("failed_login_attempts")
        batch_op.drop_column("is_verified")
