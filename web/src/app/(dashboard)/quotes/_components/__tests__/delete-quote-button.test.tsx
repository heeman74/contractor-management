/**
 * Deleting a quote from the list.
 *
 * Two behaviours carry the weight. The button must not also navigate — the row it
 * sits in opens the quote on click, so a delete that bubbles would file the user
 * away from the confirmation they were asked for. And the server's 409 explains
 * WHICH dependent blocks the delete, so that sentence has to reach the user
 * rather than being replaced by a generic failure.
 */
import type { ReactNode } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";

jest.mock("@/lib/api-client", () => ({ apiDelete: jest.fn() }));
const mockCan = jest.fn();
jest.mock("@/lib/hooks/usePermissions", () => ({
  usePermissions: () => ({ can: mockCan, permissions: new Set(), isLoading: false }),
}));

import { apiDelete } from "@/lib/api-client";
import { DeleteQuoteButton } from "../delete-quote-button";

const mockDelete = apiDelete as jest.MockedFunction<typeof apiDelete>;

function wrapper({ children }: { children: ReactNode }) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>;
}

function renderButton(onRowClick = jest.fn()) {
  return render(
    <div onClick={onRowClick}>
      <DeleteQuoteButton quoteId="q-1" quoteReference="Q-1001" />
    </div>,
    { wrapper }
  );
}

beforeEach(() => {
  mockDelete.mockReset();
  mockCan.mockReset();
  mockCan.mockReturnValue(true);
});

it("renders nothing without the delete permission", () => {
  mockCan.mockReturnValue(false);
  renderButton();
  expect(screen.queryByRole("button", { name: /Delete quote Q-1001/ })).toBeNull();
});

it("asks before deleting", async () => {
  renderButton();
  fireEvent.click(screen.getByRole("button", { name: /Delete quote Q-1001/ }));

  expect(await screen.findByText(/Delete quote Q-1001\?/)).toBeInTheDocument();
  expect(mockDelete).not.toHaveBeenCalled();
});

it("does not open the quote when the delete button is clicked", () => {
  const onRowClick = jest.fn();
  renderButton(onRowClick);

  fireEvent.click(screen.getByRole("button", { name: /Delete quote Q-1001/ }));

  expect(onRowClick).not.toHaveBeenCalled();
});

it("deletes once confirmed", async () => {
  mockDelete.mockResolvedValue(undefined as never);
  renderButton();

  fireEvent.click(screen.getByRole("button", { name: /Delete quote Q-1001/ }));
  fireEvent.click(await screen.findByRole("button", { name: /^Delete quote$/ }));

  await waitFor(() => expect(mockDelete).toHaveBeenCalledWith("/api/v1/quotes/q-1"));
});

it("shows the server's reason when a delete is refused", async () => {
  mockDelete.mockRejectedValue({
    detail: "This quote has a later revision attached, so it cannot be deleted.",
  });
  renderButton();

  fireEvent.click(screen.getByRole("button", { name: /Delete quote Q-1001/ }));
  fireEvent.click(await screen.findByRole("button", { name: /^Delete quote$/ }));

  expect(await screen.findByRole("alert")).toHaveTextContent(/later revision/);
});

it("cancels without deleting", async () => {
  renderButton();
  fireEvent.click(screen.getByRole("button", { name: /Delete quote Q-1001/ }));
  fireEvent.click(await screen.findByRole("button", { name: /Cancel/ }));

  expect(mockDelete).not.toHaveBeenCalled();
  await waitFor(() =>
    expect(screen.queryByText(/Delete quote Q-1001\?/)).not.toBeInTheDocument()
  );
});
