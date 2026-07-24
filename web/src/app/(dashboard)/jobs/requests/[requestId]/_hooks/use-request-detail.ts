import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { apiGet, apiPost, ApiError } from "@/lib/api-client";
import type { JobRequestResponse, JobRequestReviewAction } from "@/types/api";
import { useAppDispatch } from "@/store/hooks";
import { setPageTitle } from "@/store/slices/ui-slice";

export function useRequestDetail(requestId: string) {
  const router = useRouter();
  const dispatch = useAppDispatch();
  const queryClient = useQueryClient();

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
      queryClient.invalidateQueries({ queryKey: ["job-requests"] });
      if (result.converted_job_id) {
        router.push(`/jobs/${result.converted_job_id}`);
      } else {
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

  return {
    request,
    isLoading,
    isReviewing: reviewMutation.isPending,
    approve: () => reviewMutation.mutate({ action: "accepted" }),
    decline: (declineReason: string) =>
      reviewMutation.mutate({ action: "declined", decline_reason: declineReason }),
  };
}
