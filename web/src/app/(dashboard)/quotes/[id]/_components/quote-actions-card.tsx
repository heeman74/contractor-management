import type { Quote, Job } from "@/types/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { StatusStepper } from "./status-stepper";

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
              <Button size="sm" onClick={onSend} disabled={isSending}>
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
