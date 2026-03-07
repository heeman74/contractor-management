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
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
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
async def refresh_endpoint(
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
async def logout_endpoint(
    data: RefreshRequest,
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> None:
    """Revoke the refresh token family. Requires valid access token."""
    svc = AuthService(db)
    await svc.logout(refresh_token_str=data.refresh_token)
