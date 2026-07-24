"""Unit tests for the RBAC capability helpers in app.core.security.

These verify the role-set gates (owner/admin/manager/gc) accept the right roles
and raise HTTP 403 otherwise. Pure unit tests — no DB, no ASGI client.
"""

import uuid

import pytest
from fastapi import HTTPException

from app.core.security import (
    CurrentUser,
    require_admin,
    require_gc,
    require_manager,
    require_owner,
)


def _user_with_roles(*roles: str) -> CurrentUser:
    """Build a CurrentUser holding the given roles with throwaway ids."""
    return CurrentUser(user_id=uuid.uuid4(), company_id=uuid.uuid4(), roles=list(roles))


def _assert_forbidden(guard, current_user: CurrentUser) -> None:
    """Assert the guard raises HTTP 403 for this user."""
    with pytest.raises(HTTPException) as exc_info:
        guard(current_user)
    assert exc_info.value.status_code == 403


@pytest.mark.parametrize("role", ["owner"])
def test_require_owner_allows_owner(role):
    require_owner(_user_with_roles(role))  # does not raise


@pytest.mark.parametrize("role", ["admin", "project_manager", "gc", "contractor", "client"])
def test_require_owner_forbids_non_owner(role):
    _assert_forbidden(require_owner, _user_with_roles(role))


@pytest.mark.parametrize("role", ["owner", "admin"])
def test_require_admin_allows_owner_and_admin(role):
    require_admin(_user_with_roles(role))  # does not raise


@pytest.mark.parametrize("role", ["project_manager", "gc", "foreman", "contractor", "worker"])
def test_require_admin_forbids_non_admin(role):
    _assert_forbidden(require_admin, _user_with_roles(role))


@pytest.mark.parametrize("role", ["owner", "admin", "project_manager"])
def test_require_manager_allows_management_roles(role):
    require_manager(_user_with_roles(role))  # does not raise


@pytest.mark.parametrize("role", ["gc", "foreman", "contractor", "worker", "client"])
def test_require_manager_forbids_non_management_roles(role):
    _assert_forbidden(require_manager, _user_with_roles(role))


@pytest.mark.parametrize("role", ["owner", "admin", "gc"])
def test_require_gc_allows_gc_roles(role):
    require_gc(_user_with_roles(role))  # does not raise


@pytest.mark.parametrize("role", ["project_manager", "foreman", "contractor", "worker", "client"])
def test_require_gc_forbids_non_gc_roles(role):
    _assert_forbidden(require_gc, _user_with_roles(role))


def test_helpers_honor_any_matching_role_in_a_multi_role_user():
    """A user holding several roles passes if ANY role satisfies the gate."""
    contractor_and_admin = _user_with_roles("contractor", "admin")
    require_admin(contractor_and_admin)  # admin satisfies it
    require_manager(contractor_and_admin)  # admin is in MANAGER_ROLES
