import type { Invoice } from "@/types/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { formatCurrency } from "@/lib/format";
import { InvoiceTotals } from "./invoice-totals";
import type { EditableLineItem } from "../_lib/invoice-line-items";

const HEADER_CLASS =
  "text-xs font-semibold text-gray-500 uppercase tracking-wide";
const CELL_CLASS = "py-2 px-4";

function ReadOnlyLineItems({ invoice }: { invoice: Invoice }) {
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead className={HEADER_CLASS}>Type</TableHead>
          <TableHead className={HEADER_CLASS}>Description</TableHead>
          <TableHead className={`${HEADER_CLASS} text-right`}>Qty</TableHead>
          <TableHead className={HEADER_CLASS}>Unit</TableHead>
          <TableHead className={`${HEADER_CLASS} text-right`}>Unit Price</TableHead>
          <TableHead className={`${HEADER_CLASS} text-right`}>Total</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {invoice.line_items.map((item) => (
          <TableRow key={item.id}>
            <TableCell className={`${CELL_CLASS} text-sm text-gray-600 capitalize`}>
              {item.item_type}
            </TableCell>
            <TableCell className={`${CELL_CLASS} text-sm text-gray-700`}>
              {item.description}
            </TableCell>
            <TableCell className={`${CELL_CLASS} font-mono text-sm text-gray-900 text-right`}>
              {Number(item.quantity).toFixed(2)}
            </TableCell>
            <TableCell className={`${CELL_CLASS} text-sm text-gray-600`}>
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
  );
}

interface EditableLineItemsProps {
  items: EditableLineItem[];
  onUpdate: (index: number, field: keyof EditableLineItem, value: string) => void;
  onSave: () => void;
  onFinalize: () => void;
  isSaving: boolean;
  isFinalizing: boolean;
}

function EditableLineItems({
  items,
  onUpdate,
  onSave,
  onFinalize,
  isSaving,
  isFinalizing,
}: EditableLineItemsProps) {
  return (
    <div className="space-y-3">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead className={HEADER_CLASS}>Description</TableHead>
            <TableHead className={`${HEADER_CLASS} text-right`}>Qty</TableHead>
            <TableHead className={HEADER_CLASS}>Unit</TableHead>
            <TableHead className={`${HEADER_CLASS} text-right`}>Unit Price</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {items.map((item, index) => (
            <TableRow key={item.id}>
              <TableCell className="py-1 px-2">
                <Input
                  value={item.description}
                  onChange={(e) => onUpdate(index, "description", e.target.value)}
                  className="h-8 text-sm"
                />
              </TableCell>
              <TableCell className="py-1 px-2">
                <Input
                  type="number"
                  value={item.quantity}
                  onChange={(e) => onUpdate(index, "quantity", e.target.value)}
                  className="h-8 text-sm text-right w-20"
                />
              </TableCell>
              <TableCell className="py-1 px-2">
                <Input
                  value={item.unit}
                  onChange={(e) => onUpdate(index, "unit", e.target.value)}
                  className="h-8 text-sm w-20"
                />
              </TableCell>
              <TableCell className="py-1 px-2">
                <Input
                  type="number"
                  step="0.01"
                  value={item.unit_price}
                  onChange={(e) => onUpdate(index, "unit_price", e.target.value)}
                  className="h-8 text-sm text-right w-24"
                />
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
      <div className="flex gap-2 justify-end pt-2">
        <Button variant="outline" size="sm" onClick={onSave} disabled={isSaving}>
          Save Changes
        </Button>
        <Button size="sm" onClick={onFinalize} disabled={isFinalizing}>
          Finalize Invoice
        </Button>
      </div>
    </div>
  );
}

interface InvoiceLineItemsCardProps {
  invoice: Invoice;
  isFinalized: boolean;
  editableItems: EditableLineItem[];
  onUpdateItem: (index: number, field: keyof EditableLineItem, value: string) => void;
  onSave: () => void;
  onFinalize: () => void;
  isSaving: boolean;
  isFinalizing: boolean;
}

export function InvoiceLineItemsCard({
  invoice,
  isFinalized,
  editableItems,
  onUpdateItem,
  onSave,
  onFinalize,
  isSaving,
  isFinalizing,
}: InvoiceLineItemsCardProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Line Items</CardTitle>
      </CardHeader>
      <CardContent>
        {isFinalized ? (
          <ReadOnlyLineItems invoice={invoice} />
        ) : (
          <EditableLineItems
            items={editableItems}
            onUpdate={onUpdateItem}
            onSave={onSave}
            onFinalize={onFinalize}
            isSaving={isSaving}
            isFinalizing={isFinalizing}
          />
        )}
        <InvoiceTotals invoice={invoice} />
      </CardContent>
    </Card>
  );
}
