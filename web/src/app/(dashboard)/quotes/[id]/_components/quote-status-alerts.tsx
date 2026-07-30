import { useRouter } from "next/navigation";
import type { Quote } from "@/types/api";
import { Button } from "@/components/ui/button";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { formatDate } from "@/lib/format";
import { sendBlockedCopy, unreviewedAiLineCount } from "../_lib/review-state";

interface QuoteStatusAlertsProps {
  quote: Quote;
  onRevise: () => void;
  onExtendExpiry: () => void;
}

// Shared by the expired-quote branch and the blocked-send branch below — both
// reuse the shipped QuoteStatusAlerts amber recipe (in place since Phase 25),
// a different scale from the --brand accent. Extracted once so the recipe
// cannot drift between the two call sites.
const ALERT_AMBER_CLASS =
  "bg-amber-50 border-l-4 border-amber-400 text-amber-800";

/** The blocked-send alert's DOM id — the Send Quote button's
 * `aria-describedby` points here so the disabled control and the copy
 * explaining why it is disabled can never point at different anchors. */
export const SEND_BLOCKED_ALERT_ID = "send-blocked-alert";

export function QuoteStatusAlerts({
  quote,
  onRevise,
  onExtendExpiry,
}: QuoteStatusAlertsProps) {
  const router = useRouter();

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
      <Alert className={ALERT_AMBER_CLASS}>
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

  const unreviewedCount = unreviewedAiLineCount(quote.line_items);
  if (quote.status === "draft" && unreviewedCount > 0) {
    const { heading, body } = sendBlockedCopy(unreviewedCount);
    return (
      <Alert
        id={SEND_BLOCKED_ALERT_ID}
        data-testid="send-blocked-alert"
        className={ALERT_AMBER_CLASS}
      >
        <AlertDescription className="text-amber-800">
          <div className="flex items-start justify-between gap-4 flex-wrap">
            <div>
              <strong>{heading}</strong>
              <p className="mt-1 text-sm">{body}</p>
            </div>
            <Button
              size="sm"
              onClick={() => router.push(`/quotes/${quote.id}/edit`)}
            >
              Review Line Items
            </Button>
          </div>
        </AlertDescription>
      </Alert>
    );
  }

  return null;
}
