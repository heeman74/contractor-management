"use client";

import dynamic from "next/dynamic";
import { Suspense } from "react";
import { CalendarSkeleton } from "./_components/calendar-skeleton";

const ScheduleCalendar = dynamic(
  () => import("./_components/schedule-calendar"),
  { ssr: false, loading: () => <CalendarSkeleton /> }
);

export default function SchedulePage() {
  return (
    <Suspense fallback={<CalendarSkeleton />}>
      <div className="space-y-0">
        <div className="flex items-center justify-between mb-4">
          <h1 className="text-xl font-semibold text-gray-900">Schedule</h1>
        </div>
        <ScheduleCalendar />
      </div>
    </Suspense>
  );
}
