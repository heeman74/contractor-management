import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { apiGet, apiPost, apiPatch, ApiError } from "@/lib/api-client";
import type {
  Job,
  JobNoteResponse,
  JobTransitionRequest,
  TimeEntryResponse,
  JobStatus,
  Quote,
  Invoice,
} from "@/types/api";
import { useAppDispatch } from "@/store/hooks";
import { setPageTitle } from "@/store/slices/ui-slice";
import { formatStatus } from "@/lib/format";

const DOCUMENT_STATUSES: JobStatus[] = ["quote", "complete", "invoiced"];
const INVOICE_STATUSES: JobStatus[] = ["complete", "invoiced"];

function sortByDateDesc<T>(items: T[], getDate: (item: T) => string): T[] {
  return [...items].sort(
    (a, b) => new Date(getDate(b)).getTime() - new Date(getDate(a)).getTime()
  );
}

export function useJobDetail(jobId: string) {
  const router = useRouter();
  const dispatch = useAppDispatch();
  const queryClient = useQueryClient();

  const [transitionError, setTransitionError] = useState<string | null>(null);

  // Queries -----------------------------------------------------------------

  const {
    data: job,
    isLoading: jobLoading,
    isError: jobError,
  } = useQuery<Job>({
    queryKey: ["job", jobId],
    queryFn: () => apiGet<Job>(`/api/v1/jobs/${jobId}`),
  });

  const { data: notes = [] } = useQuery<JobNoteResponse[]>({
    queryKey: ["job-notes", jobId],
    queryFn: () => apiGet<JobNoteResponse[]>(`/api/v1/jobs/${jobId}/notes`),
    enabled: !!jobId,
  });

  const { data: timeEntries = [] } = useQuery<TimeEntryResponse[]>({
    queryKey: ["job-time-entries", jobId],
    queryFn: () =>
      apiGet<TimeEntryResponse[]>(`/api/v1/jobs/${jobId}/time-entries`),
    enabled: !!jobId,
    retry: false,
  });

  const { data: existingQuote } = useQuery<Quote | null>({
    queryKey: ["quote-for-job", jobId],
    queryFn: () =>
      apiGet<Quote>(`/api/v1/quotes/for-job/${jobId}`, {
        silentStatuses: [404],
      }).catch(() => null),
    enabled: !!job && DOCUMENT_STATUSES.includes(job.status),
  });

  const { data: existingInvoice } = useQuery<Invoice | null>({
    queryKey: ["invoice-for-job", jobId],
    queryFn: () =>
      apiGet<Invoice>(`/api/v1/invoices/for-job/${jobId}`, {
        silentStatuses: [404],
      }).catch(() => null),
    enabled: !!job && INVOICE_STATUSES.includes(job.status),
  });

  // Side effects ------------------------------------------------------------

  useEffect(() => {
    if (job) {
      dispatch(setPageTitle(`Job #${job.id.slice(0, 8).toUpperCase()}`));
    }
    return () => {
      dispatch(setPageTitle(null));
    };
  }, [job, dispatch]);

  useEffect(() => {
    if (jobError) {
      toast.error(
        "Failed to load job details. Check your connection and try again.",
        { duration: Infinity }
      );
    }
  }, [jobError]);

  // Mutations ---------------------------------------------------------------

  const transitionMutation = useMutation<Job, Error, JobTransitionRequest>({
    mutationFn: (data) => apiPatch<Job>(`/api/v1/jobs/${jobId}/transition`, data),
    onSuccess: (updatedJob) => {
      queryClient.setQueryData(["job", jobId], updatedJob);
      toast.success(`Job marked ${formatStatus(updatedJob.status)}`);
      setTransitionError(null);
    },
    onError: (err) => {
      const apiErr = err as ApiError;
      if (apiErr.status === 409) {
        queryClient.invalidateQueries({ queryKey: ["job", jobId] });
        setTransitionError(
          "This job was updated by someone else. Refreshing to get the latest version"
        );
      } else {
        setTransitionError(apiErr.detail ?? "Transition failed");
      }
    },
  });

  const generateInvoiceMutation = useMutation<Invoice, Error, void>({
    mutationFn: () => apiPost<Invoice>(`/api/v1/invoices/generate/${jobId}`, {}),
    onSuccess: (invoice) => {
      queryClient.invalidateQueries({ queryKey: ["invoice-for-job", jobId] });
      toast.success(`Invoice #${invoice.invoice_number} generated`);
      router.push(`/invoices/${invoice.id}`);
    },
    onError: (err) => {
      const detail = err instanceof ApiError ? err.detail : "Try again.";
      toast.error(`Failed to generate invoice. ${detail}`, {
        duration: Infinity,
      });
    },
  });

  const addNoteMutation = useMutation<JobNoteResponse, Error, string>({
    mutationFn: (body) =>
      apiPost<JobNoteResponse>(`/api/v1/jobs/${jobId}/notes`, { body }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["job-notes", jobId] });
      toast.success("Note added");
    },
    onError: () => toast.error("Failed to add note", { duration: Infinity }),
  });

  // Transition helpers ------------------------------------------------------

  function transitionTo(newStatus: JobStatus) {
    if (!job) return;
    setTransitionError(null);
    transitionMutation.mutate({ new_status: newStatus, version: job.version });
  }

  function cancelJob(reason: string) {
    if (!job || !reason.trim()) return;
    transitionMutation.mutate(
      { new_status: "cancelled", reason, version: job.version },
      {
        onSuccess: async () => {
          try {
            await apiPost(`/api/v1/jobs/${jobId}/notes`, {
              body: `Job cancelled: ${reason}`,
            });
            queryClient.invalidateQueries({ queryKey: ["job-notes", jobId] });
          } catch {
            // Non-fatal: note save failure should not block the cancel.
          }
        },
      }
    );
  }

  return {
    job,
    jobLoading,
    jobError,
    notes: sortByDateDesc(notes, (n) => n.created_at),
    statusHistory: job
      ? sortByDateDesc(job.status_history, (h) => h.timestamp)
      : [],
    timeEntries,
    totalMinutes: timeEntries.reduce(
      (sum, entry) => sum + (entry.duration_minutes ?? 0),
      0
    ),
    existingQuote,
    existingInvoice,
    transitionError,
    isTransitioning: transitionMutation.isPending,
    isGeneratingInvoice: generateInvoiceMutation.isPending,
    isAddingNote: addNoteMutation.isPending,
    transitionTo,
    cancelJob,
    addNote: (body: string) => addNoteMutation.mutate(body),
    generateInvoice: () => generateInvoiceMutation.mutate(),
  };
}
