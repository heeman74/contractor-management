import type { Job, JobStatus } from "@/types/api";

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

const CANCELLABLE_STATUSES: JobStatus[] = ["quote", "scheduled", "in_progress"];

export interface JobTransitionOptions {
  nextStatus: JobStatus | undefined;
  revertStatus: JobStatus | undefined;
  canCancel: boolean;
}

export function getTransitionOptions(status: JobStatus): JobTransitionOptions {
  return {
    nextStatus: NEXT_STATUS[status],
    revertStatus: REVERT_STATUS[status],
    canCancel: CANCELLABLE_STATUSES.includes(status),
  };
}

const DOCUMENT_STATUSES: JobStatus[] = ["quote", "complete", "invoiced"];

export function jobHasDocuments(job: Job): boolean {
  return DOCUMENT_STATUSES.includes(job.status);
}
