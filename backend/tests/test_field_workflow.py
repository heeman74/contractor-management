import pytest


@pytest.mark.skip(reason="Wave 0 stub — implementation in plan 06-01")
def test_create_note(client, contractor_token):
    """POST /jobs/{job_id}/notes creates a note with 201 status."""
    pass


@pytest.mark.skip(reason="Wave 0 stub — implementation in plan 06-01")
def test_list_notes(client, contractor_token):
    """GET /jobs/{job_id}/notes returns list of notes ordered newest first."""
    pass


@pytest.mark.skip(reason="Wave 0 stub — implementation in plan 06-01")
def test_create_note_empty_body(client, contractor_token):
    """POST /jobs/{job_id}/notes with empty body returns 422 validation error."""
    pass


@pytest.mark.skip(reason="Wave 0 stub — implementation in plan 06-01")
def test_create_note_body_too_long(client, contractor_token):
    """POST /jobs/{job_id}/notes with body > 2000 chars returns 422 validation error."""
    pass


@pytest.mark.skip(reason="Wave 0 stub — implementation in plan 06-01")
def test_create_time_entry(client, contractor_token):
    """POST /jobs/{job_id}/time-entries creates a time entry and returns 201."""
    pass


@pytest.mark.skip(reason="Wave 0 stub — implementation in plan 06-01")
def test_clock_out_time_entry(client, contractor_token):
    """PATCH /jobs/{job_id}/time-entries/{id} clocks out an active entry and returns 200."""
    pass


@pytest.mark.skip(reason="Wave 0 stub — implementation in plan 06-01")
def test_auto_close_active_session(client, contractor_token):
    """POST new time entry auto-closes any previous active session for the same contractor."""
    pass


@pytest.mark.skip(reason="Wave 0 stub — implementation in plan 06-01")
def test_adjust_time_entry_admin(client, admin_token):
    """PATCH /jobs/{job_id}/time-entries/{id}/adjust updates times with audit trail."""
    pass


@pytest.mark.skip(reason="Wave 0 stub — implementation in plan 06-01")
def test_list_time_entries(client, contractor_token):
    """GET /jobs/{job_id}/time-entries returns entries ordered by clock_in descending."""
    pass


@pytest.mark.skip(reason="Wave 0 stub — implementation in plan 06-01/06-06")
def test_upload_file(client, contractor_token):
    """POST /files/upload with valid file and auth returns 201 with remote URL."""
    pass


@pytest.mark.skip(reason="Wave 0 stub — implementation in plan 06-01/06-06")
def test_upload_file_no_auth(client):
    """POST /files/upload without authentication token returns 401."""
    pass


@pytest.mark.skip(reason="Wave 0 stub — implementation in plan 06-01/06-06")
def test_rls_note_isolation(client, contractor_token, other_company_token):
    """Notes created by one tenant are not visible to another tenant (RLS enforced)."""
    pass


@pytest.mark.skip(reason="Wave 0 stub — implementation in plan 06-01/06-06")
def test_rls_time_entry_isolation(client, contractor_token, other_company_token):
    """Time entries created by one tenant are not visible to another tenant (RLS enforced)."""
    pass


@pytest.mark.skip(reason="Wave 0 stub — implementation in plan 06-01/06-06")
def test_gps_geocode_on_sync(client, contractor_token):
    """Syncing a job with GPS coordinates triggers reverse geocoding to populate gps_address."""
    pass
