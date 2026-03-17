"use client";

import "react-big-calendar/lib/css/react-big-calendar.css";
import "react-big-calendar/lib/addons/dragAndDrop/styles.css";

import { useState, useEffect, useCallback, useMemo } from "react";
import { Calendar, dateFnsLocalizer, Views, type View, type EventProps } from "react-big-calendar";
import withDragAndDrop, { type EventInteractionArgs } from "react-big-calendar/lib/addons/dragAndDrop";
import { format, parse, startOfWeek, getDay, addDays, subDays, addWeeks, subWeeks, addMonths, subMonths } from "date-fns";
import { enUS } from "date-fns/locale";
import { CalendarOff } from "lucide-react";
import Link from "next/link";
import { toast } from "sonner";

import { CalendarToolbar } from "./calendar-toolbar";
import { BookingEvent } from "./booking-event";
import { ContractorLaneHeader } from "./contractor-lane-header";
import { BookingPanel } from "./booking-panel";
import { BookingCreatePanel } from "./booking-create-panel";
import { FilterToolbar } from "./filter-toolbar";
import { FilterChips } from "./filter-chips";
import { ConflictModal } from "./conflict-modal";
import { useBookings } from "../_hooks/use-bookings";
import { useContractors } from "../_hooks/use-contractors";
import { useScheduleUrl } from "../_hooks/use-schedule-url";
import { useRescheduleMutation } from "../_hooks/use-reschedule";
import { useConflictCheck } from "../_hooks/use-conflict-check";
import type { CalendarBooking, ContractorResource, CalendarView, ConflictDetail } from "@/types/schedule";
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

// Fix #8: Extract noop toolbar to module-level constant to avoid new reference per render
const NoopToolbar = () => null;

// Fix #3: Module-level scroll target (8 AM) — avoids re-scroll on every render
const SCROLL_TO_TIME = new Date(1970, 0, 1, 8, 0, 0);

// Module-level calendar bounds and draggable accessor — avoids new objects every render
const CALENDAR_MIN = new Date(1970, 0, 1, 6, 0, 0);
const CALENDAR_MAX = new Date(1970, 0, 1, 20, 0, 0);
const ALWAYS_DRAGGABLE = () => true as const;

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
  const {
    date,
    view,
    filterTrades,
    filterStatuses,
    filterContractors,
    navigate,
    setFilters,
    clearFilters,
  } = useScheduleUrl();
  const { bookings, isLoading } = useBookings(date, view);
  const { contractors, isLoading: contractorsLoading } = useContractors();

  const [selectedBookingId, setSelectedBookingId] = useState<string | null>(null);
  const [bookingPanelOpen, setBookingPanelOpen] = useState(false);

  // Derive selected booking from bookings array so panel always shows fresh data after reschedule
  const selectedBooking = useMemo(
    () => (selectedBookingId ? bookings.find((b) => b.id === selectedBookingId) ?? null : null),
    [selectedBookingId, bookings]
  );

  // Slot selection state for booking creation panel
  const [createPanelOpen, setCreatePanelOpen] = useState(false);
  const [selectedSlot, setSelectedSlot] = useState<{
    contractorId: string;
    contractorName: string;
    start: Date;
    end: Date;
  } | null>(null);

  // Fix #9: Memoize contractor name lookup map
  const contractorNameMap = useMemo(
    () => new Map(contractors.map((c) => [c.id, c.name])),
    [contractors]
  );

  // Fix #9: Memoize filtered bookings
  const filteredBookings = useMemo(
    () =>
      bookings.filter((b) => {
        if (filterTrades.length > 0) {
          const contractor = contractors.find((c) => c.id === b.resourceId);
          if (!contractor?.tradeType || !filterTrades.includes(contractor.tradeType))
            return false;
        }
        if (filterStatuses.length > 0 && !filterStatuses.includes(b.status))
          return false;
        if (
          filterContractors.length > 0 &&
          !filterContractors.includes(b.resourceId)
        )
          return false;
        return true;
      }),
    [bookings, contractors, filterTrades, filterStatuses, filterContractors]
  );

  // Fix #9: Memoize filtered contractors
  const filteredContractors = useMemo(
    () =>
      filterContractors.length > 0
        ? contractors.filter((c) => filterContractors.includes(c.id))
        : filterTrades.length > 0
          ? contractors.filter(
              (c) => c.tradeType && filterTrades.includes(c.tradeType)
            )
          : contractors,
    [contractors, filterContractors, filterTrades]
  );

  // Filter change handlers
  const handleFiltersChange = useCallback(
    (trades: string[], statuses: string[], contractorIds: string[]) => {
      setFilters(trades, statuses, contractorIds);
    },
    [setFilters]
  );

  const handleRemoveTrade = useCallback(
    (trade: string) => {
      setFilters(
        filterTrades.filter((t) => t !== trade),
        filterStatuses,
        filterContractors
      );
    },
    [filterTrades, filterStatuses, filterContractors, setFilters]
  );

  const handleRemoveStatus = useCallback(
    (status: string) => {
      setFilters(
        filterTrades,
        filterStatuses.filter((s) => s !== status),
        filterContractors
      );
    },
    [filterTrades, filterStatuses, filterContractors, setFilters]
  );

  const handleRemoveContractor = useCallback(
    (id: string) => {
      setFilters(
        filterTrades,
        filterStatuses,
        filterContractors.filter((c) => c !== id)
      );
    },
    [filterTrades, filterStatuses, filterContractors, setFilters]
  );

  // DnD state: pending move awaiting conflict confirmation
  const [pendingMove, setPendingMove] = useState<{
    bookingId: string;
    start: Date;
    end: Date;
    contractorId: string;
    contractorName?: string;
  } | null>(null);
  const [conflicts, setConflicts] = useState<ConflictDetail[]>([]);
  const [conflictModalOpen, setConflictModalOpen] = useState(false);

  // DnD hooks
  const reschedule = useRescheduleMutation();
  const conflictCheck = useConflictCheck();

  const handleEventClick = useCallback((event: CalendarBooking) => {
    setSelectedBookingId(event.id);
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

  // Toolbar-compatible view change handler (accepts CalendarView directly)
  const handleToolbarViewChange = useCallback(
    (newView: CalendarView) => {
      navigate(date, newView);
    },
    [date, navigate]
  );

  // Handle click on empty time slot to open booking creation panel
  const handleSelectSlot = useCallback(
    ({ start, end, resourceId }: { start: Date; end: Date; resourceId?: string | number }) => {
      if (!resourceId) return; // No contractor lane identified
      const resourceIdStr = String(resourceId);
      const contractor = contractors.find((c) => c.id === resourceIdStr);
      if (!contractor) return;

      // Default end time = start + 1 hour if end equals start (single click)
      const effectiveEnd =
        end.getTime() === start.getTime()
          ? new Date(start.getTime() + 60 * 60 * 1000)
          : end;

      setSelectedSlot({
        contractorId: resourceIdStr,
        contractorName: contractor.name,
        start,
        end: effectiveEnd,
      });
      setCreatePanelOpen(true);
    },
    [contractors]
  );

  // DnD: handle event drop — runs conflict pre-check before saving
  const handleEventDrop = useCallback(
    async ({ event, start, end, resourceId }: EventInteractionArgs<CalendarBooking>) => {
      // Coerce stringOrDate to Date (react-big-calendar may pass strings in some views)
      const startDate = start instanceof Date ? start : new Date(start);
      const endDate = end instanceof Date ? end : new Date(end);

      // Fall back to original contractor if same-lane drop (resourceId may be undefined)
      const contractorId = (resourceId as string | undefined) ?? event.resourceId;

      // Find contractor name for the success toast
      const contractor = contractors.find((c) => c.id === contractorId);
      const contractorName = contractor?.name;

      try {
        // Pre-check for conflicts (SCHED-03) before committing the move
        const conflictResults = await conflictCheck.mutateAsync({
          contractor_id: contractorId,
          start: startDate.toISOString(),
          end: endDate.toISOString(),
          exclude_booking_id: event.id,
        });

        if (conflictResults.length > 0) {
          // Conflicts found — hold move in pending state and show modal
          setPendingMove({ bookingId: event.id, start: startDate, end: endDate, contractorId, contractorName });
          setConflicts(conflictResults);
          setConflictModalOpen(true);
          // Do NOT apply optimistic update yet — wait for user confirmation
        } else {
          // No conflicts — save immediately with optimistic update
          reschedule.mutate({ bookingId: event.id, start: startDate, end: endDate, contractorId, contractorName });
        }
      } catch {
        // Conflict check itself failed (network error)
        toast.error("Failed to check for conflicts — please try again", { duration: Infinity });
      }
    },
    [contractors, conflictCheck, reschedule]
  );

  // DnD: user clicked "Confirm Anyway" — proceed with the pending move
  const handleConfirmConflict = useCallback(() => {
    if (pendingMove) {
      reschedule.mutate(pendingMove);
    }
    setConflictModalOpen(false);
    setPendingMove(null);
    setConflicts([]);
  }, [pendingMove, reschedule]);

  // DnD: user clicked "Cancel" — discard pending move (no optimistic update was applied)
  const handleCancelConflict = useCallback(() => {
    setConflictModalOpen(false);
    setPendingMove(null);
    setConflicts([]);
    // No optimistic update was applied, so nothing to rollback
  }, []);

  // Fix #5: ConflictModal overlay close handler — clears all related state
  const handleConflictModalOpenChange = useCallback(
    (open: boolean) => {
      if (!open) {
        setConflictModalOpen(false);
        setPendingMove(null);
        setConflicts([]);
      } else {
        setConflictModalOpen(true);
      }
    },
    []
  );

  // Fix #4: DST-safe keyboard navigation using date-fns
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

      // Escape closes open panels/modals; all other shortcuts are suppressed when a panel/modal is open
      if (e.key === "Escape") {
        if (conflictModalOpen) {
          handleCancelConflict();
        } else if (createPanelOpen) {
          setCreatePanelOpen(false);
        } else if (bookingPanelOpen) {
          setBookingPanelOpen(false);
        }
        return;
      }

      // Suppress navigation/shortcut keys while any panel or modal is open
      if (bookingPanelOpen || createPanelOpen || conflictModalOpen) {
        return;
      }

      switch (e.key) {
        case "ArrowLeft":
          e.preventDefault();
          if (view === "day") {
            navigate(subDays(date, 1));
          } else if (view === "month") {
            navigate(subMonths(date, 1));
          } else {
            navigate(subWeeks(date, 1));
          }
          break;
        case "ArrowRight":
          e.preventDefault();
          if (view === "day") {
            navigate(addDays(date, 1));
          } else if (view === "month") {
            navigate(addMonths(date, 1));
          } else {
            navigate(addWeeks(date, 1));
          }
          break;
        case "t":
        case "T":
          navigate(new Date());
          break;
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [date, view, navigate, bookingPanelOpen, createPanelOpen, conflictModalOpen, handleCancelConflict]);

  // Look up contractor name for the booking panel
  const selectedContractorName = selectedBooking
    ? contractors.find((c) => c.id === selectedBooking.resourceId)?.name
    : undefined;

  // Fix #10: Memoize components object to prevent recreation every render
  const calendarComponents = useMemo(
    () => ({
      event: BookingEventWrapper,
      resourceHeader: ContractorLaneHeaderWrapper,
      toolbar: NoopToolbar,
    }),
    []
  );

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
        onViewChange={handleToolbarViewChange}
      />

      <FilterToolbar
        contractors={contractors}
        filterTrades={filterTrades}
        filterStatuses={filterStatuses}
        filterContractors={filterContractors}
        onFiltersChange={handleFiltersChange}
      />

      <FilterChips
        filterTrades={filterTrades}
        filterStatuses={filterStatuses}
        filterContractors={filterContractors}
        contractorNames={contractorNameMap}
        onRemoveTrade={handleRemoveTrade}
        onRemoveStatus={handleRemoveStatus}
        onRemoveContractor={handleRemoveContractor}
        onClearAll={clearFilters}
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
          .rbc-addons-dnd-drag-preview {
            opacity: 0.7;
            outline: 2px dashed;
            outline-color: oklch(0.205 0 0);
          }
        `}</style>

        <DnDCalendar
          localizer={localizer}
          events={filteredBookings}
          resources={filteredContractors}
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
          min={CALENDAR_MIN}
          max={CALENDAR_MAX}
          onSelectEvent={handleEventClick}
          selectable={true}
          onSelectSlot={handleSelectSlot}
          onEventDrop={handleEventDrop}
          draggableAccessor={ALWAYS_DRAGGABLE}
          resizable={false}
          components={calendarComponents}
          scrollToTime={SCROLL_TO_TIME}
          style={{ height: "calc(100vh - 200px)", minHeight: 600 }}
        />
      </div>

      <ConflictModal
        open={conflictModalOpen}
        onOpenChange={handleConflictModalOpenChange}
        conflicts={conflicts}
        onConfirm={handleConfirmConflict}
        onCancel={handleCancelConflict}
      />

      <BookingPanel
        booking={selectedBooking}
        open={bookingPanelOpen}
        onOpenChange={setBookingPanelOpen}
        contractorName={selectedContractorName}
      />

      {selectedSlot && (
        <BookingCreatePanel
          open={createPanelOpen}
          onOpenChange={setCreatePanelOpen}
          contractorId={selectedSlot.contractorId}
          contractorName={selectedSlot.contractorName}
          startTime={selectedSlot.start}
          endTime={selectedSlot.end}
        />
      )}
    </div>
  );
}
