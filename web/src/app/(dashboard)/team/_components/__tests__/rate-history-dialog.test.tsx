import React from "react";
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { toast } from "sonner";
import {
  RateHistoryDialog,
  currentRate,
  nextFutureRate,
  supersededRateIds,
} from "../rate-history-dialog";
import { useLaborRateHistory, useAddLaborRate } from "@/features/finance/hooks";
import type { LaborRate } from "@/features/finance/types";

jest.mock("@/features/finance/hooks", () => ({
  useLaborRateHistory: jest.fn(),
  useAddLaborRate: jest.fn(),
}));
jest.mock("sonner", () => ({ toast: { success: jest.fn(), error: jest.fn() } }));

const mockUseLaborRateHistory = useLaborRateHistory as jest.Mock;
const mockUseAddLaborRate = useAddLaborRate as jest.Mock;

const TODAY = new Date().toISOString().slice(0, 10);
const PAST_DATE = "2026-05-01";
const FUTURE_DATE = "2099-01-01";

function makeRate(overrides: Partial<LaborRate> = {}): LaborRate {
  return {
    id: "rate-1",
    userId: "u1",
    hourlyCost: "45.00",
    effectiveFrom: PAST_DATE,
    createdAt: "2026-05-01T09:00:00Z",
    updatedAt: "2026-05-01T09:00:00Z",
    ...overrides,
  };
}

function mockHistory(rates: LaborRate[], { isError = false } = {}) {
  mockUseLaborRateHistory.mockReturnValue({
    data: rates,
    isLoading: false,
    isError,
  });
}

function renderDialog(
  rates: LaborRate[],
  { onOpenChange = () => {}, mutate = jest.fn(), isPending = false } = {}
) {
  mockHistory(rates);
  mockUseAddLaborRate.mockReturnValue({ mutate, isPending });
  render(
    <RateHistoryDialog
      open
      onOpenChange={onOpenChange}
      userId="u1"
      memberName="Sarah Mitchell"
    />
  );
  return { mutate };
}

describe("RateHistoryDialog", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test("renders the dialog title with the member name", () => {
    renderDialog([makeRate()]);
    expect(screen.getByText("Labor rate — Sarah Mitchell")).toBeInTheDocument();
  });

  test("shows the current rate headline for a past-effective rate", () => {
    renderDialog([makeRate({ hourlyCost: "45.00", effectiveFrom: PAST_DATE })]);
    expect(screen.getByTestId("current-rate-figure")).toHaveTextContent("$45.00/hr");
  });

  test("shows the em dash headline and empty state with no history", () => {
    renderDialog([]);
    expect(screen.getByTestId("current-rate-figure")).toHaveTextContent("—");
    expect(screen.getByText("No rate set yet")).toBeInTheDocument();
    expect(
      screen.getByText(
        "Hours this member tracks will show as unrated until you add a rate. Backdate the effective date to cover past work."
      )
    ).toBeInTheDocument();
    expect(screen.queryByRole("table")).not.toBeInTheDocument();
  });

  test("blocks submission with an empty amount", async () => {
    const user = userEvent.setup();
    const { mutate } = renderDialog([]);
    await user.click(screen.getByRole("button", { name: "Add Rate" }));
    expect(
      screen.getByText("Enter an hourly rate greater than $0.")
    ).toBeInTheDocument();
    expect(mutate).not.toHaveBeenCalled();
  });

  test("blocks submission with a zero amount", async () => {
    const user = userEvent.setup();
    const { mutate } = renderDialog([]);
    await user.type(screen.getByLabelText("Hourly rate"), "0");
    await user.click(screen.getByRole("button", { name: "Add Rate" }));
    expect(
      screen.getByText("Enter an hourly rate greater than $0.")
    ).toBeInTheDocument();
    expect(mutate).not.toHaveBeenCalled();
  });

  test("submits a valid amount with today's date and keeps the dialog open", async () => {
    const user = userEvent.setup();
    const onOpenChange = jest.fn();
    const mutate = jest.fn(
      (_input: unknown, options?: { onSuccess?: () => void }) =>
        options?.onSuccess?.()
    );
    renderDialog([], { onOpenChange, mutate });

    await user.type(screen.getByLabelText("Hourly rate"), "45");
    await user.click(screen.getByRole("button", { name: "Add Rate" }));

    expect(mutate).toHaveBeenCalledTimes(1);
    expect(mutate.mock.calls[0][0]).toEqual({
      userId: "u1",
      hourlyCost: "45",
      effectiveFrom: TODAY,
    });
    expect(onOpenChange).not.toHaveBeenCalled();
    expect(toast.success).toHaveBeenCalledWith(
      expect.stringMatching(/^Rate added — effective .+\.$/)
    );
  });

  test("shows the save error toast when the mutation fails", async () => {
    const user = userEvent.setup();
    const mutate = jest.fn(
      (_input: unknown, options?: { onError?: () => void }) =>
        options?.onError?.()
    );
    renderDialog([], { mutate });

    await user.type(screen.getByLabelText("Hourly rate"), "45");
    await user.click(screen.getByRole("button", { name: "Add Rate" }));

    expect(toast.error).toHaveBeenCalledWith("Could not save rate. Please try again.");
  });

  test("badges a future-dated rate and excludes it from the headline", () => {
    renderDialog([
      makeRate({ id: "r-current", hourlyCost: "45.00", effectiveFrom: PAST_DATE }),
      makeRate({
        id: "r-future",
        hourlyCost: "50.00",
        effectiveFrom: FUTURE_DATE,
        createdAt: "2026-06-01T09:00:00Z",
      }),
    ]);
    expect(screen.getByTestId("current-rate-figure")).toHaveTextContent("$45.00/hr");
    const futureRow = screen.getByTestId("rate-row-r-future");
    expect(within(futureRow).getByText("Starts Jan 1, 2099")).toBeInTheDocument();
  });

  test("badges only the older row when two rates share an effective date", () => {
    renderDialog([
      makeRate({ id: "r-old", createdAt: "2026-05-01T08:00:00Z" }),
      makeRate({
        id: "r-new",
        hourlyCost: "47.00",
        createdAt: "2026-05-01T10:00:00Z",
      }),
    ]);
    expect(screen.getAllByText("Superseded")).toHaveLength(1);
    expect(
      within(screen.getByTestId("rate-row-r-old")).getByText("Superseded")
    ).toBeInTheDocument();
    expect(
      within(screen.getByTestId("rate-row-r-new")).queryByText("Superseded")
    ).not.toBeInTheDocument();
  });

  test("shows the history load error toast when the query errors", () => {
    mockHistory([], { isError: true });
    mockUseAddLaborRate.mockReturnValue({ mutate: jest.fn(), isPending: false });
    render(
      <RateHistoryDialog
        open
        onOpenChange={() => {}}
        userId="u1"
        memberName="Sarah Mitchell"
      />
    );
    expect(toast.error).toHaveBeenCalledWith(
      "Failed to load rate history. Please try again."
    );
  });
});

describe("currentRate", () => {
  test("picks the greatest effectiveFrom on or before today", () => {
    const older = makeRate({ id: "a", effectiveFrom: "2026-01-01" });
    const newer = makeRate({ id: "b", effectiveFrom: PAST_DATE });
    const future = makeRate({ id: "c", effectiveFrom: FUTURE_DATE });
    expect(currentRate([older, newer, future], TODAY)?.id).toBe("b");
  });

  test("breaks same-day ties with the latest createdAt", () => {
    const first = makeRate({ id: "a", createdAt: "2026-05-01T08:00:00Z" });
    const second = makeRate({ id: "b", createdAt: "2026-05-01T10:00:00Z" });
    expect(currentRate([first, second], TODAY)?.id).toBe("b");
    expect(currentRate([second, first], TODAY)?.id).toBe("b");
  });

  test("returns null when every rate is future-dated", () => {
    expect(currentRate([makeRate({ effectiveFrom: FUTURE_DATE })], TODAY)).toBeNull();
  });
});

describe("nextFutureRate", () => {
  test("returns the soonest future-dated rate", () => {
    const near = makeRate({ id: "near", effectiveFrom: "2098-01-01" });
    const far = makeRate({ id: "far", effectiveFrom: FUTURE_DATE });
    const past = makeRate({ id: "past", effectiveFrom: PAST_DATE });
    expect(nextFutureRate([far, near, past], TODAY)?.id).toBe("near");
  });

  test("returns null when nothing is scheduled", () => {
    expect(nextFutureRate([makeRate({ effectiveFrom: PAST_DATE })], TODAY)).toBeNull();
  });
});

describe("supersededRateIds", () => {
  test("marks every same-day row except the latest-created", () => {
    const oldest = makeRate({ id: "a", createdAt: "2026-05-01T08:00:00Z" });
    const middle = makeRate({ id: "b", createdAt: "2026-05-01T09:00:00Z" });
    const latest = makeRate({ id: "c", createdAt: "2026-05-01T10:00:00Z" });
    const otherDay = makeRate({ id: "d", effectiveFrom: "2026-06-01" });
    const ids = supersededRateIds([oldest, middle, latest, otherDay]);
    expect(ids).toEqual(new Set(["a", "b"]));
  });

  test("marks nothing when effective dates are unique", () => {
    const rates = [
      makeRate({ id: "a", effectiveFrom: "2026-05-01" }),
      makeRate({ id: "b", effectiveFrom: "2026-06-01" }),
    ];
    expect(supersededRateIds(rates).size).toBe(0);
  });
});
