"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";

import { apiPatch } from "@/lib/api-client";
import type { BookingResponse } from "@/types/schedule";
import type { Job } from "@/types/api";

interface RescheduleArgs {
  bookingId: string;
  start: Date;
  end: Date;
  contractorId: string;
  contractorName?: string;
}

/** Raw cache shape stored by useBookings queryFn */
interface BookingsCacheData {
  rawBookings: BookingResponse[];
  rawJobs: Job[];
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

      // 2. Snapshot ALL matching booking queries for rollback (fuzzy match)
      const queryCache = queryClient.getQueryCache();
      const matchingQueries = queryCache.findAll({ queryKey: ["bookings"] });
      const snapshots: Array<{ queryKey: readonly unknown[]; data: unknown }> = [];
      for (const query of matchingQueries) {
        snapshots.push({ queryKey: query.queryKey, data: query.state.data });
      }

      // 3. Optimistically update the raw cache shape — find all queries whose key starts with "bookings"
      queryClient.setQueriesData<BookingsCacheData>(
        { queryKey: ["bookings"] },
        (old) => {
          if (!old) return old;
          return {
            ...old,
            rawBookings: old.rawBookings.map((b) =>
              b.id === args.bookingId
                ? {
                    ...b,
                    time_range_start: args.start.toISOString(),
                    time_range_end: args.end.toISOString(),
                    contractor_id: args.contractorId,
                  }
                : b
            ),
          };
        }
      );
      return { snapshots };
    },

    onError: (_err, _args, context) => {
      // Roll back ALL snapshotted queries on ANY error
      if (context?.snapshots) {
        for (const { queryKey, data } of context.snapshots) {
          queryClient.setQueryData(queryKey, data);
        }
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
