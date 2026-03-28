"use client";

import { use, useEffect, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { ChevronDown } from "lucide-react";
import { apiGet, apiPost, apiPatch, ApiError } from "@/lib/api-client";
import type {
  Job,
  JobNoteResponse,
  JobTransitionRequest,
  TimeEntryResponse,
  AttachmentResponse,
  JobStatus,
  Quote,
  Invoice,
} from "@/types/api";
import { StatusBadge } from "@/components/shared/status-badge";
import { useAppDispatch } from "@/store/hooks";
import { setPageTitle } from "@/store/slices/ui-slice";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Alert, AlertDescription } from "@/components/ui/alert";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

// ---------------------------------------------------------------------------
// Transition maps
// ---------------------------------------------------------------------------

const NEXT_STATUS: Partial<Record<JobStatus, JobStatus>> = {
  quote: "scheduled",
  scheduled: "in_progress",
  in_progress: "complete",
  complete: "invoiced",
};

const REVERT_STATUS: Partial<Record<JobStatus, JobStatus>> = {
  scheduled: "quote",
  in_progress: "scheduled",
  complete: "in_progress",
};

const CAN_CANCEL: JobStatus[] = ["quote", "scheduled", "in_progress"];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function formatStatus(status: string | undefined): string {
  if (!status) return "";
  return status.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

function formatRelativeTime(dateStr: string): string {
  try {
    const date = new Date(dateStr);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMin = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMin / 60);
    const diffDays = Math.floor(diffHours / 24);

    if (diffMin < 1) return "just now";
    if (diffMin < 60) return `${diffMin}m ago`;
    if (diffHours < 24) return `${diffHours}h ago`;
    if (diffDays < 7) return `${diffDays}d ago`;
    return date.toLocaleDateString();
  } catch {
    return "";
  }
}

function formatDuration(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h === 0) return `${m}m`;
  if (m === 0) return `${h}h`;
  return `${h}h ${m}m`;
}

function formatDateTime(dateStr: string): string {
  try {
    return new Date(dateStr).toLocaleString();
  } catch {
    return dateStr;
  }
}

// ---------------------------------------------------------------------------
// Skeleton
// ---------------------------------------------------------------------------

function PageSkeleton() {
  return (
    <div className="space-y-6 animate-pulse">
      {/* Header skeleton */}
      <div className="space-y-2">
        <div className="h-7 w-2/3 rounded bg-gray-200" />
        <div className="h-5 w-24 rounded-full bg-gray-200" />
      </div>
      {/* Two-column skeleton */}
      <div className="grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-8">
        <div className="space-y-6">
          <div className="rounded-xl bg-gray-100 h-28" />
          <div className="rounded-xl bg-gray-100 h-48" />
          <div className="rounded-xl bg-gray-100 h-32" />
        </div>
        <div className="space-y-4">
          <div className="rounded-xl bg-gray-100 h-32" />
          <div className="rounded-xl bg-gray-100 h-52" />
          <div className="rounded-xl bg-gray-100 h-28" />
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------

export default function JobDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id: jobId } = use(params);
  const router = useRouter();
  const dispatch = useAppDispatch();
  const queryClient = useQueryClient();

  // --- State ---
  const [noteBody, setNoteBody] = useState("");
  const [transitionError, setTransitionError] = useState<string | null>(null);
  const [revertDialogOpen, setRevertDialogOpen] = useState(false);
  const [cancelDialogOpen, setCancelDialogOpen] = useState(false);
  const [cancelReason, setCancelReason] = useState("");
  const [lightboxPhoto, setLightboxPhoto] = useState<AttachmentResponse | null>(null);
  const [showAllTimeEntries, setShowAllTimeEntries] = useState(false);

  // --- Queries ---
  const {
    data: job,
    isLoading: jobLoading,
    isError: jobError,
  } = useQuery<Job>({
    queryKey: ["job", jobId],
    queryFn: () => apiGet<Job>(`/api/v1/jobs/${jobId}`),
  });

  const { data: notesData = [] } = useQuery<JobNoteResponse[]>({
    queryKey: ["job-notes", jobId],
    queryFn: () => apiGet<JobNoteResponse[]>(`/api/v1/jobs/${jobId}/notes`),
    enabled: !!jobId,
  });

  const { data: timeEntries = [] } = useQuery<TimeEntryResponse[]>({
    queryKey: ["job-time-entries", jobId],
    queryFn: () => apiGet<TimeEntryResponse[]>(`/api/v1/jobs/${jobId}/time-entries`),
    enabled: !!jobId,
    retry: false,
  });

  const { data: existingQuote } = useQuery<Quote | null>({
    queryKey: ["quote-for-job", jobId],
    queryFn: () =>
      apiGet<Quote>(`/api/v1/quotes/for-job/${jobId}`).catch(() => null),
    enabled: !!job && (job.status === "quote" || job.status === "complete" || job.status === "invoiced"),
  });

  const { data: existingInvoice } = useQuery<Invoice | null>({
    queryKey: ["invoice-for-job", jobId],
    queryFn: () =>
      apiGet<Invoice>(`/api/v1/invoices/for-job/${jobId}`).catch(() => null),
    enabled: !!job && (job.status === "complete" || job.status === "invoiced"),
  });

  // --- Breadcrumb title ---
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
      toast.error("Failed to load job details. Check your connection and try again.", {
        duration: Infinity,
      });
    }
  }, [jobError]);

  // --- Mutations ---
  const transitionMutation = useMutation<Job, Error, JobTransitionRequest>({
    mutationFn: (data: JobTransitionRequest) =>
      apiPatch<Job>(`/api/v1/jobs/${jobId}/transition`, data),
    onSuccess: (updatedJob) => {
      queryClient.setQueryData(["job", jobId], updatedJob);
      toast.success(`Job marked ${formatStatus(updatedJob.status)}`);
      setTransitionError(null);
    },
    onError: (err: Error) => {
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
    onSuccess: (inv) => {
      queryClient.invalidateQueries({ queryKey: ["invoice-for-job", jobId] });
      toast.success(`Invoice #${inv.invoice_number} generated`);
      router.push(`/invoices/${inv.id}`);
    },
    onError: (err: Error) => {
      const detail = err instanceof ApiError ? err.detail : "Try again.";
      toast.error(`Failed to generate invoice. ${detail}`, { duration: Infinity });
    },
  });

  const addNoteMutation = useMutation<JobNoteResponse, Error, string>({
    mutationFn: (body: string) =>
      apiPost<JobNoteResponse>(`/api/v1/jobs/${jobId}/notes`, { body }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["job-notes", jobId] });
      setNoteBody("");
      toast.success("Note added");
    },
    onError: () => {
      toast.error("Failed to add note", { duration: Infinity });
    },
  });

  // --- Handlers ---
  function handleForwardTransition() {
    if (!job || !NEXT_STATUS[job.status]) return;
    setTransitionError(null);
    transitionMutation.mutate({
      new_status: NEXT_STATUS[job.status]!,
      version: job.version,
    });
  }

  function handleRevert() {
    if (!job || !REVERT_STATUS[job.status]) return;
    transitionMutation.mutate({
      new_status: REVERT_STATUS[job.status]!,
      version: job.version,
    });
    setRevertDialogOpen(false);
  }

  async function handleCancel() {
    if (!job || !cancelReason.trim()) return;
    // Fire transition
    transitionMutation.mutate(
      {
        new_status: "cancelled",
        reason: cancelReason,
        version: job.version,
      },
      {
        onSuccess: async () => {
          // Save cancel reason as a job note
          try {
            await apiPost(`/api/v1/jobs/${jobId}/notes`, {
              body: `Job cancelled: ${cancelReason}`,
            });
            queryClient.invalidateQueries({ queryKey: ["job-notes", jobId] });
          } catch {
            // Non-fatal: note save failure should not block UI
          }
          setCancelDialogOpen(false);
          setCancelReason("");
        },
      }
    );
  }

  // --- Derived values ---
  const sortedNotes = [...notesData].sort(
    (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  );

  const sortedHistory = job
    ? [...job.status_history].sort(
        (a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime()
      )
    : [];

  const totalMinutes = timeEntries.reduce(
    (sum, e) => sum + (e.duration_minutes ?? 0),
    0
  );

  // --- Loading / error states ---
  if (jobLoading) return <PageSkeleton />;

  if (jobError || !job) {
    return (
      <div className="rounded-xl bg-white p-8 text-center ring-1 ring-foreground/10">
        <p className="text-sm text-gray-500">
          Failed to load job details. Check your connection and try again.
        </p>
      </div>
    );
  }

  const nextStatus = NEXT_STATUS[job.status];
  const revertStatus = REVERT_STATUS[job.status];
  const canCancel = CAN_CANCEL.includes(job.status);

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          <h1 className="text-xl font-semibold text-gray-900 truncate">
            {job.description}
          </h1>
          <div className="mt-1 flex flex-wrap gap-2 items-center">
            <span className="inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium text-gray-700">
              {job.trade_type}
            </span>
            <span className="inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium text-gray-700">
              Priority: {job.priority}
            </span>
          </div>
        </div>
      </div>

      {/* Two-column grid */}
      <div className="grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-8">
        {/* ------------------------------------------------------------------ */}
        {/* Main column                                                         */}
        {/* ------------------------------------------------------------------ */}
        <div className="space-y-6">
          {/* Description card */}
          <Card>
            <CardHeader>
              <CardTitle>Description</CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-sm leading-relaxed text-gray-700">{job.description}</p>
            </CardContent>
          </Card>

          {/* Notes card */}
          <Card>
            <CardHeader>
              <CardTitle>Notes</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              {sortedNotes.length === 0 ? (
                <p className="text-sm text-gray-500">
                  No notes yet. Add a note to track progress or log important details.
                </p>
              ) : (
                <ul className="space-y-4">
                  {sortedNotes.map((note) => (
                    <li key={note.id} className="space-y-1">
                      <div className="flex items-center justify-between">
                        <span className="text-xs font-semibold text-gray-500">
                          {note.author_id.slice(0, 8)}
                        </span>
                        <span className="text-xs text-gray-400">
                          {formatRelativeTime(note.created_at)}
                        </span>
                      </div>
                      <p className="text-sm text-gray-700">{note.body}</p>
                      {note.attachments.length > 0 && (
                        <div className="grid grid-cols-4 gap-2 mt-2">
                          {note.attachments.map((attachment) => (
                            <button
                              key={attachment.id}
                              onClick={() => setLightboxPhoto(attachment)}
                              className="rounded overflow-hidden focus:outline-none focus:ring-2 focus:ring-indigo-500"
                            >
                              {attachment.remote_url ? (
                                <Image
                                  src={attachment.remote_url}
                                  alt={attachment.filename}
                                  width={200}
                                  height={200}
                                  unoptimized
                                  className="aspect-square w-full rounded object-cover bg-gray-100"
                                  onError={(e) => {
                                    (e.currentTarget as HTMLImageElement).style.display =
                                      "none";
                                    (
                                      e.currentTarget.nextSibling as HTMLElement
                                    )?.classList.remove("hidden");
                                  }}
                                />
                              ) : (
                                <div className="flex items-center justify-center aspect-square bg-gray-100 rounded">
                                  <span className="text-xs text-gray-400">
                                    Photo unavailable
                                  </span>
                                </div>
                              )}
                            </button>
                          ))}
                        </div>
                      )}
                    </li>
                  ))}
                </ul>
              )}

              {/* Add note form */}
              <div className="space-y-2 pt-2 border-t">
                <Textarea
                  placeholder="Add a note..."
                  className="resize-none"
                  maxLength={2000}
                  value={noteBody}
                  onChange={(e) => setNoteBody(e.target.value)}
                />
                <div className="flex justify-end">
                  <Button
                    size="sm"
                    onClick={() => addNoteMutation.mutate(noteBody)}
                    disabled={!noteBody.trim() || addNoteMutation.isPending}
                  >
                    Add Note
                  </Button>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Activity / Status history card */}
          <Card>
            <CardHeader>
              <CardTitle>Activity</CardTitle>
            </CardHeader>
            <CardContent>
              {sortedHistory.length === 0 ? (
                <p className="text-sm text-gray-500">No status history yet.</p>
              ) : (
                <ul className="space-y-3">
                  {sortedHistory.map((entry, index) => (
                    <li key={index} className="flex items-start gap-3">
                      <StatusBadge status={entry.status} size="sm" />
                      <div className="flex-1 min-w-0">
                        <div className="text-xs text-gray-500">
                          {formatDateTime(entry.timestamp)}
                        </div>
                        {entry.reason && (
                          <div className="text-xs text-gray-400 mt-0.5">
                            Reason: {entry.reason}
                          </div>
                        )}
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </CardContent>
          </Card>
        </div>

        {/* ------------------------------------------------------------------ */}
        {/* Sidebar column                                                      */}
        {/* ------------------------------------------------------------------ */}
        <div className="space-y-4">
          {/* Status + transition actions card */}
          <Card>
            <CardHeader>
              <CardTitle>Status</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <StatusBadge status={job.status} size="md" />

              {/* Transition error banner */}
              {transitionError && (
                <Alert variant="destructive">
                  <AlertDescription>
                    {transitionError}. The page will refresh job data.
                  </AlertDescription>
                </Alert>
              )}

              {/* Action buttons — only when job is actionable */}
              {(nextStatus || revertStatus || canCancel) && (
                <div className="flex gap-2">
                  {/* Primary action button */}
                  {nextStatus && (
                    <Button
                      className="flex-1"
                      size="sm"
                      onClick={handleForwardTransition}
                      disabled={transitionMutation.isPending}
                    >
                      Mark {formatStatus(nextStatus)}
                    </Button>
                  )}

                  {/* Dropdown for other actions */}
                  <DropdownMenu>
                    <DropdownMenuTrigger
                      disabled={transitionMutation.isPending}
                      className="inline-flex h-7 items-center justify-center rounded-[min(var(--radius-md),12px)] border border-border bg-background px-2.5 text-sm font-medium transition-all outline-none hover:bg-muted focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 disabled:pointer-events-none disabled:opacity-50"
                    >
                      <ChevronDown className="h-4 w-4" />
                      <span className="sr-only">More transition options</span>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      {nextStatus && (
                        <DropdownMenuItem
                          onClick={handleForwardTransition}
                        >
                          Mark {formatStatus(nextStatus)}
                        </DropdownMenuItem>
                      )}
                      {revertStatus && nextStatus && <DropdownMenuSeparator />}
                      {revertStatus && (
                        <DropdownMenuItem
                          className="text-gray-500"
                          onClick={() => setRevertDialogOpen(true)}
                        >
                          Revert to {formatStatus(revertStatus)}
                        </DropdownMenuItem>
                      )}
                      {canCancel && (revertStatus || nextStatus) && (
                        <DropdownMenuSeparator />
                      )}
                      {canCancel && (
                        <DropdownMenuItem
                          variant="destructive"
                          onClick={() => setCancelDialogOpen(true)}
                        >
                          Cancel Job
                        </DropdownMenuItem>
                      )}
                    </DropdownMenuContent>
                  </DropdownMenu>
                </div>
              )}

              {/* Terminal state message */}
              {!nextStatus && !revertStatus && !canCancel && (
                <p className="text-xs text-gray-400">
                  {job.status === "invoiced" && "This job has been invoiced."}
                  {job.status === "cancelled" && "This job has been cancelled."}
                </p>
              )}
            </CardContent>
          </Card>

          {/* Documents card — Create Quote and Generate Invoice */}
          {(job.status === "quote" ||
            job.status === "complete" ||
            job.status === "invoiced") && (
            <Card>
              <CardHeader>
                <CardTitle>Documents</CardTitle>
              </CardHeader>
              <CardContent className="space-y-2">
                {/* Quote section */}
                {job.status === "quote" && (
                  existingQuote ? (
                    <Button
                      size="sm"
                      variant="outline"
                      className="w-full"
                      onClick={() => router.push(`/quotes/${existingQuote.id}`)}
                    >
                      View Quote
                    </Button>
                  ) : (
                    <Button
                      size="sm"
                      className="w-full"
                      onClick={() =>
                        router.push(`/quotes/new/edit?job_id=${jobId}`)
                      }
                    >
                      Create Quote
                    </Button>
                  )
                )}

                {/* Generate Invoice section */}
                {job.status === "complete" && (
                  existingInvoice ? (
                    <Button
                      size="sm"
                      variant="outline"
                      className="w-full"
                      onClick={() =>
                        router.push(`/invoices/${existingInvoice.id}`)
                      }
                    >
                      View Invoice
                    </Button>
                  ) : existingQuote?.status === "approved" ? (
                    <Button
                      size="sm"
                      className="w-full"
                      onClick={() => generateInvoiceMutation.mutate()}
                      disabled={generateInvoiceMutation.isPending}
                    >
                      {generateInvoiceMutation.isPending
                        ? "Generating..."
                        : "Generate Invoice"}
                    </Button>
                  ) : (
                    <p className="text-xs text-gray-400">
                      An approved quote is required to generate an invoice.
                    </p>
                  )
                )}

                {/* Invoiced state — show links to both */}
                {job.status === "invoiced" && (
                  <div className="space-y-2">
                    {existingQuote && (
                      <Button
                        size="sm"
                        variant="outline"
                        className="w-full"
                        onClick={() =>
                          router.push(`/quotes/${existingQuote.id}`)
                        }
                      >
                        View Quote
                      </Button>
                    )}
                    {existingInvoice && (
                      <Button
                        size="sm"
                        variant="outline"
                        className="w-full"
                        onClick={() =>
                          router.push(`/invoices/${existingInvoice.id}`)
                        }
                      >
                        View Invoice
                      </Button>
                    )}
                  </div>
                )}
              </CardContent>
            </Card>
          )}

          {/* Job info card */}
          <Card>
            <CardHeader>
              <CardTitle>Job Details</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {/* Contractor */}
              <div>
                <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Contractor
                </p>
                {job.contractor_id ? (
                  <Link
                    href={`/contractors/${job.contractor_id}`}
                    className="text-sm text-indigo-600 hover:text-indigo-800 hover:underline"
                  >
                    {job.contractor_name ?? job.contractor_id.slice(0, 8)}
                  </Link>
                ) : (
                  <p className="text-sm font-normal text-gray-900">Not assigned</p>
                )}
              </div>

              {/* Client */}
              <div>
                <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Client
                </p>
                {job.client_id ? (
                  <Link
                    href={`/clients/${job.client_id}`}
                    className="text-sm text-indigo-600 hover:text-indigo-800 hover:underline"
                  >
                    {job.client_name ?? job.client_id.slice(0, 8)}
                  </Link>
                ) : (
                  <p className="text-sm font-normal text-gray-900">Not assigned</p>
                )}
              </div>

              {/* Scheduled date */}
              <div>
                <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Scheduled Date
                </p>
                <p className="text-sm font-normal text-gray-900">
                  {job.scheduled_completion_date
                    ? new Date(job.scheduled_completion_date).toLocaleDateString()
                    : "Not scheduled"}
                </p>
              </div>

              {/* Address */}
              <div>
                <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Address
                </p>
                <p className="text-sm font-normal text-gray-900">
                  {job.gps_address ?? "No address"}
                </p>
              </div>

              {/* Tags */}
              {job.tags.length > 0 && (
                <div>
                  <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                    Tags
                  </p>
                  <div className="flex flex-wrap gap-1 mt-1">
                    {job.tags.map((tag) => (
                      <span
                        key={tag}
                        className="inline-flex items-center rounded-full bg-gray-100 px-2 py-0.5 text-xs text-gray-700"
                      >
                        {tag}
                      </span>
                    ))}
                  </div>
                </div>
              )}

              {/* Version */}
              <div>
                <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                  Version
                </p>
                <p className="text-sm font-normal text-gray-400">v{job.version}</p>
              </div>
            </CardContent>
          </Card>

          {/* Time tracking card */}
          <Card>
            <CardHeader>
              <CardTitle>Time Tracking</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              {timeEntries.length === 0 ? (
                <p className="text-sm text-gray-500">
                  No time entries recorded for this job.
                </p>
              ) : (
                <>
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                      Total Time
                    </span>
                    <span className="text-sm font-medium text-gray-900">
                      {formatDuration(totalMinutes)}
                    </span>
                  </div>
                  <button
                    className="text-xs text-indigo-600 hover:underline"
                    onClick={() => setShowAllTimeEntries((v) => !v)}
                  >
                    {showAllTimeEntries ? "Hide entries" : `Show ${timeEntries.length} entries`}
                  </button>
                  {showAllTimeEntries && (
                    <ul className="space-y-2 mt-2">
                      {timeEntries.map((entry) => (
                        <li key={entry.id} className="text-xs text-gray-600">
                          <span>{formatDateTime(entry.clock_in)}</span>
                          <span className="mx-1">—</span>
                          <span>
                            {entry.clock_out
                              ? formatDateTime(entry.clock_out)
                              : "In progress"}
                          </span>
                          {entry.duration_minutes != null && (
                            <span className="ml-1 text-gray-400">
                              ({formatDuration(entry.duration_minutes)})
                            </span>
                          )}
                        </li>
                      ))}
                    </ul>
                  )}
                </>
              )}
            </CardContent>
          </Card>

          {/* Quote / Invoice reference card (stub) */}
          {(job.purchase_order_number || job.external_reference) && (
            <Card>
              <CardHeader>
                <CardTitle>Financial References</CardTitle>
              </CardHeader>
              <CardContent className="space-y-2">
                {job.purchase_order_number && (
                  <div>
                    <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                      Purchase Order
                    </p>
                    <p className="text-sm text-gray-900">{job.purchase_order_number}</p>
                  </div>
                )}
                {job.external_reference && (
                  <div>
                    <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                      External Reference
                    </p>
                    <p className="text-sm text-gray-900">{job.external_reference}</p>
                  </div>
                )}
                <p className="text-xs text-gray-400 italic">
                  Linked quotes and invoices will appear here in Phase 16.
                </p>
              </CardContent>
            </Card>
          )}
        </div>
      </div>

      {/* -------------------------------------------------------------------- */}
      {/* Photo lightbox                                                        */}
      {/* -------------------------------------------------------------------- */}
      <Dialog
        open={!!lightboxPhoto}
        onOpenChange={(open) => !open && setLightboxPhoto(null)}
      >
        <DialogContent className="max-w-3xl" showCloseButton>
          {lightboxPhoto?.remote_url ? (
            <Image
              src={lightboxPhoto.remote_url}
              width={800}
              height={600}
              unoptimized
              className="w-full object-contain"
              alt="Photo note"
            />
          ) : (
            <div className="flex items-center justify-center aspect-video bg-gray-100 rounded">
              <span className="text-xs text-gray-400">Photo unavailable</span>
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* -------------------------------------------------------------------- */}
      {/* Revert confirmation dialog                                            */}
      {/* -------------------------------------------------------------------- */}
      <Dialog open={revertDialogOpen} onOpenChange={setRevertDialogOpen}>
        <DialogContent showCloseButton>
          <DialogHeader>
            <DialogTitle>Revert job status?</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-gray-600">
            This will move the job back to{" "}
            <strong>{formatStatus(revertStatus)}</strong>. Are you sure?
          </p>
          <DialogFooter>
            <Button variant="outline" onClick={() => setRevertDialogOpen(false)}>
              Cancel
            </Button>
            <Button
              onClick={handleRevert}
              disabled={transitionMutation.isPending}
            >
              Revert Status
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* -------------------------------------------------------------------- */}
      {/* Cancel confirmation dialog                                            */}
      {/* -------------------------------------------------------------------- */}
      <Dialog open={cancelDialogOpen} onOpenChange={setCancelDialogOpen}>
        <DialogContent showCloseButton>
          <DialogHeader>
            <DialogTitle>Cancel this job?</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-gray-600">
            This action cannot be undone. The job will be marked Cancelled and a note
            will be saved. Please provide a reason.
          </p>
          <div className="space-y-1">
            <label className="text-xs font-semibold text-gray-700">
              Cancellation reason (required)
            </label>
            <Textarea
              value={cancelReason}
              onChange={(e) => setCancelReason(e.target.value)}
              placeholder="Enter reason..."
              className="resize-none"
              maxLength={500}
            />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setCancelDialogOpen(false)}>
              Keep Job
            </Button>
            <Button
              variant="destructive"
              disabled={!cancelReason.trim() || transitionMutation.isPending}
              onClick={handleCancel}
            >
              Cancel Job
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
