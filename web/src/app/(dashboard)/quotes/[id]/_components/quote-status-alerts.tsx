import type { Quote } from "@/types/api";
import { Button } from "@/components/ui/button";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { formatDate } from "@/lib/format";

interface QuoteStatusAlertsProps {
  quote: Quote;
  onRevise: () => void;
  onExtendExpiry: () => void;
}

export function QuoteStatusAlerts({
  quote,
  onRevise,
  onExtendExpiry,
}: QuoteStatusAlertsProps) {
  if (quote.status === "declined") {
    return (
      <Alert className="bg-red-50 border-l-4 border-red-400 text-red-800">
        <AlertDescription className="text-red-800">
          <div className="flex items-start justify-between gap-4 flex-wrap">
            <div>
              <strong>Declined by client</strong>
              {quote.decline_reason && <span>: {quote.decline_reason}</span>}
              {quote.decline_detail && (
                <p className="mt-1 text-sm">{quote.decline_detail}</p>
              )}
            </div>
            <Button size="sm" onClick={onRevise}>
              Revise &amp; Resend
            </Button>
          </div>
        </AlertDescription>
      </Alert>
    );
  }

  if (quote.status === "expired") {
    return (
      <Alert className="bg-amber-50 border-l-4 border-amber-400 text-amber-800">
        <AlertDescription className="text-amber-800">
          <div className="flex items-start justify-between gap-4 flex-wrap">
            <div>
              <strong>This quote expired on</strong>{" "}
              {formatDate(quote.expiry_date, "unknown date")}. The client can no
              longer approve it.
            </div>
            <div className="flex gap-2">
              <Button size="sm" onClick={onExtendExpiry}>
                Extend Expiry
              </Button>
              <Button size="sm" variant="outline" onClick={onRevise}>
                Revise
              </Button>
            </div>
          </div>
        </AlertDescription>
      </Alert>
    );
  }

  return null;
}
