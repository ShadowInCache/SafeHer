from datetime import timedelta
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.config import Settings, get_settings
from fastapi_app.db import get_session
from fastapi_app.repositories import users as user_repo
from fastapi_app.schemas import (
    FirebaseTokenExchangeRequest,
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

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])


@router.post("/register", response_model=UserPublic, status_code=status.HTTP_201_CREATED)
async def register(payload: UserCreate, session: AsyncSession = Depends(get_session)):
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
        )
    except IntegrityError:
        await session.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="User already exists")

    return UserPublic.model_validate(user)


@router.post("/login", response_model=Token)
async def login(payload: UserLogin, settings: Settings = Depends(get_settings), session: AsyncSession = Depends(get_session)):
    user = await user_repo.get_by_email(session, payload.email)
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Incorrect email or password")
    if not user.is_active:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Inactive user")

    access_token = create_access_token(
        subject=user.email,
        role=user.role,
        settings=settings,
        expires_delta=timedelta(minutes=settings.access_token_expire_minutes),
    )
    refresh_token = create_refresh_token(subject=user.email, role=user.role, settings=settings)
    return Token(access_token=access_token, refresh_token=refresh_token)


@router.post("/firebase/exchange", response_model=Token)
async def firebase_exchange(
    payload: FirebaseTokenExchangeRequest,
    settings: Settings = Depends(get_settings),
    session: AsyncSession = Depends(get_session),
):
    requested_role = (payload.role or "user").lower()
    if requested_role not in {"user", "guardian"}:
        requested_role = "user"

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
                role=requested_role,
            )
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
