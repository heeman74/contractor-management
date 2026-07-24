import type { QuoteTotals } from "../_lib/quote-form";

function TotalItem({
  label,
  amount,
  accentClass = "text-gray-900",
  emphasized = false,
}: {
  label: string;
  amount: number;
  accentClass?: string;
  emphasized?: boolean;
}) {
  return (
    <div
      className={`flex items-center gap-1.5 ${emphasized ? "border-l border-gray-200 pl-6" : ""}`}
    >
      <span className="text-xs text-gray-500 uppercase tracking-wide">
        {label}
      </span>
      <span
        className={`font-mono font-semibold ${emphasized ? "text-base" : "text-sm"} ${accentClass}`}
      >
        {amount < 0 ? "-" : ""}${Math.abs(amount).toFixed(2)}
      </span>
    </div>
  );
}

export function StickyTotalsBar({
  subtotal,
  discountAmount,
  taxAmount,
  total,
}: QuoteTotals) {
  return (
    <div className="fixed bottom-0 left-0 right-0 bg-white border-t border-gray-200 px-6 py-3 z-40">
      <div className="flex items-center justify-end gap-6 max-w-screen-2xl mx-auto">
        <TotalItem label="Subtotal" amount={subtotal} />
        {discountAmount > 0 && (
          <TotalItem
            label="Discount"
            amount={-discountAmount}
            accentClass="text-red-600"
          />
        )}
        <TotalItem label="Tax" amount={taxAmount} />
        <TotalItem label="Total" amount={total} emphasized />
      </div>
    </div>
  );
}
