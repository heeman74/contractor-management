import {
  Calendar,
  dateFnsLocalizer,
  Views,
  type View,
  type EventProps,
} from "react-big-calendar";
import withDragAndDrop from "react-big-calendar/lib/addons/dragAndDrop";
import { format, parse, startOfWeek, getDay } from "date-fns";
import { enUS } from "date-fns/locale";
import { BookingEvent } from "../_components/booking-event";
import { ContractorLaneHeader } from "../_components/contractor-lane-header";
import type {
  CalendarBooking,
  ContractorResource,
  CalendarView,
} from "@/types/schedule";

export const localizer = dateFnsLocalizer({
  format,
  parse,
  startOfWeek,
  getDay,
  locales: { "en-US": enUS },
});

export const DnDCalendar = withDragAndDrop<CalendarBooking, ContractorResource>(
  Calendar
);

// Module-level constants — stable references avoid recreating objects each render.
export const SCROLL_TO_TIME = new Date(1970, 0, 1, 8, 0, 0);
export const CALENDAR_MIN = new Date(1970, 0, 1, 6, 0, 0);
export const CALENDAR_MAX = new Date(1970, 0, 1, 20, 0, 0);
export const ALWAYS_DRAGGABLE = () => true as const;

export function toRBCView(view: CalendarView): View {
  switch (view) {
    case "day":
      return Views.DAY;
    case "month":
      return Views.MONTH;
    default:
      return Views.WEEK;
  }
}

export function fromRBCView(view: View): CalendarView {
  switch (view) {
    case Views.DAY:
      return "day";
    case Views.MONTH:
      return "month";
    default:
      return "week";
  }
}

const NoopToolbar = () => null;

function BookingEventWrapper(props: EventProps<CalendarBooking>) {
  return <BookingEvent event={props.event} />;
}

function ContractorLaneHeaderWrapper({
  resource,
}: {
  resource: ContractorResource;
}) {
  return <ContractorLaneHeader resource={resource} />;
}

// Stable components map (defined once at module load).
export const CALENDAR_COMPONENTS = {
  event: BookingEventWrapper,
  resourceHeader: ContractorLaneHeaderWrapper,
  toolbar: NoopToolbar,
};
