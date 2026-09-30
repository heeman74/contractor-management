"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Loader2, Trash2 } from "lucide-react";

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { ApiError, apiDelete } from "@/lib/api-client";
import { usePermissions } from "@/lib/hooks/usePermissions";

/**
 * Delete a quote, behind a confirmation.
 *
 * The server decides what may go: an approved quote is the origin of the work
 * approval created, and an invoice, contract or later revision is a row that
 * points at this one. Those come back as a 409 explaining which, and that
 * sentence is shown rather than replaced with a generic failure — it is the
 * only thing that tells the user why.
 */

export interface DeleteQuoteButtonProps {
  quoteId: string;
  quoteReference: string;
}

export function DeleteQuoteButton({ quoteId, quoteReference }: DeleteQuoteButtonProps) {
  const { can } = usePermissions();
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const settle = () => {
    void queryClient.invalidateQueries({ queryKey: ["quotes"] });
    setOpen(false);
    setError(null);
  };

  const remove = useMutation({
    mutationFn: () => apiDelete<void>(`/api/v1/quotes/${quoteId}`),
    onSuccess: settle,
    onError: (err: unknown) => {
      // A 404 means the quote is already gone, which is the outcome asked for.
      // Reporting it as a failure would show an error for a list that is merely
      // stale — and leave the stale row on screen, inviting another click.
      if (err instanceof ApiError && err.status === 404) {
        settle();
        return;
      }
      const detail =
        err && typeof err === "object" && "detail" in err
          ? String((err as { detail: unknown }).detail)
          : "Could not delete this quote.";
      setError(detail);
    },
  });

  if (!can("quotes.delete")) return null;

  return (
    <>
      <button
        type="button"
        aria-label={`Delete quote ${quoteReference}`}
        onClick={(event) => {
          // The row navigates on click; deleting must not also open the quote.
          event.stopPropagation();
          setError(null);
          setOpen(true);
        }}
        className="rounded p-1.5 text-gray-400 transition-colors hover:bg-red-50 hover:text-red-600"
      >
        <Trash2 className="h-4 w-4" aria-hidden />
      </button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent onClick={(event) => event.stopPropagation()}>
          <DialogHeader>
            <DialogTitle>Delete quote {quoteReference}?</DialogTitle>
            <DialogDescription>
              It will be removed from your quotes. Approved quotes, and quotes with
              an invoice, contract or later revision, cannot be deleted.
            </DialogDescription>
          </DialogHeader>

          {error ? (
            <p role="alert" className="text-sm text-red-600">
              {error}
            </p>
          ) : null}

          <DialogFooter>
            <button
              type="button"
              onClick={() => setOpen(false)}
              className="h-9 rounded-lg border border-gray-300 px-3 text-sm text-gray-700"
            >
              Cancel
            </button>
            <button
              type="button"
              disabled={remove.isPending}
              onClick={() => remove.mutate()}
              className="inline-flex h-9 items-center gap-1.5 rounded-lg bg-red-600 px-3 text-sm font-medium text-white transition-colors hover:bg-red-700 disabled:opacity-50"
            >
              {remove.isPending ? (
                <Loader2 className="h-4 w-4 animate-spin" aria-hidden />
              ) : null}
              Delete quote
            </button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
