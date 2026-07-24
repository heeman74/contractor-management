import type { Invoice } from "@/types/api";
import { formatCurrency } from "@/lib/format";

/** Subtotal / discount / tax / total footer for the invoice line-items table. */
export function InvoiceTotals({ invoice }: { invoice: Invoice }) {
  const hasDiscount = Number(invoice.discount_amount) > 0;
  const discountLabel =
    invoice.discount_type === "percent"
      ? `Discount (${Number(invoice.discount_value)}%)`
      : "Discount";

  return (
    <div className="mt-4 border-t pt-4 space-y-1">
      <div className="flex justify-between text-sm">
        <span className="text-gray-500">Subtotal</span>
        <span className="font-mono text-gray-900">
          {formatCurrency(invoice.subtotal)}
        </span>
      </div>

      {hasDiscount && (
        <div className="flex justify-between text-sm">
          <span className="text-gray-500">{discountLabel}</span>
          <span className="font-mono text-gray-900">
            -{formatCurrency(invoice.discount_amount)}
          </span>
        </div>
      )}

      <div className="flex justify-between text-sm">
        <span className="text-gray-500">Tax ({Number(invoice.tax_rate)}%)</span>
        <span className="font-mono text-gray-900">
          {formatCurrency(invoice.tax_amount)}
        </span>
      </div>

      <div className="flex justify-between text-sm font-semibold border-t pt-2 mt-2">
        <span className="text-gray-900">Total</span>
        <span className="font-mono text-gray-900">
          {formatCurrency(invoice.total)}
        </span>
      </div>
    </div>
  );
}
