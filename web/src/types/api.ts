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
  client_name: string | null;
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

// Quote types
export type QuoteStatus =
  | "draft"
  | "sent"
  | "viewed"
  | "approved"
  | "declined"
  | "expired"
  | "revised";
export type InvoiceStatus = "unpaid" | "partially_paid" | "paid";
export type ItemType = "labor" | "material";
export type DiscountType = "percent" | "fixed";

export interface QuoteLineItem {
  id: string;
  quote_id: string;
  item_type: ItemType;
  description: string;
  quantity: string;
  unit: string;
  unit_price: string;
  sort_order: number;
}

export interface Quote {
  id: string;
  company_id: string;
  job_id: string;
  status: QuoteStatus;
  revision_number: number;
  tax_rate: string;
  discount_type: DiscountType | null;
  discount_value: string;
  expiry_date: string | null;
  sent_at: string | null;
  viewed_at: string | null;
  approved_at: string | null;
  declined_at: string | null;
  decline_reason: string | null;
  decline_detail: string | null;
  admin_notes: string | null;
  line_items: QuoteLineItem[];
  subtotal: string;
  discount_amount: string;
  tax_amount: string;
  total: string;
  version: number;
  created_at: string;
  updated_at: string;
}

export interface QuoteTemplate {
  id: string;
  company_id: string;
  name: string;
  description: string | null;
  line_items_json: string;
  tax_rate: string;
}

export interface InvoiceLineItem {
  id: string;
  invoice_id: string;
  item_type: ItemType;
  description: string;
  quantity: string;
  unit: string;
  unit_price: string;
  sort_order: number;
}

export interface Invoice {
  id: string;
  company_id: string;
  job_id: string;
  quote_id: string | null;
  invoice_number: string;
  status: InvoiceStatus;
  tax_rate: string;
  discount_type: DiscountType | null;
  discount_value: string;
  due_date: string | null;
  issued_at: string;
  finalized_at: string | null;
  amount_paid: string;
  line_items: InvoiceLineItem[];
  subtotal: string;
  discount_amount: string;
  tax_amount: string;
  total: string;
  version: number;
  created_at: string;
  updated_at: string;
}

// CRM types (Phase 17)
export interface ClientListItem {
  id: string;
  user_id: string;
  first_name: string | null;
  last_name: string | null;
  email: string;
  phone: string | null;
  tags: string[];
  preferred_contractor_id: string | null;
  preferred_contractor_name: string | null;
  jobs_count: number;
}

export interface ClientProperty {
  id: string;
  client_id: string;
  job_site_id: string;
  nickname: string | null;
  is_default: boolean;
  address_line1: string | null;
  city: string | null;
  state: string | null;
  postal_code: string | null;
}

export interface ClientDetail {
  id: string;
  user_id: string;
  first_name: string | null;
  last_name: string | null;
  email: string;
  phone: string | null;
  tags: string[];
  admin_notes: string | null;
  referral_source: string | null;
  preferred_contractor_id: string | null;
  preferred_contractor_name: string | null;
  preferred_contact_method: string | null;
  billing_address: string | null;
  average_rating: string | null;
  jobs: Job[];
  properties: ClientProperty[];
}

// Contractor types
export interface ContractorListItem {
  id: string;
  email: string;
  first_name: string | null;
  last_name: string | null;
  phone: string | null;
  roles: string[];
}

// Availability types
export interface AvailabilityResponse {
  contractor_id: string;
  contractor_name: string;
  date: string;
  free_windows: { start: string; end: string; reason_before: string | null }[];
  blocked_intervals: { start: string; end: string; reason: string }[];
}

// Schedule types
export interface WeeklyBlock {
  id: string;
  contractor_id: string;
  day_of_week: number;
  block_index: number;
  start_time: string;
  end_time: string;
}

export interface DateOverride {
  id: string;
  contractor_id: string;
  override_date: string;
  is_unavailable: boolean;
  block_index: number;
  start_time: string | null;
  end_time: string | null;
}

export interface TimeBlock {
  start_time: string;
  end_time: string;
}
