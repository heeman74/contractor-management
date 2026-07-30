import React from "react";
import { render, screen } from "@testing-library/react";
import { QUOTE_CONFIDENCE_CHIP, REVIEW_MARKER } from "../[id]/edit/_lib/confidence-band";
import { ConfidenceChip } from "../[id]/edit/_components/confidence-chip";
import {
  buildQuotePayload,
  createEmptyLineItem,
  mapQuoteToFormValues,
} from "../[id]/edit/_lib/quote-form";
import {
  aiLineCount,
  AI_DISCLOSURE_NOTE,
  sendBlockedCopy,
  unreviewedAiLineCount,
  unreviewedBannerCopy,
} from "../[id]/_lib/review-state";
import {
  FINANCE_FLAG_CHIP_CLASS,
  FINANCE_NOTE_CHIP_CLASS,
  FINANCE_OUTLINE_CHIP_CLASS,
} from "@/features/finance/components/FinanceFlagChip";
import type { Quote, QuoteLineItem } from "@/types/api";

function makeLineItem(overrides: Partial<QuoteLineItem> = {}): QuoteLineItem {
  return {
    id: "line-1",
    quote_id: "quote-1",
    item_type: "labor",
    description: "Rough-in plumbing",
    quantity: "4",
    unit: "hr",
    unit_price: "75",
    sort_order: 0,
    field: "Plumbing",
    ai_origin: false,
    review_state: "unreviewed",
    confidence_band: null,
    basis: null,
    ...overrides,
  };
}

function makeQuote(lineItems: QuoteLineItem[]): Quote {
  return {
    id: "quote-1",
    company_id: "company-1",
    job_id: null,
    trade_scope_id: null,
    title: "Kitchen remodel",
    project_id: null,
    status: "draft",
    revision_number: 1,
    tax_rate: "0",
    discount_type: null,
    discount_value: "0",
    expiry_date: null,
    sent_at: null,
    viewed_at: null,
    approved_at: null,
    declined_at: null,
    decline_reason: null,
    decline_detail: null,
    admin_notes: null,
    line_items: lineItems,
    subtotal: "0",
    discount_amount: "0",
    tax_amount: "0",
    total: "0",
    version: 1,
    created_at: "2026-07-01T00:00:00Z",
    updated_at: "2026-07-01T00:00:00Z",
  };
}

describe("confidence band map", () => {
  it("maps high band to Strong history in the outline recipe", () => {
    expect(QUOTE_CONFIDENCE_CHIP.high).toEqual({
      label: "Strong history",
      className: FINANCE_OUTLINE_CHIP_CLASS,
    });
  });

  it("maps medium band to Limited history in the note recipe", () => {
    expect(QUOTE_CONFIDENCE_CHIP.medium).toEqual({
      label: "Limited history",
      className: FINANCE_NOTE_CHIP_CLASS,
    });
  });

  it("maps low band to Thin history in the flag recipe", () => {
    expect(QUOTE_CONFIDENCE_CHIP.low).toEqual({
      label: "Thin history",
      className: FINANCE_FLAG_CHIP_CLASS,
    });
  });

  it("maps every review state to its marker copy", () => {
    expect(REVIEW_MARKER).toEqual({
      unreviewed: "Needs review",
      accepted: "Accepted",
      edited: "AI-originated, user-edited",
    });
  });

  it("renders a labeled chip carrying the mapped class and testid", () => {
    render(<ConfidenceChip band="medium" index={2} />);
    const chip = screen.getByTestId("confidence-chip-2");
    expect(chip).toHaveTextContent("Limited history");
    expect(chip.className).toBe(FINANCE_NOTE_CHIP_CLASS);
  });

  it("renders nothing when the band is null", () => {
    const { container } = render(<ConfidenceChip band={null} index={0} />);
    expect(container).toBeEmptyDOMElement();
  });
});

describe("quote form round trip", () => {
  it("carries id, field and review-state fields off every line in mapQuoteToFormValues", () => {
    const line = makeLineItem({
      id: "line-9",
      field: "Electrical",
      ai_origin: true,
      review_state: "edited",
      confidence_band: "high",
      basis: "median of 5 comparable jobs",
    });
    const values = mapQuoteToFormValues(makeQuote([line]));

    expect(values.line_items[0]).toMatchObject({
      id: "line-9",
      field: "Electrical",
      ai_origin: true,
      review_state: "edited",
      confidence_band: "high",
      basis: "median of 5 comparable jobs",
    });
  });

  it("emits id and field for a mapped line, and omits id for a hand-added line", () => {
    const mapped = mapQuoteToFormValues(makeQuote([makeLineItem({ id: "line-1" })]));
    const created = createEmptyLineItem(1);
    const payload = buildQuotePayload({
      line_items: [mapped.line_items[0], created],
      tax_rate: "0",
      discount_type: null,
      discount_value: "0",
      expiry_date: null,
      admin_notes: null,
    });

    expect(payload.line_items[0]).toMatchObject({ id: "line-1", field: "Plumbing" });
    expect(payload.line_items[1]).not.toHaveProperty("id");
  });

  it("re-indexes sort_order from array position regardless of input order", () => {
    const items = [makeLineItem({ sort_order: 9 }), makeLineItem({ sort_order: 2 })];
    const mapped = mapQuoteToFormValues(makeQuote(items));
    const payload = buildQuotePayload({
      line_items: mapped.line_items,
      tax_rate: "0",
      discount_type: null,
      discount_value: "0",
      expiry_date: null,
      admin_notes: null,
    });

    expect(payload.line_items[0].sort_order).toBe(0);
    expect(payload.line_items[1].sort_order).toBe(1);
  });

  it("emits review_state for every line", () => {
    const mapped = mapQuoteToFormValues(
      makeQuote([makeLineItem({ review_state: "accepted" })])
    );
    const payload = buildQuotePayload({
      line_items: mapped.line_items,
      tax_rate: "0",
      discount_type: null,
      discount_value: "0",
      expiry_date: null,
      admin_notes: null,
    });

    expect(payload.line_items[0].review_state).toBe("accepted");
  });

  it("round-trips both ids and both field values unchanged over a two-line quote", () => {
    const lines = [
      makeLineItem({ id: "line-a", field: "Plumbing" }),
      makeLineItem({ id: "line-b", field: "Electrical" }),
    ];
    const mapped = mapQuoteToFormValues(makeQuote(lines));
    const payload = buildQuotePayload({
      line_items: mapped.line_items,
      tax_rate: "0",
      discount_type: null,
      discount_value: "0",
      expiry_date: null,
      admin_notes: null,
    });

    expect(payload.line_items[0]).toMatchObject({ id: "line-a", field: "Plumbing" });
    expect(payload.line_items[1]).toMatchObject({ id: "line-b", field: "Electrical" });
  });
});

describe("review state helpers", () => {
  it("counts only AI-originated, unreviewed lines", () => {
    const lines = [
      makeLineItem({ ai_origin: true, review_state: "unreviewed" }),
      makeLineItem({ ai_origin: true, review_state: "accepted" }),
      makeLineItem({ ai_origin: false, review_state: "unreviewed" }),
    ];
    expect(unreviewedAiLineCount(lines)).toBe(1);
  });

  it("returns 0 for a quote whose lines are all hand-built", () => {
    const lines = [makeLineItem({ ai_origin: false }), makeLineItem({ ai_origin: false })];
    expect(unreviewedAiLineCount(lines)).toBe(0);
  });

  it("builds the singular unreviewed banner heading", () => {
    expect(unreviewedBannerCopy(1).heading).toBe("1 AI-suggested line still needs review");
  });

  it("builds the plural unreviewed banner heading", () => {
    expect(unreviewedBannerCopy(3).heading).toBe("3 AI-suggested lines still need review");
  });

  it("shares one body string across singular and plural banner copy", () => {
    expect(unreviewedBannerCopy(1).body).toBe(unreviewedBannerCopy(3).body);
  });

  it("builds the singular send-blocked body", () => {
    expect(sendBlockedCopy(1).body).toMatch(
      /^1 suggested line hasn't been accepted or edited yet\./
    );
  });

  it("builds the plural send-blocked body", () => {
    expect(sendBlockedCopy(2).body).toMatch(
      /^2 suggested lines haven't been accepted or edited yet\./
    );
  });

  it("counts every AI-origin line regardless of review state", () => {
    const lines = [
      makeLineItem({ ai_origin: true, review_state: "unreviewed" }),
      makeLineItem({ ai_origin: true, review_state: "accepted" }),
      makeLineItem({ ai_origin: false, review_state: "unreviewed" }),
    ];
    expect(aiLineCount(lines)).toBe(2);
  });

  it("exports the byte-locked AI disclosure sentence", () => {
    expect(AI_DISCLOSURE_NOTE).toBe(
      "AI-suggested from your own completed work — every figure is from your recorded history, never an AI estimate."
    );
  });
});
