"use client";

import { useQuery } from "@tanstack/react-query";
import { apiGet } from "@/lib/api-client";
import { toZonedTime } from "date-fns-tz";
import {
  startOfWeek,
  endOfWeek,
  startOfDay,
  endOfDay,
  startOfMonth,
  endOfMonth,
  format,
} from "date-fns";
import type { BookingResponse, CalendarBooking, CalendarView } from "@/types/schedule";
import type { Job } from "@/types/api";

// The jobs list endpoint caps `limit` at 200 (requesting more returns 422).
// We pull the max page so bookings can resolve their job details from one call.
const JOBS_LOOKUP_PAGE_SIZE = 200;

export function useBookings(
  date: Date,
  view: CalendarView,
  companyTimezone?: string
) {
  // Compute date range based on view
  let rangeStart: Date;
  let rangeEnd: Date;

  switch (view) {
    case "day":
      rangeStart = startOfDay(date);
      rangeEnd = endOfDay(date);
      break;
    case "month":
      rangeStart = startOfMonth(date);
      rangeEnd = endOfMonth(date);
      break;
    case "week":
    default:
      rangeStart = startOfWeek(date);
      rangeEnd = endOfWeek(date);
      break;
  }

  const dateFrom = format(rangeStart, "yyyy-MM-dd");
  const dateTo = format(rangeEnd, "yyyy-MM-dd");

  const tz =
    companyTimezone ?? Intl.DateTimeFormat().resolvedOptions().timeZone;

  const { data: bookings, isLoading, isError, error } = useQuery({
    queryKey: ["bookings", { dateFrom, dateTo }],
    queryFn: async () => {
      const [rawBookings, rawJobs] = await Promise.all([
        apiGet<BookingResponse[]>(
          `/api/v1/scheduling/bookings?date_from=${dateFrom}&date_to=${dateTo}`
        ),
        apiGet<Job[]>(`/api/v1/jobs?limit=${JOBS_LOOKUP_PAGE_SIZE}`),
      ]);
      return { rawBookings, rawJobs };
    },
    select: (data) => {
      const { rawBookings, rawJobs } = data;

      // Build a map of job_id -> Job for fast lookup
      const jobMap = new Map<string, Job>();
      rawJobs.forEach((job) => jobMap.set(job.id, job));

      return rawBookings.map((booking): CalendarBooking => {
        const job = jobMap.get(booking.job_id);

        // Convert UTC ISO strings to company timezone
        const startZoned = toZonedTime(new Date(booking.time_range_start), tz);
        const endZoned = toZonedTime(new Date(booking.time_range_end), tz);

        return {
          id: booking.id,
          title: job?.description ?? "Unknown Job",
          clientName: job?.client_name ?? "",
          start: startZoned,
          end: endZoned,
          resourceId: booking.contractor_id,
          status: job?.status ?? "scheduled",
          jobId: booking.job_id,
          dayIndex: booking.day_index ?? undefined,
          parentBookingId: booking.parent_booking_id ?? undefined,
          address: job?.gps_address ?? undefined,
          notes: booking.notes ?? undefined,
        };
      });
    },
    refetchOnWindowFocus: true,
  });

  return {
    bookings: bookings ?? [],
    isLoading,
    isError,
    error,
  };
}
