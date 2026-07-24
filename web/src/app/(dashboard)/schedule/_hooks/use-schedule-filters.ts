import { useCallback, useMemo } from "react";
import type { CalendarBooking, ContractorResource } from "@/types/schedule";

interface ScheduleFiltersOptions {
  contractors: ContractorResource[];
  bookings: CalendarBooking[];
  filterTrades: string[];
  filterStatuses: string[];
  filterContractors: string[];
  setFilters: (trades: string[], statuses: string[], contractorIds: string[]) => void;
}

/**
 * Derives the filtered bookings/contractors for the calendar and the handlers that
 * remove a single active filter chip. Keeps the calendar component focused on layout.
 */
export function useScheduleFilters({
  contractors,
  bookings,
  filterTrades,
  filterStatuses,
  filterContractors,
  setFilters,
}: ScheduleFiltersOptions) {
  const contractorNameMap = useMemo(
    () => new Map(contractors.map((c) => [c.id, c.name])),
    [contractors]
  );

  const filteredBookings = useMemo(
    () =>
      bookings.filter((booking) => {
        if (filterTrades.length > 0) {
          const contractor = contractors.find((c) => c.id === booking.resourceId);
          if (!contractor?.tradeType || !filterTrades.includes(contractor.tradeType)) {
            return false;
          }
        }
        if (filterStatuses.length > 0 && !filterStatuses.includes(booking.status)) {
          return false;
        }
        if (
          filterContractors.length > 0 &&
          !filterContractors.includes(booking.resourceId)
        ) {
          return false;
        }
        return true;
      }),
    [bookings, contractors, filterTrades, filterStatuses, filterContractors]
  );

  const filteredContractors = useMemo(() => {
    if (filterContractors.length > 0) {
      return contractors.filter((c) => filterContractors.includes(c.id));
    }
    if (filterTrades.length > 0) {
      return contractors.filter(
        (c) => c.tradeType && filterTrades.includes(c.tradeType)
      );
    }
    return contractors;
  }, [contractors, filterContractors, filterTrades]);

  const removeTrade = useCallback(
    (trade: string) =>
      setFilters(
        filterTrades.filter((t) => t !== trade),
        filterStatuses,
        filterContractors
      ),
    [filterTrades, filterStatuses, filterContractors, setFilters]
  );

  const removeStatus = useCallback(
    (status: string) =>
      setFilters(
        filterTrades,
        filterStatuses.filter((s) => s !== status),
        filterContractors
      ),
    [filterTrades, filterStatuses, filterContractors, setFilters]
  );

  const removeContractor = useCallback(
    (id: string) =>
      setFilters(
        filterTrades,
        filterStatuses,
        filterContractors.filter((c) => c !== id)
      ),
    [filterTrades, filterStatuses, filterContractors, setFilters]
  );

  return {
    contractorNameMap,
    filteredBookings,
    filteredContractors,
    setFilters,
    removeTrade,
    removeStatus,
    removeContractor,
  };
}
