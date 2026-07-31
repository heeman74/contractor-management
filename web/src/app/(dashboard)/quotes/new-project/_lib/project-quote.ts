// Pure helpers for the "New Project Quote" builder: a project-level quote is a
// quote with no job/scope, a title (the future project name), and line items
// grouped into field sections. On approval the backend turns it into a project
// with one job per field.

export type ProjectQuoteItemType = "labor" | "material";

export interface ProjectQuoteItem {
  /** Local-only key for React lists. */
  key: string;
  item_type: ProjectQuoteItemType;
  description: string;
  quantity: string;
  unit: string;
  unit_price: string;
}

export interface ProjectQuoteFieldSection {
  /** Local-only key for React lists. */
  key: string;
  /** The trade/field for this section — becomes a job's trade_type. */
  field: string;
  items: ProjectQuoteItem[];
}

export interface ProjectQuotePayloadItem {
  item_type: ProjectQuoteItemType;
  description: string;
  quantity: string;
  unit: string;
  unit_price: string;
  sort_order: number;
  field: string;
}

export interface ProjectQuotePayload {
  title: string;
  line_items: ProjectQuotePayloadItem[];
}

/**
 * The default unit for a line-item type: labor is billed by the hour, material
 * by the each. Used to seed new rows and to swap the unit when the type changes
 * (so a material line never reads "hr").
 */
export function defaultUnitFor(type: ProjectQuoteItemType): string {
  return type === "labor" ? "hr" : "ea";
}

/** Column label for the price input — labor is a rate, material a unit price. */
export function priceLabelFor(type: ProjectQuoteItemType): string {
  return type === "labor" ? "Rate ($/hr)" : "Unit price";
}

/** Column label for the quantity input — hours for labor, a count for material. */
export function quantityLabelFor(type: ProjectQuoteItemType): string {
  return type === "labor" ? "Hours" : "Qty";
}

export function emptyItem(key: string): ProjectQuoteItem {
  return {
    key,
    item_type: "labor",
    description: "",
    quantity: "1",
    unit: defaultUnitFor("labor"),
    unit_price: "0",
  };
}

export function emptyFieldSection(key: string, itemKey: string): ProjectQuoteFieldSection {
  return { key, field: "", items: [emptyItem(itemKey)] };
}

export function lineTotal(item: { quantity: string; unit_price: string }): number {
  return (Number(item.quantity) || 0) * (Number(item.unit_price) || 0);
}

export function sectionTotal(section: ProjectQuoteFieldSection): number {
  return section.items.reduce((sum, item) => sum + lineTotal(item), 0);
}

export function quoteTotal(sections: ProjectQuoteFieldSection[]): number {
  return sections.reduce((sum, section) => sum + sectionTotal(section), 0);
}

/**
 * Flatten field sections into the `/quotes/` create payload. `field` is carried
 * on every item and `sort_order` is a single sequence across all sections so
 * the backend preserves section order when grouping into jobs. Items with a
 * blank description are dropped; a section's field falls back to "General".
 */
export function buildProjectQuotePayload(
  title: string,
  sections: ProjectQuoteFieldSection[]
): ProjectQuotePayload {
  const line_items: ProjectQuotePayloadItem[] = [];
  let sortOrder = 0;
  for (const section of sections) {
    const field = section.field.trim() || "General";
    for (const item of section.items) {
      if (!item.description.trim()) continue;
      line_items.push({
        item_type: item.item_type,
        description: item.description.trim(),
        quantity: item.quantity || "0",
        unit: item.unit.trim() || "ea",
        unit_price: item.unit_price || "0",
        sort_order: sortOrder,
        field,
      });
      sortOrder += 1;
    }
  }
  return { title: title.trim(), line_items };
}

export interface ProjectQuoteValidation {
  ok: boolean;
  error?: string;
}

export function validateProjectQuote(
  title: string,
  sections: ProjectQuoteFieldSection[]
): ProjectQuoteValidation {
  if (!title.trim()) return { ok: false, error: "Enter a project title." };
  const payload = buildProjectQuotePayload(title, sections);
  if (payload.line_items.length === 0) {
    return { ok: false, error: "Add at least one line item with a description." };
  }
  const missingField = sections.some(
    (s) => !s.field.trim() && s.items.some((i) => i.description.trim())
  );
  if (missingField) return { ok: false, error: "Name the field/trade for each section." };
  return { ok: true };
}
