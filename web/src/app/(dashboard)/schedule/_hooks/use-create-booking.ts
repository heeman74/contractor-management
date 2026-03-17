"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { apiPost } from "@/lib/api-client";
import { toast } from "sonner";
import type { BookingResponse } from "@/types/schedule";

interface CreateBookingArgs {
  contractor_id: string;
  job_id: string;
  start: string;  // ISO datetime
  end: string;    // ISO datetime
  notes?: string;
}

export function useCreateBookingMutation() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (args: CreateBookingArgs) =>
      apiPost<BookingResponse>("/api/v1/scheduling/bookings", args),

    onSuccess: () => {
      toast.success("Booking created successfully");
      queryClient.invalidateQueries({ queryKey: ["bookings"] });
    },

    onError: (error) => {
      const message = error instanceof Error ? error.message : "Failed to create booking";
      toast.error(message, { duration: Infinity });
    },
  });
}
