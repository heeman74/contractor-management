import { formatCurrency } from "@/lib/format";

export interface QuoteFinancials {
  subtotal: string;
  discount_amount: string;
  discount_type: "percent" | "fixed" | null;
  discount_value: string;
  tax_rate: string;
  tax_amount: string;
  total: string;
}

interface QuoteFinancialSummaryProps {
  quote: QuoteFinancials;
  /** The sidebar card emphasizes the total (bold + larger); the table footer does not. */
  emphasizeTotal?: boolean;
}

export function QuoteFinancialSummary({
  quote,
  emphasizeTotal = false,
}: QuoteFinancialSummaryProps) {
  const hasDiscount = Number(quote.discount_amount) > 0;
  const discountLabel =
    quote.discount_type === "percent"
      ? `Discount (${quote.discount_value}%)`
      : "Discount";

  return (
    <div className={emphasizeTotal ? "space-y-2" : "space-y-1"}>
      <div className="flex justify-between text-sm text-gray-600">
        <span>Subtotal</span>
        <span className="font-mono">{formatCurrency(quote.subtotal)}</span>
      </div>

      {hasDiscount && (
        <div className="flex justify-between text-sm text-gray-600">
          <span>{discountLabel}</span>
          <span className="font-mono text-red-600">
            -{formatCurrency(quote.discount_amount)}
          </span>
        </div>
      )}

      <div className="flex justify-between text-sm text-gray-600">
        <span>Tax ({quote.tax_rate}%)</span>
        <span className="font-mono">{formatCurrency(quote.tax_amount)}</span>
      </div>

      <div
        className={`flex justify-between text-gray-900 pt-1 border-t ${
          emphasizeTotal
            ? "text-base font-bold pt-2"
            : "text-base font-semibold"
        }`}
      >
        <span>Total</span>
        <span className={`font-mono ${emphasizeTotal ? "text-lg" : ""}`}>
          {formatCurrency(quote.total)}
        </span>
      </div>
    </div>
  );
}
