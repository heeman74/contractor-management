import React from "react";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { CreateUserDialog } from "../create-user-dialog";
import { apiPost } from "@/lib/api-client";

jest.mock("@/lib/api-client", () => ({
  apiPost: jest.fn(),
  ApiError: class ApiError extends Error {},
}));
jest.mock("sonner", () => ({ toast: { success: jest.fn(), error: jest.fn() } }));

const mockApiPost = apiPost as jest.MockedFunction<typeof apiPost>;

function renderDialog() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return render(
    <QueryClientProvider client={client}>
      <CreateUserDialog open onOpenChange={() => {}} />
    </QueryClientProvider>
  );
}

describe("CreateUserDialog", () => {
  beforeEach(() => {
    mockApiPost.mockReset();
  });

  test("does not submit when required fields are empty", async () => {
    const user = userEvent.setup();
    renderDialog();
    await user.click(screen.getByRole("button", { name: /create user/i }));
    // Native required fields + the role guard block submission — no API call.
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  test("shows validation error when role is not selected", async () => {
    const user = userEvent.setup();
    renderDialog();
    await user.type(screen.getByLabelText(/email/i), "jane@example.com");
    await user.type(screen.getByLabelText(/first name/i), "Jane");
    await user.type(screen.getByLabelText(/last name/i), "Walsh");
    await user.click(screen.getByRole("button", { name: /create user/i }));
    expect(await screen.findByText("Role is required")).toBeInTheDocument();
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  test("creates the user, then assigns the selected role", async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    mockApiPost.mockResolvedValueOnce({
      id: "user-123",
      email: "jane@example.com",
      first_name: "Jane",
      last_name: "Walsh",
      phone: null,
    });
    mockApiPost.mockResolvedValueOnce({});
    renderDialog();

    await user.type(screen.getByLabelText(/email/i), "jane@example.com");
    await user.type(screen.getByLabelText(/first name/i), "Jane");
    await user.type(screen.getByLabelText(/last name/i), "Walsh");

    // Radix Select: open the trigger, choose "Foreman"
    await user.click(screen.getByRole("combobox", { name: /role/i }));
    await user.click(await screen.findByRole("option", { name: "Foreman" }));

    await user.click(screen.getByRole("button", { name: /create user/i }));

    await waitFor(() => expect(mockApiPost).toHaveBeenCalledTimes(2));

    // Step 1: create user (no phone since blank)
    expect(mockApiPost).toHaveBeenNthCalledWith(1, "/api/v1/users/", {
      email: "jane@example.com",
      first_name: "Jane",
      last_name: "Walsh",
    });
    // Step 2: assign the chosen role to the new user
    expect(mockApiPost).toHaveBeenNthCalledWith(2, "/api/v1/users/user-123/roles", {
      user_id: "user-123",
      role: "foreman",
    });
  });
});
