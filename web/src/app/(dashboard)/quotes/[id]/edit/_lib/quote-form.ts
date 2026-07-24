import { z } from "zod";
import type { Quote } from "@/types/api";

// ---------------------------------------------------------------------------
// Schema & types
// ---------------------------------------------------------------------------

export const lineItemSchema = z.object({
  item_type: z.enum(["labor", "material"]),
  description: z.string().min(1, "Required").max(500),
  quantity: z.string().refine((v) => Number(v) > 0, "Must be > 0"),
  unit: z.string().min(1, "Required").max(50),
  unit_price: z.string().refine((v) => Number(v) >= 0, "Must be >= 0"),
  sort_order: z.number(),
});

export const quoteFormSchema = z.object({
  line_items: z.array(lineItemSchema).min(1, "At least one line item required"),
  tax_rate: z
    .string()
    .refine((v) => {
      const n = Number(v);
      return n >= 0 && n <= 100;
    }, "0-100"),
  discount_type: z.enum(["percent", "fixed"]).nullable(),
  discount_value: z.string(),
  expiry_date: z.string().nullable(),
  admin_notes: z.string().nullable(),
});

export type QuoteFormValues = z.infer<typeof quoteFormSchema>;
export type QuoteLineItemValues = QuoteFormValues["line_items"][number];

// ---------------------------------------------------------------------------
// Defaults & factories
// ---------------------------------------------------------------------------

export function createEmptyLineItem(sortOrder: number): QuoteLineItemValues {
  return {
    item_type: "labor",
    description: "",
    quantity: "1",
    unit: "hr",
    unit_price: "0",
    sort_order: sortOrder,
  };
}

export const DEFAULT_FORM_VALUES: QuoteFormValues = {
  line_items: [createEmptyLineItem(0)],
  tax_rate: "0",
  discount_type: null,
  discount_value: "0",
  expiry_date: null,
  admin_notes: null,
};

// ---------------------------------------------------------------------------
// Mapping to/from the API
// ---------------------------------------------------------------------------

export function mapQuoteToFormValues(quote: Quote): QuoteFormValues {
  return {
    line_items: quote.line_items.map((item) => ({
      item_type: item.item_type,
      description: item.description,
      quantity: item.quantity,
      unit: item.unit,
      unit_price: item.unit_price,
      sort_order: item.sort_order,
    })),
    tax_rate: quote.tax_rate,
    discount_type: quote.discount_type,
    discount_value: quote.discount_value,
    expiry_date: quote.expiry_date,
    admin_notes: quote.admin_notes,
  };
}

export function buildQuotePayload(data: QuoteFormValues) {
  return {
    tax_rate: data.tax_rate,
    discount_type: data.discount_type,
    discount_value: data.discount_value,
    expiry_date: data.expiry_date,
    admin_notes: data.admin_notes,
    line_items: data.line_items.map((item, index) => ({
      item_type: item.item_type,
      description: item.description,
      quantity: item.quantity,
      unit: item.unit,
      unit_price: item.unit_price,
      sort_order: index,
    })),
  };
}

// ---------------------------------------------------------------------------
// Financial calculations (single source of truth)
// ---------------------------------------------------------------------------

export function computeLineTotal(item: {
  quantity: string;
  unit_price: string;
}): number {
  return (Number(item.quantity) || 0) * (Number(item.unit_price) || 0);
}

export interface QuoteTotals {
  subtotal: number;
  discountAmount: number;
  taxAmount: number;
  total: number;
}

export function computeQuoteTotals(values: QuoteFormValues): QuoteTotals {
  const subtotal = values.line_items.reduce(
    (sum, item) => sum + computeLineTotal(item),
    0
  );

  const discountValue = Number(values.discount_value);
  const discountAmount =
    values.discount_type === "percent"
      ? (subtotal * discountValue) / 100
      : values.discount_type === "fixed"
        ? Math.min(discountValue, subtotal)
        : 0;

  const taxAmount = ((subtotal - discountAmount) * Number(values.tax_rate)) / 100;
  const total = subtotal - discountAmount + taxAmount;

  return { subtotal, discountAmount, taxAmount, total };
}
