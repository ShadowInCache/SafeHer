"""Contract tests for SRS §4.1 authentication requirements.

Covers FR-AUTH-01 (emailed OTP verification), FR-AUTH-04 (token lifetimes),
FR-AUTH-06 (session invalidation on password change), FR-AUTH-07 (failed-login
lockout) and FR-AUTH-08 (deletion with a grace period).

These run in-process against the ASGI app, so no live server is needed.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import os
import unittest
from unittest.mock import patch
from uuid import uuid4

os.environ["DATABASE_URL"] = "sqlite:///./test_safeher.db"
os.environ["ENABLE_MQTT_WORKER"] = "false"
os.environ["JWT_SECRET_KEY"] = "test-secret-key-change-me"
os.environ["LOG_LEVEL"] = "WARNING"

import httpx
from sqlalchemy import select

from fastapi_app.config import get_settings
from fastapi_app.db import SessionLocal, init_db
from fastapi_app.main import app
from fastapi_app.models import User
from fastapi_app.repositories import auth_security
from fastapi_app.security import decode_token
from fastapi_app.workers.deletion_purge import purge_expired_accounts

PASSWORD = "TestPass123!"


class AuthTestBase(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        await init_db()
        self.settings = get_settings()
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://testserver",
        )

    async def asyncTearDown(self):
        await self.client.aclose()

    @staticmethod
    def _email() -> str:
        return f"auth-{uuid4().hex[:12]}@example.com"

    async def _register(self, email: str, password: str = PASSWORD) -> dict:
        response = await self.client.post(
            "/api/v1/auth/register",
            json={"email": email, "password": password, "full_name": "Test User"},
        )
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()

    async def _login(self, email: str, password: str = PASSWORD) -> httpx.Response:
        return await self.client.post(
            "/api/v1/auth/login", json={"email": email, "password": password}
        )

    async def _fetch_user(self, email: str) -> User:
        async with SessionLocal() as session:
            result = await session.execute(select(User).where(User.email == email))
            user = result.scalars().first()
            self.assertIsNotNone(user, f"user {email} not found")
            return user


class TestTokenLifetimes(AuthTestBase):
    """FR-AUTH-04: 15-minute access token, 30-day refresh token."""

    async def test_access_token_expires_in_fifteen_minutes(self):
        email = self._email()
        await self._register(email)
        tokens = (await self._login(email)).json()

        payload = decode_token(tokens["access_token"], self.settings, expected_type="access")
        lifetime = datetime.fromtimestamp(payload.exp, tz=timezone.utc) - datetime.now(
            timezone.utc
        )
        self.assertAlmostEqual(lifetime.total_seconds(), 15 * 60, delta=60)

    async def test_refresh_token_expires_in_thirty_days(self):
        email = self._email()
        await self._register(email)
        tokens = (await self._login(email)).json()

        payload = decode_token(tokens["refresh_token"], self.settings, expected_type="refresh")
        lifetime = datetime.fromtimestamp(payload.exp, tz=timezone.utc) - datetime.now(
            timezone.utc
        )
        self.assertAlmostEqual(lifetime.total_seconds(), 30 * 86400, delta=120)


class TestLoginLockout(AuthTestBase):
    """FR-AUTH-07: 5 failed logins trigger a 15-minute lockout."""

    async def test_fifth_failure_locks_the_account(self):
        email = self._email()
        await self._register(email)

        statuses = []
        for _ in range(self.settings.max_failed_logins):
            statuses.append((await self._login(email, "WrongPassword!")).status_code)

        self.assertEqual(statuses[:-1], [401] * (self.settings.max_failed_logins - 1))
        self.assertEqual(statuses[-1], 429, "5th failure should lock the account")

    async def test_correct_password_is_refused_while_locked(self):
        email = self._email()
        await self._register(email)
        for _ in range(self.settings.max_failed_logins):
            await self._login(email, "WrongPassword!")

        response = await self._login(email)
        self.assertEqual(response.status_code, 429)
        self.assertIn("Retry-After", response.headers)
        self.assertGreater(int(response.headers["Retry-After"]), 0)

    async def test_lockout_expiry_restores_access(self):
        email = self._email()
        await self._register(email)
        for _ in range(self.settings.max_failed_logins):
            await self._login(email, "WrongPassword!")

        # Rather than sleeping 15 minutes, move the stored expiry into the past.
        async with SessionLocal() as session:
            result = await session.execute(select(User).where(User.email == email))
            user = result.scalars().first()
            user.locked_until = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(
                seconds=1
            )
            await session.commit()

        self.assertEqual((await self._login(email)).status_code, 200)

    async def test_successful_login_resets_the_failure_counter(self):
        email = self._email()
        await self._register(email)
        for _ in range(self.settings.max_failed_logins - 1):
            await self._login(email, "WrongPassword!")

        self.assertEqual((await self._login(email)).status_code, 200)

        user = await self._fetch_user(email)
        self.assertEqual(user.failed_login_attempts, 0)

    async def test_unknown_email_is_indistinguishable_from_wrong_password(self):
        email = self._email()
        await self._register(email)

        unknown = await self._login(f"missing-{uuid4().hex[:8]}@example.com")
        wrong = await self._login(email, "WrongPassword!")

        self.assertEqual(unknown.status_code, 401)
        self.assertEqual(wrong.status_code, 401)
        self.assertEqual(unknown.json()["detail"], wrong.json()["detail"])


class TestPasswordChangeRevocation(AuthTestBase):
    """FR-AUTH-06: changing the password revokes sessions everywhere."""

    async def _authed_headers(self, email: str) -> tuple[dict, str]:
        tokens = (await self._login(email)).json()
        return {"Authorization": f"Bearer {tokens['access_token']}"}, tokens["access_token"]

    async def test_other_sessions_are_revoked(self):
        email = self._email()
        await self._register(email)
        headers, old_token = await self._authed_headers(email)

        # A second device, signed in independently before the change.
        other = (await self._login(email)).json()["access_token"]
        other_headers = {"Authorization": f"Bearer {other}"}

        self.assertEqual((await self.client.get("/api/v1/auth/me", headers=other_headers)).status_code, 200)

        # Push the cutoff past the existing tokens' `iat`, which has one-second
        # resolution; without this the change lands inside the same second.
        async with SessionLocal() as session:
            result = await session.execute(select(User).where(User.email == email))
            user = result.scalars().first()
            await auth_security.set_password(session, user=user, new_password="AnotherPass456!")
            user.tokens_valid_from = user.tokens_valid_from + timedelta(seconds=2)
            await session.commit()

        self.assertEqual(
            (await self.client.get("/api/v1/auth/me", headers=other_headers)).status_code,
            401,
            "a session issued before the password change must stop working",
        )
        self.assertEqual(
            (await self.client.get("/api/v1/auth/me", headers=headers)).status_code, 401
        )

    async def test_change_password_returns_a_working_session(self):
        email = self._email()
        await self._register(email)
        headers, _ = await self._authed_headers(email)

        response = await self.client.post(
            "/api/v1/auth/change-password",
            json={"current_password": PASSWORD, "new_password": "AnotherPass456!"},
            headers=headers,
        )
        self.assertEqual(response.status_code, 200, response.text)
        fresh = {"Authorization": f"Bearer {response.json()['access_token']}"}
        self.assertEqual((await self.client.get("/api/v1/auth/me", headers=fresh)).status_code, 200)

    async def test_wrong_current_password_is_rejected(self):
        email = self._email()
        await self._register(email)
        headers, _ = await self._authed_headers(email)

        response = await self.client.post(
            "/api/v1/auth/change-password",
            json={"current_password": "NotMyPassword!", "new_password": "AnotherPass456!"},
            headers=headers,
        )
        self.assertEqual(response.status_code, 400)

    async def test_new_password_must_differ(self):
        email = self._email()
        await self._register(email)
        headers, _ = await self._authed_headers(email)

        response = await self.client.post(
            "/api/v1/auth/change-password",
            json={"current_password": PASSWORD, "new_password": PASSWORD},
            headers=headers,
        )
        self.assertEqual(response.status_code, 400)


class TestAccountDeletion(AuthTestBase):
    """FR-AUTH-08: deletion is deferred by a 30-day grace period."""

    async def test_deletion_is_scheduled_not_immediate(self):
        email = self._email()
        await self._register(email)
        tokens = (await self._login(email)).json()
        headers = {"Authorization": f"Bearer {tokens['access_token']}"}

        response = await self.client.request("DELETE", "/api/v1/auth/account", headers=headers)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["grace_period_days"], 30)

        # The row must still exist -- the account is deactivated, not erased.
        user = await self._fetch_user(email)
        self.assertIsNotNone(user.deletion_requested_at)
        self.assertFalse(user.is_active)

    async def test_signing_in_during_grace_restores_the_account(self):
        email = self._email()
        await self._register(email)
        tokens = (await self._login(email)).json()
        headers = {"Authorization": f"Bearer {tokens['access_token']}"}
        await self.client.request("DELETE", "/api/v1/auth/account", headers=headers)

        response = await self._login(email)
        self.assertEqual(response.status_code, 200, "sign-in must cancel a pending deletion")

        user = await self._fetch_user(email)
        self.assertIsNone(user.deletion_requested_at)
        self.assertTrue(user.is_active)

    async def test_purge_leaves_accounts_inside_the_grace_period_alone(self):
        email = self._email()
        await self._register(email)
        tokens = (await self._login(email)).json()
        headers = {"Authorization": f"Bearer {tokens['access_token']}"}
        await self.client.request("DELETE", "/api/v1/auth/account", headers=headers)

        await purge_expired_accounts()

        user = await self._fetch_user(email)
        self.assertIsNotNone(user, "an account still in its grace period must survive the purge")

    async def test_purge_erases_accounts_past_the_grace_period(self):
        email = self._email()
        await self._register(email)
        tokens = (await self._login(email)).json()
        headers = {"Authorization": f"Bearer {tokens['access_token']}"}
        await self.client.request("DELETE", "/api/v1/auth/account", headers=headers)

        # Backdate the request past the grace window instead of waiting 30 days.
        async with SessionLocal() as session:
            result = await session.execute(select(User).where(User.email == email))
            user = result.scalars().first()
            user.deletion_requested_at = datetime.now(timezone.utc).replace(
                tzinfo=None
            ) - timedelta(days=self.settings.account_deletion_grace_days + 1)
            await session.commit()

        purged = await purge_expired_accounts()
        self.assertGreaterEqual(purged, 1)

        async with SessionLocal() as session:
            result = await session.execute(select(User).where(User.email == email))
            self.assertIsNone(result.scalars().first(), "account should be erased after grace")


class TestEmailVerification(AuthTestBase):
    """FR-AUTH-01: account inactive until the emailed OTP is confirmed."""

    async def test_verification_is_not_enforced_without_smtp(self):
        """Sign-up must not be bricked by an unconfigured mail server."""
        email = self._email()
        body = await self._register(email)

        self.assertFalse(body["verification_required"])
        self.assertEqual((await self._login(email)).status_code, 200)

    async def test_otp_gates_login_when_verification_is_required(self):
        email = self._email()

        with patch.object(type(self.settings), "email_verification_required", property(lambda _: True)):
            body = await self._register(email)
            self.assertTrue(body["verification_required"])
            self.assertFalse(body["user"]["is_verified"])

            # No SMTP in tests, so the code comes back on the development path.
            code = body["debug_code"]
            self.assertIsNotNone(code, "development sign-up must surface a usable code")

            blocked = await self._login(email)
            self.assertEqual(blocked.status_code, 403, "unverified login must be refused")

            wrong = await self.client.post(
                "/api/v1/auth/verify-email", json={"email": email, "code": "000000"}
            )
            self.assertEqual(wrong.status_code, 400)

            ok = await self.client.post(
                "/api/v1/auth/verify-email", json={"email": email, "code": code}
            )
            self.assertEqual(ok.status_code, 200, ok.text)
            self.assertIn("access_token", ok.json())

            self.assertEqual((await self._login(email)).status_code, 200)

    async def test_code_is_stored_hashed(self):
        email = self._email()
        with patch.object(type(self.settings), "email_verification_required", property(lambda _: True)):
            body = await self._register(email)
        code = body["debug_code"]

        async with SessionLocal() as session:
            from fastapi_app.models import EmailVerificationCode

            result = await session.execute(
                select(EmailVerificationCode).where(
                    EmailVerificationCode.user_id == body["user"]["id"]
                )
            )
            record = result.scalars().first()
            self.assertIsNotNone(record)
            self.assertNotIn(code, record.code_hash, "the raw OTP must never be stored")

    async def test_code_is_single_use(self):
        email = self._email()
        with patch.object(type(self.settings), "email_verification_required", property(lambda _: True)):
            body = await self._register(email)
            code = body["debug_code"]

            first = await self.client.post(
                "/api/v1/auth/verify-email", json={"email": email, "code": code}
            )
            self.assertEqual(first.status_code, 200)

        user = await self._fetch_user(email)
        self.assertTrue(user.is_verified)

    async def test_expired_code_is_refused(self):
        email = self._email()
        with patch.object(type(self.settings), "email_verification_required", property(lambda _: True)):
            body = await self._register(email)
            code = body["debug_code"]

            async with SessionLocal() as session:
                from fastapi_app.models import EmailVerificationCode

                result = await session.execute(
                    select(EmailVerificationCode).where(
                        EmailVerificationCode.user_id == body["user"]["id"]
                    )
                )
                record = result.scalars().first()
                record.expires_at = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(
                    minutes=1
                )
                await session.commit()

            response = await self.client.post(
                "/api/v1/auth/verify-email", json={"email": email, "code": code}
            )
            self.assertEqual(response.status_code, 400)
            self.assertIn("expired", response.json()["detail"].lower())

    async def test_brute_force_burns_the_code(self):
        email = self._email()
        with patch.object(type(self.settings), "email_verification_required", property(lambda _: True)):
            body = await self._register(email)
            code = body["debug_code"]

            for _ in range(self.settings.email_otp_max_attempts):
                await self.client.post(
                    "/api/v1/auth/verify-email", json={"email": email, "code": "111111"}
                )

            response = await self.client.post(
                "/api/v1/auth/verify-email", json={"email": email, "code": code}
            )
            self.assertEqual(
                response.status_code, 400, "the correct code must not work after the attempt budget"
            )

    async def test_resend_does_not_leak_account_existence(self):
        known = self._email()
        await self._register(known)

        for target in (known, f"ghost-{uuid4().hex[:8]}@example.com"):
            response = await self.client.post(
                "/api/v1/auth/resend-verification", json={"email": target}
            )
            self.assertEqual(response.status_code, 202)


class TestPasswordReset(AuthTestBase):
    """Forgot-password via emailed OTP, backing the app's reset screen."""

    async def _request_reset(self, email: str) -> dict:
        response = await self.client.post(
            "/api/v1/auth/password-reset/request", json={"email": email}
        )
        self.assertEqual(response.status_code, 202, response.text)
        return response.json()

    async def test_reset_sets_a_working_password(self):
        email = self._email()
        await self._register(email)

        code = (await self._request_reset(email))["debug_code"]
        self.assertIsNotNone(code)

        response = await self.client.post(
            "/api/v1/auth/password-reset/confirm",
            json={"email": email, "code": code, "new_password": "ResetPass789!"},
        )
        self.assertEqual(response.status_code, 200, response.text)

        self.assertEqual((await self._login(email, "ResetPass789!")).status_code, 200)
        self.assertEqual((await self._login(email, PASSWORD)).status_code, 401)

    async def test_reset_does_not_leak_account_existence(self):
        response = await self.client.post(
            "/api/v1/auth/password-reset/request",
            json={"email": f"ghost-{uuid4().hex[:8]}@example.com"},
        )
        self.assertEqual(response.status_code, 202)

    async def test_verification_code_cannot_reset_a_password(self):
        """Purpose separation: an email-verification OTP is not a reset token."""
        email = self._email()
        with patch.object(
            type(self.settings), "email_verification_required", property(lambda _: True)
        ):
            body = await self._register(email)
        verification_code = body["debug_code"]
        self.assertIsNotNone(verification_code)

        response = await self.client.post(
            "/api/v1/auth/password-reset/confirm",
            json={
                "email": email,
                "code": verification_code,
                "new_password": "HijackedPass1!",
            },
        )
        self.assertEqual(
            response.status_code, 400, "a verification code must not be redeemable as a reset code"
        )
        self.assertEqual((await self._login(email, "HijackedPass1!")).status_code, 401)

    async def test_reset_code_cannot_verify_an_email(self):
        email = self._email()
        with patch.object(
            type(self.settings), "email_verification_required", property(lambda _: True)
        ):
            await self._register(email)
            reset_code = (await self._request_reset(email))["debug_code"]

            response = await self.client.post(
                "/api/v1/auth/verify-email", json={"email": email, "code": reset_code}
            )
            self.assertEqual(response.status_code, 400)

    async def test_reset_revokes_existing_sessions(self):
        email = self._email()
        await self._register(email)
        old = (await self._login(email)).json()["access_token"]
        headers = {"Authorization": f"Bearer {old}"}
        self.assertEqual((await self.client.get("/api/v1/auth/me", headers=headers)).status_code, 200)

        code = (await self._request_reset(email))["debug_code"]
        await self.client.post(
            "/api/v1/auth/password-reset/confirm",
            json={"email": email, "code": code, "new_password": "ResetPass789!"},
        )
        # Match the one-second `iat` resolution, as in the change-password test.
        async with SessionLocal() as session:
            result = await session.execute(select(User).where(User.email == email))
            user = result.scalars().first()
            user.tokens_valid_from = user.tokens_valid_from + timedelta(seconds=2)
            await session.commit()

        self.assertEqual(
            (await self.client.get("/api/v1/auth/me", headers=headers)).status_code, 401
        )


if __name__ == "__main__":
    unittest.main()
