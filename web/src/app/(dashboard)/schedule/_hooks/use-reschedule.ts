"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";

import { apiPatch } from "@/lib/api-client";
import type { CalendarBooking } from "@/types/schedule";

interface RescheduleArgs {
  bookingId: string;
  start: Date;
  end: Date;
  contractorId: string;
  contractorName?: string;
}

/**
 * TanStack Query optimistic mutation for booking reschedule with rollback.
 *
 * On mutate: cancels outgoing refetches, snapshots the current cache, and
 * optimistically updates the booking position in the cache immediately so
 * the UI reflects the drag result without waiting for the server.
 *
 * On error: rolls back to the snapshot so the booking snaps back to its
 * original position. Persistent error toast (duration: Infinity) ensures
 * the admin notices the failure.
 *
 * On settled: always invalidates the bookings query to sync from server.
 */
export function useRescheduleMutation() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ bookingId, start, end, contractorId }: RescheduleArgs) =>
      apiPatch(`/api/v1/scheduling/bookings/${bookingId}/reschedule`, {
        start: start.toISOString(),
        end: end.toISOString(),
        contractor_id: contractorId,
      }),

    onMutate: async (args) => {
      // 1. Cancel outgoing refetches to prevent overwrite
      await queryClient.cancelQueries({ queryKey: ["bookings"] });
      // 2. Snapshot current data for rollback
      const previousBookings = queryClient.getQueryData(["bookings"]);
      // 3. Optimistically update the cache — find all queries whose key starts with "bookings"
      queryClient.setQueriesData<CalendarBooking[]>(
        { queryKey: ["bookings"] },
        (old) =>
          old?.map((b) =>
            b.id === args.bookingId
              ? { ...b, start: args.start, end: args.end, resourceId: args.contractorId }
              : b
          )
      );
      return { previousBookings };
    },

    onError: (_err, _args, context) => {
      // Roll back to snapshot on ANY error
      if (context?.previousBookings) {
        queryClient.setQueriesData(
          { queryKey: ["bookings"] },
          context.previousBookings
        );
      }
      toast.error("Failed to reschedule — please try again", { duration: Infinity });
    },

    onSuccess: (_data, args) => {
      const time = args.start.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
      const name = args.contractorName ?? "contractor";
      toast.success(`Booking moved to ${name} at ${time}`);
    },

    onSettled: () => {
      // Always refetch after mutation to ensure server consistency
      queryClient.invalidateQueries({ queryKey: ["bookings"] });
    },
  });
}
