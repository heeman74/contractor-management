"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { apiPost, ApiError } from "@/lib/api-client";
import type { Quote } from "@/types/api";
import {
  ChangeOrderForm,
  ChangeOrderItem,
  buildChangeOrderPayload,
  changeOrderTotal,
  emptyChangeOrderForm,
  emptyChangeOrderItem,
  validateChangeOrder,
} from "../_lib/change-order";

const SAVE_ERROR_MESSAGE = "Failed to save change order.";
const MISSING_CONTEXT_MESSAGE = "Missing project or originating job.";
const SAVED_MESSAGE = "Change order saved as draft.";

/**
 * All the state, mutation and edit handlers behind the change-order builder.
 *
 * The page renders; this decides. Keeping them apart means the form's rules —
 * what a blank context refuses, what validation blocks, where a saved change
 * order navigates — are testable without mounting a single input.
 */
export function useChangeOrderBuilder(projectId: string, originatingJobId: string) {
  const router = useRouter();
  const queryClient = useQueryClient();

  // Row keys must be stable across re-renders and unique per row; an index
  // would re-key every row below a removal and blur the focused input.
  const keySequence = useRef(0);
  const nextKey = () => `k${keySequence.current++}`;

  const [form, setForm] = useState<ChangeOrderForm>(() => emptyChangeOrderForm("i0"));
  const missingContext = !projectId || !originatingJobId;

  const createMutation = useMutation({
    mutationFn: () =>
      apiPost<Quote>(
        "/api/v1/quotes/",
        buildChangeOrderPayload(projectId, originatingJobId, form)
      ),
    onSuccess: (quote) => {
      queryClient.invalidateQueries({ queryKey: ["quotes"] });
      toast.success(SAVED_MESSAGE);
      router.push(`/quotes/${quote.id}`);
    },
    onError: (error: Error) =>
      toast.error(error instanceof ApiError ? error.detail : SAVE_ERROR_MESSAGE, {
        duration: Infinity,
      }),
  });

  const patchForm = (patch: Partial<ChangeOrderForm>) =>
    setForm((previous) => ({ ...previous, ...patch }));

  const patchItem = (key: string, patch: Partial<ChangeOrderItem>) =>
    setForm((previous) => ({
      ...previous,
      items: previous.items.map((item) =>
        item.key === key ? { ...item, ...patch } : item
      ),
    }));

  const addItem = () =>
    setForm((previous) => ({
      ...previous,
      items: [...previous.items, emptyChangeOrderItem(nextKey())],
    }));

  const removeItem = (key: string) =>
    setForm((previous) => ({
      ...previous,
      items: previous.items.filter((item) => item.key !== key),
    }));

  const save = () => {
    if (missingContext) {
      toast.error(MISSING_CONTEXT_MESSAGE);
      return;
    }
    const validation = validateChangeOrder(form);
    if (!validation.ok) {
      toast.error(validation.error);
      return;
    }
    createMutation.mutate();
  };

  return {
    form,
    total: changeOrderTotal(form.items),
    missingContext,
    isSaving: createMutation.isPending,
    patchForm,
    patchItem,
    addItem,
    removeItem,
    save,
    cancel: () => router.back(),
  };
}
