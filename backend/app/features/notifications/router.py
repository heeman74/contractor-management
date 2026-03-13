"""Notifications router — FCM device token registration endpoint.

Endpoints:
  POST /api/v1/notifications/token  — register or refresh FCM device token (204)

All endpoints require authentication via Depends(get_current_user).
Router is registered in main.py with prefix="/api/v1/notifications".
"""

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user
from app.features.notifications.schemas import TokenRegisterRequest
from app.features.notifications.service import NotificationService

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.post("/token", status_code=status.HTTP_204_NO_CONTENT)
async def register_device_token(
    data: TokenRegisterRequest,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> None:
    """Register or refresh an FCM device token for the authenticated user.

    Upserts the (user_id, token) pair — if the token already exists for this
    user, last_used_at is updated. If it is new, a new record is created.

    Returns 204 No Content on success.
    """
    svc = NotificationService(db)
    await svc.upsert_token(
        user_id=current_user.user_id,
        token=data.token,
        platform=data.platform,
    )
