"use client";

import { useSearchParams, useRouter } from "next/navigation";
import { useCallback, useMemo } from "react";
import { parseISO, format, isValid } from "date-fns";
import type { CalendarView } from "@/types/schedule";

export function useScheduleUrl() {
  const searchParams = useSearchParams();
  const router = useRouter();

  // Parse date from URL (default to today, memoized to avoid new Date() every render)
  const defaultDate = useMemo(() => new Date(), []);
  const dateParam = searchParams.get("date");
  let date: Date;
  if (dateParam) {
    const parsed = parseISO(dateParam);
    date = isValid(parsed) ? parsed : defaultDate;
  } else {
    date = defaultDate;
  }

  // Parse view from URL (default to "week")
  const viewParam = searchParams.get("view");
  const validViews: CalendarView[] = ["week", "day", "month"];
  const view: CalendarView = validViews.includes(viewParam as CalendarView)
    ? (viewParam as CalendarView)
    : "week";

  // Parse multi-value filter params
  const filterTrades = searchParams.getAll("trade");
  const filterStatuses = searchParams.getAll("status");
  const filterContractors = searchParams.getAll("contractor");

  const navigate = useCallback(
    (newDate: Date, newView?: CalendarView) => {
      const params = new URLSearchParams(searchParams.toString());
      params.set("date", format(newDate, "yyyy-MM-dd"));
      if (newView) {
        params.set("view", newView);
      }
      router.replace(`/schedule?${params.toString()}`);
    },
    [searchParams, router]
  );

  const setFilters = useCallback(
    (trades: string[], statuses: string[], contractors: string[]) => {
      const params = new URLSearchParams(searchParams.toString());

      // Remove existing filter params
      params.delete("trade");
      params.delete("status");
      params.delete("contractor");

      // Add new filter params
      trades.forEach((t) => params.append("trade", t));
      statuses.forEach((s) => params.append("status", s));
      contractors.forEach((c) => params.append("contractor", c));

      router.replace(`/schedule?${params.toString()}`);
    },
    [searchParams, router]
  );

  const clearFilters = useCallback(() => {
    const params = new URLSearchParams(searchParams.toString());
    params.delete("trade");
    params.delete("status");
    params.delete("contractor");
    router.replace(`/schedule?${params.toString()}`);
  }, [searchParams, router]);

  return {
    date,
    view,
    filterTrades,
    filterStatuses,
    filterContractors,
    navigate,
    setFilters,
    clearFilters,
  };
}
