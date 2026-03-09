"""Unit tests for the job lifecycle state machine transition logic.

Pure unit tests — no DB, no HTTP, no async I/O.
Tests the ALLOWED_TRANSITIONS matrix and is_backward() helper function
imported directly from app.features.jobs.service.

Design:
- Each test exercises one facet of the state machine rules.
- No fixtures required — all inputs are literals/constants.
- Tests must fail if ALLOWED_TRANSITIONS or BACKWARD_TRANSITIONS is incorrectly defined.
"""

import pytest

from app.features.jobs.schemas import JobStatus
from app.features.jobs.service import ALLOWED_TRANSITIONS, BACKWARD_TRANSITIONS, is_backward


# ---------------------------------------------------------------------------
# Test 1: All valid admin forward transitions
# ---------------------------------------------------------------------------


def test_all_valid_admin_forward_transitions():
    """Admin can perform all defined forward transitions (progressive stage advancement).

    Forward transitions: quote -> scheduled, scheduled -> in_progress,
    in_progress -> complete, complete -> invoiced.
    Each must be in the ALLOWED_TRANSITIONS frozenset for role='admin'.
    """
    forward_transitions = [
        (JobStatus.quote, JobStatus.scheduled),
        (JobStatus.scheduled, JobStatus.in_progress),
        (JobStatus.in_progress, JobStatus.complete),
        (JobStatus.complete, JobStatus.invoiced),
    ]

    for from_status, to_status in forward_transitions:
        allowed = ALLOWED_TRANSITIONS.get((from_status, "admin"), frozenset())
        assert to_status in allowed, (
            f"Admin should be able to transition {from_status} -> {to_status}, "
            f"but got allowed set: {allowed}"
        )


# ---------------------------------------------------------------------------
# Test 2: All valid admin backward transitions
# ---------------------------------------------------------------------------


def test_all_valid_admin_backward_transitions():
    """Admin can perform all defined backward transitions and they are flagged as backward.

    Backward transitions: scheduled -> quote, in_progress -> scheduled,
    complete -> in_progress, invoiced -> complete.
    Each must be in ALLOWED_TRANSITIONS and is_backward() must return True.
    """
    backward_transitions = [
        (JobStatus.scheduled, JobStatus.quote),
        (JobStatus.in_progress, JobStatus.scheduled),
        (JobStatus.complete, JobStatus.in_progress),
        (JobStatus.invoiced, JobStatus.complete),
    ]

    for from_status, to_status in backward_transitions:
        # 1. Transition must be allowed for admin
        allowed = ALLOWED_TRANSITIONS.get((from_status, "admin"), frozenset())
        assert to_status in allowed, (
            f"Admin should be able to backward-transition {from_status} -> {to_status}"
        )

        # 2. is_backward must flag this as a backward move
        assert is_backward(from_status, to_status) is True, (
            f"is_backward({from_status}, {to_status}) should return True"
        )


# ---------------------------------------------------------------------------
# Test 3: All valid contractor transitions
# ---------------------------------------------------------------------------


def test_all_valid_contractor_transitions():
    """Contractor can perform scheduled -> in_progress and in_progress -> complete.

    These are the only two transitions allowed for contractor role.
    """
    valid_contractor_transitions = [
        (JobStatus.scheduled, JobStatus.in_progress),
        (JobStatus.in_progress, JobStatus.complete),
    ]

    for from_status, to_status in valid_contractor_transitions:
        allowed = ALLOWED_TRANSITIONS.get((from_status, "contractor"), frozenset())
        assert to_status in allowed, (
            f"Contractor should be able to transition {from_status} -> {to_status}, "
            f"but got allowed set: {allowed}"
        )


# ---------------------------------------------------------------------------
# Test 4: Contractor cannot perform admin-only transitions
# ---------------------------------------------------------------------------


def test_contractor_cannot_perform_admin_transitions():
    """Contractor is blocked from admin-only transitions.

    Blocked transitions:
    - quote -> scheduled (admin-only, requires scheduling decision)
    - complete -> invoiced (admin-only, financial step)
    - Any backward transition
    """
    admin_only_transitions = [
        (JobStatus.quote, JobStatus.scheduled),
        (JobStatus.complete, JobStatus.invoiced),
        # Backward transitions
        (JobStatus.scheduled, JobStatus.quote),
        (JobStatus.in_progress, JobStatus.scheduled),
    ]

    for from_status, to_status in admin_only_transitions:
        allowed = ALLOWED_TRANSITIONS.get((from_status, "contractor"), frozenset())
        assert to_status not in allowed, (
            f"Contractor should NOT be able to transition {from_status} -> {to_status}, "
            f"but it was in allowed set: {allowed}"
        )


# ---------------------------------------------------------------------------
# Test 5: Client cannot perform any transition
# ---------------------------------------------------------------------------


def test_client_cannot_perform_any_transition():
    """Client role has empty frozenset for all statuses — clients are view-only.

    Verified against every status in the state machine to ensure no gaps.
    """
    all_statuses = [
        JobStatus.quote,
        JobStatus.scheduled,
        JobStatus.in_progress,
        JobStatus.complete,
        JobStatus.invoiced,
        JobStatus.cancelled,
    ]

    for status in all_statuses:
        allowed = ALLOWED_TRANSITIONS.get((status, "client"), frozenset())
        assert len(allowed) == 0, (
            f"Client should have NO allowed transitions from status '{status}', "
            f"but got: {allowed}"
        )


# ---------------------------------------------------------------------------
# Test 6: Cancelled is terminal — no transitions out
# ---------------------------------------------------------------------------


def test_cancelled_is_terminal():
    """No role can transition out of 'cancelled' status.

    Cancelled is a terminal state — once a job is cancelled, it stays cancelled.
    All three roles must have empty frozensets for (cancelled, role).
    """
    roles = ["admin", "contractor", "client"]

    for role in roles:
        allowed = ALLOWED_TRANSITIONS.get((JobStatus.cancelled, role), frozenset())
        assert len(allowed) == 0, (
            f"Role '{role}' should have NO transitions from 'cancelled', "
            f"but got: {allowed}"
        )


# ---------------------------------------------------------------------------
# Test 7: Admin can cancel from any active (non-terminal) status
# ---------------------------------------------------------------------------


def test_admin_can_cancel_from_any_active_status():
    """Admin can cancel a job from any non-terminal active status.

    Active statuses: quote, scheduled, in_progress, complete.
    Note: invoiced -> cancelled is also allowed (admin can void an invoice).
    """
    active_statuses = [
        JobStatus.quote,
        JobStatus.scheduled,
        JobStatus.in_progress,
        JobStatus.complete,
        JobStatus.invoiced,
    ]

    for status in active_statuses:
        allowed = ALLOWED_TRANSITIONS.get((status, "admin"), frozenset())
        assert JobStatus.cancelled in allowed, (
            f"Admin should be able to cancel from '{status}', "
            f"but 'cancelled' was not in allowed set: {allowed}"
        )


# ---------------------------------------------------------------------------
# Test 8: is_backward helper correctness
# ---------------------------------------------------------------------------


def test_is_backward_helper():
    """is_backward returns True for known backward pairs and False for forward ones.

    Tests both directions of the mapping:
    - Known backward pairs must return True.
    - Known forward pairs must return False.
    - Cancellation transitions must return False (cancellation is terminal, not backward).
    """
    # Backward pairs — should return True
    backward_pairs = [
        (JobStatus.scheduled, JobStatus.quote),
        (JobStatus.in_progress, JobStatus.scheduled),
        (JobStatus.complete, JobStatus.in_progress),
        (JobStatus.invoiced, JobStatus.complete),
    ]
    for from_status, to_status in backward_pairs:
        assert is_backward(from_status, to_status) is True, (
            f"is_backward({from_status}, {to_status}) should be True"
        )

    # Forward pairs — should return False
    forward_pairs = [
        (JobStatus.quote, JobStatus.scheduled),
        (JobStatus.scheduled, JobStatus.in_progress),
        (JobStatus.in_progress, JobStatus.complete),
        (JobStatus.complete, JobStatus.invoiced),
    ]
    for from_status, to_status in forward_pairs:
        assert is_backward(from_status, to_status) is False, (
            f"is_backward({from_status}, {to_status}) should be False"
        )

    # Cancellation transitions — NOT backward (terminal, not reversal)
    cancellation_pairs = [
        (JobStatus.quote, JobStatus.cancelled),
        (JobStatus.scheduled, JobStatus.cancelled),
        (JobStatus.in_progress, JobStatus.cancelled),
        (JobStatus.complete, JobStatus.cancelled),
    ]
    for from_status, to_status in cancellation_pairs:
        assert is_backward(from_status, to_status) is False, (
            f"is_backward({from_status}, {to_status}) should be False — "
            f"cancellation is a terminal transition, not a backward step"
        )
