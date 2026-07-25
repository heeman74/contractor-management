import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactElement } from "react";
import type { TaskResponse } from "@/types/projects";

jest.mock("../TaskPhotos", () => ({ TaskPhotos: () => null }));
jest.mock("@/lib/api/projects", () => ({
  updateTask: jest.fn(),
  deleteTask: jest.fn(),
}));

import { updateTask, deleteTask } from "@/lib/api/projects";
import { TaskDetail } from "../TaskDetail";

function makeTask(overrides: Partial<TaskResponse> = {}): TaskResponse {
  return {
    id: "task-1",
    company_id: "co-1",
    trade_scope_id: "scope-1",
    title: "Rough-in wiring",
    description: "Run feeders.",
    status: "not_started",
    sort_order: 1,
    priority: "high",
    estimated_hours: 8,
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
    ...overrides,
  };
}

function renderWithClient(ui: ReactElement) {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return render(<QueryClientProvider client={client}>{ui}</QueryClientProvider>);
}

afterEach(() => jest.clearAllMocks());

describe("TaskDetail", () => {
  test("renders read-only detail by default", () => {
    renderWithClient(<TaskDetail task={makeTask()} />);
    expect(screen.getByRole("heading", { name: "Rough-in wiring" })).toBeInTheDocument();
    expect(screen.getByText("Run feeders.")).toBeInTheDocument();
  });

  test("editing and saving PATCHes the task with the new values", async () => {
    (updateTask as jest.Mock).mockResolvedValue(
      makeTask({ title: "Set 150A panel", priority: "high" })
    );
    const user = userEvent.setup();
    renderWithClient(<TaskDetail task={makeTask()} />);

    await user.click(screen.getByRole("button", { name: /edit task/i }));
    const title = screen.getByLabelText("Title");
    await user.clear(title);
    await user.type(title, "Set 150A panel");
    await user.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() =>
      expect(updateTask).toHaveBeenCalledWith(
        "task-1",
        expect.objectContaining({ title: "Set 150A panel" })
      )
    );
    // The saved title is reflected in the panel afterwards.
    await waitFor(() =>
      expect(screen.getByRole("heading", { name: "Set 150A panel" })).toBeInTheDocument()
    );
  });

  test("save is blocked when the title is emptied", async () => {
    const user = userEvent.setup();
    renderWithClient(<TaskDetail task={makeTask()} />);
    await user.click(screen.getByRole("button", { name: /edit task/i }));
    await user.clear(screen.getByLabelText("Title"));
    await user.click(screen.getByRole("button", { name: "Save" }));
    expect(updateTask).not.toHaveBeenCalled();
  });

  test("deleting after confirmation DELETEs the task and notifies the parent", async () => {
    (deleteTask as jest.Mock).mockResolvedValue(undefined);
    const onTaskDeleted = jest.fn();
    const user = userEvent.setup();
    renderWithClient(<TaskDetail task={makeTask()} onTaskDeleted={onTaskDeleted} />);

    await user.click(screen.getByRole("button", { name: /delete task/i }));
    // Confirm in the dialog (the dialog's button is named exactly "Delete").
    await user.click(screen.getByRole("button", { name: "Delete" }));

    await waitFor(() => expect(deleteTask).toHaveBeenCalledWith("task-1"));
    await waitFor(() => expect(onTaskDeleted).toHaveBeenCalled());
  });
});
