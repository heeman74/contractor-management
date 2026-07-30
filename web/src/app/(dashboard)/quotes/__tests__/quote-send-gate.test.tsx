import React from "react";
import { render, screen } from "@testing-library/react";
import type { Quote, QuoteLineItem } from "@/types/api";
import { QuoteStatusAlerts } from "../[id]/_components/quote-status-alerts";

const mockPush = jest.fn();

jest.mock("next/navigation", () => ({
  useRouter: () => ({ push: mockPush }),
}));

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

function makeQuote(overrides: Partial<Quote> = {}): Quote {
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
    line_items: [],
    subtotal: "0",
    discount_amount: "0",
    tax_amount: "0",
    total: "0",
    version: 1,
    created_at: "2026-07-01T00:00:00Z",
    updated_at: "2026-07-01T00:00:00Z",
    ...overrides,
  };
}

// ---------------------------------------------------------------------------

describe("blocked send alert", () => {
  const noop = () => {};

  it("renders the singular body for one unreviewed AI line", () => {
    const quote = makeQuote({
      line_items: [makeLineItem({ ai_origin: true, review_state: "unreviewed" })],
    });
    render(<QuoteStatusAlerts quote={quote} onRevise={noop} onExtendExpiry={noop} />);

    expect(screen.getByTestId("send-blocked-alert")).toHaveTextContent(
      "Review the AI-suggested line items before sending"
    );
    expect(
      screen.getByText(/^1 suggested line hasn't been accepted or edited yet\./)
    ).toBeInTheDocument();
  });

  it("renders the plural body for three unreviewed AI lines", () => {
    const quote = makeQuote({
      line_items: [
        makeLineItem({ id: "l1", ai_origin: true, review_state: "unreviewed" }),
        makeLineItem({ id: "l2", ai_origin: true, review_state: "unreviewed" }),
        makeLineItem({ id: "l3", ai_origin: true, review_state: "unreviewed" }),
      ],
    });
    render(<QuoteStatusAlerts quote={quote} onRevise={noop} onExtendExpiry={noop} />);

    expect(
      screen.getByText(/^3 suggested lines haven't been accepted or edited yet\./)
    ).toBeInTheDocument();
  });

  it("renders no alert once every AI line is accepted or edited", () => {
    const quote = makeQuote({
      line_items: [
        makeLineItem({ id: "l1", ai_origin: true, review_state: "accepted" }),
        makeLineItem({ id: "l2", ai_origin: true, review_state: "edited" }),
      ],
    });
    render(<QuoteStatusAlerts quote={quote} onRevise={noop} onExtendExpiry={noop} />);

    expect(screen.queryByTestId("send-blocked-alert")).not.toBeInTheDocument();
  });

  it("renders no alert for a draft quote with no AI lines at all", () => {
    const quote = makeQuote({ line_items: [makeLineItem({ ai_origin: false })] });
    render(<QuoteStatusAlerts quote={quote} onRevise={noop} onExtendExpiry={noop} />);

    expect(screen.queryByTestId("send-blocked-alert")).not.toBeInTheDocument();
  });

  it("still renders the declined alert (regression)", () => {
    const quote = makeQuote({ status: "declined", decline_reason: "Too expensive" });
    render(<QuoteStatusAlerts quote={quote} onRevise={noop} onExtendExpiry={noop} />);

    expect(screen.getByText("Declined by client")).toBeInTheDocument();
    expect(screen.queryByTestId("send-blocked-alert")).not.toBeInTheDocument();
  });

  it("still renders the expired alert with the extracted amber class (regression)", () => {
    const quote = makeQuote({ status: "expired", expiry_date: "2026-01-01" });
    render(<QuoteStatusAlerts quote={quote} onRevise={noop} onExtendExpiry={noop} />);

    expect(screen.getByText("This quote expired on")).toBeInTheDocument();
    expect(screen.queryByTestId("send-blocked-alert")).not.toBeInTheDocument();
  });

  it("links the action button to the quote's edit route", () => {
    const quote = makeQuote({
      line_items: [makeLineItem({ ai_origin: true, review_state: "unreviewed" })],
    });
    render(<QuoteStatusAlerts quote={quote} onRevise={noop} onExtendExpiry={noop} />);

    screen.getByRole("button", { name: "Review Line Items" }).click();
    expect(mockPush).toHaveBeenCalledWith(`/quotes/${quote.id}/edit`);
  });
});
