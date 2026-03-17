"use client";

import "react-big-calendar/lib/css/react-big-calendar.css";
import "react-big-calendar/lib/addons/dragAndDrop/styles.css";

import { useState, useEffect, useCallback } from "react";
import { Calendar, dateFnsLocalizer, Views, type View, type EventProps } from "react-big-calendar";
import withDragAndDrop from "react-big-calendar/lib/addons/dragAndDrop";
import { format, parse, startOfWeek, getDay } from "date-fns";
import { enUS } from "date-fns/locale";
import { CalendarOff } from "lucide-react";
import Link from "next/link";

import { CalendarToolbar } from "./calendar-toolbar";
import { BookingEvent } from "./booking-event";
import { ContractorLaneHeader } from "./contractor-lane-header";
import { BookingPanel } from "./booking-panel";
import { useBookings } from "../_hooks/use-bookings";
import { useContractors } from "../_hooks/use-contractors";
import { useScheduleUrl } from "../_hooks/use-schedule-url";
import type { CalendarBooking, ContractorResource, CalendarView } from "@/types/schedule";
import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";

// Set up date-fns localizer for react-big-calendar
const localizer = dateFnsLocalizer({
  format,
  parse,
  startOfWeek,
  getDay,
  locales: { "en-US": enUS },
});

// Create DnD-capable calendar
const DnDCalendar = withDragAndDrop<CalendarBooking, ContractorResource>(Calendar);

// Map CalendarView -> react-big-calendar View
function toRBCView(view: CalendarView): View {
  switch (view) {
    case "day":
      return Views.DAY;
    case "month":
      return Views.MONTH;
    case "week":
    default:
      return Views.WEEK;
  }
}

// Map react-big-calendar View -> CalendarView
function fromRBCView(view: View): CalendarView {
  switch (view) {
    case Views.DAY:
      return "day";
    case Views.MONTH:
      return "month";
    default:
      return "week";
  }
}

// Wrapper component to adapt react-big-calendar EventProps to BookingEvent props
function BookingEventWrapper(props: EventProps<CalendarBooking>) {
  return <BookingEvent event={props.event} />;
}

// Wrapper for resource header
function ContractorLaneHeaderWrapper({ resource }: { resource: ContractorResource }) {
  return <ContractorLaneHeader resource={resource} />;
}

export default function ScheduleCalendar() {
  const { date, view, navigate } = useScheduleUrl();
  const { bookings, isLoading } = useBookings(date, view);
  const { contractors, isLoading: contractorsLoading } = useContractors();

  const [selectedBooking, setSelectedBooking] = useState<CalendarBooking | null>(null);
  const [bookingPanelOpen, setBookingPanelOpen] = useState(false);

  const handleEventClick = useCallback((event: CalendarBooking) => {
    setSelectedBooking(event);
    setBookingPanelOpen(true);
  }, []);

  const handleNavigate = useCallback(
    (newDate: Date) => {
      navigate(newDate);
    },
    [navigate]
  );

  const handleViewChange = useCallback(
    (newView: View) => {
      navigate(date, fromRBCView(newView));
    },
    [date, navigate]
  );

  // Keyboard shortcuts
  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      // Don't fire shortcuts when typing in inputs
      const target = e.target as HTMLElement;
      if (
        target.tagName === "INPUT" ||
        target.tagName === "TEXTAREA" ||
        target.isContentEditable
      ) {
        return;
      }

      switch (e.key) {
        case "ArrowLeft":
          e.preventDefault();
          if (view === "day") {
            navigate(new Date(date.getTime() - 86400000));
          } else {
            navigate(new Date(date.getTime() - 7 * 86400000));
          }
          break;
        case "ArrowRight":
          e.preventDefault();
          if (view === "day") {
            navigate(new Date(date.getTime() + 86400000));
          } else {
            navigate(new Date(date.getTime() + 7 * 86400000));
          }
          break;
        case "t":
        case "T":
          navigate(new Date());
          break;
        case "Escape":
          if (bookingPanelOpen) {
            setBookingPanelOpen(false);
          }
          break;
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [date, view, navigate, bookingPanelOpen]);

  // Look up contractor name for the booking panel
  const selectedContractorName = selectedBooking
    ? contractors.find((c) => c.id === selectedBooking.resourceId)?.name
    : undefined;

  // Empty state: no contractors yet
  if (!contractorsLoading && contractors.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-24 text-center">
        <CalendarOff className="h-12 w-12 text-gray-300 mb-4" />
        <h3 className="text-base font-semibold text-gray-900 mb-1">
          No contractors yet
        </h3>
        <p className="text-sm text-gray-500 mb-6">
          Add your team to start scheduling jobs.
        </p>
        <Link
          href="/contractors"
          className={cn(buttonVariants({ variant: "outline", size: "sm" }))}
        >
          Add Contractors
        </Link>
      </div>
    );
  }

  const rbcView = toRBCView(view);

  return (
    <div className="flex flex-col">
      <CalendarToolbar
        date={date}
        view={view}
        onNavigate={handleNavigate}
        onViewChange={(newView) => navigate(date, newView)}
      />

      <div className="relative">
        {isLoading && (
          <div className="absolute inset-0 bg-white/60 z-10 flex items-center justify-center">
            <div className="text-sm text-gray-500">Loading...</div>
          </div>
        )}

        <style>{`
          .rbc-current-time-indicator {
            background-color: rgb(239 68 68);
            height: 2px;
          }
          .rbc-today {
            background-color: rgb(239 246 255);
          }
        `}</style>

        <DnDCalendar
          localizer={localizer}
          events={bookings}
          resources={contractors}
          resourceIdAccessor="id"
          resourceTitleAccessor="name"
          resourceAccessor="resourceId"
          defaultView={Views.WEEK}
          view={rbcView}
          date={date}
          onNavigate={handleNavigate}
          onView={handleViewChange}
          views={[Views.WEEK, Views.DAY, Views.MONTH]}
          step={15}
          timeslots={2}
          min={new Date(0, 0, 0, 6, 0, 0)}
          max={new Date(0, 0, 0, 20, 0, 0)}
          onSelectEvent={handleEventClick}
          selectable={true}
          components={{
            event: BookingEventWrapper,
            resourceHeader: ContractorLaneHeaderWrapper,
            toolbar: () => null,
          }}
          scrollToTime={new Date()}
          style={{ height: "calc(100vh - 200px)", minHeight: 600 }}
        />
      </div>

      <BookingPanel
        booking={selectedBooking}
        open={bookingPanelOpen}
        onOpenChange={setBookingPanelOpen}
        contractorName={selectedContractorName}
      />
    </div>
  );
}
