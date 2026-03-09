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


class RatingResponse(BaseResponseSchema):
    """Full rating response."""

    company_id: uuid.UUID
    job_id: uuid.UUID
    rater_id: uuid.UUID
    ratee_id: uuid.UUID
    direction: RatingDirection
    stars: int
    review_text: str | None = None
