import React from "react";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { AddCostDialog } from "../components/AddCostDialog";
import { apiGet, apiPost } from "@/lib/api-client";

jest.mock("@/lib/api-client", () => ({
  apiGet: jest.fn(),
  apiPost: jest.fn(),
  apiPatch: jest.fn(),
  apiDelete: jest.fn(),
  apiUpload: jest.fn(),
  ApiError: class ApiError extends Error {},
}));
jest.mock("sonner", () => ({ toast: { success: jest.fn(), error: jest.fn() } }));

const mockApiGet = apiGet as jest.MockedFunction<typeof apiGet>;
const mockApiPost = apiPost as jest.MockedFunction<typeof apiPost>;

const MOCK_CATEGORIES = [
  { id: "cat-1", name: "Materials", is_system: true },
  { id: "cat-2", name: "Subcontractor", is_system: true },
];

function renderDialog(props: Partial<React.ComponentProps<typeof AddCostDialog>> = {}) {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return render(
    <QueryClientProvider client={client}>
      <AddCostDialog open onOpenChange={() => {}} jobId="job-1" {...props} />
    </QueryClientProvider>
  );
}

describe("AddCostDialog", () => {
  beforeEach(() => {
    mockApiGet.mockReset();
    mockApiPost.mockReset();
    mockApiGet.mockResolvedValue(MOCK_CATEGORIES);
  });

  test("blocks submit when amount is 0 or less", async () => {
    const user = userEvent.setup();
    renderDialog();

    await user.type(screen.getByLabelText(/amount/i), "0");
    await user.click(screen.getByRole("button", { name: /add cost/i }));

    expect(await screen.findByText(/amount greater than 0/i)).toBeInTheDocument();
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  test("blocks submit when category is not selected", async () => {
    const user = userEvent.setup();
    renderDialog();

    await user.type(screen.getByLabelText(/amount/i), "150");
    await user.click(screen.getByRole("button", { name: /add cost/i }));

    expect(await screen.findByText(/select a category/i)).toBeInTheDocument();
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  test("submits a valid cost entry once", async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    mockApiPost.mockResolvedValueOnce({
      id: "entry-1",
      job_id: "job-1",
      trade_scope_id: null,
      category_id: "cat-1",
      category_name: "Materials",
      amount: "150",
      incurred_date: "2026-07-25",
      vendor: null,
      note: null,
      created_at: "2026-07-25T00:00:00Z",
      updated_at: "2026-07-25T00:00:00Z",
    });

    renderDialog();

    await user.type(screen.getByLabelText(/amount/i), "150");
    await user.click(screen.getByRole("combobox", { name: /category/i }));
    await user.click(await screen.findByRole("option", { name: "Materials" }));
    await user.click(screen.getByRole("button", { name: /add cost/i }));

    await waitFor(() => expect(mockApiPost).toHaveBeenCalledTimes(1));
    expect(mockApiPost).toHaveBeenCalledWith(
      "/api/v1/cost-entries/",
      expect.objectContaining({
        job_id: "job-1",
        category_id: "cat-1",
        amount: "150",
      })
    );
  });
});
