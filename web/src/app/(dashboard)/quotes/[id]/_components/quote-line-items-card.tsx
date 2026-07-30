import { Fragment } from "react";
import { Bot } from "lucide-react";
import type { QuoteLineItem, Quote } from "@/types/api";
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
import { ConfidenceChip } from "../edit/_components/confidence-chip";
import { REVIEW_MARKER, REVIEW_MARKER_CLASS, BASIS_WITHHELD_CAPTION } from "../edit/_lib/confidence-band";
import { aiLineCount, AI_DISCLOSURE_NOTE } from "../_lib/review-state";

const HEADER_CLASS =
  "text-xs font-semibold text-gray-500 uppercase tracking-wide";
const CELL_CLASS = "py-2 px-4";
const LINE_ITEMS_COLUMN_COUNT = 6;

/**
 * The read-only counterpart to the editor's AI sub-row: same anatomy (band
 * chip, review marker, basis), minus the `Accept` button and minus the
 * unreviewed-row tint — review happens in the editor, not here.
 */
function AiLineSubRow({ item, index }: { item: QuoteLineItem; index: number }) {
  const markerClass =
    item.review_state === "unreviewed"
      ? REVIEW_MARKER_CLASS.unreviewed
      : REVIEW_MARKER_CLASS.reviewed;

  return (
    <TableRow data-testid={`ai-line-sub-row-${index}`}>
      <TableCell
        colSpan={LINE_ITEMS_COLUMN_COUNT}
        className={`${CELL_CLASS} whitespace-normal`}
      >
        <div className="flex items-center gap-2 flex-wrap">
          <Bot className="h-3 w-3 text-foreground/70" />
          <ConfidenceChip band={item.confidence_band} index={index} />
          <span data-testid={`review-marker-${index}`} className={markerClass}>
            {REVIEW_MARKER[item.review_state]}
          </span>
        </div>
        {item.basis === null ? (
          <p className="mt-1 text-xs text-gray-500">{BASIS_WITHHELD_CAPTION}</p>
        ) : (
          <p data-testid={`line-basis-${index}`} className="mt-1 text-xs text-gray-500">
            {item.basis}
          </p>
        )}
      </TableCell>
    </TableRow>
  );
}

export function QuoteLineItemsCard({ quote }: { quote: Quote }) {
  const hasAiLines = aiLineCount(quote.line_items) > 0;

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
              {quote.line_items.map((item, index) => (
                <Fragment key={item.id}>
                  <TableRow>
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
                  {item.ai_origin && <AiLineSubRow item={item} index={index} />}
                </Fragment>
              ))}
            </TableBody>
          </Table>
        )}

        <div className="mt-4 border-t pt-4">
          <QuoteFinancialSummary quote={quote} />
        </div>

        {hasAiLines && (
          <p data-testid="quote-ai-disclosure" className="mt-4 text-xs text-gray-500">
            {AI_DISCLOSURE_NOTE}
          </p>
        )}
      </CardContent>
    </Card>
  );
}
