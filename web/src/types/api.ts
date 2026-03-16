// Auth
export interface LoginRequest {
  email: string;
  password: string;
}

export interface TokenResponse {
  access_token: string;
  refresh_token: string;
  token_type: string;
  user_id: string;
  company_id: string;
  roles: string[];
}

export interface AuthUser {
  user_id: string;
  company_id: string;
  roles: string[];
}

// Error
export interface ApiErrorResponse {
  detail: string;
}

// Job statuses
export type JobStatus =
  | "quote"
  | "scheduled"
  | "in_progress"
  | "complete"
  | "invoiced"
  | "cancelled";

// Status history entry
export interface StatusHistoryEntry {
  status: string;
  timestamp: string;
  changed_by?: string;
  reason?: string;
}

// Job -- matches backend JobResponse exactly
export interface Job {
  id: string;
  company_id: string;
  description: string;
  trade_type: string;
  status: JobStatus;
  status_history: StatusHistoryEntry[];
  priority: "low" | "medium" | "high" | "urgent";
  client_id: string | null;
  contractor_id: string | null;
  purchase_order_number: string | null;
  external_reference: string | null;
  tags: string[];
  notes: string | null;
  estimated_duration_minutes: number | null;
  scheduled_completion_date: string | null;
  gps_latitude: string | null;
  gps_longitude: string | null;
  gps_address: string | null;
  version: number;
  created_at: string;
  updated_at: string;
}

// Job transition
export interface JobTransitionRequest {
  new_status: JobStatus;
  reason?: string;
  version: number;
}

// Job notes
export interface JobNoteCreate {
  body: string;
}

export interface AttachmentResponse {
  id: string;
  filename: string;
  content_type: string;
  remote_url: string | null;
}

export interface JobNoteResponse {
  id: string;
  job_id: string;
  author_id: string;
  body: string;
  attachments: AttachmentResponse[];
  created_at: string;
}

// Job requests
export type ReviewAction = "accepted" | "declined" | "info_requested";

export interface JobRequestReviewAction {
  action: ReviewAction;
  decline_reason?: string;
  decline_message?: string;
}

export interface JobRequestResponse {
  id: string;
  company_id: string;
  client_name: string;
  client_email: string | null;
  client_phone: string | null;
  description: string;
  job_type: string | null;
  preferred_date: string | null;
  preferred_time: string | null;
  property_address: string | null;
  status: string;
  converted_job_id: string | null;
  created_at: string;
  updated_at: string;
}

// Time entries
export interface TimeEntryResponse {
  id: string;
  job_id: string;
  user_id: string;
  clock_in: string;
  clock_out: string | null;
  duration_minutes: number | null;
}
