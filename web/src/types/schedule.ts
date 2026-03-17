// Calendar event mapped from BookingResponse + Job join
export interface CalendarBooking {
  id: string;                // booking.id
  title: string;             // job.description
  clientName: string;        // from client lookup or job notes
  start: Date;               // booking.time_range_start (UTC -> company tz)
  end: Date;                 // booking.time_range_end (UTC -> company tz)
  resourceId: string;        // booking.contractor_id (maps to resource lane)
  status: string;            // job.status (for StatusBadge color coding)
  jobId: string;             // booking.job_id (for "View Job" link)
  dayIndex?: number;         // multi-day badge: booking.day_index
  parentBookingId?: string;  // multi-day grouping
  address?: string;          // job.gps_address
  notes?: string;            // booking.notes
}

// Contractor resource for react-big-calendar resources prop
export interface ContractorResource {
  id: string;           // user.id
  name: string;         // user.full_name or first_name + last_name
  avatarUrl?: string;   // user.avatar_url
  tradeType?: string;   // user.trade_type (for filtering)
}

// API response types matching backend schemas exactly
export interface BookingResponse {
  id: string;
  company_id: string;
  contractor_id: string;
  job_id: string;
  job_site_id: string | null;
  time_range_start: string;  // ISO datetime UTC
  time_range_end: string;    // ISO datetime UTC
  day_index: number | null;
  parent_booking_id: string | null;
  notes: string | null;
  version: number;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface ConflictDetail {
  booking_id: string;
  contractor_id: string;
  contractor_name: string | null;
  time_range_start: string;
  time_range_end: string;
  job_id: string;
}

export interface ConflictCheckRequest {
  contractor_id: string;
  start: string;  // ISO datetime
  end: string;    // ISO datetime
}

export interface RescheduleRequest {
  start: string;
  end: string;
  contractor_id?: string;  // for cross-lane reassignment
}

export type CalendarView = "week" | "day" | "month";
