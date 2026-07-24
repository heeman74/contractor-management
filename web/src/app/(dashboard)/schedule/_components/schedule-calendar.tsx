"use client";

import "react-big-calendar/lib/css/react-big-calendar.css";
import "react-big-calendar/lib/addons/dragAndDrop/styles.css";

import { useCallback, useMemo, useState } from "react";
import { Views, type View } from "react-big-calendar";

import { CalendarToolbar } from "./calendar-toolbar";
import { BookingPanel } from "./booking-panel";
import { BookingCreatePanel } from "./booking-create-panel";
import { FilterToolbar } from "./filter-toolbar";
import { FilterChips } from "./filter-chips";
import { ConflictModal } from "./conflict-modal";
import { NoContractorsEmptyState } from "./no-contractors-empty-state";
import { useBookings } from "../_hooks/use-bookings";
import { useContractors } from "../_hooks/use-contractors";
import { useScheduleUrl } from "../_hooks/use-schedule-url";
import { useCalendarDnd } from "../_hooks/use-calendar-dnd";
import { useScheduleKeyboardNav } from "../_hooks/use-schedule-keyboard-nav";
import { useScheduleFilters } from "../_hooks/use-schedule-filters";
import type { CalendarBooking, CalendarView } from "@/types/schedule";
import {
  ALWAYS_DRAGGABLE,
  CALENDAR_COMPONENTS,
  CALENDAR_MAX,
  CALENDAR_MIN,
  DnDCalendar,
  SCROLL_TO_TIME,
  fromRBCView,
  localizer,
  toRBCView,
} from "../_lib/calendar-config";

const CALENDAR_STYLES = `
  .rbc-current-time-indicator { background-color: rgb(239 68 68); height: 2px; }
  .rbc-today { background-color: rgb(239 246 255); }
  .rbc-addons-dnd-drag-preview {
    opacity: 0.7;
    outline: 2px dashed;
    outline-color: oklch(0.205 0 0);
  }
`;

const ONE_HOUR_MS = 60 * 60 * 1000;

export default function ScheduleCalendar() {
  const { date, view, navigate, ...filterState } = useScheduleUrl();
  const { bookings, isLoading } = useBookings(date, view);
  const { contractors, isLoading: contractorsLoading } = useContractors();

  const [selectedBookingId, setSelectedBookingId] = useState<string | null>(null);
  const [bookingPanelOpen, setBookingPanelOpen] = useState(false);
  const [createPanelOpen, setCreatePanelOpen] = useState(false);
  const [selectedSlot, setSelectedSlot] = useState<{
    contractorId: string;
    contractorName: string;
    start: Date;
    end: Date;
  } | null>(null);

  const filters = useScheduleFilters({ contractors, bookings, ...filterState });
  const dnd = useCalendarDnd(contractors);

  const selectedBooking = useMemo(
    () =>
      selectedBookingId
        ? bookings.find((b) => b.id === selectedBookingId) ?? null
        : null,
    [selectedBookingId, bookings]
  );
  const selectedContractorName = selectedBooking
    ? contractors.find((c) => c.id === selectedBooking.resourceId)?.name
    : undefined;

  const handleEventClick = useCallback((event: CalendarBooking) => {
    setSelectedBookingId(event.id);
    setBookingPanelOpen(true);
  }, []);

  const handleNavigate = useCallback((next: Date) => navigate(next), [navigate]);
  const handleViewChange = useCallback(
    (next: View) => navigate(date, fromRBCView(next)),
    [date, navigate]
  );
  const handleToolbarViewChange = useCallback(
    (next: CalendarView) => navigate(date, next),
    [date, navigate]
  );

  const handleSelectSlot = useCallback(
    ({ start, end, resourceId }: { start: Date; end: Date; resourceId?: string | number }) => {
      if (!resourceId) return;
      const contractorId = String(resourceId);
      const contractor = contractors.find((c) => c.id === contractorId);
      if (!contractor) return;

      // A single click gives start === end; default to a one-hour slot.
      const effectiveEnd =
        end.getTime() === start.getTime()
          ? new Date(start.getTime() + ONE_HOUR_MS)
          : end;

      setSelectedSlot({
        contractorId,
        contractorName: contractor.name,
        start,
        end: effectiveEnd,
      });
      setCreatePanelOpen(true);
    },
    [contractors]
  );

  const { conflictModalOpen, cancelConflict } = dnd;
  const handleEscape = useCallback(() => {
    if (conflictModalOpen) cancelConflict();
    else if (createPanelOpen) setCreatePanelOpen(false);
    else if (bookingPanelOpen) setBookingPanelOpen(false);
  }, [conflictModalOpen, cancelConflict, createPanelOpen, bookingPanelOpen]);

  useScheduleKeyboardNav({
    date,
    view,
    navigate,
    isOverlayOpen: bookingPanelOpen || createPanelOpen || conflictModalOpen,
    onEscape: handleEscape,
  });

  if (!contractorsLoading && contractors.length === 0) {
    return <NoContractorsEmptyState />;
  }

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
        filterTrades={filterState.filterTrades}
        filterStatuses={filterState.filterStatuses}
        filterContractors={filterState.filterContractors}
        onFiltersChange={filters.setFilters}
      />

      <FilterChips
        filterTrades={filterState.filterTrades}
        filterStatuses={filterState.filterStatuses}
        filterContractors={filterState.filterContractors}
        contractorNames={filters.contractorNameMap}
        onRemoveTrade={filters.removeTrade}
        onRemoveStatus={filters.removeStatus}
        onRemoveContractor={filters.removeContractor}
        onClearAll={filterState.clearFilters}
      />

      <div className="relative">
        {isLoading && (
          <div className="absolute inset-0 bg-white/60 z-10 flex items-center justify-center">
            <div className="text-sm text-gray-500">Loading...</div>
          </div>
        )}

        <style>{CALENDAR_STYLES}</style>

        <DnDCalendar
          localizer={localizer}
          events={filters.filteredBookings}
          resources={filters.filteredContractors}
          resourceIdAccessor="id"
          resourceTitleAccessor="name"
          resourceAccessor="resourceId"
          defaultView={Views.WEEK}
          view={toRBCView(view)}
          date={date}
          onNavigate={handleNavigate}
          onView={handleViewChange}
          views={[Views.WEEK, Views.DAY, Views.MONTH]}
          step={15}
          timeslots={2}
          min={CALENDAR_MIN}
          max={CALENDAR_MAX}
          onSelectEvent={handleEventClick}
          selectable
          onSelectSlot={handleSelectSlot}
          onEventDrop={dnd.handleEventDrop}
          draggableAccessor={ALWAYS_DRAGGABLE}
          resizable={false}
          components={CALENDAR_COMPONENTS}
          scrollToTime={SCROLL_TO_TIME}
          style={{ height: "calc(100vh - 200px)", minHeight: 600 }}
        />
      </div>

      <ConflictModal
        open={conflictModalOpen}
        onOpenChange={dnd.handleModalOpenChange}
        conflicts={dnd.conflicts}
        onConfirm={dnd.confirmConflict}
        onCancel={dnd.cancelConflict}
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
