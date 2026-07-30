import React from "react";
import { render, screen, within } from "@testing-library/react";
import { renderHook, waitFor } from "@testing-library/react";
import { useForm } from "react-hook-form";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { toast } from "sonner";
import { apiPost } from "@/lib/api-client";
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
import { useQuoteSuggestions } from "../[id]/edit/_hooks/use-quote-suggestions";
import { AiLineSubRow } from "../[id]/edit/_components/ai-line-sub-row";
import { SuggestionNotice } from "../[id]/edit/_components/suggestion-notice";
import { UnreviewedBanner } from "../[id]/edit/_components/unreviewed-banner";
import { SortableLineItemRow } from "../[id]/edit/_components/sortable-line-item-row";
import {
  DEFAULT_FORM_VALUES,
  createEmptyLineItem,
  type QuoteFormValues,
} from "../[id]/edit/_lib/quote-form";

jest.mock("sonner", () => ({ toast: { error: jest.fn(), success: jest.fn() } }));
jest.mock("@/lib/api-client", () => ({
  ...jest.requireActual("@/lib/api-client"),
  apiPost: jest.fn(),
}));

const mockApiPost = apiPost as jest.Mock;
const mockToastError = toast.error as jest.Mock;

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
