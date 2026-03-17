"use client";

import { useMutation } from "@tanstack/react-query";

import { apiPost } from "@/lib/api-client";
import type { ConflictDetail, ConflictCheckRequest } from "@/types/schedule";

/**
 * TanStack Query mutation hook for pre-checking scheduling conflicts.
 *
 * Fires POST /api/v1/scheduling/conflicts — read-only, no booking is created.
 * Returns an empty array when the slot is free, or a list of conflicting bookings.
 * Called by the onEventDrop handler before committing a drag-and-drop move.
 */
export function useConflictCheck() {
  return useMutation({
    mutationFn: (request: ConflictCheckRequest) =>
      apiPost<ConflictDetail[]>("/api/v1/scheduling/conflicts", request),
  });
}
