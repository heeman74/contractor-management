import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactElement } from "react";
import type { TradeScopeResponse, TaskResponse } from "@/types/projects";

jest.mock("@/lib/api/projects", () => ({
  useTasks: jest.fn(),
  updateTradeScope: jest.fn(),
  createTask: jest.fn(),
  deleteTask: jest.fn(),
}));

jest.mock("@/lib/hooks/usePermissions", () => ({
  usePermissions: () => ({ can: () => true, permissions: new Set(), isLoading: false }),
}));

jest.mock("@/features/finance/hooks", () => ({
  useCostEntriesForTradeScope: () => ({ data: [] }),
  useTradeScopeCostBreakdown: () => ({ data: null, isLoading: false, isError: false }),
  useCostCategories: () => ({ data: [] }),
  useAddCostEntry: () => ({ mutateAsync: jest.fn(), isPending: false }),
  useUploadReceipt: () => ({ mutateAsync: jest.fn(), isPending: false }),
  useDeleteCostEntry: () => ({ mutate: jest.fn(), isPending: false }),
  useSetBudget: () => ({ mutate: jest.fn(), isPending: false }),
  useUpdateBudget: () => ({ mutate: jest.fn(), isPending: false }),
  useDeleteBudget: () => ({ mutate: jest.fn(), isPending: false }),
}));

import { useTasks, createTask, deleteTask } from "@/lib/api/projects";
import { TradeScopeDetail } from "../TradeScopeDetail";

const SCOPE: TradeScopeResponse = {
  id: "scope-1",
  company_id: "co-1",
  project_id: "proj-1",
  trade_catalog_id: null,
  trade_name: "Electrical",
  trade_color: "#eab308",
  contractor_id: null,
  status: "not_started",
  status_override: false,
  sort_order: 0,
  version: 1,
  created_at: "2026-07-25T00:00:00Z",
  updated_at: "2026-07-25T00:00:00Z",
};

function makeTask(id: string, title: string): TaskResponse {
  return {
    id,
    company_id: "co-1",
    trade_scope_id: "scope-1",
    title,
    description: null,
    status: "not_started",
    sort_order: 1,
    priority: "medium",
    estimated_hours: null,
    estimated_cost: null,
    start_date: null,
    due_date: null,
    zone_id: null,
    photo_required: false,
    assigned_to: null,
    materials_needed: [],
    version: 1,
    created_at: "2026-07-25T00:00:00Z",
    updated_at: "2026-07-25T00:00:00Z",
  };
}

function renderWithClient(ui: ReactElement) {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return render(<QueryClientProvider client={client}>{ui}</QueryClientProvider>);
}

beforeEach(() => {
  (useTasks as jest.Mock).mockReturnValue({
    data: [makeTask("t-1", "Rough-in wiring")],
  });
});
afterEach(() => jest.clearAllMocks());

describe("TradeScopeDetail", () => {
  test("adds a task via the inline quick-add", async () => {
    (createTask as jest.Mock).mockResolvedValue(makeTask("t-2", "Set panel"));
    const user = userEvent.setup();
    renderWithClient(<TradeScopeDetail scope={SCOPE} onSelectTask={() => {}} />);

    await user.click(screen.getByTestId("add-task-button"));
    await user.type(screen.getByPlaceholderText("Task title"), "Set panel");
    await user.click(screen.getByRole("button", { name: "Add" }));

    await waitFor(() =>
      expect(createTask).toHaveBeenCalledWith({
        trade_scope_id: "scope-1",
        title: "Set panel",
      })
    );
  });

  test("does not create a task for a blank title", async () => {
    const user = userEvent.setup();
    renderWithClient(<TradeScopeDetail scope={SCOPE} onSelectTask={() => {}} />);
    await user.click(screen.getByTestId("add-task-button"));
    // Add button is disabled while the field is empty.
    expect(screen.getByRole("button", { name: "Add" })).toBeDisabled();
    expect(createTask).not.toHaveBeenCalled();
  });

  test("removes a task after confirming the dialog", async () => {
    (deleteTask as jest.Mock).mockResolvedValue(undefined);
    const user = userEvent.setup();
    renderWithClient(<TradeScopeDetail scope={SCOPE} onSelectTask={() => {}} />);

    await user.click(screen.getByRole("button", { name: /delete rough-in wiring/i }));
    await user.click(screen.getByRole("button", { name: "Delete" }));

    await waitFor(() => expect(deleteTask).toHaveBeenCalledWith("t-1"));
  });

  test("clicking a task row selects it (not the delete button)", async () => {
    const onSelectTask = jest.fn();
    const user = userEvent.setup();
    renderWithClient(<TradeScopeDetail scope={SCOPE} onSelectTask={onSelectTask} />);

    await user.click(screen.getByText("Rough-in wiring"));
    expect(onSelectTask).toHaveBeenCalledWith(
      expect.objectContaining({ id: "t-1" })
    );
  });
});
