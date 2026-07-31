import {
  buildChangeOrderPayload,
  changeOrderTotal,
  emptyChangeOrderForm,
  validateChangeOrder,
  type ChangeOrderForm,
} from "../change-order";

function form(overrides: Partial<ChangeOrderForm> = {}): ChangeOrderForm {
  return {
    reason: "Rotted subfloor found",
    co_target: "new_job",
    schedule_impact_days: "",
    items: [
      { key: "i0", item_type: "labor", description: "Replace subfloor", quantity: "8", unit: "hr", unit_price: "80" },
    ],
    ...overrides,
  };
}

describe("buildChangeOrderPayload", () => {
  test("produces a change-order quote payload with context + line items", () => {
    const payload = buildChangeOrderPayload("proj-1", "job-1", form());
    expect(payload).toMatchObject({
      quote_kind: "change_order",
      project_id: "proj-1",
      originating_job_id: "job-1",
      co_target: "new_job",
      change_reason: "Rotted subfloor found",
    });
    expect(payload.line_items).toEqual([
      {
        item_type: "labor",
        description: "Replace subfloor",
        quantity: "8",
        unit: "hr",
        unit_price: "80",
        sort_order: 0,
      },
    ]);
    expect(payload.schedule_impact_days).toBeUndefined();
  });

  test("includes a positive schedule impact and drops blank rows", () => {
    const payload = buildChangeOrderPayload(
      "proj-1",
      "job-1",
      form({
        schedule_impact_days: "5",
        items: [
          { key: "i0", item_type: "labor", description: "Real work", quantity: "1", unit: "hr", unit_price: "10" },
          { key: "i1", item_type: "material", description: "   ", quantity: "1", unit: "ea", unit_price: "5" },
        ],
      })
    );
    expect(payload.schedule_impact_days).toBe(5);
    expect(payload.line_items).toHaveLength(1);
  });

  test("omits a zero/blank schedule impact", () => {
    expect(buildChangeOrderPayload("p", "j", form({ schedule_impact_days: "0" })).schedule_impact_days).toBeUndefined();
  });
});

describe("changeOrderTotal", () => {
  test("sums quantity × unit price", () => {
    expect(changeOrderTotal(form().items)).toBe(640);
  });
});

describe("validateChangeOrder", () => {
  test("passes with a reason and a described item", () => {
    expect(validateChangeOrder(form())).toEqual({ ok: true });
  });

  test("requires a reason", () => {
    expect(validateChangeOrder(form({ reason: "  " })).ok).toBe(false);
  });

  test("requires at least one described line item", () => {
    expect(validateChangeOrder(emptyChangeOrderForm("i0")).ok).toBe(false);
  });
});
