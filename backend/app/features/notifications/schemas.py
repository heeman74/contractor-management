"""Pydantic schemas for the notifications feature.

TokenRegisterRequest: validates the FCM token and platform submitted by
mobile clients when registering for push notifications.
"""

from typing import Literal

from pydantic import BaseModel


class TokenRegisterRequest(BaseModel):
    """Request body for POST /api/v1/notifications/token.

    Attributes:
        token:    FCM registration token string (from FirebaseMessaging.instance.getToken()).
        platform: 'android' or 'ios' — used to select correct FCM message format.
    """

    token: str
    platform: Literal["android", "ios"]
