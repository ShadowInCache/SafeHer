from datetime import datetime, timedelta
import logging
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.config import Settings, get_settings
from fastapi_app.db import get_session
from fastapi_app.repositories import users as user_repo
from fastapi_app.schemas import (
    AccountDeletionResponse,
    EmailVerificationRequest,
    FirebaseTokenExchangeRequest,
    PasswordChangeRequest,
    PasswordResetConfirmRequest,
    PasswordResetRequest,
    RegistrationResult,
    ResendVerificationRequest,
    Token,
    TokenRefreshRequest,
    UserCreate,
    UserLogin,
    UserPublic,
)
from fastapi_app.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    get_current_user,
    get_password_hash,
    verify_password,
)
from fastapi_app.services.firebase_auth import verify_firebase_id_token
from fastapi_app.repositories import auth_security
from fastapi_app.services import email as email_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])


def _issue_tokens(user, settings: Settings) -> Token:
    return Token(
        access_token=create_access_token(
            subject=user.email,
            role=user.role,
            settings=settings,
            expires_delta=timedelta(minutes=settings.access_token_expire_minutes),
        ),
        refresh_token=create_refresh_token(
            subject=user.email, role=user.role, settings=settings
        ),
    )


async def _notify_lockout(*, user, settings: Settings) -> None:
    """Tell the account owner their account was locked (SRS FR-AUTH-07).

    Best-effort: a mail failure must not turn a lockout into a 500, because the
    lockout itself has already been recorded.
    """
    if not settings.email_configured:
        return
    try:
        await email_service.send_email(
            settings=settings,
            to=user.email,
            subject="SafeHer account temporarily locked",
            body=(
                f"There were {settings.max_failed_logins} failed sign-in attempts on "
                "your SafeHer account, so it has been locked for "
                f"{settings.login_lockout_minutes} minutes.\n\n"
                "If this was not you, change your password once the lock expires.\n"
            ),
        )
    except (email_service.EmailNotConfigured, email_service.EmailDeliveryError):
        logger.warning("Could not send lockout notice to %s", user.email)


async def _deliver_verification_code(
    session, *, user, settings: Settings
) -> tuple[bool, str | None]:
    """Issue an OTP and try to email it.

    Returns (sent, debug_code). `debug_code` is non-None only when SMTP is
    absent in development, so a developer can complete sign-up locally without
    standing up a mail server. It is never returned once SMTP is configured,
    and never outside development.
    """
    code = await auth_security.issue_verification_code(
        session, user=user, ttl_minutes=settings.email_otp_ttl_minutes
    )
    try:
        await email_service.send_verification_code(
            settings=settings, to=user.email, code=code
        )
        return True, None
    except email_service.EmailNotConfigured:
        if settings.environment == "development":
            logger.warning(
                "SMTP not configured; returning verification code in the response "
                "because ENVIRONMENT=development."
            )
            return False, code
        logger.error("Cannot send verification code to %s: SMTP not configured", user.email)
        return False, None
    except email_service.EmailDeliveryError:
        return False, None


@router.post("/register", response_model=RegistrationResult, status_code=status.HTTP_201_CREATED)
async def register(
    payload: UserCreate,
    settings: Settings = Depends(get_settings),
    session: AsyncSession = Depends(get_session),
):
    if await user_repo.exists(session, payload.email):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="User already exists")

    hashed = get_password_hash(payload.password)
    try:
        user = await user_repo.create(
            session,
            email=payload.email,
            password_hash=hashed,
            full_name=payload.full_name,
            role=payload.role,
            phone=payload.phone,
        )
    except IntegrityError:
        await session.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="User already exists")

    # SRS FR-AUTH-01: the account exists but stays unverified until the emailed
    # OTP is entered. When email cannot be delivered at all, verification is not
    # enforced, so the account is usable immediately rather than stranded.
    required = settings.email_verification_required
    user.is_verified = not required
    await session.commit()
    await session.refresh(user)

    sent, debug_code = (False, None)
    if required or settings.email_configured:
        sent, debug_code = await _deliver_verification_code(
            session, user=user, settings=settings
        )

    return RegistrationResult(
        user=UserPublic.model_validate(user),
        verification_required=required,
        verification_sent=sent,
        debug_code=debug_code,
    )


@router.post("/login", response_model=Token)
async def login(
    payload: UserLogin,
    settings: Settings = Depends(get_settings),
    session: AsyncSession = Depends(get_session),
):
    user = await user_repo.get_by_email(session, payload.email)

    # An unknown address and a wrong password produce the same 401 so the
    # endpoint cannot be used to enumerate which emails have accounts.
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Incorrect email or password"
        )

    # SRS FR-AUTH-07 -- checked before the password so a locked account cannot
    # be probed for the correct password during the lockout window.
    if auth_security.is_locked(user):
        retry_after = auth_security.lock_seconds_remaining(user)
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=(
                "Too many failed sign-in attempts. Try again in "
                f"{max(1, retry_after // 60)} minute(s)."
            ),
            headers={"Retry-After": str(retry_after)},
        )

    if not verify_password(payload.password, user.password_hash):
        just_locked = await auth_security.register_failed_login(
            session,
            user=user,
            max_attempts=settings.max_failed_logins,
            lockout_minutes=settings.login_lockout_minutes,
        )
        if just_locked:
            logger.warning("Account %s locked after repeated failed sign-ins", user.email)
            await _notify_lockout(user=user, settings=settings)
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=(
                    "Too many failed sign-in attempts. Try again in "
                    f"{settings.login_lockout_minutes} minutes."
                ),
                headers={"Retry-After": str(settings.login_lockout_minutes * 60)},
            )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Incorrect email or password"
        )

    # SRS FR-AUTH-08 -- signing in is the documented way to take an account back
    # out of the deletion queue, so it is restored rather than refused.
    if user.deletion_requested_at is not None:
        await auth_security.cancel_deletion(session, user=user)
        logger.info("Pending deletion cancelled for %s by successful sign-in", user.email)

    if not user.is_active:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Inactive user")

    # SRS FR-AUTH-01 -- enforced only where OTPs can actually be delivered.
    if settings.email_verification_required and not user.is_verified:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Email not verified. Check your inbox for the verification code.",
        )

    await auth_security.clear_failed_logins(session, user=user)
    return _issue_tokens(user, settings)


@router.post("/verify-email", response_model=Token)
async def verify_email(
    payload: EmailVerificationRequest,
    settings: Settings = Depends(get_settings),
    session: AsyncSession = Depends(get_session),
):
    """Consume an emailed OTP and return a session (SRS FR-AUTH-01)."""
    user = await user_repo.get_by_email(session, payload.email)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid or expired code"
        )

    if user.is_verified:
        return _issue_tokens(user, settings)

    ok, reason = await auth_security.verify_code(
        session,
        user=user,
        code=payload.code,
        max_attempts=settings.email_otp_max_attempts,
    )
    if not ok:
        detail = {
            "expired": "That code has expired. Request a new one.",
            "too_many_attempts": "Too many incorrect attempts. Request a new code.",
            "no_code": "No verification code is outstanding. Request a new one.",
        }.get(reason, "Invalid or expired code")
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=detail)

    return _issue_tokens(user, settings)


@router.post("/resend-verification", status_code=status.HTTP_202_ACCEPTED)
async def resend_verification(
    payload: ResendVerificationRequest,
    settings: Settings = Depends(get_settings),
    session: AsyncSession = Depends(get_session),
):
    """Re-issue an OTP.

    Always reports acceptance: telling an anonymous caller whether an address is
    registered would leak account existence.
    """
    user = await user_repo.get_by_email(session, payload.email)
    response = {"status": "accepted", "verification_sent": False, "debug_code": None}
    if user is None or user.is_verified:
        return response

    sent, debug_code = await _deliver_verification_code(session, user=user, settings=settings)
    response["verification_sent"] = sent
    response["debug_code"] = debug_code
    return response


@router.post("/change-password", response_model=Token)
async def change_password(
    payload: PasswordChangeRequest,
    settings: Settings = Depends(get_settings),
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    """Change the password and revoke all other sessions (SRS FR-AUTH-06).

    A fresh token pair is returned so the device that made the change stays
    signed in while every other device is logged out.
    """
    user = await user_repo.get_by_email(session, current_user.email)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    if not verify_password(payload.current_password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Current password is incorrect"
        )
    if payload.current_password == payload.new_password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="New password must differ from the current one",
        )

    await auth_security.set_password(session, user=user, new_password=payload.new_password)
    logger.info("Password changed for %s; all other sessions revoked", user.email)
    return _issue_tokens(user, settings)


@router.delete("/account", response_model=AccountDeletionResponse)
async def request_account_deletion(
    settings: Settings = Depends(get_settings),
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    """Schedule deletion after a grace period (SRS FR-AUTH-08, GDPR Art. 17).

    Data is not destroyed here. The account is deactivated and its sessions
    revoked; signing in during the grace period restores it.
    """
    user = await user_repo.get_by_email(session, current_user.email)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    requested_at = await auth_security.request_deletion(session, user=user)
    grace = settings.account_deletion_grace_days
    logger.info("Deletion scheduled for %s in %s days", user.email, grace)
    return AccountDeletionResponse(
        deletion_requested_at=requested_at,
        purge_scheduled_for=requested_at + timedelta(days=grace),
        grace_period_days=grace,
    )


@router.post("/firebase/exchange", response_model=Token)
async def firebase_exchange(
    payload: FirebaseTokenExchangeRequest,
    settings: Settings = Depends(get_settings),
    session: AsyncSession = Depends(get_session),
):
    identity = verify_firebase_id_token(
        id_token=payload.id_token,
        project_id=settings.firebase_project_id,
    )

    user = await user_repo.get_by_email(session, identity.email)
    if not user:
        random_password = f"firebase-{identity.uid}-{uuid4()}"
        try:
            user = await user_repo.create(
                session,
                email=identity.email,
                password_hash=get_password_hash(random_password),
                full_name=payload.full_name or identity.name,
                # Server-assigned, never taken from the request. Elevating an
                # account is an operator action, not a sign-up option.
                role="user",
                phone=payload.phone,
            )
            # Google has already confirmed this address, which is exactly what
            # `is_verified` records. Leaving it False provisioned an account
            # that could sign in with Google forever but was rejected by
            # `/auth/login` with "check your inbox" -- for a code that is
            # never sent, because this user never registered by email.
            if identity.email_verified and not user.is_verified:
                user.is_verified = True
                session.add(user)
                await session.commit()
                await session.refresh(user)
            if payload.avatar_url:
                user.avatar_url = payload.avatar_url
                session.add(user)
                await session.commit()
                await session.refresh(user)
        except IntegrityError:
            await session.rollback()
            user = await user_repo.get_by_email(session, identity.email)
            if not user:
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="Unable to provision user from Firebase identity",
                )
    else:
        updated = False
        if not user.full_name and (payload.full_name or identity.name):
            user.full_name = payload.full_name or identity.name
            updated = True
        # Backfill only — a value the user has since edited in their profile
        # must not be overwritten by whatever the identity provider holds.
        if not user.phone and payload.phone:
            user.phone = payload.phone
            updated = True
        if not user.avatar_url and payload.avatar_url:
            user.avatar_url = payload.avatar_url
            updated = True
        # Repairs accounts provisioned before the line above existed, on
        # their next Google sign-in, without anyone having to notice.
        if identity.email_verified and not user.is_verified:
            user.is_verified = True
            updated = True
        if not user.is_active:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Inactive user")
        if updated:
            session.add(user)
            await session.commit()
            await session.refresh(user)

    access_token = create_access_token(
        subject=user.email,
        role=user.role,
        settings=settings,
        expires_delta=timedelta(minutes=settings.access_token_expire_minutes),
    )
    refresh_token = create_refresh_token(subject=user.email, role=user.role, settings=settings)
    return Token(access_token=access_token, refresh_token=refresh_token)


@router.get("/me", response_model=UserPublic)
async def me(current_user: UserPublic = Depends(get_current_user)):
    return current_user


@router.post("/refresh", response_model=Token)
async def refresh(payload: TokenRefreshRequest, settings: Settings = Depends(get_settings)):
    token_payload = decode_token(payload.refresh_token, settings, expected_type="refresh")
    access_token = create_access_token(
        subject=token_payload.sub,
        role=token_payload.role,
        settings=settings,
        expires_delta=timedelta(minutes=settings.access_token_expire_minutes),
    )
    refresh_token = create_refresh_token(subject=token_payload.sub, role=token_payload.role, settings=settings)
    return Token(access_token=access_token, refresh_token=refresh_token)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(_: UserPublic = Depends(get_current_user)):
    # Stateless JWT flow: logout is handled client-side by deleting tokens.
    return None


@router.post("/password-reset/request", status_code=status.HTTP_202_ACCEPTED)
async def request_password_reset(
    payload: PasswordResetRequest,
    settings: Settings = Depends(get_settings),
    session: AsyncSession = Depends(get_session),
):
    """Email a reset code.

    Always reports acceptance so the endpoint cannot be used to discover which
    addresses have accounts.
    """
    user = await user_repo.get_by_email(session, payload.email)
    response = {"status": "accepted", "code_sent": False, "debug_code": None}
    if user is None:
        return response

    code = await auth_security.issue_verification_code(
        session,
        user=user,
        ttl_minutes=settings.email_otp_ttl_minutes,
        purpose=auth_security.PURPOSE_RESET_PASSWORD,
    )
    try:
        await email_service.send_email(
            settings=settings,
            to=user.email,
            subject="Reset your SafeHer password",
            body=(
                f"Your SafeHer password reset code is {code}\n\n"
                f"It expires in {settings.email_otp_ttl_minutes} minutes. If you did "
                "not request a reset, you can ignore this email and your password "
                "will stay unchanged.\n"
            ),
        )
        response["code_sent"] = True
    except email_service.EmailNotConfigured:
        if settings.environment == "development":
            response["debug_code"] = code
        else:
            logger.error("Cannot send reset code to %s: SMTP not configured", user.email)
    except email_service.EmailDeliveryError:
        logger.warning("Reset code delivery to %s failed", user.email)

    return response


@router.post("/password-reset/confirm", response_model=Token)
async def confirm_password_reset(
    payload: PasswordResetConfirmRequest,
    settings: Settings = Depends(get_settings),
    session: AsyncSession = Depends(get_session),
):
    """Redeem a reset code and set a new password.

    Succeeding here also revokes every existing session, on the assumption that
    a forgotten password may mean a compromised one.
    """
    user = await user_repo.get_by_email(session, payload.email)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid or expired code"
        )

    ok, reason = await auth_security.verify_code(
        session,
        user=user,
        code=payload.code,
        max_attempts=settings.email_otp_max_attempts,
        purpose=auth_security.PURPOSE_RESET_PASSWORD,
    )
    if not ok:
        detail = {
            "expired": "That code has expired. Request a new one.",
            "too_many_attempts": "Too many incorrect attempts. Request a new code.",
            "no_code": "No reset code is outstanding. Request a new one.",
        }.get(reason, "Invalid or expired code")
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=detail)

    await auth_security.set_password(session, user=user, new_password=payload.new_password)

    # A completed reset proves control of the mailbox, which is the same thing
    # verification checks -- so an unverified account becomes verified here.
    if not user.is_verified:
        user.is_verified = True
        await session.commit()
        await session.refresh(user)

    logger.info("Password reset completed for %s; all sessions revoked", user.email)
    return _issue_tokens(user, settings)
