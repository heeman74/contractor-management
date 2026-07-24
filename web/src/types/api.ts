import type { Role } from "@/lib/roles";

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
  email?: string | null;
  display_name?: string | null;
  company_name?: string | null;
}

export interface AuthUser {
  user_id: string;
  company_id: string;
  roles: string[];
  email?: string | null;
  display_name?: string | null;
  company_name?: string | null;
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
// A job's status_history is a heterogeneous JSONB array holding two shapes:
// status transitions ({status,...}) and audit events ({type,...} — e.g.
// quote_created, quote_sent, invoice_generated, delay). Both carry a timestamp.
export interface StatusChangeEntry {
  status: string;
  timestamp: string;
  changed_by?: string;
  reason?: string;
}

export interface JobEventEntry {
  type: string;
  timestamp: string;
  user_id?: string | null;
  reason?: string;
  new_eta?: string;
}

export type StatusHistoryEntry = StatusChangeEntry | JobEventEntry;

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
  contractor_name: string | null;
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

// Job create
export interface JobCreateRequest {
  description: string;
  trade_type: string;
  priority?: string;
  client_id?: string;
  contractor_id?: string;
  estimated_duration_minutes?: number;
  notes?: string;
}

// Job transition
export interface JobTransitionRequest {
  new_status: JobStatus;
  reason?: string;
  version: number;
}

export type AttachmentType = "photo" | "pdf" | "drawing";

// Matches backend AttachmentResponse (job-note attachments).
export interface AttachmentResponse {
  id: string;
  company_id: string;
  note_id: string;
  attachment_type: AttachmentType;
  remote_url: string | null;
  caption: string | null;
  sort_order: number;
  created_at: string;
  updated_at: string;
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

// Reports types (Phase 18)
export interface JobsByStatusItem {
  status: string;
  count: number;
}

export interface RevenueByMonthItem {
  month: string; // YYYY-MM
  paid: string; // Decimal as string from backend
  unpaid: string;
}

export interface ContractorUtilizationItem {
  contractor_name: string;
  booked_hours: string;
  available_hours: string;
  utilization_percent: string;
}

export interface QuoteConversionItem {
  approved: number;
  declined: number;
  pending: number;
  conversion_rate: string;
}

export interface DashboardResponse {
  jobs_by_status: JobsByStatusItem[];
  revenue_by_month: RevenueByMonthItem[];
  contractor_utilization: ContractorUtilizationItem[];
  quote_conversion: QuoteConversionItem;
}

export interface UtilizationWeekItem {
  iso_week: string;
  booked_hours: string;
  available_hours: string;
  utilization_percent: string;
}

export interface UtilizationHeatmapContractor {
  contractor_id: string;
  contractor_name: string;
  weeks: UtilizationWeekItem[];
}

export interface UtilizationHeatmapResponse {
  weeks: string[];
  contractors: UtilizationHeatmapContractor[];
}

// User — matches backend UserResponse (returned by GET /api/v1/users/)
export interface UserResponse {
  id: string;
  company_id: string;
  email: string;
  first_name: string | null;
  last_name: string | null;
  phone: string | null;
  roles: string[];
  version: number;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

// Create Client types
export interface UserCreateRequest {
  email: string;
  first_name: string;
  last_name: string;
  phone?: string;
}

export interface ClientProfileCreateRequest {
  user_id: string;
  billing_address?: string;
  tags?: string[];
  admin_notes?: string;
}

export interface RoleAssignmentRequest {
  user_id: string;
  role: Role;
}

// RBAC — editable per-company role permission matrix (Phase 27)
export interface PermissionCatalogItem {
  key: string;
  label: string;
  group: string;
}

export interface RolePermissionsResponse {
  catalog: PermissionCatalogItem[];
  roles: Record<string, string[]>;
  defaults: Record<string, string[]>;
}

export interface RolePermissionsUpdate {
  permissions: string[];
}

export interface MyPermissionsResponse {
  permissions: string[];
}

// Company — mirrors backend CompanyResponse (Phase 29 adds license_number)
export interface Company {
  id: string;
  name: string;
  address: string | null;
  phone: string | null;
  trade_types: string[] | null;
  logo_url: string | null;
  business_number: string | null;
  license_number: string | null;
  version: number;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

// Fields the company-settings form may update (Phase 29 scope: license_number).
export interface CompanyUpdate {
  license_number?: string | null;
}

// Contracts & e-signature (Phase 29) --------------------------------------

export type ContractStatus =
  | "draft"
  | "sent"
  | "viewed"
  | "signed"
  | "declined"
  | "voided";

// Contract — mirrors backend ContractResponse exactly.
export interface Contract {
  id: string;
  company_id: string;
  quote_id: string;
  job_id: string | null;
  client_user_id: string | null;
  template_id: string | null;
  status: ContractStatus;
  terms_snapshot: string;
  validity_statement: string | null;
  unsigned_pdf_url: string | null;
  signed_pdf_url: string | null;
  provider: string | null;
  provider_request_id: string | null;
  signer_name: string | null;
  signer_email: string | null;
  version: number;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

// Company-editable contract-terms template.
export interface ContractTemplate {
  id: string;
  company_id: string;
  name: string;
  body: string;
  is_default: boolean;
  version: number;
  created_at: string;
  updated_at: string;
}

export interface ContractTemplateUpdate {
  body: string;
  name?: string;
}

// POST /contracts/{id}/send response.
export interface SendContractResponse {
  contract: Contract;
  sign_url: string;
  magic_link: string;
}

// GET /public/contracts/{token} — public, token-scoped view (no auth cookie).
export interface PublicContractView {
  contract_id: string;
  status: ContractStatus;
  company_name: string;
  signer_name: string | null;
  terms_snapshot: string;
  validity_statement: string | null;
  signed_pdf_url: string | null;
  sign_url: string | null;
}
