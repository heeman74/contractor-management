import { useCallback, useState } from "react";
import type { EventInteractionArgs } from "react-big-calendar/lib/addons/dragAndDrop";
import { toast } from "sonner";
import type {
  CalendarBooking,
  ContractorResource,
  ConflictDetail,
} from "@/types/schedule";
import { useRescheduleMutation } from "./use-reschedule";
import { useConflictCheck } from "./use-conflict-check";

interface PendingMove {
  bookingId: string;
  start: Date;
  end: Date;
  contractorId: string;
  contractorName?: string;
}

/**
 * Encapsulates drag-and-drop rescheduling: on drop it pre-checks for conflicts,
 * saving immediately when clear or holding the move in a pending state (with a
 * conflict modal) until the user confirms or cancels.
 */
export function useCalendarDnd(contractors: ContractorResource[]) {
  const reschedule = useRescheduleMutation();
  const conflictCheck = useConflictCheck();

  const [pendingMove, setPendingMove] = useState<PendingMove | null>(null);
  const [conflicts, setConflicts] = useState<ConflictDetail[]>([]);
  const [conflictModalOpen, setConflictModalOpen] = useState(false);

  const clearPending = useCallback(() => {
    setConflictModalOpen(false);
    setPendingMove(null);
    setConflicts([]);
  }, []);

  const handleEventDrop = useCallback(
    async ({ event, start, end, resourceId }: EventInteractionArgs<CalendarBooking>) => {
      const startDate = start instanceof Date ? start : new Date(start);
      const endDate = end instanceof Date ? end : new Date(end);
      const contractorId = (resourceId as string | undefined) ?? event.resourceId;
      const contractorName = contractors.find((c) => c.id === contractorId)?.name;
      const move: PendingMove = {
        bookingId: event.id,
        start: startDate,
        end: endDate,
        contractorId,
        contractorName,
      };

      try {
        const conflictResults = await conflictCheck.mutateAsync({
          contractor_id: contractorId,
          start: startDate.toISOString(),
          end: endDate.toISOString(),
          exclude_booking_id: event.id,
        });

        if (conflictResults.length > 0) {
          // Hold the move until the user resolves the conflict — no optimistic update yet.
          setPendingMove(move);
          setConflicts(conflictResults);
          setConflictModalOpen(true);
        } else {
          reschedule.mutate(move);
        }
      } catch {
        toast.error("Failed to check for conflicts — please try again", {
          duration: Infinity,
        });
      }
    },
    [contractors, conflictCheck, reschedule]
  );

  const confirmConflict = useCallback(() => {
    if (pendingMove) reschedule.mutate(pendingMove);
    clearPending();
  }, [pendingMove, reschedule, clearPending]);

  const handleModalOpenChange = useCallback(
    (open: boolean) => {
      if (open) {
        setConflictModalOpen(true);
      } else {
        clearPending();
      }
    },
    [clearPending]
  );

  return {
    conflicts,
    conflictModalOpen,
    handleEventDrop,
    confirmConflict,
    cancelConflict: clearPending,
    handleModalOpenChange,
  };
}
