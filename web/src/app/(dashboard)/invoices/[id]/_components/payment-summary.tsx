import type { Invoice } from "@/types/api";
import { cn } from "@/lib/utils";
import { formatCurrency } from "@/lib/format";

interface PaymentSummaryProps {
  invoice: Invoice;
  balance: number;
  isOverdue: boolean;
  /** "inline" = label/value on one row (payment card); "stacked" = label above value (sidebar). */
  layout: "inline" | "stacked";
}

const LABEL_CLASS = "text-xs text-gray-500 uppercase tracking-wide";

export function PaymentSummary({
  invoice,
  balance,
  isOverdue,
  layout,
}: PaymentSummaryProps) {
  const balanceClass = cn(
    "font-mono text-sm",
    isOverdue ? "text-red-700" : "text-gray-900"
  );

  if (layout === "inline") {
    return (
      <div className="space-y-2">
        <div className="flex justify-between items-center">
          <span className={LABEL_CLASS}>Total</span>
          <span className="font-mono text-sm text-gray-900">
            {formatCurrency(invoice.total)}
          </span>
        </div>
        <div className="flex justify-between items-center">
          <span className={LABEL_CLASS}>Paid</span>
          <span className="font-mono text-sm text-green-700">
            {formatCurrency(invoice.amount_paid)}
          </span>
        </div>
        <div className="flex justify-between items-center border-t pt-2">
          <span className={LABEL_CLASS}>Balance</span>
          <span className={balanceClass}>{formatCurrency(balance)}</span>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      <div>
        <p className={LABEL_CLASS}>Total</p>
        <p className="font-mono text-sm text-gray-900">
          {formatCurrency(invoice.total)}
        </p>
      </div>
      <div>
        <p className={LABEL_CLASS}>Paid</p>
        <p className="font-mono text-sm text-green-700">
          {formatCurrency(invoice.amount_paid)}
        </p>
      </div>
      <div className="border-t pt-3">
        <p className={LABEL_CLASS}>Balance</p>
        <p className={balanceClass}>{formatCurrency(balance)}</p>
      </div>
    </div>
  );
}
