// Pure helpers for the "Create Change Order" builder. A change order is a
// project-scoped quote (quote_kind='change_order') raised from an in-progress
// job. On approval it adds a new job or extends the originating job, so the
// builder collects a reason, a target, an optional schedule impact, and line
// items — no field grouping (a change order is one unit of work).

export type ChangeOrderItemType = "labor" | "material";
export type ChangeOrderTarget = "new_job" | "existing_job";

export interface ChangeOrderItem {
  key: string;
  item_type: ChangeOrderItemType;
  description: string;
  quantity: string;
  unit: string;
  unit_price: string;
}

export interface ChangeOrderForm {
  reason: string;
  co_target: ChangeOrderTarget;
  schedule_impact_days: string;
  items: ChangeOrderItem[];
}

export interface ChangeOrderPayloadItem {
  item_type: ChangeOrderItemType;
  description: string;
  quantity: string;
  unit: string;
  unit_price: string;
  sort_order: number;
}

export interface ChangeOrderPayload {
  quote_kind: "change_order";
  project_id: string;
  originating_job_id: string;
  co_target: ChangeOrderTarget;
  change_reason: string;
  schedule_impact_days?: number;
  line_items: ChangeOrderPayloadItem[];
}

export function emptyChangeOrderItem(key: string): ChangeOrderItem {
  return { key, item_type: "labor", description: "", quantity: "1", unit: "hr", unit_price: "0" };
}

export function emptyChangeOrderForm(itemKey: string): ChangeOrderForm {
  return {
    reason: "",
    co_target: "new_job",
    schedule_impact_days: "",
    items: [emptyChangeOrderItem(itemKey)],
  };
}

export function lineTotal(item: { quantity: string; unit_price: string }): number {
  return (Number(item.quantity) || 0) * (Number(item.unit_price) || 0);
}

export function changeOrderTotal(items: ChangeOrderItem[]): number {
  return items.reduce((sum, item) => sum + lineTotal(item), 0);
}

/**
 * Build the `/quotes/` create payload for a change order. Blank-description rows
 * are dropped; schedule impact is included only when a positive number.
 */
export function buildChangeOrderPayload(
  projectId: string,
  originatingJobId: string,
  form: ChangeOrderForm
): ChangeOrderPayload {
  const line_items: ChangeOrderPayloadItem[] = form.items
    .filter((item) => item.description.trim())
    .map((item, index) => ({
      item_type: item.item_type,
      description: item.description.trim(),
      quantity: item.quantity || "0",
      unit: item.unit.trim() || "ea",
      unit_price: item.unit_price || "0",
      sort_order: index,
    }));

  const days = form.schedule_impact_days.trim();
  const payload: ChangeOrderPayload = {
    quote_kind: "change_order",
    project_id: projectId,
    originating_job_id: originatingJobId,
    co_target: form.co_target,
    change_reason: form.reason.trim(),
    line_items,
  };
  if (days !== "" && Number(days) > 0) {
    payload.schedule_impact_days = Number(days);
  }
  return payload;
}

export interface ChangeOrderValidation {
  ok: boolean;
  error?: string;
}

export function validateChangeOrder(form: ChangeOrderForm): ChangeOrderValidation {
  if (!form.reason.trim()) {
    return { ok: false, error: "Describe the reason for this change order." };
  }
  if (form.items.every((item) => !item.description.trim())) {
    return { ok: false, error: "Add at least one line item with a description." };
  }
  return { ok: true };
}
