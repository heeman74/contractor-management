import type { Quote, Job } from "@/types/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { StatusStepper } from "./status-stepper";
import { SEND_BLOCKED_ALERT_ID } from "./quote-status-alerts";
import { unreviewedAiLineCount } from "../_lib/review-state";

interface QuoteActionsCardProps {
  quote: Quote;
  job: Job | undefined;
  isPdfDownloading: boolean;
  isSending: boolean;
  isGeneratingInvoice: boolean;
  onSend: () => void;
  onEdit: () => void;
  onRevise: () => void;
  onExtendExpiry: () => void;
  onDownloadPdf: () => void;
  onGenerateInvoice: () => void;
}

export function QuoteActionsCard({
  quote,
  job,
  isPdfDownloading,
  isSending,
  isGeneratingInvoice,
  onSend,
  onEdit,
  onRevise,
  onExtendExpiry,
  onDownloadPdf,
  onGenerateInvoice,
}: QuoteActionsCardProps) {
  const status = quote.status;
  const unreviewedCount = unreviewedAiLineCount(quote.line_items);

  const downloadPdfButton = (
    <Button
      size="sm"
      variant="outline"
      onClick={onDownloadPdf}
      disabled={isPdfDownloading}
    >
      Download PDF
    </Button>
  );

  const reviseButton = (
    <Button size="sm" variant="outline" onClick={onRevise}>
      Revise
    </Button>
  );

  const extendButton = (
    <Button size="sm" variant="outline" onClick={onExtendExpiry}>
      Extend Expiry
    </Button>
  );

  return (
    <Card>
      <CardHeader>
        <CardTitle>Status</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <StatusStepper currentStatus={status} />

        <div className="flex flex-col gap-2">
          {status === "draft" && (
            <>
              {/* The disable is a convenience that stops a click from burning a
                  request into a guaranteed 409 — the actual guarantee is the
                  server-side D-07 check. aria-describedby links the control to
                  the alert that explains why, so the reason is announced with
                  the control rather than sitting silently beside it. */}
              <Button
                size="sm"
                onClick={onSend}
                disabled={isSending || unreviewedCount > 0}
                aria-describedby={
                  unreviewedCount > 0 ? SEND_BLOCKED_ALERT_ID : undefined
                }
              >
                Send Quote
              </Button>
              <Button size="sm" variant="outline" onClick={onEdit}>
                Edit
              </Button>
              {downloadPdfButton}
            </>
          )}

          {(status === "sent" || status === "viewed") && (
            <>
              {reviseButton}
              {extendButton}
              {downloadPdfButton}
            </>
          )}

          {status === "approved" && (
            <>
              {downloadPdfButton}
              {job?.status === "complete" && (
                <Button
                  size="sm"
                  onClick={onGenerateInvoice}
                  disabled={isGeneratingInvoice}
                >
                  Generate Invoice
                </Button>
              )}
            </>
          )}

          {status === "declined" && (
            <>
              <Button size="sm" onClick={onRevise}>
                Revise &amp; Resend
              </Button>
              {downloadPdfButton}
            </>
          )}

          {status === "expired" && (
            <>
              <Button size="sm" onClick={onExtendExpiry}>
                Extend Expiry
              </Button>
              {reviseButton}
              {downloadPdfButton}
            </>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
