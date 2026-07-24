import type { InvoiceLineItem, ItemType } from "@/types/api";

export { isInvoiceOverdue, invoiceBalance } from "../../_lib/invoice-status";

export interface EditableLineItem {
  id: string;
  item_type: ItemType;
  description: string;
  quantity: string;
  unit: string;
  unit_price: string;
  sort_order: number;
}

export function toEditableLineItems(
  lineItems: InvoiceLineItem[]
): EditableLineItem[] {
  return lineItems.map((item) => ({
    id: item.id,
    item_type: item.item_type,
    description: item.description,
    quantity: item.quantity,
    unit: item.unit,
    unit_price: item.unit_price,
    sort_order: item.sort_order,
  }));
}
