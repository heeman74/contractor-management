import { ChevronDown } from "lucide-react";
import type { Job } from "@/types/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Alert, AlertDescription } from "@/components/ui/alert";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { StatusBadge } from "@/components/shared/status-badge";
import { formatStatus } from "@/lib/format";
import type { JobTransitionOptions } from "../_lib/job-transitions";

const TERMINAL_MESSAGES: Partial<Record<Job["status"], string>> = {
  invoiced: "This job has been invoiced.",
  cancelled: "This job has been cancelled.",
};

interface JobStatusCardProps {
  job: Job;
  options: JobTransitionOptions;
  transitionError: string | null;
  isTransitioning: boolean;
  onAdvance: () => void;
  onRevertClick: () => void;
  onCancelClick: () => void;
}

export function JobStatusCard({
  job,
  options,
  transitionError,
  isTransitioning,
  onAdvance,
  onRevertClick,
  onCancelClick,
}: JobStatusCardProps) {
  const { nextStatus, revertStatus, canCancel } = options;
  const hasActions = Boolean(nextStatus || revertStatus || canCancel);

  return (
    <Card>
      <CardHeader>
        <CardTitle>Status</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        <StatusBadge status={job.status} size="md" />

        {transitionError && (
          <Alert variant="destructive">
            <AlertDescription>
              {transitionError}. The page will refresh job data.
            </AlertDescription>
          </Alert>
        )}

        {hasActions && (
          <div className="flex gap-2">
            {nextStatus && (
              <Button
                className="flex-1"
                size="sm"
                onClick={onAdvance}
                disabled={isTransitioning}
              >
                Mark {formatStatus(nextStatus)}
              </Button>
            )}

            <DropdownMenu>
              <DropdownMenuTrigger
                disabled={isTransitioning}
                className="inline-flex h-7 items-center justify-center rounded-[min(var(--radius-md),12px)] border border-border bg-background px-2.5 text-sm font-medium transition-all outline-none hover:bg-muted focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 disabled:pointer-events-none disabled:opacity-50"
              >
                <ChevronDown className="h-4 w-4" />
                <span className="sr-only">More transition options</span>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                {nextStatus && (
                  <DropdownMenuItem onClick={onAdvance}>
                    Mark {formatStatus(nextStatus)}
                  </DropdownMenuItem>
                )}
                {revertStatus && nextStatus && <DropdownMenuSeparator />}
                {revertStatus && (
                  <DropdownMenuItem
                    className="text-gray-500"
                    onClick={onRevertClick}
                  >
                    Revert to {formatStatus(revertStatus)}
                  </DropdownMenuItem>
                )}
                {canCancel && (revertStatus || nextStatus) && (
                  <DropdownMenuSeparator />
                )}
                {canCancel && (
                  <DropdownMenuItem variant="destructive" onClick={onCancelClick}>
                    Cancel Job
                  </DropdownMenuItem>
                )}
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        )}

        {!hasActions && TERMINAL_MESSAGES[job.status] && (
          <p className="text-xs text-gray-400">{TERMINAL_MESSAGES[job.status]}</p>
        )}
      </CardContent>
    </Card>
  );
}
