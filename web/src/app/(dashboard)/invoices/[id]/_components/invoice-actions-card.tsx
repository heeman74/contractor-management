import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { StatusBadge } from "@/components/shared/status-badge";

interface InvoiceActionsCardProps {
  status: string;
  isPaid: boolean;
  isFinalized: boolean;
  isRecordingPayment: boolean;
  isFinalizing: boolean;
  onRecordPayment: () => void;
  onMarkFullyPaid: () => void;
  onDownloadPdf: () => void;
  onFinalize: () => void;
}

export function InvoiceActionsCard({
  status,
  isPaid,
  isFinalized,
  isRecordingPayment,
  isFinalizing,
  onRecordPayment,
  onMarkFullyPaid,
  onDownloadPdf,
  onFinalize,
}: InvoiceActionsCardProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Actions</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        <StatusBadge status={status} size="md" />

        <div className="flex flex-col gap-2">
          <Button
            variant="outline"
            size="sm"
            disabled={isPaid}
            onClick={onRecordPayment}
          >
            Record Payment
          </Button>

          <Button
            size="sm"
            className="bg-primary hover:bg-primary/90 text-white"
            disabled={isPaid || isRecordingPayment}
            onClick={onMarkFullyPaid}
          >
            Mark Fully Paid
          </Button>

          <Button variant="outline" size="sm" onClick={onDownloadPdf}>
            Download PDF
          </Button>

          {!isFinalized && (
            <Button
              variant="outline"
              size="sm"
              onClick={onFinalize}
              disabled={isFinalizing}
            >
              Finalize Invoice
            </Button>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
