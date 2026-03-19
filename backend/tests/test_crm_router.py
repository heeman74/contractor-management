"""CRM router endpoint tests — Phase 17."""

import pytest


@pytest.mark.skip(reason="Stub — implement in plan 17-05")
async def test_list_clients(client, seed_company):
    """GET /api/v1/crm/clients returns paginated client list."""
    pass


@pytest.mark.skip(reason="Stub — implement in plan 17-05")
async def test_list_clients_search(client, seed_company):
    """GET /api/v1/crm/clients?search=name filters results."""
    pass


@pytest.mark.skip(reason="Stub — implement in plan 17-05")
async def test_client_detail(client, seed_company):
    """GET /api/v1/crm/clients/{user_id} returns profile with jobs."""
    pass


@pytest.mark.skip(reason="Stub — implement in plan 17-05")
async def test_client_detail_not_found(client, seed_company):
    """GET /api/v1/crm/clients/{unknown_id} returns 404."""
    pass
