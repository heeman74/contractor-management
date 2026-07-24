"""Request/response schemas for the role-permission editor."""

from __future__ import annotations

from pydantic import BaseModel, field_validator

from app.core.permissions import PERMISSION_KEYS


class PermissionCatalogItem(BaseModel):
    """One entry in the fixed permission catalog."""

    key: str
    label: str
    group: str


class RolePermissionsResponse(BaseModel):
    """The full per-company matrix plus the catalog and defaults for the editor."""

    catalog: list[PermissionCatalogItem]
    roles: dict[str, list[str]]
    defaults: dict[str, list[str]]


class RolePermissionsUpdate(BaseModel):
    """New permission-key list for a single role."""

    permissions: list[str]

    @field_validator("permissions")
    @classmethod
    def reject_unknown_keys(cls, value: list[str]) -> list[str]:
        """Reject keys outside the fixed catalog (wildcard is owner-only, not settable)."""
        unknown = sorted(set(value) - PERMISSION_KEYS)
        if unknown:
            raise ValueError(f"Unknown permission keys: {unknown}")
        return value


class ResetRequest(BaseModel):
    """Reset one role (by name) or all roles (null) to their defaults."""

    role: str | None = None


class MyPermissionsResponse(BaseModel):
    """The current user's effective permission keys (union across their roles)."""

    permissions: list[str]
