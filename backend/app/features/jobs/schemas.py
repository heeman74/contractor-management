"""Pydantic schemas for the job lifecycle domain.

Covers: Job, ClientProfile, ClientProperty, JobRequest, Rating, and search.

Design notes:
- JobStatus and JobPriority use StrEnum for type-safe status comparisons
  and OpenAPI enum generation.
- JobTransitionRequest includes `version` (int) for optimistic locking —
  the service layer must verify ORM version matches before writing the transition.
- All response schemas inherit BaseResponseSchema (id, version, timestamps)
  per CLAUDE.md OOP Architecture rules.
- JobCreate / JobUpdate keep all non-system fields optional for PATCH semantics.
- StatusHistoryEntry is embedded in JobResponse.status_history — each entry
  records who transitioned to what status and why.
"""

import uuid
from datetime import date, datetime
from decimal import Decimal
from enum import StrEnum
from typing import Any

from pydantic import BaseModel, Field

from app.core.base_schemas import BaseResponseSchema

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class JobStatus(StrEnum):
    """Valid values for Job.status state machine."""

    quote = "quote"
    scheduled = "scheduled"
    in_progress = "in_progress"
    complete = "complete"
    invoiced = "invoiced"
    cancelled = "cancelled"


class JobPriority(StrEnum):
    """Valid values for Job.priority."""

    low = "low"
    medium = "medium"
    high = "high"
    urgent = "urgent"


class JobUrgency(StrEnum):
    """Valid values for JobRequest.urgency (client-indicated, not job priority)."""

    normal = "normal"
    urgent = "urgent"


class RatingDirection(StrEnum):
    """Who is rating whom in a Rating record."""

    admin_to_client = "admin_to_client"
    client_to_company = "client_to_company"


class JobRequestStatus(StrEnum):
    """Valid values for JobRequest.status."""

    pending = "pending"
    accepted = "accepted"
    declined = "declined"
    info_requested = "info_requested"


# ---------------------------------------------------------------------------
# Job schemas
# ---------------------------------------------------------------------------


class StatusHistoryEntry(BaseModel):
    """A single entry in Job.status_history JSONB array.

    Recorded each time the job transitions to a new status.
    """

    status: JobStatus
    timestamp: datetime
    user_id: uuid.UUID
    reason: str | None = None


class JobCreate(BaseModel):
    """Schema for creating a new job."""

    description: str
    trade_type: str
    status: JobStatus = JobStatus.quote
    priority: JobPriority = JobPriority.medium
    client_id: uuid.UUID | None = None
    contractor_id: uuid.UUID | None = None
    purchase_order_number: str | None = None
    external_reference: str | None = None
    tags: list[str] = Field(default_factory=list)
    notes: str | None = None
    estimated_duration_minutes: int | None = None
    scheduled_completion_date: date | None = None


class JobUpdate(BaseModel):
    """Schema for partially updating a job (all fields optional for PATCH)."""

    description: str | None = None
    trade_type: str | None = None
    priority: JobPriority | None = None
    client_id: uuid.UUID | None = None
    contractor_id: uuid.UUID | None = None
    purchase_order_number: str | None = None
    external_reference: str | None = None
    tags: list[str] | None = None
    notes: str | None = None
    estimated_duration_minutes: int | None = None
    scheduled_completion_date: date | None = None
    # GPS fields — set via sync from mobile field workflow
    gps_latitude: Decimal | None = None
    gps_longitude: Decimal | None = None
    gps_address: str | None = None


class JobResponse(BaseResponseSchema):
    """Full job response including all fields."""

    company_id: uuid.UUID
    description: str
    trade_type: str
    status: JobStatus
    status_history: list[dict[str, Any]] = Field(default_factory=list)
    priority: JobPriority
    client_id: uuid.UUID | None = None
    contractor_id: uuid.UUID | None = None
    purchase_order_number: str | None = None
    external_reference: str | None = None
    tags: list[Any] = Field(default_factory=list)
    notes: str | None = None
    estimated_duration_minutes: int | None = None
    scheduled_completion_date: date | None = None
    # GPS fields added in Phase 6 (migration 0009)
    gps_latitude: Decimal | None = None
    gps_longitude: Decimal | None = None
    gps_address: str | None = None


class JobTransitionRequest(BaseModel):
    """Request to transition a job to a new status.

    `version` is required for optimistic locking: the service layer will
    compare this value against the current ORM model version before writing.
    If they differ, a 409 Conflict is raised (concurrent modification detected).
    """

    new_status: JobStatus
    reason: str | None = None
    version: int


class JobSearchRequest(BaseModel):
    """Request body for full-text search across jobs."""

    query: str
    status: JobStatus | None = None
    contractor_id: uuid.UUID | None = None
    client_id: uuid.UUID | None = None
    trade_type: str | None = None
    priority: JobPriority | None = None
    date_from: date | None = None
    date_to: date | None = None


# ---------------------------------------------------------------------------
# ClientProfile schemas
# ---------------------------------------------------------------------------


class ClientProfileCreate(BaseModel):
    """Schema for creating a new client profile."""

    user_id: uuid.UUID
    billing_address: str | None = None
    tags: list[str] = Field(default_factory=list)
    admin_notes: str | None = None
    referral_source: str | None = None
    preferred_contractor_id: uuid.UUID | None = None
    preferred_contact_method: str | None = None


class ClientProfileUpdate(BaseModel):
    """Schema for partially updating a client profile (all fields optional)."""

    billing_address: str | None = None
    tags: list[str] | None = None
    admin_notes: str | None = None
    referral_source: str | None = None
    preferred_contractor_id: uuid.UUID | None = None
    preferred_contact_method: str | None = None


class ClientProfileResponse(BaseResponseSchema):
    """Full client profile response."""

    company_id: uuid.UUID
    user_id: uuid.UUID
    billing_address: str | None = None
    tags: list[Any] = Field(default_factory=list)
    admin_notes: str | None = None
    referral_source: str | None = None
    preferred_contractor_id: uuid.UUID | None = None
    preferred_contact_method: str | None = None
    average_rating: Decimal | None = None


# ---------------------------------------------------------------------------
# ClientProperty schemas
# ---------------------------------------------------------------------------


class ClientPropertyCreate(BaseModel):
    """Schema for creating a new client property association."""

    client_id: uuid.UUID
    job_site_id: uuid.UUID
    nickname: str | None = None
    is_default: bool = False


class ClientPropertyResponse(BaseResponseSchema):
    """Full client property response."""

    company_id: uuid.UUID
    client_id: uuid.UUID
    job_site_id: uuid.UUID
    nickname: str | None = None
    is_default: bool


# ---------------------------------------------------------------------------
# JobRequest schemas
# ---------------------------------------------------------------------------


class JobRequestCreate(BaseModel):
    """Schema for submitting a new job request (inbound from client portal)."""

    description: str
    trade_type: str | None = None
    urgency: JobUrgency = JobUrgency.normal
    preferred_date_start: date | None = None
    preferred_date_end: date | None = None
    budget_min: Decimal | None = None
    budget_max: Decimal | None = None
    # Anonymous submissions include contact details inline
    submitted_name: str | None = None
    submitted_email: str | None = None
    submitted_phone: str | None = None


class JobRequestResponse(BaseResponseSchema):
    """Full job request response."""

    company_id: uuid.UUID
    client_id: uuid.UUID | None = None
    description: str
    trade_type: str | None = None
    urgency: JobUrgency
    preferred_date_start: date | None = None
    preferred_date_end: date | None = None
    budget_min: Decimal | None = None
    budget_max: Decimal | None = None
    photos: list[Any] = Field(default_factory=list)
    status: JobRequestStatus
    decline_reason: str | None = None
    decline_message: str | None = None
    converted_job_id: uuid.UUID | None = None
    submitted_name: str | None = None
    submitted_email: str | None = None
    submitted_phone: str | None = None


class JobRequestReviewAction(BaseModel):
    """Admin action on a pending job request."""

    action: JobRequestStatus  # accepted | declined | info_requested
    decline_reason: str | None = None
    decline_message: str | None = None


# ---------------------------------------------------------------------------
# Rating schemas
# ---------------------------------------------------------------------------


class RatingCreate(BaseModel):
    """Schema for submitting a star rating for a completed job."""

    stars: int = Field(ge=1, le=5, description="Star rating from 1 (worst) to 5 (best)")
    review_text: str | None = None
    direction: RatingDirection


# ---------------------------------------------------------------------------
# Delay report schema
# ---------------------------------------------------------------------------


class DelayReportRequest(BaseModel):
    """Request body for PATCH /jobs/{job_id}/delay.

    Appends a delay entry to the job's status_history JSONB array and updates
    scheduled_completion_date to the new ETA. Used by contractors and admins
    to signal that a job in progress is running late.

    Fields:
    - reason: Human-readable explanation for the delay (required, non-empty).
    - new_eta: The revised completion date (must be a date, not datetime).
    - version: Current job version for optimistic locking — rejects stale clients.
    """

    reason: str = Field(min_length=1, description="Reason for the delay")
    new_eta: date = Field(description="Revised scheduled completion date")
    version: int = Field(description="Current job version for optimistic locking")


class RatingResponse(BaseResponseSchema):
    """Full rating response."""

    company_id: uuid.UUID
    job_id: uuid.UUID
    rater_id: uuid.UUID
    ratee_id: uuid.UUID
    direction: RatingDirection
    stars: int
    review_text: str | None = None


# ---------------------------------------------------------------------------
# Phase 6 — Field workflow schemas (migration 0009)
# ---------------------------------------------------------------------------


class AttachmentResponse(BaseResponseSchema):
    """Response schema for a file attachment linked to a job note."""

    company_id: uuid.UUID
    note_id: uuid.UUID
    attachment_type: str
    remote_url: str | None = None
    caption: str | None = None
    sort_order: int


class JobNoteCreate(BaseModel):
    """Schema for creating a new job note."""

    body: str = Field(max_length=2000, description="Note content (max 2000 characters)")


class JobNoteResponse(BaseResponseSchema):
    """Full job note response including any attachments."""

    company_id: uuid.UUID
    job_id: uuid.UUID
    author_id: uuid.UUID
    body: str
    attachments: list[AttachmentResponse] = Field(default_factory=list)


class TimeEntryCreate(BaseModel):
    """Schema for clocking in (creating an active time entry)."""

    clocked_in_at: datetime


class TimeEntryUpdate(BaseModel):
    """Schema for clocking out (completing an active time entry)."""

    clocked_out_at: datetime
    duration_seconds: int | None = None


class TimeEntryAdjust(BaseModel):
    """Schema for an admin adjustment to a time entry.

    Appends an entry to adjustment_log and recalculates duration.
    """

    clocked_in_at: datetime | None = None
    clocked_out_at: datetime | None = None
    reason: str = Field(min_length=1, description="Reason for the adjustment")


class TimeEntryResponse(BaseResponseSchema):
    """Full time entry response."""

    company_id: uuid.UUID
    job_id: uuid.UUID
    contractor_id: uuid.UUID
    clocked_in_at: datetime
    clocked_out_at: datetime | None = None
    duration_seconds: int | None = None
    session_status: str
    adjustment_log: list[Any] = Field(default_factory=list)
