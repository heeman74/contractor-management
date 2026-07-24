import type { Quote } from "@/types/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { formatCurrency } from "@/lib/format";
import { QuoteFinancialSummary } from "./quote-financial-summary";

const HEADER_CLASS =
  "text-xs font-semibold text-gray-500 uppercase tracking-wide";
const CELL_CLASS = "py-2 px-4";

export function QuoteLineItemsCard({ quote }: { quote: Quote }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Line Items</CardTitle>
      </CardHeader>
      <CardContent>
        {quote.line_items.length === 0 ? (
          <p className="text-sm text-gray-500">No line items added.</p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className={HEADER_CLASS}>Type</TableHead>
                <TableHead className={HEADER_CLASS}>Description</TableHead>
                <TableHead className={`${HEADER_CLASS} text-right`}>Qty</TableHead>
                <TableHead className={HEADER_CLASS}>Unit</TableHead>
                <TableHead className={`${HEADER_CLASS} text-right`}>
                  Unit Price
                </TableHead>
                <TableHead className={`${HEADER_CLASS} text-right`}>
                  Total
                </TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {quote.line_items.map((item) => (
                <TableRow key={item.id}>
                  <TableCell className={`${CELL_CLASS} text-xs capitalize text-gray-600`}>
                    {item.item_type}
                  </TableCell>
                  <TableCell className={`${CELL_CLASS} text-sm text-gray-700`}>
                    {item.description}
                  </TableCell>
                  <TableCell className={`${CELL_CLASS} font-mono text-sm text-gray-900 text-right`}>
                    {item.quantity}
                  </TableCell>
                  <TableCell className={`${CELL_CLASS} text-sm text-gray-500`}>
                    {item.unit}
                  </TableCell>
                  <TableCell className={`${CELL_CLASS} font-mono text-sm text-gray-900 text-right`}>
                    {formatCurrency(item.unit_price)}
                  </TableCell>
                  <TableCell className={`${CELL_CLASS} font-mono text-sm text-gray-900 text-right`}>
                    {formatCurrency(Number(item.quantity) * Number(item.unit_price))}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}

        <div className="mt-4 border-t pt-4">
          <QuoteFinancialSummary quote={quote} />
        </div>
      </CardContent>
    </Card>
  );
}
