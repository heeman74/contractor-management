import {
  computeLineTotal,
  computeQuoteTotals,
  type QuoteFormValues,
} from "../_lib/quote-form";

interface QuotePreviewProps {
  values: QuoteFormValues;
  revisionNumber?: number;
}

export function QuotePreview({ values, revisionNumber = 1 }: QuotePreviewProps) {
  const { subtotal, discountAmount, taxAmount, total } =
    computeQuoteTotals(values);

  return (
    <div className="bg-white p-8 shadow-sm rounded-xl max-w-3xl mx-auto">
      {/* Header */}
      <div className="flex items-start justify-between mb-8">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">QUOTE</h2>
          <p className="text-sm text-gray-500 mt-1">v{revisionNumber}</p>
        </div>
        <div className="text-right text-sm text-gray-600">
          <p className="font-semibold text-gray-800">Your Company Name</p>
          {values.expiry_date && (
            <p className="mt-1 text-xs text-gray-400">
              Expires: {new Date(values.expiry_date).toLocaleDateString()}
            </p>
          )}
        </div>
      </div>

      {/* Line items table */}
      <table className="w-full mb-6 text-sm">
        <thead>
          <tr className="border-b-2 border-gray-200">
            <th className="text-left py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">
              Type
            </th>
            <th className="text-left py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">
              Description
            </th>
            <th className="text-right py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">
              Qty
            </th>
            <th className="text-left py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">
              Unit
            </th>
            <th className="text-right py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">
              Unit Price
            </th>
            <th className="text-right py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">
              Total
            </th>
          </tr>
        </thead>
        <tbody>
          {values.line_items.map((item, idx) => (
            <tr key={idx} className="border-b border-gray-100">
              <td className="py-2 text-xs capitalize text-gray-600">
                {item.item_type}
              </td>
              <td className="py-2 text-sm text-gray-700">{item.description}</td>
              <td className="py-2 font-mono text-right text-gray-900">
                {item.quantity}
              </td>
              <td className="py-2 text-sm text-gray-500">{item.unit}</td>
              <td className="py-2 font-mono text-right text-gray-900">
                ${Number(item.unit_price).toFixed(2)}
              </td>
              <td className="py-2 font-mono text-right text-gray-900">
                ${computeLineTotal(item).toFixed(2)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {/* Financial summary */}
      <div className="space-y-1 max-w-xs ml-auto">
        <div className="flex justify-between text-sm text-gray-600">
          <span>Subtotal</span>
          <span className="font-mono">${subtotal.toFixed(2)}</span>
        </div>
        {discountAmount > 0 && (
          <div className="flex justify-between text-sm text-gray-600">
            <span>
              Discount
              {values.discount_type === "percent"
                ? ` (${values.discount_value}%)`
                : ""}
            </span>
            <span className="font-mono text-red-600">
              -${discountAmount.toFixed(2)}
            </span>
          </div>
        )}
        <div className="flex justify-between text-sm text-gray-600">
          <span>Tax ({values.tax_rate}%)</span>
          <span className="font-mono">${taxAmount.toFixed(2)}</span>
        </div>
        <div className="flex justify-between text-base font-bold text-gray-900 pt-1 border-t">
          <span>Total</span>
          <span className="font-mono">${total.toFixed(2)}</span>
        </div>
      </div>

      {/* Admin notes (preview only for admin) */}
      {values.admin_notes && (
        <div className="mt-6 border-t pt-4">
          <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-1">
            Admin Notes
          </p>
          <p className="text-sm text-gray-600 whitespace-pre-wrap">
            {values.admin_notes}
          </p>
        </div>
      )}
    </div>
  );
}
