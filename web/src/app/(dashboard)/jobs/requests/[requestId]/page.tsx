"use client";

import { use, useState } from "react";
import { Button } from "@/components/ui/button";
import { DeclineRequestDialog } from "./_components/decline-request-dialog";
import { RequestDetailSkeleton } from "./_components/request-detail-skeleton";
import {
  JobScheduleInfoCard,
  RequestDetailsCard,
} from "./_components/request-info-cards";
import { RequestSidebar } from "./_components/request-sidebar";
import { useRequestDetail } from "./_hooks/use-request-detail";

export default function RequestDetailPage({
  params,
}: {
  params: Promise<{ requestId: string }>;
}) {
  const { requestId } = use(params);
  const { request, isLoading, isReviewing, approve, decline } =
    useRequestDetail(requestId);

  const [declineDialogOpen, setDeclineDialogOpen] = useState(false);
  const [declineReason, setDeclineReason] = useState("");

  function confirmDecline() {
    decline(declineReason);
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
      {request.status === "pending" && (
        <div className="flex items-center gap-3">
          <Button onClick={approve} disabled={isReviewing}>
            Approve Request
          </Button>
          <Button
            variant="outline"
            className="text-destructive border-destructive hover:bg-destructive/10"
            onClick={() => setDeclineDialogOpen(true)}
            disabled={isReviewing}
          >
            Decline
          </Button>
        </div>
      )}

      <div className="grid grid-cols-[1fr_360px] gap-8">
        <div className="space-y-4">
          <RequestDetailsCard request={request} />
          <JobScheduleInfoCard request={request} />
        </div>

        <RequestSidebar request={request} />
      </div>

      <DeclineRequestDialog
        open={declineDialogOpen}
        onOpenChange={setDeclineDialogOpen}
        reason={declineReason}
        onReasonChange={setDeclineReason}
        onConfirm={confirmDecline}
        isSubmitting={isReviewing}
      />
    </div>
  );
}
