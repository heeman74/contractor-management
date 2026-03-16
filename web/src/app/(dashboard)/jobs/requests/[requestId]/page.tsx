"use client";

import { use, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { apiGet, apiPost, ApiError } from "@/lib/api-client";
import type { JobRequestResponse, JobRequestReviewAction } from "@/types/api";
import { useAppDispatch } from "@/store/hooks";
import { setPageTitle } from "@/store/slices/ui-slice";
import { StatusBadge } from "@/components/shared/status-badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import { Skeleton } from "@/components/ui/skeleton";

export default function RequestDetailPage({
  params,
}: {
  params: Promise<{ requestId: string }>;
}) {
  const { requestId } = use(params);
  const router = useRouter();
  const dispatch = useAppDispatch();
  const queryClient = useQueryClient();

  const [declineDialogOpen, setDeclineDialogOpen] = useState(false);
  const [declineReason, setDeclineReason] = useState("");

  const {
    data: request,
    isLoading,
    isError,
  } = useQuery({
    queryKey: ["job-request", requestId],
    queryFn: () =>
      apiGet<JobRequestResponse>(`/api/v1/jobs/requests/${requestId}`),
  });

  useEffect(() => {
    if (request) {
      dispatch(setPageTitle(`Request from ${request.client_name}`));
    }
    return () => {
      dispatch(setPageTitle(null));
    };
  }, [request, dispatch]);

  useEffect(() => {
    if (isError) {
      toast.error("Failed to load request. Check your connection and try again.", {
        duration: Infinity,
      });
    }
  }, [isError]);

  const reviewMutation = useMutation({
    mutationFn: (data: JobRequestReviewAction) =>
      apiPost<JobRequestResponse>(
        `/api/v1/jobs/requests/${requestId}/review`,
        data
      ),
    onSuccess: (result) => {
      if (result.converted_job_id) {
        // Approved — navigate to the new job detail page
        queryClient.invalidateQueries({ queryKey: ["job-requests"] });
        router.push(`/jobs/${result.converted_job_id}`);
      } else {
        // Declined — navigate back to requests tab
        queryClient.invalidateQueries({ queryKey: ["job-requests"] });
        router.push("/jobs?tab=requests");
        toast.success("Request declined and client notified");
      }
    },
    onError: (err: Error) => {
      const apiErr = err as ApiError;
      toast.error(apiErr.detail ?? "Failed to review request", {
        duration: Infinity,
      });
    },
  });

  function handleApprove() {
    reviewMutation.mutate({ action: "accepted" });
  }

  function handleDecline() {
    reviewMutation.mutate({ action: "declined", decline_reason: declineReason });
    setDeclineDialogOpen(false);
    setDeclineReason("");
  }

  if (isLoading) {
    return <RequestDetailSkeleton />;
  }

  if (!request) {
    return null;
  }

  return (
    <div className="space-y-6">
      {/* Action bar */}
      <div className="flex items-center gap-3">
        <Button
          onClick={handleApprove}
          disabled={reviewMutation.isPending}
        >
          Approve Request
        </Button>
        <Button
          variant="outline"
          className="text-destructive border-destructive hover:bg-destructive/10"
          onClick={() => setDeclineDialogOpen(true)}
          disabled={reviewMutation.isPending}
        >
          Decline
        </Button>
      </div>

      {/* Two-column layout */}
      <div className="grid grid-cols-[1fr_360px] gap-8">
        {/* Main column */}
        <div className="space-y-4">
          {/* Request description card */}
          <Card>
            <CardHeader>
              <CardTitle>Request Details</CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-sm leading-relaxed text-gray-700">
                {request.description}
              </p>
            </CardContent>
          </Card>

          {/* Request info card */}
          <Card>
            <CardHeader>
              <CardTitle>Job &amp; Schedule Info</CardTitle>
            </CardHeader>
            <CardContent>
              <dl className="space-y-4">
                <div>
                  <dt className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                    Job Type
                  </dt>
                  <dd className="mt-1 text-sm text-gray-900">
                    {request.job_type ?? "Not specified"}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                    Preferred Date
                  </dt>
                  <dd className="mt-1 text-sm text-gray-900">
                    {request.preferred_date
                      ? new Date(request.preferred_date).toLocaleDateString()
                      : "Flexible"}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                    Preferred Time
                  </dt>
                  <dd className="mt-1 text-sm text-gray-900">
                    {request.preferred_time ?? "Not specified"}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                    Property Address
                  </dt>
                  <dd className="mt-1 text-sm text-gray-900">
                    {request.property_address ?? "No address provided"}
                  </dd>
                </div>
              </dl>
            </CardContent>
          </Card>
        </div>

        {/* Sidebar column */}
        <div className="space-y-4">
          {/* Client info card */}
          <Card>
            <CardHeader>
              <CardTitle>Client Info</CardTitle>
            </CardHeader>
            <CardContent>
              <dl className="space-y-4">
                <div>
                  <dt className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                    Name
                  </dt>
                  <dd className="mt-1">
                    <p className="text-sm font-medium text-gray-900">
                      {request.client_name}
                    </p>
                  </dd>
                </div>
                {request.client_email && (
                  <div>
                    <dt className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                      Email
                    </dt>
                    <dd className="mt-1">
                      <a
                        href={`mailto:${request.client_email}`}
                        className="text-sm text-blue-600 hover:underline"
                      >
                        {request.client_email}
                      </a>
                    </dd>
                  </div>
                )}
                {request.client_phone && (
                  <div>
                    <dt className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                      Phone
                    </dt>
                    <dd className="mt-1">
                      <a
                        href={`tel:${request.client_phone}`}
                        className="text-sm text-blue-600 hover:underline"
                      >
                        {request.client_phone}
                      </a>
                    </dd>
                  </div>
                )}
              </dl>
            </CardContent>
          </Card>

          {/* Request metadata card */}
          <Card>
            <CardHeader>
              <CardTitle>Request Metadata</CardTitle>
            </CardHeader>
            <CardContent>
              <dl className="space-y-4">
                <div>
                  <dt className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                    Status
                  </dt>
                  <dd className="mt-1">
                    <StatusBadge status={request.status} />
                  </dd>
                </div>
                <div>
                  <dt className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
                    Submitted
                  </dt>
                  <dd className="mt-1 text-sm text-gray-900">
                    {new Date(request.created_at).toLocaleDateString()}
                  </dd>
                </div>
              </dl>
            </CardContent>
          </Card>
        </div>
      </div>

      {/* Decline confirmation dialog */}
      <Dialog open={declineDialogOpen} onOpenChange={setDeclineDialogOpen}>
        <DialogContent showCloseButton={false}>
          <DialogHeader>
            <DialogTitle>Decline this request?</DialogTitle>
            <DialogDescription>
              The client will be notified their request was declined. Please
              provide a reason.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
              Decline reason (required)
            </label>
            <Textarea
              value={declineReason}
              onChange={(e) => setDeclineReason(e.target.value)}
              placeholder="Enter reason..."
            />
          </div>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setDeclineDialogOpen(false)}
            >
              Keep Request
            </Button>
            <Button
              variant="destructive"
              disabled={!declineReason.trim() || reviewMutation.isPending}
              onClick={handleDecline}
            >
              Decline Request
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

function RequestDetailSkeleton() {
  return (
    <div className="space-y-6">
      {/* Action bar skeleton */}
      <div className="flex items-center gap-3">
        <Skeleton className="h-8 w-32" />
        <Skeleton className="h-8 w-20" />
      </div>

      {/* Two-column layout skeleton */}
      <div className="grid grid-cols-[1fr_360px] gap-8">
        {/* Main column skeleton */}
        <div className="space-y-4">
          <Card>
            <CardHeader>
              <Skeleton className="h-5 w-32" />
            </CardHeader>
            <CardContent>
              <Skeleton className="h-4 w-full" />
              <Skeleton className="mt-2 h-4 w-3/4" />
              <Skeleton className="mt-2 h-4 w-1/2" />
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <Skeleton className="h-5 w-40" />
            </CardHeader>
            <CardContent className="space-y-4">
              {[...Array(4)].map((_, i) => (
                <div key={i}>
                  <Skeleton className="h-3 w-20" />
                  <Skeleton className="mt-1 h-4 w-32" />
                </div>
              ))}
            </CardContent>
          </Card>
        </div>

        {/* Sidebar column skeleton */}
        <div className="space-y-4">
          <Card>
            <CardHeader>
              <Skeleton className="h-5 w-24" />
            </CardHeader>
            <CardContent className="space-y-4">
              {[...Array(3)].map((_, i) => (
                <div key={i}>
                  <Skeleton className="h-3 w-16" />
                  <Skeleton className="mt-1 h-4 w-40" />
                </div>
              ))}
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <Skeleton className="h-5 w-36" />
            </CardHeader>
            <CardContent className="space-y-4">
              {[...Array(2)].map((_, i) => (
                <div key={i}>
                  <Skeleton className="h-3 w-16" />
                  <Skeleton className="mt-1 h-4 w-24" />
                </div>
              ))}
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
