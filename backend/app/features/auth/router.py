"""Auth endpoints — register, login, refresh, logout.

Rate limiting:
  - /login: 5 attempts per minute per IP
  - /register: 3 attempts per minute per IP

Auth router stays custom (does not use CRUDRouter) because auth flows
are unique and do not follow standard CRUD patterns.
"""

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.rate_limit import limiter
from app.core.security import CurrentUser, get_current_user
from app.features.auth.schemas import (
    ChangePasswordRequest,
    ForgotPasswordRequest,
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    ResetPasswordRequest,
    TokenResponse,
)
from app.features.auth.service import AuthService

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit("3/minute")
async def register_endpoint(
    request: Request,
    data: RegisterRequest,
    db: AsyncSession = Depends(get_db),
) -> TokenResponse:
    """Register a new company + admin user. Returns token pair."""
    try:
        svc = AuthService(db)
        result = await svc.register(
            email=data.email,
            password=data.password,
            company_name=data.company_name,
            first_name=data.first_name,
            last_name=data.last_name,
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(e),
        ) from e

    return TokenResponse(**result)


@router.post("/login", response_model=TokenResponse)
@limiter.limit("5/minute")
async def login_endpoint(
    request: Request,
    data: LoginRequest,
    db: AsyncSession = Depends(get_db),
) -> TokenResponse:
    """Authenticate with email + password. Returns token pair."""
    try:
        svc = AuthService(db)
        result = await svc.login(email=data.email, password=data.password)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e),
        ) from e

    return TokenResponse(**result)


@router.post("/refresh", response_model=TokenResponse)
@limiter.limit("10/minute")
async def refresh_endpoint(
    request: Request,
    data: RefreshRequest,
    db: AsyncSession = Depends(get_db),
) -> TokenResponse:
    """Exchange a refresh token for a new token pair (rotation)."""
    try:
        svc = AuthService(db)
        result = await svc.refresh_tokens(refresh_token_str=data.refresh_token)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e),
        ) from e

    return TokenResponse(**result)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("10/minute")
async def logout_endpoint(
    request: Request,
    data: RefreshRequest,
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> None:
    """Revoke the refresh token family. Requires valid access token."""
    svc = AuthService(db)
    await svc.logout(refresh_token_str=data.refresh_token)


@router.post("/change-password", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("5/minute")
async def change_password_endpoint(
    request: Request,
    data: ChangePasswordRequest,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> None:
    """Change the signed-in user's password (verifies the current password)."""
    svc = AuthService(db)
    try:
        await svc.change_password(
            user_id=current_user.user_id,
            current_password=data.current_password,
            new_password=data.new_password,
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        ) from e


@router.post("/forgot-password", status_code=status.HTTP_202_ACCEPTED)
@limiter.limit("3/minute")
async def forgot_password_endpoint(
    request: Request,
    data: ForgotPasswordRequest,
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    """Email a reset link if the address has an account.

    Always responds 202 with the same body so callers can't tell whether the
    email is registered (no account enumeration).
    """
    svc = AuthService(db)
    await svc.request_password_reset(email=data.email)
    return {"detail": "If an account exists for that email, a reset link has been sent."}


@router.post("/reset-password", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("5/minute")
async def reset_password_endpoint(
    request: Request,
    data: ResetPasswordRequest,
    db: AsyncSession = Depends(get_db),
) -> None:
    """Set a new password using a valid reset token."""
    svc = AuthService(db)
    try:
        await svc.reset_password(token=data.token, new_password=data.new_password)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        ) from e
