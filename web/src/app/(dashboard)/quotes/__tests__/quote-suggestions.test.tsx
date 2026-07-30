import React from "react";
import { render, screen, within, fireEvent } from "@testing-library/react";
import { renderHook, waitFor } from "@testing-library/react";
import { useForm } from "react-hook-form";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { toast } from "sonner";
import { apiPost } from "@/lib/api-client";
import { usePermissions } from "@/lib/hooks/usePermissions";
import type { Quote, QuoteLineItem } from "@/types/api";
import {
  DIRTY_FORM_REASON,
  SUGGEST_AGAIN_LABEL,
  SUGGEST_ERROR_MESSAGE,
  SUGGEST_LABEL,
  SUGGEST_PENDING_LABEL,
  UNSAVED_QUOTE_REASON,
  suggestionRefusalCopy,
  triggerDisabledReason,
  triggerLabel,
} from "../[id]/edit/_lib/suggestion-copy";
import {
  useQuoteSuggestions,
  type QuoteSuggestionResult,
} from "../[id]/edit/_hooks/use-quote-suggestions";
import { AiLineSubRow } from "../[id]/edit/_components/ai-line-sub-row";
import { SuggestionNotice } from "../[id]/edit/_components/suggestion-notice";
import { UnreviewedBanner } from "../[id]/edit/_components/unreviewed-banner";
import { SortableLineItemRow } from "../[id]/edit/_components/sortable-line-item-row";
import { LineItemsTable } from "../[id]/edit/_components/line-items-table";
import {
  DEFAULT_FORM_VALUES,
  createEmptyLineItem,
  mapQuoteToFormValues,
  type QuoteFormValues,
} from "../[id]/edit/_lib/quote-form";

jest.mock("sonner", () => ({ toast: { error: jest.fn(), success: jest.fn() } }));
jest.mock("@/lib/api-client", () => ({
  ...jest.requireActual("@/lib/api-client"),
  apiPost: jest.fn(),
}));
jest.mock("@/lib/hooks/usePermissions", () => ({ usePermissions: jest.fn() }));

const mockApiPost = apiPost as jest.Mock;
const mockToastError = toast.error as jest.Mock;
const mockUsePermissions = usePermissions as jest.Mock;

function grantFinanceView(granted: boolean) {
  mockUsePermissions.mockReturnValue({
    can: () => granted,
    permissions: new Set<string>(),
    isLoading: false,
  });
}

const QUOTE_ID = "quote-1";
const SUGGEST_PATH = `/api/v1/quotes/${QUOTE_ID}/suggest-line-items`;

function createWrapper() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  );
  return { queryClient, wrapper };
}

describe("suggestion copy", () => {
  test("insufficient_history renders the heading and body from the response, never a client constant", () => {
    const { heading, body } = suggestionRefusalCopy("insufficient_history", {
      tradeName: "plumbing",
      requiredCount: 5,
      comparableCount: 2,
    });
    expect(heading).toBe("Not enough plumbing history yet");
    expect(body).toBe(
      "AI suggestions need at least 5 completed plumbing jobs with recorded costs and an issued invoice. You have 2. Record costs as work happens and invoice completed jobs — suggestions turn on by themselves."
    );
  });

  test("trade_unresolved returns its locked heading/body pair", () => {
    const { heading, body } = suggestionRefusalCopy("trade_unresolved", {
      tradeName: null,
      requiredCount: null,
      comparableCount: null,
    });
    expect(heading).toBe("Add a trade to a line first");
    expect(body).toBe(
      "Suggestions match a line's trade against your completed work in that trade. Fill in the Trade column on at least one line, save the draft, then try again."
    );
  });

  test("ungrounded returns its locked heading/body pair", () => {
    const { heading, body } = suggestionRefusalCopy("ungrounded", {
      tradeName: null,
      requiredCount: null,
      comparableCount: null,
    });
    expect(heading).toBe("No suggestions this time");
    expect(body).toBe(
      "The AI's draft cited figures that aren't in your recorded history, so it was discarded rather than shown. Try again, or build the lines by hand."
    );
  });

  test("triggerDisabledReason: unsaved new quote wins", () => {
    expect(
      triggerDisabledReason({ isNewQuote: true, isDirty: true })
    ).toBe(UNSAVED_QUOTE_REASON);
  });

  test("triggerDisabledReason: dirty form", () => {
    expect(
      triggerDisabledReason({ isNewQuote: false, isDirty: true })
    ).toBe(DIRTY_FORM_REASON);
  });

  test("triggerDisabledReason: null when saved and clean", () => {
    expect(
      triggerDisabledReason({ isNewQuote: false, isDirty: false })
    ).toBeNull();
  });

  test("triggerLabel: Suggest line items at zero AI lines", () => {
    expect(triggerLabel(0, false)).toBe(SUGGEST_LABEL);
  });

  test("triggerLabel: Suggest again above zero AI lines", () => {
    expect(triggerLabel(3, false)).toBe(SUGGEST_AGAIN_LABEL);
  });

  test("triggerLabel: Analyzing history while pending", () => {
    expect(triggerLabel(0, true)).toBe(SUGGEST_PENDING_LABEL);
  });
});

describe("useQuoteSuggestions", () => {
  beforeEach(() => {
    mockApiPost.mockReset();
    mockToastError.mockReset();
  });

  test("posts exactly once to /suggest-line-items and maps the snake_case body to camelCase", async () => {
    mockApiPost.mockResolvedValue({
      refusal_reason: null,
      trade_name: null,
      comparable_count: null,
      required_count: null,
      suggested_line_count: 3,
    });
    const { wrapper } = createWrapper();
    const { result } = renderHook(() => useQuoteSuggestions(QUOTE_ID), { wrapper });

    result.current.suggest();

    await waitFor(() => expect(mockApiPost).toHaveBeenCalledTimes(1));
    expect(mockApiPost).toHaveBeenCalledWith(SUGGEST_PATH, {});
    await waitFor(() => expect(result.current.isPending).toBe(false));
    expect(result.current.refusal).toBeNull();
  });

  test("a refusal response leaves the refusal state populated and fires no toast", async () => {
    mockApiPost.mockResolvedValue({
      refusal_reason: "insufficient_history",
      trade_name: "plumbing",
      comparable_count: 1,
      required_count: 5,
      suggested_line_count: 0,
    });
    const { wrapper } = createWrapper();
    const { result } = renderHook(() => useQuoteSuggestions(QUOTE_ID), { wrapper });

    result.current.suggest();

    await waitFor(() =>
      expect(result.current.refusal?.refusalReason).toBe("insufficient_history")
    );
    expect(result.current.refusal?.tradeName).toBe("plumbing");
    expect(result.current.refusal?.requiredCount).toBe(5);
    expect(result.current.refusal?.comparableCount).toBe(1);
    expect(mockToastError).not.toHaveBeenCalled();
  });

  test("a rejected mutation fires the locked toast and leaves the refusal state null", async () => {
    mockApiPost.mockRejectedValue(new Error("boom"));
    const { wrapper } = createWrapper();
    const { result } = renderHook(() => useQuoteSuggestions(QUOTE_ID), { wrapper });

    result.current.suggest();

    await waitFor(() =>
      expect(mockToastError).toHaveBeenCalledWith(SUGGEST_ERROR_MESSAGE, {
        duration: Infinity,
      })
    );
    expect(result.current.refusal).toBeNull();
  });
});

describe("ai line anatomy", () => {
  test("renders a full-width sub-row with no background class", () => {
    render(
      <table>
        <tbody>
          <AiLineSubRow
            index={0}
            columnCount={8}
            band="high"
            reviewState="unreviewed"
            basis="median of 7 comparable plumbing scopes"
            onAccept={jest.fn()}
          />
        </tbody>
      </table>
    );
    const row = screen.getByTestId("ai-line-sub-row-0");
    expect(row.className).toBe("");
  });

  test("renders the band chip, then the marker, then an Accept button while unreviewed", () => {
    render(
      <table>
        <tbody>
          <AiLineSubRow
            index={2}
            columnCount={8}
            band="medium"
            reviewState="unreviewed"
            basis="median of 3 comparable electrical scopes"
            onAccept={jest.fn()}
          />
        </tbody>
      </table>
    );
    expect(screen.getByTestId("confidence-chip-2")).toHaveTextContent("Limited history");
    expect(screen.getByTestId("review-marker-2")).toHaveTextContent("Needs review");
    expect(
      screen.getByRole("button", { name: "Accept suggested line 3" })
    ).toBeInTheDocument();
  });

  test("renders the basis on its own line, verbatim and unclamped", () => {
    const basis = "median of 7 comparable plumbing scopes; past plumbing quotes ran 12% under actual";
    render(
      <table>
        <tbody>
          <AiLineSubRow
            index={0}
            columnCount={8}
            band="high"
            reviewState="accepted"
            basis={basis}
            onAccept={jest.fn()}
          />
        </tbody>
      </table>
    );
    expect(screen.getByTestId("line-basis-0")).toHaveTextContent(basis);
    expect(
      screen.queryByRole("button", { name: /accept suggested line/i })
    ).not.toBeInTheDocument();
  });

  test("a null band and a null basis render no chip and the withheld caption", () => {
    render(
      <table>
        <tbody>
          <AiLineSubRow
            index={0}
            columnCount={8}
            band={null}
            reviewState="unreviewed"
            basis={null}
            onAccept={jest.fn()}
          />
        </tbody>
      </table>
    );
    expect(screen.queryByTestId("confidence-chip-0")).not.toBeInTheDocument();
    expect(screen.getByTestId("line-basis-0")).toHaveTextContent(
      "Basis hidden — requires finance access."
    );
  });

  test("SuggestionNotice renders role=status and the heading/body for the given refusal reason", () => {
    render(
      <SuggestionNotice
        reason="insufficient_history"
        context={{ tradeName: "plumbing", requiredCount: 5, comparableCount: 1 }}
      />
    );
    const notice = screen.getByTestId("suggestion-notice");
    expect(notice).toHaveAttribute("role", "status");
    expect(within(notice).getByText("Not enough plumbing history yet")).toBeInTheDocument();
  });

  test("UnreviewedBanner renders the singular heading at count 1 and the plural above it", () => {
    const { rerender } = render(<UnreviewedBanner count={1} />);
    expect(screen.getByTestId("unreviewed-banner")).toHaveTextContent(
      "1 AI-suggested line still needs review"
    );
    rerender(<UnreviewedBanner count={3} />);
    expect(screen.getByTestId("unreviewed-banner")).toHaveTextContent(
      "3 AI-suggested lines still need review"
    );
  });
});

function TestRow({
  defaultValues,
  showTradeColumn,
}: {
  defaultValues: QuoteFormValues;
  showTradeColumn?: boolean;
}) {
  const form = useForm<QuoteFormValues>({ defaultValues });
  return (
    <table>
      <tbody>
        <SortableLineItemRow
          fieldId="row-0"
          index={0}
          isLast
          onRemove={jest.fn()}
          onAppendRow={jest.fn()}
          register={form.register}
          control={form.control}
          watch={form.watch}
          errors={form.formState.errors}
          showTradeColumn={showTradeColumn}
        />
      </tbody>
    </table>
  );
}

describe("line item row", () => {
  test("tints the row bg-secondary for an unreviewed AI line", () => {
    const values: QuoteFormValues = {
      ...DEFAULT_FORM_VALUES,
      line_items: [
        {
          ...createEmptyLineItem(0),
          ai_origin: true,
          review_state: "unreviewed",
        },
      ],
    };
    render(<TestRow defaultValues={values} />);
    const row = screen.getByRole("row");
    expect(row).toHaveClass("bg-secondary");
  });

  test("carries no background class for a hand-built line", () => {
    const values: QuoteFormValues = {
      ...DEFAULT_FORM_VALUES,
      line_items: [createEmptyLineItem(0)],
    };
    render(<TestRow defaultValues={values} />);
    const row = screen.getByRole("row");
    expect(row).not.toHaveClass("bg-secondary");
  });

  test("renders the Trade cell only when the Trade column is shown", () => {
    const values: QuoteFormValues = {
      ...DEFAULT_FORM_VALUES,
      line_items: [createEmptyLineItem(0)],
    };
    const { rerender } = render(<TestRow defaultValues={values} showTradeColumn={false} />);
    expect(screen.queryByPlaceholderText("e.g. Plumbing")).not.toBeInTheDocument();
    rerender(<TestRow defaultValues={values} showTradeColumn />);
    expect(screen.getByPlaceholderText("e.g. Plumbing")).toBeInTheDocument();
  });
});

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
    job_id: "job-1",
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
    total: "0",
    created_at: "2026-07-01T00:00:00Z",
    updated_at: "2026-07-01T00:00:00Z",
    ...overrides,
  } as Quote;
}

function TestLineItemsTable({
  quote,
  isNewQuote = false,
  aiLineCount = 0,
  unreviewedCount = 0,
  suggest = jest.fn(),
  isPending = false,
  refusal = null,
  onRegenerateNeeded = jest.fn(),
}: {
  quote: Quote | null;
  isNewQuote?: boolean;
  aiLineCount?: number;
  unreviewedCount?: number;
  suggest?: () => void;
  isPending?: boolean;
  refusal?: QuoteSuggestionResult | null;
  onRegenerateNeeded?: () => void;
}) {
  const form = useForm<QuoteFormValues>({
    defaultValues: quote ? mapQuoteToFormValues(quote) : DEFAULT_FORM_VALUES,
  });
  return (
    <>
      <button
        type="button"
        onClick={() =>
          form.setValue("line_items.0.description", "changed", {
            shouldDirty: true,
          })
        }
      >
        Make dirty
      </button>
      <LineItemsTable
        form={form}
        quote={quote}
        isNewQuote={isNewQuote}
        aiLineCount={aiLineCount}
        unreviewedCount={unreviewedCount}
        suggestion={{ suggest, isPending, refusal }}
        onRegenerateNeeded={onRegenerateNeeded}
      />
    </>
  );
}

describe("line items table", () => {
  beforeEach(() => {
    mockApiPost.mockReset();
  });

  test("a draft quote, clean form, viewer with finance.view shows the trigger", () => {
    grantFinanceView(true);
    render(<TestLineItemsTable quote={makeQuote({ status: "draft" })} />);
    expect(screen.getByTestId("suggest-line-items-trigger")).toBeInTheDocument();
  });

  test("a viewer without finance.view sees no trigger and no deny panel", () => {
    grantFinanceView(false);
    render(<TestLineItemsTable quote={makeQuote({ status: "draft" })} />);
    expect(screen.queryByTestId("suggest-line-items-trigger")).not.toBeInTheDocument();
    expect(screen.queryByText(/don't have permission/i)).not.toBeInTheDocument();
  });

  test("a non-draft quote hides the trigger but still renders existing AI lines", () => {
    grantFinanceView(true);
    const quote = makeQuote({
      status: "sent",
      line_items: [
        makeLineItem({
          ai_origin: true,
          review_state: "accepted",
          confidence_band: "high",
          basis: "median of 7 comparable plumbing scopes",
        }),
      ],
    });
    render(<TestLineItemsTable quote={quote} aiLineCount={1} unreviewedCount={0} />);
    expect(screen.queryByTestId("suggest-line-items-trigger")).not.toBeInTheDocument();
    expect(screen.queryByTestId("unreviewed-banner")).not.toBeInTheDocument();
    expect(screen.getByTestId("confidence-chip-0")).toHaveTextContent("Strong history");
    expect(screen.getByTestId("line-basis-0")).toHaveTextContent(
      "median of 7 comparable plumbing scopes"
    );
  });

  test("a dirty form disables the trigger and shows the dirty-form caption", () => {
    grantFinanceView(true);
    render(<TestLineItemsTable quote={makeQuote({ status: "draft" })} />);
    fireEvent.click(screen.getByRole("button", { name: "Make dirty" }));
    expect(screen.getByTestId("suggest-line-items-trigger")).toBeDisabled();
    expect(screen.getByTestId("suggest-trigger-reason")).toHaveTextContent(
      DIRTY_FORM_REASON
    );
  });

  test("clicking Accept sets that line's review_state to accepted with zero network requests", () => {
    grantFinanceView(true);
    const quote = makeQuote({
      line_items: [
        makeLineItem({ ai_origin: true, review_state: "unreviewed", confidence_band: "high" }),
      ],
    });
    render(<TestLineItemsTable quote={quote} aiLineCount={1} unreviewedCount={1} />);
    fireEvent.click(screen.getByTestId("accept-line-0"));
    expect(screen.getByTestId("review-marker-0")).toHaveTextContent("Accepted");
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  test("12 unreviewed AI lines render exactly 12 accept affordances and no bulk-approve control", () => {
    grantFinanceView(true);
    const lineItems = Array.from({ length: 12 }, (_, i) =>
      makeLineItem({
        id: `line-${i}`,
        sort_order: i,
        ai_origin: true,
        review_state: "unreviewed",
        confidence_band: "medium",
      })
    );
    const quote = makeQuote({ line_items: lineItems });
    render(<TestLineItemsTable quote={quote} aiLineCount={12} unreviewedCount={12} />);
    expect(screen.getAllByTestId(/^accept-line-/)).toHaveLength(12);
    expect(
      screen.queryAllByRole("button", { name: /accept all|approve all|select all/i })
    ).toHaveLength(0);
  });

  test("no element in the rendered tree carries a confidence percentage or score", () => {
    grantFinanceView(true);
    const quote = makeQuote({
      line_items: [
        makeLineItem({
          ai_origin: true,
          review_state: "unreviewed",
          confidence_band: "low",
          basis: "median of 2 comparable plumbing scopes",
        }),
      ],
    });
    const { container } = render(
      <TestLineItemsTable quote={quote} aiLineCount={1} unreviewedCount={1} />
    );
    expect(container.textContent).not.toMatch(/\d+(\.\d+)?\s*%/);
    expect(container.querySelector('[role="progressbar"]')).toBeNull();
  });

  test("a hand-built line renders no sub-row at all", () => {
    grantFinanceView(true);
    const quote = makeQuote({ line_items: [makeLineItem({ ai_origin: false })] });
    render(<TestLineItemsTable quote={quote} />);
    expect(screen.queryByTestId("ai-line-sub-row-0")).not.toBeInTheDocument();
  });

  test("the Trade column renders only for a project-level quote", () => {
    grantFinanceView(true);
    const projectQuote = makeQuote({
      job_id: null,
      trade_scope_id: null,
      line_items: [makeLineItem()],
    });
    const { rerender } = render(<TestLineItemsTable quote={projectQuote} />);
    expect(screen.getByPlaceholderText("e.g. Plumbing")).toBeInTheDocument();

    const jobQuote = makeQuote({
      job_id: "job-1",
      trade_scope_id: null,
      line_items: [makeLineItem()],
    });
    rerender(<TestLineItemsTable quote={jobQuote} />);
    expect(screen.queryByPlaceholderText("e.g. Plumbing")).not.toBeInTheDocument();
  });
});

describe("regenerate", () => {
  beforeEach(() => {
    grantFinanceView(true);
  });

  test("clicking Suggest again with unreviewedCount > 0 requests the confirmation instead of mutating", () => {
    const suggest = jest.fn();
    const onRegenerateNeeded = jest.fn();
    const quote = makeQuote({
      line_items: [makeLineItem({ ai_origin: true, review_state: "unreviewed" })],
    });
    render(
      <TestLineItemsTable
        quote={quote}
        aiLineCount={1}
        unreviewedCount={1}
        suggest={suggest}
        onRegenerateNeeded={onRegenerateNeeded}
      />
    );
    fireEvent.click(screen.getByTestId("suggest-line-items-trigger"));
    expect(onRegenerateNeeded).toHaveBeenCalledTimes(1);
    expect(suggest).not.toHaveBeenCalled();
  });

  test("clicking Suggest again with nothing unreviewed calls the mutation directly", () => {
    const suggest = jest.fn();
    const onRegenerateNeeded = jest.fn();
    const quote = makeQuote({
      line_items: [makeLineItem({ ai_origin: true, review_state: "accepted" })],
    });
    render(
      <TestLineItemsTable
        quote={quote}
        aiLineCount={1}
        unreviewedCount={0}
        suggest={suggest}
        onRegenerateNeeded={onRegenerateNeeded}
      />
    );
    fireEvent.click(screen.getByTestId("suggest-line-items-trigger"));
    expect(suggest).toHaveBeenCalledTimes(1);
    expect(onRegenerateNeeded).not.toHaveBeenCalled();
  });
});
