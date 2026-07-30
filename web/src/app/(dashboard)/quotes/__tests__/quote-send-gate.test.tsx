import React from "react";
import { render, screen, renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { toast } from "sonner";
import { ApiError } from "@/lib/api-client";
import type { Quote, QuoteLineItem } from "@/types/api";
import {
  QuoteStatusAlerts,
  SEND_BLOCKED_ALERT_ID,
} from "../[id]/_components/quote-status-alerts";
import { QuoteActionsCard } from "../[id]/_components/quote-actions-card";
import { useQuoteDetail } from "../[id]/_hooks/use-quote-detail";

const mockPush = jest.fn();
const mockDispatch = jest.fn();
const mockApiGet = jest.fn();
const mockApiPost = jest.fn();

jest.mock("next/navigation", () => ({
  useRouter: () => ({ push: mockPush }),
}));

jest.mock("@/store/hooks", () => ({
  useAppDispatch: () => mockDispatch,
}));

jest.mock("sonner", () => ({
  toast: { success: jest.fn(), error: jest.fn(), loading: jest.fn(), dismiss: jest.fn() },
}));

jest.mock("@/lib/api-client", () => ({
  ...jest.requireActual("@/lib/api-client"),
  apiGet: (...args: unknown[]) => mockApiGet(...args),
  apiPost: (...args: unknown[]) => mockApiPost(...args),
}));

const mockToastError = toast.error as jest.Mock;
const mockToastSuccess = toast.success as jest.Mock;

const SEND_BLOCKED_DETAIL =
  "This quote has AI-suggested line items that have not been reviewed. Accept or edit every suggested line before sending.";

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

// ---------------------------------------------------------------------------

describe("send button gating", () => {
  const cardProps = {
    job: undefined,
    isPdfDownloading: false,
    isGeneratingInvoice: false,
    onSend: jest.fn(),
    onEdit: jest.fn(),
    onRevise: jest.fn(),
    onExtendExpiry: jest.fn(),
    onDownloadPdf: jest.fn(),
    onGenerateInvoice: jest.fn(),
  };

  it("disables Send Quote with aria-describedby pointing at the alert when a line is unreviewed", () => {
    const quote = makeQuote({
      line_items: [makeLineItem({ ai_origin: true, review_state: "unreviewed" })],
    });
    render(<QuoteActionsCard quote={quote} isSending={false} {...cardProps} />);

    const sendButton = screen.getByRole("button", { name: "Send Quote" });
    expect(sendButton).toBeDisabled();
    expect(sendButton).toHaveAttribute("aria-describedby", SEND_BLOCKED_ALERT_ID);
  });

  it("enables Send Quote with no aria-describedby when nothing is unreviewed", () => {
    const quote = makeQuote({ line_items: [makeLineItem({ ai_origin: false })] });
    render(<QuoteActionsCard quote={quote} isSending={false} {...cardProps} />);

    const sendButton = screen.getByRole("button", { name: "Send Quote" });
    expect(sendButton).not.toBeDisabled();
    expect(sendButton).not.toHaveAttribute("aria-describedby");
  });

  it("keeps the shipped isSending disable independent of the unreviewed gate", () => {
    const quote = makeQuote({ line_items: [makeLineItem({ ai_origin: false })] });
    render(<QuoteActionsCard quote={quote} isSending={true} {...cardProps} />);

    const sendButton = screen.getByRole("button", { name: "Send Quote" });
    expect(sendButton).toBeDisabled();
    expect(sendButton).not.toHaveAttribute("aria-describedby");
  });

  function createWrapper() {
    const queryClient = new QueryClient({
      defaultOptions: { queries: { retry: false } },
    });
    const wrapper = ({ children }: { children: React.ReactNode }) => (
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    );
    return wrapper;
  }

  beforeEach(() => {
    mockApiGet.mockReset().mockResolvedValue(makeQuote());
    mockApiPost.mockReset();
    mockToastError.mockReset();
    mockToastSuccess.mockReset();
    mockDispatch.mockReset();
  });

  it("fires a toast with the server's 409 detail verbatim on a rejected send", async () => {
    mockApiPost.mockRejectedValue(new ApiError(409, SEND_BLOCKED_DETAIL));
    const { result } = renderHook(() => useQuoteDetail("quote-1"), {
      wrapper: createWrapper(),
    });
    await waitFor(() => expect(result.current.quote).toBeDefined());

    result.current.sendQuote();

    await waitFor(() => expect(mockToastError).toHaveBeenCalled());
    expect(mockToastError).toHaveBeenCalledWith(SEND_BLOCKED_DETAIL, {
      duration: Infinity,
    });
  });

  it("fires the shipped generic message for a non-ApiError rejection", async () => {
    mockApiPost.mockRejectedValue(new Error("network down"));
    const { result } = renderHook(() => useQuoteDetail("quote-1"), {
      wrapper: createWrapper(),
    });
    await waitFor(() => expect(result.current.quote).toBeDefined());

    result.current.sendQuote();

    await waitFor(() => expect(mockToastError).toHaveBeenCalled());
    expect(mockToastError).toHaveBeenCalledWith("Failed to send quote. Try again.", {
      duration: Infinity,
    });
  });

  it("leaves the success path unchanged", async () => {
    mockApiPost.mockResolvedValue(makeQuote({ status: "sent" }));
    const { result } = renderHook(() => useQuoteDetail("quote-1"), {
      wrapper: createWrapper(),
    });
    await waitFor(() => expect(result.current.quote).toBeDefined());

    result.current.sendQuote();

    await waitFor(() => expect(mockToastSuccess).toHaveBeenCalled());
    expect(mockToastSuccess).toHaveBeenCalledWith("Quote sent to client");
    expect(mockToastError).not.toHaveBeenCalled();
  });
});
